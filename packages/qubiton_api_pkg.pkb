--------------------------------------------------------------------------------
-- QUBITON_API_PKG — Layer 1 API Client (Package Body)
--
-- Implements all 42 API endpoint wrappers plus internal HTTP, JSON, logging,
-- and error handling utilities. Configuration is loaded from QUBITON_CONFIG
-- table on first use (auto-init) or via explicit init() call.
--
-- Compatible with Oracle 11g+ (no JSON_OBJECT, uses string-based JSON build).
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY qubiton_api_pkg
AS
    ---------------------------------------------------------------------------
    -- Package-level state (loaded from QUBITON_CONFIG or init())
    ---------------------------------------------------------------------------
    gv_base_url        VARCHAR2(500)  := 'https://api.qubiton.com';
    gv_api_key         VARCHAR2(500)  := NULL;
    gv_wallet_path     VARCHAR2(500)  := 'file:/opt/oracle/wallet';
    gv_wallet_password VARCHAR2(200)  := NULL;
    gv_timeout         PLS_INTEGER    := 30;
    gv_error_mode      VARCHAR2(1)    := 'E';   -- E=exception, W=warning, S=silent
    gv_log_enabled     BOOLEAN        := TRUE;
    gv_initialized     BOOLEAN        := FALSE;

    ---------------------------------------------------------------------------
    -- Forward declarations (internal helpers)
    ---------------------------------------------------------------------------
    FUNCTION json_escape(p_value IN VARCHAR2) RETURN VARCHAR2;

    PROCEDURE json_add(
        p_json  IN OUT NOCOPY VARCHAR2,
        p_sep   IN OUT NOCOPY VARCHAR2,
        p_key   IN VARCHAR2,
        p_value IN VARCHAR2,
        p_type  IN VARCHAR2 DEFAULT 'S'
    );

    FUNCTION http_post(
        p_path        IN VARCHAR2,
        p_body        IN VARCHAR2,
        p_method_name IN VARCHAR2
    ) RETURN CLOB;

    FUNCTION http_get(
        p_path        IN VARCHAR2,
        p_method_name IN VARCHAR2
    ) RETURN CLOB;

    PROCEDURE log_call(
        p_method_name  IN VARCHAR2,
        p_endpoint     IN VARCHAR2,
        p_http_status  IN PLS_INTEGER,
        p_elapsed_ms   IN NUMBER,
        p_error_msg    IN VARCHAR2 DEFAULT NULL,
        p_http_method  IN VARCHAR2 DEFAULT 'POST'
    );

    PROCEDURE ensure_init;

    PROCEDURE handle_error(
        p_error_code IN PLS_INTEGER,
        p_message    IN VARCHAR2,
        p_error_mode IN VARCHAR2 DEFAULT NULL
    );

    FUNCTION extract_json_value(
        p_json IN CLOB,
        p_key  IN VARCHAR2
    ) RETURN VARCHAR2;

    PROCEDURE require_param(
        p_value       IN VARCHAR2,
        p_param_name  IN VARCHAR2,
        p_method_name IN VARCHAR2
    );

    ---------------------------------------------------------------------------
    -- json_escape: escape special characters for JSON string embedding
    ---------------------------------------------------------------------------
    FUNCTION json_escape(p_value IN VARCHAR2) RETURN VARCHAR2
    IS
        lv_result VARCHAR2(32767);
    BEGIN
        IF p_value IS NULL THEN
            RETURN NULL;
        END IF;
        lv_result := REPLACE(p_value, '\', '\\');
        lv_result := REPLACE(lv_result, '"', '\"');
        lv_result := REPLACE(lv_result, CHR(8), '\b');
        lv_result := REPLACE(lv_result, CHR(9), '\t');
        lv_result := REPLACE(lv_result, CHR(10), '\n');
        lv_result := REPLACE(lv_result, CHR(12), '\f');
        lv_result := REPLACE(lv_result, CHR(13), '\r');
        RETURN lv_result;
    END json_escape;

    ---------------------------------------------------------------------------
    -- json_add: append a key/value pair to a JSON string being built.
    -- Skips NULL values. Types: S=string (quoted), N=number, B=boolean.
    -- For B type: 'Y','TRUE','1' → true, anything else → false.
    ---------------------------------------------------------------------------
    PROCEDURE json_add(
        p_json  IN OUT NOCOPY VARCHAR2,
        p_sep   IN OUT NOCOPY VARCHAR2,
        p_key   IN VARCHAR2,
        p_value IN VARCHAR2,
        p_type  IN VARCHAR2 DEFAULT 'S'
    )
    IS
    BEGIN
        IF p_value IS NULL THEN
            RETURN;
        END IF;

        p_json := p_json || p_sep || '"' || p_key || '":';

        CASE UPPER(p_type)
            WHEN 'S' THEN
                p_json := p_json || '"' || json_escape(p_value) || '"';
            WHEN 'N' THEN
                p_json := p_json || p_value;
            WHEN 'B' THEN
                IF UPPER(p_value) IN ('Y', 'YES', 'TRUE', '1') THEN
                    p_json := p_json || 'true';
                ELSE
                    p_json := p_json || 'false';
                END IF;
            ELSE
                p_json := p_json || '"' || json_escape(p_value) || '"';
        END CASE;

        p_sep := ',';
    END json_add;

    ---------------------------------------------------------------------------
    -- require_param: validate that a required parameter is not NULL
    ---------------------------------------------------------------------------
    PROCEDURE require_param(
        p_value       IN VARCHAR2,
        p_param_name  IN VARCHAR2,
        p_method_name IN VARCHAR2
    )
    IS
    BEGIN
        IF p_value IS NULL THEN
            RAISE_APPLICATION_ERROR(
                gc_err_required_param,
                p_method_name || ': ' || p_param_name || ' is required'
            );
        END IF;
    END require_param;

    ---------------------------------------------------------------------------
    -- log_call: autonomous transaction insert into QUBITON_API_LOG
    ---------------------------------------------------------------------------
    PROCEDURE log_call(
        p_method_name  IN VARCHAR2,
        p_endpoint     IN VARCHAR2,
        p_http_status  IN PLS_INTEGER,
        p_elapsed_ms   IN NUMBER,
        p_error_msg    IN VARCHAR2 DEFAULT NULL,
        p_http_method  IN VARCHAR2 DEFAULT 'POST'
    )
    IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        IF NOT gv_log_enabled THEN
            RETURN;
        END IF;

        BEGIN
            INSERT INTO qubiton_api_log (
                api_method,
                http_method,
                endpoint_path,
                http_status,
                elapsed_ms,
                error_message
            ) VALUES (
                SUBSTR(p_method_name, 1, 100),
                SUBSTR(p_http_method, 1, 10),
                SUBSTR(p_endpoint, 1, 500),
                p_http_status,
                p_elapsed_ms,
                SUBSTR(p_error_msg, 1, 4000)
            );
            COMMIT;
        EXCEPTION
            WHEN OTHERS THEN
                -- Logging failure must never break API calls
                ROLLBACK;
        END;
    END log_call;

    ---------------------------------------------------------------------------
    -- handle_error: apply error mode (E=raise, W=warning, S=silent)
    ---------------------------------------------------------------------------
    PROCEDURE handle_error(
        p_error_code IN PLS_INTEGER,
        p_message    IN VARCHAR2,
        p_error_mode IN VARCHAR2 DEFAULT NULL
    )
    IS
        lv_mode VARCHAR2(1) := NVL(p_error_mode, gv_error_mode);
    BEGIN
        CASE UPPER(lv_mode)
            WHEN 'E' THEN
                RAISE_APPLICATION_ERROR(p_error_code, p_message);
            WHEN 'W' THEN
                DBMS_OUTPUT.PUT_LINE('WARNING: ' || p_message);
            WHEN 'S' THEN
                NULL;  -- silent
            ELSE
                RAISE_APPLICATION_ERROR(p_error_code, p_message);
        END CASE;
    END handle_error;

    ---------------------------------------------------------------------------
    -- extract_json_value: simple INSTR/SUBSTR JSON value extraction.
    -- Works on Oracle 11g+ without JSON_VALUE. Handles string and
    -- non-string (number, boolean, null) values.
    ---------------------------------------------------------------------------
    FUNCTION extract_json_value(
        p_json IN CLOB,
        p_key  IN VARCHAR2
    ) RETURN VARCHAR2
    IS
        lv_search   VARCHAR2(500);
        lv_pos      PLS_INTEGER;
        lv_start    PLS_INTEGER;
        lv_end      PLS_INTEGER;
        lv_char     VARCHAR2(1);
        lv_value    VARCHAR2(4000);
    BEGIN
        IF p_json IS NULL OR p_key IS NULL THEN
            RETURN NULL;
        END IF;

        -- Search for "key":
        lv_search := '"' || p_key || '"';
        lv_pos := DBMS_LOB.INSTR(p_json, lv_search, 1, 1);
        IF lv_pos = 0 THEN
            RETURN NULL;
        END IF;

        -- Move past the key and colon
        lv_start := lv_pos + LENGTH(lv_search);
        -- Skip whitespace and colon
        LOOP
            lv_char := DBMS_LOB.SUBSTR(p_json, 1, lv_start);
            EXIT WHEN lv_char IS NULL;
            EXIT WHEN lv_char NOT IN (':', ' ', CHR(9), CHR(10), CHR(13));
            lv_start := lv_start + 1;
        END LOOP;

        IF lv_char IS NULL THEN
            RETURN NULL;
        END IF;

        -- Determine value type by first character
        IF lv_char = '"' THEN
            -- String value: find closing quote (handle escaped quotes)
            lv_start := lv_start + 1;  -- skip opening quote
            lv_end := lv_start;
            LOOP
                lv_char := DBMS_LOB.SUBSTR(p_json, 1, lv_end);
                EXIT WHEN lv_char IS NULL;
                IF lv_char = '\' THEN
                    lv_end := lv_end + 2;  -- skip escaped char
                    -- Guard: don't read past end of CLOB
                    IF lv_end > DBMS_LOB.GETLENGTH(p_json) THEN
                        EXIT;
                    END IF;
                ELSIF lv_char = '"' THEN
                    EXIT;
                ELSE
                    lv_end := lv_end + 1;
                END IF;
            END LOOP;
            lv_value := DBMS_LOB.SUBSTR(p_json, lv_end - lv_start, lv_start);
        ELSE
            -- Non-string value (number, boolean, null): read until delimiter
            lv_end := lv_start;
            LOOP
                lv_char := DBMS_LOB.SUBSTR(p_json, 1, lv_end);
                EXIT WHEN lv_char IS NULL;
                EXIT WHEN lv_char IN (',', '}', ']', ' ', CHR(10), CHR(13));
                lv_end := lv_end + 1;
            END LOOP;
            lv_value := TRIM(DBMS_LOB.SUBSTR(p_json, lv_end - lv_start, lv_start));
        END IF;

        -- Normalize null literal
        IF LOWER(lv_value) = 'null' THEN
            RETURN NULL;
        END IF;

        RETURN lv_value;
    END extract_json_value;

    ---------------------------------------------------------------------------
    -- ensure_init: auto-load config from QUBITON_CONFIG if not initialized
    ---------------------------------------------------------------------------
    PROCEDURE ensure_init
    IS
        lv_value VARCHAR2(4000);

        CURSOR c_config IS
            SELECT config_key, config_value
              FROM qubiton_config;
    BEGIN
        IF gv_initialized THEN
            RETURN;
        END IF;

        BEGIN
            FOR rec IN c_config LOOP
                CASE UPPER(rec.config_key)
                    WHEN 'APIKEY' THEN
                        gv_api_key := rec.config_value;
                    WHEN 'API_KEY' THEN
                        gv_api_key := rec.config_value;
                    WHEN 'BASE_URL' THEN
                        gv_base_url := rec.config_value;
                    WHEN 'WALLET_PATH' THEN
                        gv_wallet_path := rec.config_value;
                    WHEN 'WALLET_PASSWORD' THEN
                        gv_wallet_password := rec.config_value;
                    WHEN 'TIMEOUT' THEN
                        gv_timeout := TO_NUMBER(rec.config_value);
                    WHEN 'ERROR_MODE' THEN
                        gv_error_mode := UPPER(SUBSTR(rec.config_value, 1, 1));
                    WHEN 'LOG_ENABLED' THEN
                        gv_log_enabled := UPPER(rec.config_value) IN ('Y', 'YES', 'TRUE', '1');
                    ELSE
                        NULL;  -- ignore unknown keys
                END CASE;
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN
                -- Table may not exist; that is acceptable if init() is called manually
                NULL;
        END;

        IF gv_api_key IS NULL THEN
            RAISE_APPLICATION_ERROR(
                gc_err_config_missing,
                'API key not configured: populate QUBITON_CONFIG table or call init()'
            );
        END IF;

        -- Strip trailing slash from base URL
        IF gv_base_url IS NOT NULL AND SUBSTR(gv_base_url, -1) = '/' THEN
            gv_base_url := SUBSTR(gv_base_url, 1, LENGTH(gv_base_url) - 1);
        END IF;

        gv_initialized := TRUE;
    END ensure_init;

    ---------------------------------------------------------------------------
    -- http_post: execute HTTP POST, return response CLOB, log call
    ---------------------------------------------------------------------------
    FUNCTION http_post(
        p_path        IN VARCHAR2,
        p_body        IN VARCHAR2,
        p_method_name IN VARCHAR2
    ) RETURN CLOB
    IS
        l_req        UTL_HTTP.REQ;
        l_resp       UTL_HTTP.RESP;
        l_body       CLOB;
        l_chunk      VARCHAR2(32767);
        l_status     PLS_INTEGER;
        l_start_ts   TIMESTAMP := SYSTIMESTAMP;
        l_elapsed_ms NUMBER;
        l_url        VARCHAR2(2000);
    BEGIN
        l_url := gv_base_url || p_path;

        -- Configure wallet for TLS
        IF gv_wallet_password IS NOT NULL THEN
            UTL_HTTP.SET_WALLET(gv_wallet_path, gv_wallet_password);
        ELSE
            UTL_HTTP.SET_WALLET(gv_wallet_path);
        END IF;

        UTL_HTTP.SET_TRANSFER_TIMEOUT(gv_timeout);

        -- Open request
        l_req := UTL_HTTP.BEGIN_REQUEST(
            url          => l_url,
            method       => 'POST',
            http_version => 'HTTP/1.1'
        );

        -- Set headers
        UTL_HTTP.SET_HEADER(l_req, 'Content-Type',  'application/json');
        UTL_HTTP.SET_HEADER(l_req, 'Accept',        'application/json');
        UTL_HTTP.SET_HEADER(l_req, 'X-Api-Key',         gv_api_key);
        UTL_HTTP.SET_HEADER(l_req, 'User-Agent',    qubiton_types.gc_user_agent);
        UTL_HTTP.SET_HEADER(l_req, 'Content-Length', LENGTHB(p_body));

        -- Write request body
        UTL_HTTP.WRITE_TEXT(l_req, p_body);

        -- Get response
        l_resp := UTL_HTTP.GET_RESPONSE(l_req);
        l_status := l_resp.status_code;

        -- Read response body into CLOB
        DBMS_LOB.CREATETEMPORARY(l_body, TRUE);
        BEGIN
            LOOP
                UTL_HTTP.READ_TEXT(l_resp, l_chunk, 32767);
                IF l_chunk IS NOT NULL AND LENGTH(l_chunk) > 0 THEN
                    DBMS_LOB.WRITEAPPEND(l_body, LENGTH(l_chunk), l_chunk);
                END IF;
            END LOOP;
        EXCEPTION
            WHEN UTL_HTTP.END_OF_BODY THEN
                NULL;
            WHEN OTHERS THEN
                BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
                RAISE;
        END;

        UTL_HTTP.END_RESPONSE(l_resp);

        -- Calculate elapsed time
        l_elapsed_ms := (EXTRACT(HOUR FROM (SYSTIMESTAMP - l_start_ts)) * 3600
                         + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_start_ts)) * 60
                         + EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts))) * 1000;

        -- Log the call
        log_call(p_method_name, p_path, l_status, l_elapsed_ms);

        -- Check for HTTP errors (free temp LOB before returning NULL)
        IF l_status = 429 THEN
            DBMS_LOB.FREETEMPORARY(l_body);
            handle_error(
                gc_err_rate_limited,
                p_method_name || ': rate limit exceeded (HTTP 429)',
                gv_error_mode
            );
            RETURN NULL;
        ELSIF l_status = 401 OR l_status = 403 THEN
            DBMS_LOB.FREETEMPORARY(l_body);
            handle_error(
                gc_err_http_status,
                p_method_name || ': authentication failed (HTTP ' || l_status || ')',
                gv_error_mode
            );
            RETURN NULL;
        ELSIF l_status < 200 OR l_status >= 300 THEN
            DECLARE
                l_err_msg VARCHAR2(500) := SUBSTR(DBMS_LOB.SUBSTR(l_body, 500, 1), 1, 500);
            BEGIN
                DBMS_LOB.FREETEMPORARY(l_body);
                handle_error(
                    gc_err_http_status,
                    p_method_name || ': HTTP ' || l_status || ': ' || l_err_msg,
                    gv_error_mode
                );
            END;
            RETURN NULL;
        END IF;

        RETURN l_body;

    EXCEPTION
        WHEN UTL_HTTP.TOO_MANY_REQUESTS THEN
            l_elapsed_ms := (EXTRACT(HOUR FROM (SYSTIMESTAMP - l_start_ts)) * 3600
                         + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_start_ts)) * 60
                         + EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts))) * 1000;
            log_call(p_method_name, p_path, 429, l_elapsed_ms, 'rate limit exceeded');
            IF DBMS_LOB.ISTEMPORARY(l_body) = 1 THEN DBMS_LOB.FREETEMPORARY(l_body); END IF;
            BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
            handle_error(gc_err_rate_limited, p_method_name || ': rate limit exceeded', gv_error_mode);
            RETURN NULL;
        WHEN UTL_HTTP.REQUEST_FAILED THEN
            l_elapsed_ms := (EXTRACT(HOUR FROM (SYSTIMESTAMP - l_start_ts)) * 3600
                         + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_start_ts)) * 60
                         + EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts))) * 1000;
            log_call(p_method_name, p_path, NULL, l_elapsed_ms, SQLERRM);
            IF l_body IS NOT NULL AND DBMS_LOB.ISTEMPORARY(l_body) = 1 THEN DBMS_LOB.FREETEMPORARY(l_body); END IF;
            BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
            handle_error(gc_err_http_request, p_method_name || ': request failed: ' || SQLERRM, gv_error_mode);
            RETURN NULL;
        WHEN OTHERS THEN
            l_elapsed_ms := (EXTRACT(HOUR FROM (SYSTIMESTAMP - l_start_ts)) * 3600
                         + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_start_ts)) * 60
                         + EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts))) * 1000;
            log_call(p_method_name, p_path, NULL, l_elapsed_ms, SQLERRM);
            IF l_body IS NOT NULL AND DBMS_LOB.ISTEMPORARY(l_body) = 1 THEN DBMS_LOB.FREETEMPORARY(l_body); END IF;
            BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
            RAISE;
    END http_post;

    ---------------------------------------------------------------------------
    -- http_get: execute HTTP GET, return response CLOB, log call
    ---------------------------------------------------------------------------
    FUNCTION http_get(
        p_path        IN VARCHAR2,
        p_method_name IN VARCHAR2
    ) RETURN CLOB
    IS
        l_req        UTL_HTTP.REQ;
        l_resp       UTL_HTTP.RESP;
        l_body       CLOB;
        l_chunk      VARCHAR2(32767);
        l_status     PLS_INTEGER;
        l_start_ts   TIMESTAMP := SYSTIMESTAMP;
        l_elapsed_ms NUMBER;
        l_url        VARCHAR2(2000);
    BEGIN
        l_url := gv_base_url || p_path;

        -- Configure wallet for TLS
        IF gv_wallet_password IS NOT NULL THEN
            UTL_HTTP.SET_WALLET(gv_wallet_path, gv_wallet_password);
        ELSE
            UTL_HTTP.SET_WALLET(gv_wallet_path);
        END IF;

        UTL_HTTP.SET_TRANSFER_TIMEOUT(gv_timeout);

        -- Open request
        l_req := UTL_HTTP.BEGIN_REQUEST(
            url          => l_url,
            method       => 'GET',
            http_version => 'HTTP/1.1'
        );

        -- Set headers
        UTL_HTTP.SET_HEADER(l_req, 'Accept',     'application/json');
        UTL_HTTP.SET_HEADER(l_req, 'X-Api-Key',      gv_api_key);
        UTL_HTTP.SET_HEADER(l_req, 'User-Agent', qubiton_types.gc_user_agent);

        -- Get response
        l_resp := UTL_HTTP.GET_RESPONSE(l_req);
        l_status := l_resp.status_code;

        -- Read response body into CLOB
        DBMS_LOB.CREATETEMPORARY(l_body, TRUE);
        BEGIN
            LOOP
                UTL_HTTP.READ_TEXT(l_resp, l_chunk, 32767);
                IF l_chunk IS NOT NULL AND LENGTH(l_chunk) > 0 THEN
                    DBMS_LOB.WRITEAPPEND(l_body, LENGTH(l_chunk), l_chunk);
                END IF;
            END LOOP;
        EXCEPTION
            WHEN UTL_HTTP.END_OF_BODY THEN
                NULL;
            WHEN OTHERS THEN
                BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
                RAISE;
        END;

        UTL_HTTP.END_RESPONSE(l_resp);

        -- Calculate elapsed time
        l_elapsed_ms := (EXTRACT(HOUR FROM (SYSTIMESTAMP - l_start_ts)) * 3600
                         + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_start_ts)) * 60
                         + EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts))) * 1000;

        -- Log the call
        log_call(p_method_name, p_path, l_status, l_elapsed_ms, p_http_method => 'GET');

        -- Check for HTTP errors (free temp LOB before returning NULL)
        IF l_status = 429 THEN
            DBMS_LOB.FREETEMPORARY(l_body);
            handle_error(gc_err_rate_limited, p_method_name || ': rate limit exceeded (HTTP 429)', gv_error_mode);
            RETURN NULL;
        ELSIF l_status = 401 OR l_status = 403 THEN
            DBMS_LOB.FREETEMPORARY(l_body);
            handle_error(gc_err_http_status, p_method_name || ': authentication failed (HTTP ' || l_status || ')', gv_error_mode);
            RETURN NULL;
        ELSIF l_status < 200 OR l_status >= 300 THEN
            DECLARE
                l_err_msg VARCHAR2(500) := SUBSTR(DBMS_LOB.SUBSTR(l_body, 500, 1), 1, 500);
            BEGIN
                DBMS_LOB.FREETEMPORARY(l_body);
                handle_error(
                    gc_err_http_status,
                    p_method_name || ': HTTP ' || l_status || ': ' || l_err_msg,
                    gv_error_mode
                );
            END;
            RETURN NULL;
        END IF;

        RETURN l_body;

    EXCEPTION
        WHEN UTL_HTTP.TOO_MANY_REQUESTS THEN
            l_elapsed_ms := (EXTRACT(HOUR FROM (SYSTIMESTAMP - l_start_ts)) * 3600
                         + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_start_ts)) * 60
                         + EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts))) * 1000;
            log_call(p_method_name, p_path, 429, l_elapsed_ms, 'rate limit exceeded', 'GET');
            IF DBMS_LOB.ISTEMPORARY(l_body) = 1 THEN DBMS_LOB.FREETEMPORARY(l_body); END IF;
            BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
            handle_error(gc_err_rate_limited, p_method_name || ': rate limit exceeded', gv_error_mode);
            RETURN NULL;
        WHEN UTL_HTTP.REQUEST_FAILED THEN
            l_elapsed_ms := (EXTRACT(HOUR FROM (SYSTIMESTAMP - l_start_ts)) * 3600
                         + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_start_ts)) * 60
                         + EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts))) * 1000;
            log_call(p_method_name, p_path, NULL, l_elapsed_ms, SQLERRM, 'GET');
            IF l_body IS NOT NULL AND DBMS_LOB.ISTEMPORARY(l_body) = 1 THEN DBMS_LOB.FREETEMPORARY(l_body); END IF;
            BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
            handle_error(gc_err_http_request, p_method_name || ': request failed: ' || SQLERRM, gv_error_mode);
            RETURN NULL;
        WHEN OTHERS THEN
            l_elapsed_ms := (EXTRACT(HOUR FROM (SYSTIMESTAMP - l_start_ts)) * 3600
                         + EXTRACT(MINUTE FROM (SYSTIMESTAMP - l_start_ts)) * 60
                         + EXTRACT(SECOND FROM (SYSTIMESTAMP - l_start_ts))) * 1000;
            log_call(p_method_name, p_path, NULL, l_elapsed_ms, SQLERRM, 'GET');
            IF l_body IS NOT NULL AND DBMS_LOB.ISTEMPORARY(l_body) = 1 THEN DBMS_LOB.FREETEMPORARY(l_body); END IF;
            BEGIN UTL_HTTP.END_RESPONSE(l_resp); EXCEPTION WHEN OTHERS THEN NULL; END;
            RAISE;
    END http_get;

    ---------------------------------------------------------------------------
    -- PUBLIC: init
    ---------------------------------------------------------------------------
    PROCEDURE init(
        p_api_key         IN VARCHAR2 DEFAULT NULL,
        p_base_url        IN VARCHAR2 DEFAULT NULL,
        p_wallet_path     IN VARCHAR2 DEFAULT NULL,
        p_wallet_password IN VARCHAR2 DEFAULT NULL,
        p_timeout         IN PLS_INTEGER DEFAULT NULL,
        p_error_mode      IN VARCHAR2 DEFAULT NULL,
        p_log_enabled     IN BOOLEAN DEFAULT NULL
    )
    IS
    BEGIN
        -- First try loading from config table (ignore errors if table missing)
        BEGIN
            FOR rec IN (SELECT config_key, config_value FROM qubiton_config) LOOP
                CASE UPPER(rec.config_key)
                    WHEN 'APIKEY'          THEN gv_api_key         := rec.config_value;
                    WHEN 'API_KEY'         THEN gv_api_key         := rec.config_value;
                    WHEN 'BASE_URL'        THEN gv_base_url        := rec.config_value;
                    WHEN 'WALLET_PATH'     THEN gv_wallet_path     := rec.config_value;
                    WHEN 'WALLET_PASSWORD' THEN gv_wallet_password := rec.config_value;
                    WHEN 'TIMEOUT'         THEN gv_timeout         := TO_NUMBER(rec.config_value);
                    WHEN 'ERROR_MODE'      THEN gv_error_mode      := UPPER(SUBSTR(rec.config_value, 1, 1));
                    WHEN 'LOG_ENABLED'     THEN gv_log_enabled     := UPPER(rec.config_value) IN ('Y', 'YES', 'TRUE', '1');
                    ELSE NULL;
                END CASE;
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;

        -- Override with explicit params
        IF p_api_key IS NOT NULL THEN
            gv_api_key := p_api_key;
        END IF;
        IF p_base_url IS NOT NULL THEN
            gv_base_url := p_base_url;
        END IF;
        IF p_wallet_path IS NOT NULL THEN
            gv_wallet_path := p_wallet_path;
        END IF;
        IF p_wallet_password IS NOT NULL THEN
            gv_wallet_password := p_wallet_password;
        END IF;
        IF p_timeout IS NOT NULL THEN
            gv_timeout := p_timeout;
        END IF;
        IF p_error_mode IS NOT NULL THEN
            gv_error_mode := UPPER(SUBSTR(p_error_mode, 1, 1));
        END IF;
        IF p_log_enabled IS NOT NULL THEN
            gv_log_enabled := p_log_enabled;
        END IF;

        -- Strip trailing slash from base URL
        IF gv_base_url IS NOT NULL AND SUBSTR(gv_base_url, -1) = '/' THEN
            gv_base_url := SUBSTR(gv_base_url, 1, LENGTH(gv_base_url) - 1);
        END IF;

        IF gv_api_key IS NULL THEN
            RAISE_APPLICATION_ERROR(
                gc_err_config_missing,
                'API key is required: pass p_api_key or set APIKEY in QUBITON_CONFIG'
            );
        END IF;

        gv_initialized := TRUE;
    END init;

    ---------------------------------------------------------------------------
    -- PUBLIC: build_json
    ---------------------------------------------------------------------------
    FUNCTION build_json(
        p_pairs IN tt_name_value
    ) RETURN VARCHAR2
    IS
        lv_json VARCHAR2(32767) := '{';
        lv_sep  VARCHAR2(1)     := '';
        lv_idx  PLS_INTEGER;
    BEGIN
        lv_idx := p_pairs.FIRST;
        WHILE lv_idx IS NOT NULL LOOP
            json_add(lv_json, lv_sep, p_pairs(lv_idx).name, p_pairs(lv_idx).value, p_pairs(lv_idx).vtype);
            lv_idx := p_pairs.NEXT(lv_idx);
        END LOOP;
        lv_json := lv_json || '}';
        RETURN lv_json;
    END build_json;

    ---------------------------------------------------------------------------
    -- PUBLIC: parse_result
    ---------------------------------------------------------------------------
    FUNCTION parse_result(
        p_json       IN CLOB,
        p_field_name IN VARCHAR2 DEFAULT 'isValid'
    ) RETURN qubiton_types.t_result
    IS
        lv_result qubiton_types.t_result;
        lv_value  VARCHAR2(4000);
        lv_msg    VARCHAR2(4000);
    BEGIN
        lv_result.success       := FALSE;
        lv_result.is_valid      := FALSE;
        lv_result.message       := NULL;
        lv_result.field_missing := TRUE;
        lv_result.blocked       := FALSE;

        IF p_json IS NULL OR DBMS_LOB.GETLENGTH(p_json) = 0 THEN
            lv_result.message := 'no response received';
            RETURN lv_result;
        END IF;

        -- The call succeeded (we got a response)
        lv_result.success := TRUE;

        -- Extract the requested field
        lv_value := extract_json_value(p_json, p_field_name);

        IF lv_value IS NOT NULL THEN
            lv_result.field_missing := FALSE;
            lv_result.is_valid := LOWER(lv_value) = 'true';
        END IF;

        -- Try to extract a message field
        lv_msg := extract_json_value(p_json, 'message');
        IF lv_msg IS NULL THEN
            lv_msg := extract_json_value(p_json, 'errorMessage');
        END IF;
        IF lv_msg IS NULL THEN
            lv_msg := extract_json_value(p_json, 'statusMessage');
        END IF;
        lv_result.message := lv_msg;

        RETURN lv_result;
    END parse_result;

    ---------------------------------------------------------------------------
    -- PUBLIC: handle_result
    ---------------------------------------------------------------------------
    FUNCTION handle_result(
        p_json       IN CLOB,
        p_field_name IN VARCHAR2 DEFAULT 'isValid',
        p_error_mode IN VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result
    IS
        lv_result qubiton_types.t_result;
        lv_mode   VARCHAR2(1) := NVL(p_error_mode, gv_error_mode);
    BEGIN
        lv_result := parse_result(p_json, p_field_name);
        lv_result.blocked := FALSE;

        IF NOT lv_result.success THEN
            -- API call failed — set blocked based on error mode
            IF UPPER(lv_mode) = 'E' THEN
                lv_result.blocked := TRUE;
            END IF;
            IF UPPER(lv_mode) = 'W' THEN
                DBMS_OUTPUT.PUT_LINE(
                    'WARNING: API call failed: ' || NVL(lv_result.message, 'unknown error')
                );
            END IF;
        ELSIF NOT lv_result.is_valid AND NOT lv_result.field_missing THEN
            -- Validation failed — set blocked, issue warning if applicable
            IF UPPER(lv_mode) = 'E' THEN
                lv_result.blocked := TRUE;
            END IF;
            IF UPPER(lv_mode) = 'W' THEN
                DBMS_OUTPUT.PUT_LINE(
                    'WARNING: validation failed: ' || NVL(lv_result.message, 'not valid')
                );
            END IF;
        END IF;

        RETURN lv_result;
    END handle_result;

    ---------------------------------------------------------------------------
    -- PUBLIC: test_connection
    ---------------------------------------------------------------------------
    FUNCTION test_connection RETURN VARCHAR2
    IS
        l_resp CLOB;
    BEGIN
        ensure_init;

        BEGIN
            l_resp := http_get('/healthz', 'test_connection');

            IF l_resp IS NOT NULL THEN
                RETURN 'OK: connected to ' || gv_base_url;
            ELSE
                RETURN 'FAIL: no response from ' || gv_base_url;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN 'FAIL: ' || SQLERRM;
        END;
    END test_connection;

    ---------------------------------------------------------------------------
    -- ADDRESS (1)
    ---------------------------------------------------------------------------

    -- POST /api/address/validate
    FUNCTION validate_address(
        p_country       IN VARCHAR2,
        p_address_line1 IN VARCHAR2 DEFAULT NULL,
        p_address_line2 IN VARCHAR2 DEFAULT NULL,
        p_city          IN VARCHAR2 DEFAULT NULL,
        p_state         IN VARCHAR2 DEFAULT NULL,
        p_postal_code   IN VARCHAR2 DEFAULT NULL,
        p_company_name  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_country, 'p_country', 'validate_address');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'country',      p_country);
        json_add(lv_body, lv_sep, 'addressLine1', p_address_line1);
        json_add(lv_body, lv_sep, 'addressLine2', p_address_line2);
        json_add(lv_body, lv_sep, 'city',         p_city);
        json_add(lv_body, lv_sep, 'state',        p_state);
        json_add(lv_body, lv_sep, 'postalCode',   p_postal_code);
        json_add(lv_body, lv_sep, 'companyName',  p_company_name);
        lv_body := lv_body || '}';

        RETURN http_post('/api/address/validate', lv_body, 'validate_address');
    END validate_address;

    ---------------------------------------------------------------------------
    -- TAX (2)
    ---------------------------------------------------------------------------

    -- POST /api/tax/validate
    FUNCTION validate_tax(
        p_tax_number          IN VARCHAR2,
        p_tax_type            IN VARCHAR2,
        p_country             IN VARCHAR2,
        p_company_name        IN VARCHAR2,
        p_business_entity_type IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_tax_number, 'p_tax_number', 'validate_tax');
        require_param(p_tax_type, 'p_tax_type', 'validate_tax');
        require_param(p_country, 'p_country', 'validate_tax');
        require_param(p_company_name, 'p_company_name', 'validate_tax');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'identityNumber',     p_tax_number);
        json_add(lv_body, lv_sep, 'identityNumberType', p_tax_type);
        json_add(lv_body, lv_sep, 'country',            p_country);
        json_add(lv_body, lv_sep, 'companyName',        p_company_name);
        json_add(lv_body, lv_sep, 'businessEntityType', p_business_entity_type);
        lv_body := lv_body || '}';

        RETURN http_post('/api/tax/validate', lv_body, 'validate_tax');
    END validate_tax;

    -- POST /api/tax/format-validate
    FUNCTION validate_tax_format(
        p_tax_number IN VARCHAR2,
        p_tax_type   IN VARCHAR2,
        p_country    IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_tax_number, 'p_tax_number', 'validate_tax_format');
        require_param(p_tax_type, 'p_tax_type', 'validate_tax_format');
        require_param(p_country, 'p_country', 'validate_tax_format');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'identityNumber',     p_tax_number);
        json_add(lv_body, lv_sep, 'identityNumberType', p_tax_type);
        json_add(lv_body, lv_sep, 'countryIso2',        p_country);
        lv_body := lv_body || '}';

        RETURN http_post('/api/tax/format-validate', lv_body, 'validate_tax_format');
    END validate_tax_format;

    ---------------------------------------------------------------------------
    -- BANK (2)
    ---------------------------------------------------------------------------

    -- POST /api/bankaccount/validate
    FUNCTION validate_bank_account(
        p_business_entity_type IN VARCHAR2,
        p_country              IN VARCHAR2,
        p_bank_account_holder  IN VARCHAR2,
        p_account_number       IN VARCHAR2 DEFAULT NULL,
        p_business_name        IN VARCHAR2 DEFAULT NULL,
        p_tax_id_number        IN VARCHAR2 DEFAULT NULL,
        p_tax_type             IN VARCHAR2 DEFAULT NULL,
        p_bank_code            IN VARCHAR2 DEFAULT NULL,
        p_iban                 IN VARCHAR2 DEFAULT NULL,
        p_swift_code           IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_business_entity_type, 'p_business_entity_type', 'validate_bank_account');
        require_param(p_country, 'p_country', 'validate_bank_account');
        require_param(p_bank_account_holder, 'p_bank_account_holder', 'validate_bank_account');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'businessEntityType', p_business_entity_type);
        json_add(lv_body, lv_sep, 'country',            p_country);
        json_add(lv_body, lv_sep, 'bankAccountHolder',  p_bank_account_holder);
        json_add(lv_body, lv_sep, 'accountNumber',      p_account_number);
        json_add(lv_body, lv_sep, 'businessName',       p_business_name);
        json_add(lv_body, lv_sep, 'taxIdNumber',        p_tax_id_number);
        json_add(lv_body, lv_sep, 'taxType',            p_tax_type);
        json_add(lv_body, lv_sep, 'bankCode',           p_bank_code);
        json_add(lv_body, lv_sep, 'iban',               p_iban);
        json_add(lv_body, lv_sep, 'swiftCode',          p_swift_code);
        lv_body := lv_body || '}';

        RETURN http_post('/api/bankaccount/validate', lv_body, 'validate_bank_account');
    END validate_bank_account;

    -- POST /api/bankaccount/pro/validate
    FUNCTION validate_bank_pro(
        p_business_entity_type IN VARCHAR2,
        p_country              IN VARCHAR2,
        p_bank_account_holder  IN VARCHAR2,
        p_account_number       IN VARCHAR2 DEFAULT NULL,
        p_bank_code            IN VARCHAR2 DEFAULT NULL,
        p_iban                 IN VARCHAR2 DEFAULT NULL,
        p_swift_code           IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_business_entity_type, 'p_business_entity_type', 'validate_bank_pro');
        require_param(p_country, 'p_country', 'validate_bank_pro');
        require_param(p_bank_account_holder, 'p_bank_account_holder', 'validate_bank_pro');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'businessEntityType', p_business_entity_type);
        json_add(lv_body, lv_sep, 'country',            p_country);
        json_add(lv_body, lv_sep, 'bankAccountHolder',  p_bank_account_holder);
        json_add(lv_body, lv_sep, 'accountNumber',      p_account_number);
        json_add(lv_body, lv_sep, 'bankCode',           p_bank_code);
        json_add(lv_body, lv_sep, 'iban',               p_iban);
        json_add(lv_body, lv_sep, 'swiftCode',          p_swift_code);
        lv_body := lv_body || '}';

        RETURN http_post('/api/bankaccount/pro/validate', lv_body, 'validate_bank_pro');
    END validate_bank_pro;

    ---------------------------------------------------------------------------
    -- EMAIL & PHONE (2)
    ---------------------------------------------------------------------------

    -- POST /api/email/validate
    FUNCTION validate_email(
        p_email_address IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_email_address, 'p_email_address', 'validate_email');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'emailAddress', p_email_address);
        lv_body := lv_body || '}';

        RETURN http_post('/api/email/validate', lv_body, 'validate_email');
    END validate_email;

    -- POST /api/phone/validate
    FUNCTION validate_phone(
        p_phone_number    IN VARCHAR2,
        p_country         IN VARCHAR2,
        p_phone_extension IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_phone_number, 'p_phone_number', 'validate_phone');
        require_param(p_country, 'p_country', 'validate_phone');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'phoneNumber',    p_phone_number);
        json_add(lv_body, lv_sep, 'country',        p_country);
        json_add(lv_body, lv_sep, 'phoneExtension', p_phone_extension);
        lv_body := lv_body || '}';

        RETURN http_post('/api/phone/validate', lv_body, 'validate_phone');
    END validate_phone;

    ---------------------------------------------------------------------------
    -- BUSINESS REGISTRATION (1)
    ---------------------------------------------------------------------------

    -- POST /api/businessregistration/lookup
    FUNCTION lookup_business_registration(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2,
        p_state        IN VARCHAR2 DEFAULT NULL,
        p_city         IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_business_registration');
        require_param(p_country, 'p_country', 'lookup_business_registration');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'entityName', p_company_name);
        json_add(lv_body, lv_sep, 'country',    p_country);
        json_add(lv_body, lv_sep, 'state',      p_state);
        json_add(lv_body, lv_sep, 'city',       p_city);
        lv_body := lv_body || '}';

        RETURN http_post('/api/businessregistration/lookup', lv_body, 'lookup_business_registration');
    END lookup_business_registration;

    ---------------------------------------------------------------------------
    -- PEPPOL (1)
    ---------------------------------------------------------------------------

    -- POST /api/peppol/validate
    FUNCTION validate_peppol(
        p_participant_id   IN VARCHAR2,
        p_directory_lookup IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_participant_id, 'p_participant_id', 'validate_peppol');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'participantId',   p_participant_id);
        json_add(lv_body, lv_sep, 'directoryLookup', p_directory_lookup, 'B');
        lv_body := lv_body || '}';

        RETURN http_post('/api/peppol/validate', lv_body, 'validate_peppol');
    END validate_peppol;

    ---------------------------------------------------------------------------
    -- SANCTIONS & COMPLIANCE (3)
    ---------------------------------------------------------------------------

    -- POST /api/prohibited/lookup
    FUNCTION check_sanctions(
        p_company_name  IN VARCHAR2,
        p_country       IN VARCHAR2,
        p_address_line1 IN VARCHAR2 DEFAULT NULL,
        p_address_line2 IN VARCHAR2 DEFAULT NULL,
        p_city          IN VARCHAR2 DEFAULT NULL,
        p_state         IN VARCHAR2 DEFAULT NULL,
        p_postal_code   IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'check_sanctions');
        require_param(p_country, 'p_country', 'check_sanctions');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName',  p_company_name);
        json_add(lv_body, lv_sep, 'country',      p_country);
        json_add(lv_body, lv_sep, 'addressLine1', p_address_line1);
        json_add(lv_body, lv_sep, 'addressLine2', p_address_line2);
        json_add(lv_body, lv_sep, 'city',         p_city);
        json_add(lv_body, lv_sep, 'state',        p_state);
        json_add(lv_body, lv_sep, 'postalCode',   p_postal_code);
        lv_body := lv_body || '}';

        RETURN http_post('/api/prohibited/lookup', lv_body, 'check_sanctions');
    END check_sanctions;

    -- POST /api/pep/lookup
    FUNCTION screen_pep(
        p_name    IN VARCHAR2,
        p_country IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_name, 'p_name', 'screen_pep');
        require_param(p_country, 'p_country', 'screen_pep');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'name',    p_name);
        json_add(lv_body, lv_sep, 'country', p_country);
        lv_body := lv_body || '}';

        RETURN http_post('/api/pep/lookup', lv_body, 'screen_pep');
    END screen_pep;

    -- POST /api/disqualifieddirectors/validate
    FUNCTION check_directors(
        p_first_name  IN VARCHAR2,
        p_last_name   IN VARCHAR2,
        p_country     IN VARCHAR2,
        p_middle_name IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_first_name, 'p_first_name', 'check_directors');
        require_param(p_last_name, 'p_last_name', 'check_directors');
        require_param(p_country, 'p_country', 'check_directors');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'firstName',  p_first_name);
        json_add(lv_body, lv_sep, 'lastName',   p_last_name);
        json_add(lv_body, lv_sep, 'country',    p_country);
        json_add(lv_body, lv_sep, 'middleName', p_middle_name);
        lv_body := lv_body || '}';

        RETURN http_post('/api/disqualifieddirectors/validate', lv_body, 'check_directors');
    END check_directors;

    ---------------------------------------------------------------------------
    -- EPA (2)
    ---------------------------------------------------------------------------

    -- POST /api/criminalprosecution/validate
    FUNCTION check_epa_prosecution(
        p_name        IN VARCHAR2 DEFAULT NULL,
        p_state       IN VARCHAR2 DEFAULT NULL,
        p_fiscal_year IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;

        lv_body := '{';
        json_add(lv_body, lv_sep, 'name',       p_name);
        json_add(lv_body, lv_sep, 'state',      p_state);
        json_add(lv_body, lv_sep, 'fiscalYear', p_fiscal_year);
        lv_body := lv_body || '}';

        RETURN http_post('/api/criminalprosecution/validate', lv_body, 'check_epa_prosecution');
    END check_epa_prosecution;

    -- POST /api/criminalprosecution/lookup
    FUNCTION lookup_epa_prosecution(
        p_name        IN VARCHAR2 DEFAULT NULL,
        p_state       IN VARCHAR2 DEFAULT NULL,
        p_fiscal_year IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;

        lv_body := '{';
        json_add(lv_body, lv_sep, 'name',       p_name);
        json_add(lv_body, lv_sep, 'state',      p_state);
        json_add(lv_body, lv_sep, 'fiscalYear', p_fiscal_year);
        lv_body := lv_body || '}';

        RETURN http_post('/api/criminalprosecution/lookup', lv_body, 'lookup_epa_prosecution');
    END lookup_epa_prosecution;

    ---------------------------------------------------------------------------
    -- HEALTHCARE (2)
    ---------------------------------------------------------------------------

    -- POST /api/providerexclusion/validate
    FUNCTION check_healthcare_exclusion(
        p_health_care_type IN VARCHAR2,
        p_entity_name      IN VARCHAR2 DEFAULT NULL,
        p_last_name        IN VARCHAR2 DEFAULT NULL,
        p_first_name       IN VARCHAR2 DEFAULT NULL,
        p_address          IN VARCHAR2 DEFAULT NULL,
        p_city             IN VARCHAR2 DEFAULT NULL,
        p_state            IN VARCHAR2 DEFAULT NULL,
        p_zip_code         IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_health_care_type, 'p_health_care_type', 'check_healthcare_exclusion');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'healthCareType', p_health_care_type);
        json_add(lv_body, lv_sep, 'entityName',     p_entity_name);
        json_add(lv_body, lv_sep, 'lastName',       p_last_name);
        json_add(lv_body, lv_sep, 'firstName',      p_first_name);
        json_add(lv_body, lv_sep, 'address',        p_address);
        json_add(lv_body, lv_sep, 'city',           p_city);
        json_add(lv_body, lv_sep, 'state',          p_state);
        json_add(lv_body, lv_sep, 'zipCode',        p_zip_code);
        lv_body := lv_body || '}';

        RETURN http_post('/api/providerexclusion/validate', lv_body, 'check_healthcare_exclusion');
    END check_healthcare_exclusion;

    -- POST /api/providerexclusion/lookup
    FUNCTION lookup_healthcare_exclusion(
        p_health_care_type IN VARCHAR2,
        p_entity_name      IN VARCHAR2 DEFAULT NULL,
        p_last_name        IN VARCHAR2 DEFAULT NULL,
        p_first_name       IN VARCHAR2 DEFAULT NULL,
        p_address          IN VARCHAR2 DEFAULT NULL,
        p_city             IN VARCHAR2 DEFAULT NULL,
        p_state            IN VARCHAR2 DEFAULT NULL,
        p_zip_code         IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_health_care_type, 'p_health_care_type', 'lookup_healthcare_exclusion');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'healthCareType', p_health_care_type);
        json_add(lv_body, lv_sep, 'entityName',     p_entity_name);
        json_add(lv_body, lv_sep, 'lastName',       p_last_name);
        json_add(lv_body, lv_sep, 'firstName',      p_first_name);
        json_add(lv_body, lv_sep, 'address',        p_address);
        json_add(lv_body, lv_sep, 'city',           p_city);
        json_add(lv_body, lv_sep, 'state',          p_state);
        json_add(lv_body, lv_sep, 'zipCode',        p_zip_code);
        lv_body := lv_body || '}';

        RETURN http_post('/api/providerexclusion/lookup', lv_body, 'lookup_healthcare_exclusion');
    END lookup_healthcare_exclusion;

    ---------------------------------------------------------------------------
    -- RISK & FINANCIAL (5)
    ---------------------------------------------------------------------------

    -- POST /api/risk/lookup (category = Bankruptcy)
    FUNCTION check_bankruptcy_risk(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'check_bankruptcy_risk');
        require_param(p_country, 'p_country', 'check_bankruptcy_risk');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'entityName', p_company_name);
        json_add(lv_body, lv_sep, 'country',    p_country);
        json_add(lv_body, lv_sep, 'category',   'Bankruptcy');
        lv_body := lv_body || '}';

        RETURN http_post('/api/risk/lookup', lv_body, 'check_bankruptcy_risk');
    END check_bankruptcy_risk;

    -- POST /api/risk/lookup (category = Credit Score)
    FUNCTION lookup_credit_score(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_credit_score');
        require_param(p_country, 'p_country', 'lookup_credit_score');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'entityName', p_company_name);
        json_add(lv_body, lv_sep, 'country',    p_country);
        json_add(lv_body, lv_sep, 'category',   'Credit Score');
        lv_body := lv_body || '}';

        RETURN http_post('/api/risk/lookup', lv_body, 'lookup_credit_score');
    END lookup_credit_score;

    -- POST /api/risk/lookup (category = Fail Rate)
    FUNCTION lookup_fail_rate(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_fail_rate');
        require_param(p_country, 'p_country', 'lookup_fail_rate');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'entityName', p_company_name);
        json_add(lv_body, lv_sep, 'country',    p_country);
        json_add(lv_body, lv_sep, 'category',   'Fail Rate');
        lv_body := lv_body || '}';

        RETURN http_post('/api/risk/lookup', lv_body, 'lookup_fail_rate');
    END lookup_fail_rate;

    -- POST /api/entity/fraud/lookup
    FUNCTION assess_entity_risk(
        p_company_name             IN VARCHAR2,
        p_country_of_incorporation IN VARCHAR2 DEFAULT NULL,
        p_category                 IN VARCHAR2 DEFAULT NULL,
        p_url                      IN VARCHAR2 DEFAULT NULL,
        p_business_entity_type     IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'assess_entity_risk');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName',            p_company_name);
        json_add(lv_body, lv_sep, 'CountryOfIncorporation', p_country_of_incorporation);
        json_add(lv_body, lv_sep, 'category',               p_category);
        json_add(lv_body, lv_sep, 'url',                    p_url);
        json_add(lv_body, lv_sep, 'businessEntityType',     p_business_entity_type);
        lv_body := lv_body || '}';

        RETURN http_post('/api/entity/fraud/lookup', lv_body, 'assess_entity_risk');
    END assess_entity_risk;

    -- POST /api/creditanalysis/lookup
    FUNCTION lookup_credit_analysis(
        p_company_name  IN VARCHAR2,
        p_address_line1 IN VARCHAR2,
        p_city          IN VARCHAR2,
        p_state         IN VARCHAR2,
        p_country       IN VARCHAR2,
        p_duns_number   IN VARCHAR2 DEFAULT NULL,
        p_postal_code   IN VARCHAR2 DEFAULT NULL,
        p_address_line2 IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_credit_analysis');
        require_param(p_address_line1, 'p_address_line1', 'lookup_credit_analysis');
        require_param(p_city, 'p_city', 'lookup_credit_analysis');
        require_param(p_state, 'p_state', 'lookup_credit_analysis');
        require_param(p_country, 'p_country', 'lookup_credit_analysis');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName',  p_company_name);
        json_add(lv_body, lv_sep, 'addressLine1', p_address_line1);
        json_add(lv_body, lv_sep, 'city',         p_city);
        json_add(lv_body, lv_sep, 'state',        p_state);
        json_add(lv_body, lv_sep, 'country',      p_country);
        json_add(lv_body, lv_sep, 'dunsNumber',   p_duns_number);
        json_add(lv_body, lv_sep, 'postalCode',   p_postal_code);
        json_add(lv_body, lv_sep, 'addressLine2', p_address_line2);
        lv_body := lv_body || '}';

        RETURN http_post('/api/creditanalysis/lookup', lv_body, 'lookup_credit_analysis');
    END lookup_credit_analysis;

    ---------------------------------------------------------------------------
    -- ESG & CYBERSECURITY (3)
    ---------------------------------------------------------------------------

    -- POST /api/esg/Scores
    FUNCTION lookup_esg_score(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2,
        p_domain       IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
        lv_path VARCHAR2(4000);
        lv_qs   VARCHAR2(4000);
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_esg_score');
        require_param(p_country, 'p_country', 'lookup_esg_score');

        -- country and domain are bound as [FromQuery] on the API controller,
        -- not body fields. Build them into the URL with safe escaping.
        IF p_country IS NOT NULL THEN
            lv_qs := '?country=' || UTL_URL.escape(p_country, escape_reserved_chars => TRUE);
        END IF;
        IF p_domain IS NOT NULL THEN
            IF lv_qs IS NULL THEN
                lv_qs := '?domain=' || UTL_URL.escape(p_domain, escape_reserved_chars => TRUE);
            ELSE
                lv_qs := lv_qs || '&domain=' || UTL_URL.escape(p_domain, escape_reserved_chars => TRUE);
            END IF;
        END IF;
        lv_path := '/api/esg/Scores' || lv_qs;

        -- Body contains only companyName.
        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName', p_company_name);
        lv_body := lv_body || '}';

        RETURN http_post(lv_path, lv_body, 'lookup_esg_score');
    END lookup_esg_score;

    -- POST /api/itsecurity/domainreport
    FUNCTION domain_security_report(
        p_domain IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_domain, 'p_domain', 'domain_security_report');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'domain', p_domain);
        lv_body := lv_body || '}';

        RETURN http_post('/api/itsecurity/domainreport', lv_body, 'domain_security_report');
    END domain_security_report;

    -- POST /api/ipquality/validate
    FUNCTION check_ip_quality(
        p_ip_address IN VARCHAR2,
        p_user_agent IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_ip_address, 'p_ip_address', 'check_ip_quality');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'ipAddress', p_ip_address);
        json_add(lv_body, lv_sep, 'userAgent', p_user_agent);
        lv_body := lv_body || '}';

        RETURN http_post('/api/ipquality/validate', lv_body, 'check_ip_quality');
    END check_ip_quality;

    ---------------------------------------------------------------------------
    -- CORPORATE STRUCTURE (4)
    ---------------------------------------------------------------------------

    -- POST /api/beneficialownership/lookup
    FUNCTION lookup_beneficial_ownership(
        p_company_name  IN VARCHAR2,
        p_country_iso2  IN VARCHAR2,
        p_ubo_threshold IN VARCHAR2 DEFAULT NULL,
        p_max_layers    IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_beneficial_ownership');
        require_param(p_country_iso2, 'p_country_iso2', 'lookup_beneficial_ownership');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName',  p_company_name);
        json_add(lv_body, lv_sep, 'countryIso2',  p_country_iso2);
        json_add(lv_body, lv_sep, 'uboThreshold', p_ubo_threshold);
        json_add(lv_body, lv_sep, 'maxLayers',    p_max_layers);
        lv_body := lv_body || '}';

        RETURN http_post('/api/beneficialownership/lookup', lv_body, 'lookup_beneficial_ownership');
    END lookup_beneficial_ownership;

    -- POST /api/corporatehierarchy/lookup
    FUNCTION lookup_corporate_hierarchy(
        p_company_name  IN VARCHAR2,
        p_address_line1 IN VARCHAR2,
        p_city          IN VARCHAR2,
        p_state         IN VARCHAR2,
        p_zip_code      IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_corporate_hierarchy');
        require_param(p_address_line1, 'p_address_line1', 'lookup_corporate_hierarchy');
        require_param(p_city, 'p_city', 'lookup_corporate_hierarchy');
        require_param(p_state, 'p_state', 'lookup_corporate_hierarchy');
        require_param(p_zip_code, 'p_zip_code', 'lookup_corporate_hierarchy');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName',  p_company_name);
        json_add(lv_body, lv_sep, 'addressLine1', p_address_line1);
        json_add(lv_body, lv_sep, 'city',         p_city);
        json_add(lv_body, lv_sep, 'state',        p_state);
        json_add(lv_body, lv_sep, 'zipCode',      p_zip_code);
        lv_body := lv_body || '}';

        RETURN http_post('/api/corporatehierarchy/lookup', lv_body, 'lookup_corporate_hierarchy');
    END lookup_corporate_hierarchy;

    -- POST /api/duns-number-lookup
    FUNCTION lookup_duns(
        p_duns_number IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_duns_number, 'p_duns_number', 'lookup_duns');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'dunsNumber', p_duns_number);
        lv_body := lv_body || '}';

        RETURN http_post('/api/duns-number-lookup', lv_body, 'lookup_duns');
    END lookup_duns;

    -- POST /api/company/hierarchy/lookup
    FUNCTION lookup_hierarchy(
        p_identifier      IN VARCHAR2,
        p_identifier_type IN VARCHAR2,
        p_country         IN VARCHAR2 DEFAULT NULL,
        p_options         IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_identifier, 'p_identifier', 'lookup_hierarchy');
        require_param(p_identifier_type, 'p_identifier_type', 'lookup_hierarchy');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'identifier',     p_identifier);
        json_add(lv_body, lv_sep, 'identifierType', p_identifier_type);
        json_add(lv_body, lv_sep, 'country',        p_country);
        json_add(lv_body, lv_sep, 'options',        p_options);
        lv_body := lv_body || '}';

        RETURN http_post('/api/company/hierarchy/lookup', lv_body, 'lookup_hierarchy');
    END lookup_hierarchy;

    ---------------------------------------------------------------------------
    -- INDUSTRY (4)
    ---------------------------------------------------------------------------

    -- POST /api/nationalprovideridentifier/validate
    FUNCTION validate_npi(
        p_npi               IN VARCHAR2,
        p_organization_name IN VARCHAR2 DEFAULT NULL,
        p_last_name         IN VARCHAR2 DEFAULT NULL,
        p_first_name        IN VARCHAR2 DEFAULT NULL,
        p_middle_name       IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_npi, 'p_npi', 'validate_npi');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'npi',              p_npi);
        json_add(lv_body, lv_sep, 'organizationName', p_organization_name);
        json_add(lv_body, lv_sep, 'lastName',         p_last_name);
        json_add(lv_body, lv_sep, 'firstName',        p_first_name);
        json_add(lv_body, lv_sep, 'middleName',       p_middle_name);
        lv_body := lv_body || '}';

        RETURN http_post('/api/nationalprovideridentifier/validate', lv_body, 'validate_npi');
    END validate_npi;

    -- POST /api/medpass/validate
    FUNCTION validate_medpass(
        p_id                   IN VARCHAR2,
        p_business_entity_type IN VARCHAR2,
        p_company_name         IN VARCHAR2 DEFAULT NULL,
        p_tax_id               IN VARCHAR2 DEFAULT NULL,
        p_country              IN VARCHAR2 DEFAULT NULL,
        p_state                IN VARCHAR2 DEFAULT NULL,
        p_city                 IN VARCHAR2 DEFAULT NULL,
        p_postal_code          IN VARCHAR2 DEFAULT NULL,
        p_address_line1        IN VARCHAR2 DEFAULT NULL,
        p_address_line2        IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_id, 'p_id', 'validate_medpass');
        require_param(p_business_entity_type, 'p_business_entity_type', 'validate_medpass');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'id',                 p_id);
        json_add(lv_body, lv_sep, 'businessEntityType', p_business_entity_type);
        json_add(lv_body, lv_sep, 'companyName',        p_company_name);
        json_add(lv_body, lv_sep, 'taxId',              p_tax_id);
        json_add(lv_body, lv_sep, 'country',            p_country);
        json_add(lv_body, lv_sep, 'state',              p_state);
        json_add(lv_body, lv_sep, 'city',               p_city);
        json_add(lv_body, lv_sep, 'postalCode',         p_postal_code);
        json_add(lv_body, lv_sep, 'addressLine1',       p_address_line1);
        json_add(lv_body, lv_sep, 'addressLine2',       p_address_line2);
        lv_body := lv_body || '}';

        RETURN http_post('/api/medpass/validate', lv_body, 'validate_medpass');
    END validate_medpass;

    -- POST /api/dot/fmcsa/lookup
    FUNCTION lookup_dot_carrier(
        p_dot_number  IN VARCHAR2,
        p_entity_name IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_dot_number, 'p_dot_number', 'lookup_dot_carrier');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'dotNumber',  p_dot_number);
        json_add(lv_body, lv_sep, 'entityName', p_entity_name);
        lv_body := lv_body || '}';

        RETURN http_post('/api/dot/fmcsa/lookup', lv_body, 'lookup_dot_carrier');
    END lookup_dot_carrier;

    -- POST /api/inidentity/validate
    FUNCTION validate_india_identity(
        p_identity_number      IN VARCHAR2,
        p_identity_number_type IN VARCHAR2,
        p_entity_name          IN VARCHAR2 DEFAULT NULL,
        p_dob                  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_identity_number, 'p_identity_number', 'validate_india_identity');
        require_param(p_identity_number_type, 'p_identity_number_type', 'validate_india_identity');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'identityNumber',     p_identity_number);
        json_add(lv_body, lv_sep, 'identityNumberType', p_identity_number_type);
        json_add(lv_body, lv_sep, 'entityName',         p_entity_name);
        json_add(lv_body, lv_sep, 'dob',                p_dob);
        lv_body := lv_body || '}';

        RETURN http_post('/api/inidentity/validate', lv_body, 'validate_india_identity');
    END validate_india_identity;

    ---------------------------------------------------------------------------
    -- CERTIFICATION (2)
    ---------------------------------------------------------------------------

    -- POST /api/certification/validate
    FUNCTION validate_certification(
        p_company_name         IN VARCHAR2,
        p_country              IN VARCHAR2,
        p_city                 IN VARCHAR2 DEFAULT NULL,
        p_state                IN VARCHAR2 DEFAULT NULL,
        p_zip_code             IN VARCHAR2 DEFAULT NULL,
        p_address_line1        IN VARCHAR2 DEFAULT NULL,
        p_address_line2        IN VARCHAR2 DEFAULT NULL,
        p_identity_type        IN VARCHAR2 DEFAULT NULL,
        p_certification_type   IN VARCHAR2 DEFAULT NULL,
        p_certification_group  IN VARCHAR2 DEFAULT NULL,
        p_certification_number IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'validate_certification');
        require_param(p_country, 'p_country', 'validate_certification');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName',         p_company_name);
        json_add(lv_body, lv_sep, 'country',             p_country);
        json_add(lv_body, lv_sep, 'city',                p_city);
        json_add(lv_body, lv_sep, 'state',               p_state);
        json_add(lv_body, lv_sep, 'zipCode',             p_zip_code);
        json_add(lv_body, lv_sep, 'addressLine1',        p_address_line1);
        json_add(lv_body, lv_sep, 'addressLine2',        p_address_line2);
        json_add(lv_body, lv_sep, 'identityType',        p_identity_type);
        json_add(lv_body, lv_sep, 'certificationType',   p_certification_type);
        json_add(lv_body, lv_sep, 'certificationGroup',  p_certification_group);
        json_add(lv_body, lv_sep, 'certificationNumber', p_certification_number);
        lv_body := lv_body || '}';

        RETURN http_post('/api/certification/validate', lv_body, 'validate_certification');
    END validate_certification;

    -- POST /api/certification/lookup
    FUNCTION lookup_certification(
        p_company_name  IN VARCHAR2,
        p_country       IN VARCHAR2,
        p_city          IN VARCHAR2 DEFAULT NULL,
        p_state         IN VARCHAR2 DEFAULT NULL,
        p_zip_code      IN VARCHAR2 DEFAULT NULL,
        p_address_line1 IN VARCHAR2 DEFAULT NULL,
        p_address_line2 IN VARCHAR2 DEFAULT NULL,
        p_identity_type IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_certification');
        require_param(p_country, 'p_country', 'lookup_certification');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName',  p_company_name);
        json_add(lv_body, lv_sep, 'country',      p_country);
        json_add(lv_body, lv_sep, 'city',         p_city);
        json_add(lv_body, lv_sep, 'state',        p_state);
        json_add(lv_body, lv_sep, 'zipCode',      p_zip_code);
        json_add(lv_body, lv_sep, 'addressLine1', p_address_line1);
        json_add(lv_body, lv_sep, 'addressLine2', p_address_line2);
        json_add(lv_body, lv_sep, 'identityType', p_identity_type);
        lv_body := lv_body || '}';

        RETURN http_post('/api/certification/lookup', lv_body, 'lookup_certification');
    END lookup_certification;

    ---------------------------------------------------------------------------
    -- CLASSIFICATION (1)
    ---------------------------------------------------------------------------

    -- POST /api/businessclassification/lookup
    FUNCTION lookup_business_classification(
        p_company_name IN VARCHAR2,
        p_city         IN VARCHAR2,
        p_state        IN VARCHAR2,
        p_country      IN VARCHAR2,
        p_address1     IN VARCHAR2 DEFAULT NULL,
        p_address2     IN VARCHAR2 DEFAULT NULL,
        p_phone        IN VARCHAR2 DEFAULT NULL,
        p_postal_code  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_company_name, 'p_company_name', 'lookup_business_classification');
        require_param(p_city, 'p_city', 'lookup_business_classification');
        require_param(p_state, 'p_state', 'lookup_business_classification');
        require_param(p_country, 'p_country', 'lookup_business_classification');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'companyName', p_company_name);
        json_add(lv_body, lv_sep, 'city',        p_city);
        json_add(lv_body, lv_sep, 'state',       p_state);
        json_add(lv_body, lv_sep, 'country',     p_country);
        json_add(lv_body, lv_sep, 'address1',    p_address1);
        json_add(lv_body, lv_sep, 'address2',    p_address2);
        json_add(lv_body, lv_sep, 'phone',       p_phone);
        json_add(lv_body, lv_sep, 'postalCode',  p_postal_code);
        lv_body := lv_body || '}';

        RETURN http_post('/api/businessclassification/lookup', lv_body, 'lookup_business_classification');
    END lookup_business_classification;

    ---------------------------------------------------------------------------
    -- FINANCIAL OPS (2)
    ---------------------------------------------------------------------------

    -- POST /api/paymentterms/validate
    FUNCTION analyze_payment_terms(
        p_current_pay_term IN VARCHAR2,
        p_annual_spend     IN NUMBER,
        p_avg_days_pay     IN NUMBER,
        p_savings_rate     IN NUMBER,
        p_threshold        IN NUMBER,
        p_vendor_name      IN VARCHAR2 DEFAULT NULL,
        p_country          IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_current_pay_term, 'p_current_pay_term', 'analyze_payment_terms');
        require_param(TO_CHAR(p_annual_spend, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'p_annual_spend', 'analyze_payment_terms');
        require_param(TO_CHAR(p_avg_days_pay, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'p_avg_days_pay', 'analyze_payment_terms');
        require_param(TO_CHAR(p_savings_rate, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'p_savings_rate', 'analyze_payment_terms');
        require_param(TO_CHAR(p_threshold, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'p_threshold', 'analyze_payment_terms');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'currentPayTerm', p_current_pay_term, 'N');
        json_add(lv_body, lv_sep, 'annualSpend',    TO_CHAR(p_annual_spend, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'N');
        json_add(lv_body, lv_sep, 'avgDaysPay',     TO_CHAR(p_avg_days_pay, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'N');
        json_add(lv_body, lv_sep, 'savingsRate',    TO_CHAR(p_savings_rate, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'N');
        json_add(lv_body, lv_sep, 'threshold',      TO_CHAR(p_threshold, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'N');
        json_add(lv_body, lv_sep, 'vendorName',     p_vendor_name);
        json_add(lv_body, lv_sep, 'country',        p_country);
        lv_body := lv_body || '}';

        RETURN http_post('/api/paymentterms/validate', lv_body, 'analyze_payment_terms');
    END analyze_payment_terms;

    -- POST /api/currency/exchange-rates/{baseCurrency}
    -- Body is a JSON array of date strings parsed from comma-separated input.
    FUNCTION lookup_exchange_rates(
        p_base_currency IN VARCHAR2,
        p_dates         IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_path VARCHAR2(500);
        lv_rest VARCHAR2(4000);
        lv_sep  VARCHAR2(1) := '';
        lv_pos  PLS_INTEGER;
        lv_item VARCHAR2(100);
    BEGIN
        ensure_init;
        require_param(p_base_currency, 'p_base_currency', 'lookup_exchange_rates');
        require_param(p_dates, 'p_dates', 'lookup_exchange_rates');

        lv_path := '/api/currency/exchange-rates/' || p_base_currency;

        -- Build JSON array of dates from comma-separated string
        -- E.g. "2024-01-01,2024-01-02" -> ["2024-01-01","2024-01-02"]
        lv_body := '[';
        lv_rest := p_dates;

        LOOP
            lv_pos := INSTR(lv_rest, ',');
            IF lv_pos > 0 THEN
                lv_item := TRIM(SUBSTR(lv_rest, 1, lv_pos - 1));
                lv_rest := SUBSTR(lv_rest, lv_pos + 1);
            ELSE
                lv_item := TRIM(lv_rest);
                lv_rest := NULL;
            END IF;

            IF lv_item IS NOT NULL THEN
                lv_body := lv_body || lv_sep || '"' || json_escape(lv_item) || '"';
                lv_sep := ',';
            END IF;

            EXIT WHEN lv_rest IS NULL;
        END LOOP;

        lv_body := lv_body || ']';

        RETURN http_post(lv_path, lv_body, 'lookup_exchange_rates');
    END lookup_exchange_rates;

    ---------------------------------------------------------------------------
    -- SUPPLIER (2)
    ---------------------------------------------------------------------------

    -- POST /api/aribasupplierprofile/lookup
    FUNCTION lookup_ariba_supplier(
        p_anid IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_anid, 'p_anid', 'lookup_ariba_supplier');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'anid', p_anid);
        lv_body := lv_body || '}';

        RETURN http_post('/api/aribasupplierprofile/lookup', lv_body, 'lookup_ariba_supplier');
    END lookup_ariba_supplier;

    -- POST /api/aribasupplierprofile/validate
    FUNCTION validate_ariba_supplier(
        p_anid IN VARCHAR2
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_anid, 'p_anid', 'validate_ariba_supplier');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'anid', p_anid);
        lv_body := lv_body || '}';

        RETURN http_post('/api/aribasupplierprofile/validate', lv_body, 'validate_ariba_supplier');
    END validate_ariba_supplier;

    ---------------------------------------------------------------------------
    -- GENDER (1)
    ---------------------------------------------------------------------------

    -- POST /api/genderize/identifygender
    FUNCTION identify_gender(
        p_name    IN VARCHAR2,
        p_country IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB
    IS
        lv_body VARCHAR2(32767);
        lv_sep  VARCHAR2(1) := '';
    BEGIN
        ensure_init;
        require_param(p_name, 'p_name', 'identify_gender');

        lv_body := '{';
        json_add(lv_body, lv_sep, 'name',    p_name);
        json_add(lv_body, lv_sep, 'country', p_country);
        lv_body := lv_body || '}';

        RETURN http_post('/api/genderize/identifygender', lv_body, 'identify_gender');
    END identify_gender;

    ---------------------------------------------------------------------------
    -- REFERENCE (2)
    ---------------------------------------------------------------------------

    -- GET /api/tax/format-validate/countries
    FUNCTION get_supported_tax_formats RETURN CLOB
    IS
    BEGIN
        ensure_init;
        RETURN http_get('/api/tax/format-validate/countries', 'get_supported_tax_formats');
    END get_supported_tax_formats;

    -- GET /api/peppol/schemes
    FUNCTION get_peppol_schemes RETURN CLOB
    IS
    BEGIN
        ensure_init;
        RETURN http_get('/api/peppol/schemes', 'get_peppol_schemes');
    END get_peppol_schemes;

END qubiton_api_pkg;
/
