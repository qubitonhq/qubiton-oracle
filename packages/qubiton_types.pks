CREATE OR REPLACE PACKAGE qubiton_types
AS
    ---------------------------------------------------------------------------
    -- Version
    ---------------------------------------------------------------------------
    gc_version         CONSTANT VARCHAR2(10)  := '1.0.0';
    gc_user_agent      CONSTANT VARCHAR2(50)  := 'qubiton-oracle/1.0.0';

    ---------------------------------------------------------------------------
    -- Error codes (RAISE_APPLICATION_ERROR range: -20999 to -20000)
    ---------------------------------------------------------------------------
    gc_err_connection  CONSTANT PLS_INTEGER := -20001;  -- Network/connection failure
    gc_err_timeout     CONSTANT PLS_INTEGER := -20002;  -- HTTP timeout
    gc_err_auth        CONSTANT PLS_INTEGER := -20003;  -- 401 Unauthorized (bad API key)
    gc_err_forbidden   CONSTANT PLS_INTEGER := -20004;  -- 403 Forbidden
    gc_err_rate_limit  CONSTANT PLS_INTEGER := -20005;  -- 429 Too Many Requests
    gc_err_server      CONSTANT PLS_INTEGER := -20006;  -- 5xx Server Error
    gc_err_json        CONSTANT PLS_INTEGER := -20007;  -- JSON parse/build error
    gc_err_wallet      CONSTANT PLS_INTEGER := -20008;  -- Oracle Wallet error
    gc_err_acl         CONSTANT PLS_INTEGER := -20009;  -- Network ACL denied
    gc_err_authz       CONSTANT PLS_INTEGER := -20010;  -- Application authorization error
    gc_err_validation  CONSTANT PLS_INTEGER := -20011;  -- Input validation error

    ---------------------------------------------------------------------------
    -- Error mode constants
    ---------------------------------------------------------------------------
    gc_mode_stop       CONSTANT VARCHAR2(1) := 'E';  -- Raise error (stop processing)
    gc_mode_warn       CONSTANT VARCHAR2(1) := 'W';  -- Log warning, return NULL
    gc_mode_silent     CONSTANT VARCHAR2(1) := 'S';  -- Return NULL silently

    ---------------------------------------------------------------------------
    -- JSON value type constants (for build_json)
    ---------------------------------------------------------------------------
    gc_type_string     CONSTANT VARCHAR2(1) := 'S';  -- Quoted string
    gc_type_number     CONSTANT VARCHAR2(1) := 'N';  -- Unquoted number
    gc_type_boolean    CONSTANT VARCHAR2(1) := 'B';  -- true/false

    ---------------------------------------------------------------------------
    -- Name/value pair for JSON building
    ---------------------------------------------------------------------------
    TYPE t_name_value IS RECORD (
        name  VARCHAR2(100),
        value VARCHAR2(32767),
        vtype VARCHAR2(1) DEFAULT 'S'  -- S=string, N=number, B=boolean
    );
    TYPE tt_name_value IS TABLE OF t_name_value INDEX BY PLS_INTEGER;

    ---------------------------------------------------------------------------
    -- Parsed API result
    ---------------------------------------------------------------------------
    TYPE t_result IS RECORD (
        success       BOOLEAN DEFAULT FALSE,   -- TRUE if API call returned HTTP 200
        is_valid      BOOLEAN DEFAULT FALSE,   -- TRUE if validation field is true
        message       VARCHAR2(4000),          -- Human-readable summary
        field_missing BOOLEAN DEFAULT FALSE,   -- TRUE if expected field not in JSON
        blocked       BOOLEAN DEFAULT FALSE    -- TRUE if error mode = 'E' and validation failed
    );

    ---------------------------------------------------------------------------
    -- Validation configuration record (from QUBITON_VALIDATION_CFG)
    ---------------------------------------------------------------------------
    TYPE t_val_config IS RECORD (
        module_name    VARCHAR2(30),
        val_type       VARCHAR2(20),
        active         VARCHAR2(1),
        on_invalid     VARCHAR2(1),
        on_error       VARCHAR2(1),
        country_filter VARCHAR2(500)
    );
    TYPE tt_val_config IS TABLE OF t_val_config INDEX BY PLS_INTEGER;

    ---------------------------------------------------------------------------
    -- Address comparison record (for compare_address)
    ---------------------------------------------------------------------------
    TYPE t_address IS RECORD (
        address_line1 VARCHAR2(500),
        address_line2 VARCHAR2(500),
        city          VARCHAR2(200),
        state         VARCHAR2(100),
        postal_code   VARCHAR2(50),
        country       VARCHAR2(10)
    );

    TYPE t_address_comparison IS RECORD (
        is_valid          BOOLEAN DEFAULT FALSE,
        confidence_score  NUMBER,
        has_changes       BOOLEAN DEFAULT FALSE,  -- TRUE if standardized differs from original
        original          t_address,
        standardized      t_address,
        raw_response      CLOB                    -- Full API JSON for further inspection
    );

END qubiton_types;
/
