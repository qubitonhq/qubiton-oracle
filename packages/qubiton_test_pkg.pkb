--------------------------------------------------------------------------------
-- QUBITON_TEST_PKG — utPLSQL v3 Test Suite
--
-- ~70 tests covering the QubitOn Oracle connector's three layers:
--   Layer 1: JSON building, parsing, result handling (qubiton_api_pkg)
--   Layer 2: Tax type detection, country filter (qubiton_validate_pkg)
--   Layer 3: Type constants and configuration (qubiton_types)
--
-- No real API connections required.  Tests exercise JSON construction,
-- result parsing, config handling, and type constants only.
--
-- Run:  EXEC ut.run('qubiton_test_pkg');
--------------------------------------------------------------------------------

-- Package Specification (with utPLSQL annotations)
CREATE OR REPLACE PACKAGE qubiton_test_pkg
AS
    --%suite(QubitOn Oracle Connector)
    --%suitepath(qubiton)

    --%beforeall
    PROCEDURE setup_all;

    --%beforeeach
    PROCEDURE setup_each;

    --%afterall
    PROCEDURE teardown_all;

    ---------------------------------------------------------------------------
    -- Suite 1: JSON Builder Tests (12 tests)
    ---------------------------------------------------------------------------

    --%context(json_builder)

    --%test(build_json: single string field produces {"name":"value"})
    PROCEDURE test_build_json_single_string;

    --%test(build_json: multiple fields produce correct JSON)
    PROCEDURE test_build_json_multiple_fields;

    --%test(build_json: NULL values are omitted from output)
    PROCEDURE test_build_json_skips_nulls;

    --%test(build_json: type N produces unquoted number)
    PROCEDURE test_build_json_number_type;

    --%test(build_json: type B value Y produces true)
    PROCEDURE test_build_json_boolean_true;

    --%test(build_json: type B value N produces false)
    PROCEDURE test_build_json_boolean_false;

    --%test(build_json: type B value TRUE produces true)
    PROCEDURE test_build_json_boolean_true_alt;

    --%test(build_json: type B value 1 produces true)
    PROCEDURE test_build_json_boolean_one;

    --%test(build_json: double quotes are escaped to backslash-quote)
    PROCEDURE test_build_json_escapes_quotes;

    --%test(build_json: backslash is escaped to double backslash)
    PROCEDURE test_build_json_escapes_backslash;

    --%test(build_json: newline CHR(10) is escaped to backslash-n)
    PROCEDURE test_build_json_escapes_newline;

    --%test(build_json: empty collection produces {})
    PROCEDURE test_build_json_empty_table;

    --%endcontext

    ---------------------------------------------------------------------------
    -- Suite 2: JSON Extraction / Parse Result Tests (8 tests)
    ---------------------------------------------------------------------------

    --%context(json_extraction)

    --%test(parse_result: {"isValid":true} returns success=true, is_valid=true)
    PROCEDURE test_parse_valid_true;

    --%test(parse_result: {"isValid":false} returns success=true, is_valid=false)
    PROCEDURE test_parse_valid_false;

    --%test(parse_result: empty string returns success=false)
    PROCEDURE test_parse_empty_json;

    --%test(parse_result: NULL input returns success=false)
    PROCEDURE test_parse_null_json;

    --%test(parse_result: missing field sets field_missing=true)
    PROCEDURE test_parse_missing_field;

    --%test(parse_result: custom field hasMatches extracts correctly)
    PROCEDURE test_parse_custom_field;

    --%test(parse_result: custom field name is parsed successfully)
    PROCEDURE test_parse_custom_label;

    --%test(parse_result: whitespace in JSON is handled correctly)
    PROCEDURE test_parse_whitespace_json;

    --%endcontext

    ---------------------------------------------------------------------------
    -- Suite 3: Handle Result Tests (8 tests)
    ---------------------------------------------------------------------------

    --%context(handle_result)

    --%test(handle_result: silent mode + valid = success, not blocked)
    PROCEDURE test_handle_silent_valid;

    --%test(handle_result: silent mode + invalid = success, not blocked)
    PROCEDURE test_handle_silent_invalid;

    --%test(handle_result: warn mode + valid = not blocked)
    PROCEDURE test_handle_warn_valid;

    --%test(handle_result: warn mode + invalid = not blocked)
    PROCEDURE test_handle_warn_invalid;

    --%test(handle_result: stop mode + valid = not blocked)
    PROCEDURE test_handle_stop_valid;

    --%test(handle_result: stop mode + invalid = blocked)
    PROCEDURE test_handle_stop_invalid;

    --%test(handle_result: stop mode + empty JSON = error handling)
    PROCEDURE test_handle_error_json;

    --%test(handle_result: missing field in JSON = field_missing)
    PROCEDURE test_handle_missing_field;

    --%endcontext

    ---------------------------------------------------------------------------
    -- Suite 4: Type Constants Tests (6 tests)
    ---------------------------------------------------------------------------

    --%context(type_constants)

    --%test(qubiton_types.gc_err_connection = -20001)
    PROCEDURE test_error_code_connection;

    --%test(qubiton_types.gc_err_timeout = -20002)
    PROCEDURE test_error_code_timeout;

    --%test(qubiton_types.gc_err_auth = -20003)
    PROCEDURE test_error_code_auth;

    --%test(qubiton_types.gc_err_rate_limit = -20005)
    PROCEDURE test_error_code_rate_limit;

    --%test(error mode constants: E=stop, W=warn, S=silent)
    PROCEDURE test_error_mode_values;

    --%test(JSON type constants: S=string, N=number, B=boolean)
    PROCEDURE test_json_type_values;

    --%endcontext

    ---------------------------------------------------------------------------
    -- Suite 5: Version & Config Tests (4 tests)
    ---------------------------------------------------------------------------

    --%context(version_config)

    --%test(gc_version matches X.Y.Z semver pattern)
    PROCEDURE test_version_format;

    --%test(gc_user_agent contains gc_version string)
    PROCEDURE test_user_agent_contains_version;

    --%test(gc_user_agent starts with qubiton-oracle/)
    PROCEDURE test_user_agent_prefix;

    --%test(t_result default values are all FALSE/NULL)
    PROCEDURE test_result_defaults;

    --%endcontext

    ---------------------------------------------------------------------------
    -- Suite 6: Tax Type Detection Tests (16 tests)
    ---------------------------------------------------------------------------

    --%context(tax_type_detection)

    --%test(determine_tax_type: US returns EIN)
    PROCEDURE test_tax_type_us;

    --%test(determine_tax_type: GB returns UTR)
    PROCEDURE test_tax_type_gb;

    --%test(determine_tax_type: DE returns VAT)
    PROCEDURE test_tax_type_de;

    --%test(determine_tax_type: FR returns VAT)
    PROCEDURE test_tax_type_fr;

    --%test(determine_tax_type: IT returns VAT)
    PROCEDURE test_tax_type_it;

    --%test(determine_tax_type: ES returns VAT)
    PROCEDURE test_tax_type_es;

    --%test(determine_tax_type: NL returns VAT)
    PROCEDURE test_tax_type_nl;

    --%test(determine_tax_type: BR returns CNPJ)
    PROCEDURE test_tax_type_br;

    --%test(determine_tax_type: IN returns PAN)
    PROCEDURE test_tax_type_in;

    --%test(determine_tax_type: AU returns ABN)
    PROCEDURE test_tax_type_au;

    --%test(determine_tax_type: CA returns BN)
    PROCEDURE test_tax_type_ca;

    --%test(determine_tax_type: MX returns RFC)
    PROCEDURE test_tax_type_mx;

    --%test(determine_tax_type: JP returns CN)
    PROCEDURE test_tax_type_jp;

    --%test(determine_tax_type: SG returns UEN)
    PROCEDURE test_tax_type_sg;

    --%test(determine_tax_type: ZA returns VAT)
    PROCEDURE test_tax_type_za;

    --%test(determine_tax_type: unknown XX returns TIN default)
    PROCEDURE test_tax_type_unknown;

    --%endcontext

    ---------------------------------------------------------------------------
    -- Suite 7: Country Filter Tests (6 tests)
    ---------------------------------------------------------------------------

    --%context(country_filter)

    --%test(is_country_enabled: NULL filter enables all countries)
    PROCEDURE test_country_filter_null;

    --%test(is_country_enabled: US matches US,GB,DE filter)
    PROCEDURE test_country_filter_match;

    --%test(is_country_enabled: FR does not match US,GB,DE filter)
    PROCEDURE test_country_filter_no_match;

    --%test(is_country_enabled: single-country filter US matches US)
    PROCEDURE test_country_filter_single;

    --%test(is_country_enabled: case-insensitive filter us,gb matches US)
    PROCEDURE test_country_filter_case;

    --%test(is_country_enabled: spaces in filter are trimmed)
    PROCEDURE test_country_filter_spaces;

    --%endcontext

    ---------------------------------------------------------------------------
    -- Suite 8: Input Validation Tests (10 tests)
    ---------------------------------------------------------------------------

    --%context(input_validation)

    --%test(validate_address: NULL country raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_validate_address_requires_country;

    --%test(validate_address: NULL city with valid country tests optional handling)
    --%throws(-20011,-20101)
    PROCEDURE test_validate_address_requires_line1;

    --%test(validate_tax: NULL tax_number raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_validate_tax_requires_tax_id;

    --%test(validate_tax: NULL country raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_validate_tax_requires_country;

    --%test(validate_bank_account: NULL country raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_validate_bank_requires_country;

    --%test(validate_email: NULL email_address raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_validate_email_requires_email;

    --%test(validate_phone: NULL phone_number raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_validate_phone_requires_number;

    --%test(check_sanctions: NULL company_name raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_check_sanctions_requires_name;

    --%test(check_directors: NULL first_name raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_check_directors_requires_name;

    --%test(lookup_business_registration: NULL company_name raises -20011)
    --%throws(-20011,-20101)
    PROCEDURE test_lookup_business_requires_name;

    --%endcontext

END qubiton_test_pkg;
/


-- Package Body
CREATE OR REPLACE PACKAGE BODY qubiton_test_pkg
AS
    ---------------------------------------------------------------------------
    -- Helper: build a single name/value pair collection
    ---------------------------------------------------------------------------
    FUNCTION make_pair(
        p_name  VARCHAR2,
        p_value VARCHAR2,
        p_type  VARCHAR2 DEFAULT 'S'
    ) RETURN qubiton_api_pkg.tt_name_value
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
    BEGIN
        l_pairs(1).name  := p_name;
        l_pairs(1).value := p_value;
        l_pairs(1).vtype := p_type;
        RETURN l_pairs;
    END make_pair;

    ---------------------------------------------------------------------------
    -- Setup / Teardown
    ---------------------------------------------------------------------------

    PROCEDURE setup_all
    IS
    BEGIN
        -- Insert dummy config so the API package can initialise without
        -- making real HTTP calls.
        BEGIN
            INSERT INTO qubiton_config (config_key, config_value, description)
            VALUES ('api_key', 'test-key-00000000-0000-0000-0000-000000000000',
                    'Unit test dummy key');
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;

        BEGIN
            INSERT INTO qubiton_config (config_key, config_value, description)
            VALUES ('base_url', 'https://api.test.qubiton.com',
                    'Unit test dummy URL');
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;
        END;

        -- Initialise the API package with dummy values to prevent HTTP calls
        -- (error_mode is set via init() below — no config row needed)
        qubiton_api_pkg.init(
            p_api_key    => 'test-key-00000000-0000-0000-0000-000000000000',
            p_base_url   => 'https://api.test.qubiton.com',
            p_error_mode => 'E'
        );

        -- Insert validation config rows for country filter tests.
        -- Each row uses a unique TEST_* module name to avoid collisions.

        -- Multi-country filter: US,GB,DE
        BEGIN
            INSERT INTO qubiton_validation_cfg
                (module_name, val_type, active, on_invalid, on_error, country_filter)
            VALUES ('TEST_MOD', 'TAX', 'Y', 'E', 'W', 'US,GB,DE');
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                UPDATE qubiton_validation_cfg
                   SET country_filter = 'US,GB,DE'
                 WHERE module_name = 'TEST_MOD' AND val_type = 'TAX';
        END;

        -- NULL filter (all countries enabled)
        BEGIN
            INSERT INTO qubiton_validation_cfg
                (module_name, val_type, active, on_invalid, on_error, country_filter)
            VALUES ('TEST_MOD', 'BANK', 'Y', 'E', 'W', NULL);
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                UPDATE qubiton_validation_cfg
                   SET country_filter = NULL
                 WHERE module_name = 'TEST_MOD' AND val_type = 'BANK';
        END;

        -- Single-country filter
        BEGIN
            INSERT INTO qubiton_validation_cfg
                (module_name, val_type, active, on_invalid, on_error, country_filter)
            VALUES ('TEST_SINGLE', 'TAX', 'Y', 'E', 'W', 'US');
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                UPDATE qubiton_validation_cfg
                   SET country_filter = 'US'
                 WHERE module_name = 'TEST_SINGLE' AND val_type = 'TAX';
        END;

        -- Lowercase filter (case-insensitive test)
        BEGIN
            INSERT INTO qubiton_validation_cfg
                (module_name, val_type, active, on_invalid, on_error, country_filter)
            VALUES ('TEST_CASE', 'TAX', 'Y', 'E', 'W', 'us,gb');
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                UPDATE qubiton_validation_cfg
                   SET country_filter = 'us,gb'
                 WHERE module_name = 'TEST_CASE' AND val_type = 'TAX';
        END;

        -- Spaces in filter (trim test)
        BEGIN
            INSERT INTO qubiton_validation_cfg
                (module_name, val_type, active, on_invalid, on_error, country_filter)
            VALUES ('TEST_SPACES', 'TAX', 'Y', 'E', 'W', 'US, GB, DE');
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                UPDATE qubiton_validation_cfg
                   SET country_filter = 'US, GB, DE'
                 WHERE module_name = 'TEST_SPACES' AND val_type = 'TAX';
        END;

        COMMIT;
    END setup_all;

    PROCEDURE setup_each
    IS
    BEGIN
        NULL;  -- no per-test setup needed
    END setup_each;

    PROCEDURE teardown_all
    IS
    BEGIN
        DELETE FROM qubiton_validation_cfg WHERE module_name LIKE 'TEST%';
        DELETE FROM qubiton_config
         WHERE config_key IN ('api_key', 'base_url', 'error_mode')
           AND (config_value LIKE 'test-%'
                OR config_value = 'https://api.test.qubiton.com');
        COMMIT;
    END teardown_all;

    ---------------------------------------------------------------------------
    -- Suite 1: JSON Builder Tests (12 tests)
    ---------------------------------------------------------------------------

    -- 1. Single string field → {"name":"value"}
    PROCEDURE test_build_json_single_string
    IS
        l_pairs  qubiton_api_pkg.tt_name_value;
        l_json   VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('name', 'value');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(l_json).to_equal('{"name":"value"}');
    END test_build_json_single_string;

    -- 2. Three fields → all present in correct JSON
    PROCEDURE test_build_json_multiple_fields
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs(1).name := 'country'; l_pairs(1).value := 'US';    l_pairs(1).vtype := 'S';
        l_pairs(2).name := 'city';    l_pairs(2).value := 'NYC';   l_pairs(2).vtype := 'S';
        l_pairs(3).name := 'zip';     l_pairs(3).value := '10001'; l_pairs(3).vtype := 'S';
        l_json := qubiton_api_pkg.build_json(l_pairs);

        ut.expect(INSTR(l_json, '"country":"US"')).to_be_greater_than(0);
        ut.expect(INSTR(l_json, '"city":"NYC"')).to_be_greater_than(0);
        ut.expect(INSTR(l_json, '"zip":"10001"')).to_be_greater_than(0);
        ut.expect(SUBSTR(l_json, 1, 1)).to_equal('{');
        ut.expect(SUBSTR(l_json, LENGTH(l_json), 1)).to_equal('}');
    END test_build_json_multiple_fields;

    -- 3. NULL values are omitted
    PROCEDURE test_build_json_skips_nulls
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs(1).name := 'keep'; l_pairs(1).value := 'yes'; l_pairs(1).vtype := 'S';
        l_pairs(2).name := 'skip'; l_pairs(2).value := NULL;  l_pairs(2).vtype := 'S';
        l_pairs(3).name := 'also'; l_pairs(3).value := 'ok';  l_pairs(3).vtype := 'S';
        l_json := qubiton_api_pkg.build_json(l_pairs);

        ut.expect(INSTR(l_json, '"keep":"yes"')).to_be_greater_than(0);
        ut.expect(INSTR(l_json, '"also":"ok"')).to_be_greater_than(0);
        ut.expect(INSTR(l_json, '"skip"')).to_equal(0);
    END test_build_json_skips_nulls;

    -- 4. Number type → unquoted
    PROCEDURE test_build_json_number_type
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('amount', '42.50', 'N');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(l_json).to_equal('{"amount":42.50}');
    END test_build_json_number_type;

    -- 5. Boolean true (Y)
    PROCEDURE test_build_json_boolean_true
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('active', 'Y', 'B');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(l_json).to_equal('{"active":true}');
    END test_build_json_boolean_true;

    -- 6. Boolean false (N)
    PROCEDURE test_build_json_boolean_false
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('active', 'N', 'B');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(l_json).to_equal('{"active":false}');
    END test_build_json_boolean_false;

    -- 7. Boolean true (TRUE string)
    PROCEDURE test_build_json_boolean_true_alt
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('flag', 'TRUE', 'B');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(l_json).to_equal('{"flag":true}');
    END test_build_json_boolean_true_alt;

    -- 8. Boolean true (1)
    PROCEDURE test_build_json_boolean_one
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('enabled', '1', 'B');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(l_json).to_equal('{"enabled":true}');
    END test_build_json_boolean_one;

    -- 9. Escapes double quotes
    PROCEDURE test_build_json_escapes_quotes
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('text', 'say "hello"');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(INSTR(l_json, 'say \"hello\"')).to_be_greater_than(0);
    END test_build_json_escapes_quotes;

    -- 10. Escapes backslash
    PROCEDURE test_build_json_escapes_backslash
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('path', 'C:\temp');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(INSTR(l_json, 'C:\\temp')).to_be_greater_than(0);
    END test_build_json_escapes_backslash;

    -- 11. Escapes newline (CHR(10) → \n)
    PROCEDURE test_build_json_escapes_newline
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_pairs := make_pair('note', 'line1' || CHR(10) || 'line2');
        l_json  := qubiton_api_pkg.build_json(l_pairs);
        -- The escaped \n should appear as literal characters
        ut.expect(INSTR(l_json, '\n')).to_be_greater_than(0);
        -- The raw newline character should not appear
        ut.expect(INSTR(l_json, CHR(10))).to_equal(0);
    END test_build_json_escapes_newline;

    -- 12. Empty collection → {}
    PROCEDURE test_build_json_empty_table
    IS
        l_pairs qubiton_api_pkg.tt_name_value;
        l_json  VARCHAR2(32767);
    BEGIN
        l_json := qubiton_api_pkg.build_json(l_pairs);
        ut.expect(l_json).to_equal('{}');
    END test_build_json_empty_table;

    ---------------------------------------------------------------------------
    -- Suite 2: JSON Extraction / Parse Result Tests (8 tests)
    ---------------------------------------------------------------------------

    -- 13. {"isValid":true} → success=true, is_valid=true
    PROCEDURE test_parse_valid_true
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.parse_result(TO_CLOB('{"isValid":true}'));
        ut.expect(l_result.success).to_be_true();
        ut.expect(l_result.is_valid).to_be_true();
    END test_parse_valid_true;

    -- 14. {"isValid":false} → success=true, is_valid=false
    PROCEDURE test_parse_valid_false
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.parse_result(TO_CLOB('{"isValid":false}'));
        ut.expect(l_result.success).to_be_true();
        ut.expect(l_result.is_valid).to_be_false();
    END test_parse_valid_false;

    -- 15. Empty string → success=false
    PROCEDURE test_parse_empty_json
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.parse_result(TO_CLOB(''));
        ut.expect(l_result.success).to_be_false();
    END test_parse_empty_json;

    -- 16. NULL → success=false
    PROCEDURE test_parse_null_json
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.parse_result(NULL);
        ut.expect(l_result.success).to_be_false();
    END test_parse_null_json;

    -- 17. Missing expected field → field_missing=true
    PROCEDURE test_parse_missing_field
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.parse_result(
            TO_CLOB('{"otherField":true}'), 'isValid');
        ut.expect(l_result.field_missing).to_be_true();
    END test_parse_missing_field;

    -- 18. Custom field name: hasMatches
    PROCEDURE test_parse_custom_field
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.parse_result(
            TO_CLOB('{"hasMatches":true}'), 'hasMatches');
        ut.expect(l_result.success).to_be_true();
        ut.expect(l_result.is_valid).to_be_true();
    END test_parse_custom_field;

    -- 19. Custom field parses successfully
    PROCEDURE test_parse_custom_label
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.parse_result(
            TO_CLOB('{"hasMatches":true}'), 'hasMatches');
        ut.expect(l_result.success).to_be_true();
    END test_parse_custom_label;

    -- 20. Whitespace in JSON handled
    PROCEDURE test_parse_whitespace_json
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.parse_result(
            TO_CLOB('{ "isValid" : true }'));
        ut.expect(l_result.success).to_be_true();
        ut.expect(l_result.is_valid).to_be_true();
    END test_parse_whitespace_json;

    ---------------------------------------------------------------------------
    -- Suite 3: Handle Result Tests (8 tests)
    ---------------------------------------------------------------------------

    -- 21. Silent mode + valid → success=true, blocked=false
    PROCEDURE test_handle_silent_valid
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.handle_result(
            TO_CLOB('{"isValid":true}'), 'isValid', 'S');
        ut.expect(l_result.success).to_be_true();
        ut.expect(l_result.blocked).to_be_false();
    END test_handle_silent_valid;

    -- 22. Silent mode + invalid → success=true, blocked=false
    PROCEDURE test_handle_silent_invalid
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.handle_result(
            TO_CLOB('{"isValid":false}'), 'isValid', 'S');
        ut.expect(l_result.success).to_be_true();
        ut.expect(l_result.blocked).to_be_false();
    END test_handle_silent_invalid;

    -- 23. Warn mode + valid → not blocked
    PROCEDURE test_handle_warn_valid
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.handle_result(
            TO_CLOB('{"isValid":true}'), 'isValid', 'W');
        ut.expect(l_result.blocked).to_be_false();
    END test_handle_warn_valid;

    -- 24. Warn mode + invalid → not blocked
    PROCEDURE test_handle_warn_invalid
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.handle_result(
            TO_CLOB('{"isValid":false}'), 'isValid', 'W');
        ut.expect(l_result.blocked).to_be_false();
    END test_handle_warn_invalid;

    -- 25. Stop mode + valid → not blocked
    PROCEDURE test_handle_stop_valid
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.handle_result(
            TO_CLOB('{"isValid":true}'), 'isValid', 'E');
        ut.expect(l_result.blocked).to_be_false();
    END test_handle_stop_valid;

    -- 26. Stop mode + invalid → blocked=true
    PROCEDURE test_handle_stop_invalid
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.handle_result(
            TO_CLOB('{"isValid":false}'), 'isValid', 'E');
        ut.expect(l_result.blocked).to_be_true();
    END test_handle_stop_invalid;

    -- 27. Stop mode + empty JSON → success=false
    PROCEDURE test_handle_error_json
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.handle_result(
            TO_CLOB(''), 'isValid', 'E');
        ut.expect(l_result.success).to_be_false();
    END test_handle_error_json;

    -- 28. Field missing in JSON → field_missing=true
    PROCEDURE test_handle_missing_field
    IS
        l_result qubiton_types.t_result;
    BEGIN
        l_result := qubiton_api_pkg.handle_result(
            TO_CLOB('{"otherField":"value"}'), 'isValid', 'W');
        ut.expect(l_result.field_missing).to_be_true();
    END test_handle_missing_field;

    ---------------------------------------------------------------------------
    -- Suite 4: Type Constants Tests (6 tests)
    ---------------------------------------------------------------------------

    -- 29. gc_err_connection = -20001
    PROCEDURE test_error_code_connection
    IS
    BEGIN
        ut.expect(qubiton_types.gc_err_connection).to_equal(-20001);
    END test_error_code_connection;

    -- 30. gc_err_timeout = -20002
    PROCEDURE test_error_code_timeout
    IS
    BEGIN
        ut.expect(qubiton_types.gc_err_timeout).to_equal(-20002);
    END test_error_code_timeout;

    -- 31. gc_err_auth = -20003
    PROCEDURE test_error_code_auth
    IS
    BEGIN
        ut.expect(qubiton_types.gc_err_auth).to_equal(-20003);
    END test_error_code_auth;

    -- 32. gc_err_rate_limit = -20005
    PROCEDURE test_error_code_rate_limit
    IS
    BEGIN
        ut.expect(qubiton_types.gc_err_rate_limit).to_equal(-20005);
    END test_error_code_rate_limit;

    -- 33. Error mode constants
    PROCEDURE test_error_mode_values
    IS
    BEGIN
        ut.expect(qubiton_types.gc_mode_stop).to_equal('E');
        ut.expect(qubiton_types.gc_mode_warn).to_equal('W');
        ut.expect(qubiton_types.gc_mode_silent).to_equal('S');
    END test_error_mode_values;

    -- 34. JSON type constants
    PROCEDURE test_json_type_values
    IS
    BEGIN
        ut.expect(qubiton_types.gc_type_string).to_equal('S');
        ut.expect(qubiton_types.gc_type_number).to_equal('N');
        ut.expect(qubiton_types.gc_type_boolean).to_equal('B');
    END test_json_type_values;

    ---------------------------------------------------------------------------
    -- Suite 5: Version & Config Tests (4 tests)
    ---------------------------------------------------------------------------

    -- 35. Version matches X.Y.Z semver
    PROCEDURE test_version_format
    IS
    BEGIN
        ut.expect(
            CASE WHEN REGEXP_LIKE(qubiton_types.gc_version, '^\d+\.\d+\.\d+$')
                 THEN 1 ELSE 0 END
        ).to_equal(1);
    END test_version_format;

    -- 36. User agent contains version
    PROCEDURE test_user_agent_contains_version
    IS
    BEGIN
        ut.expect(
            INSTR(qubiton_types.gc_user_agent, qubiton_types.gc_version)
        ).to_be_greater_than(0);
    END test_user_agent_contains_version;

    -- 37. User agent starts with qubiton-oracle/
    PROCEDURE test_user_agent_prefix
    IS
    BEGIN
        ut.expect(qubiton_types.gc_user_agent).to_be_like('qubiton-oracle/%');
    END test_user_agent_prefix;

    -- 38. t_result defaults are all FALSE/NULL
    PROCEDURE test_result_defaults
    IS
        l_result qubiton_types.t_result;
    BEGIN
        ut.expect(l_result.success).to_be_false();
        ut.expect(l_result.is_valid).to_be_false();
        ut.expect(l_result.message).to_be_null();
        ut.expect(l_result.field_missing).to_be_false();
        ut.expect(l_result.blocked).to_be_false();
    END test_result_defaults;

    ---------------------------------------------------------------------------
    -- Suite 6: Tax Type Detection Tests (16 tests)
    ---------------------------------------------------------------------------

    -- 39. US → EIN
    PROCEDURE test_tax_type_us
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('US')).to_equal('EIN');
    END test_tax_type_us;

    -- 40. GB → UTR
    PROCEDURE test_tax_type_gb
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('GB')).to_equal('UTR');
    END test_tax_type_gb;

    -- 41. DE → VAT
    PROCEDURE test_tax_type_de
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('DE')).to_equal('VAT');
    END test_tax_type_de;

    -- 42. FR → VAT
    PROCEDURE test_tax_type_fr
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('FR')).to_equal('VAT');
    END test_tax_type_fr;

    -- 43. IT → VAT
    PROCEDURE test_tax_type_it
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('IT')).to_equal('VAT');
    END test_tax_type_it;

    -- 44. ES → VAT
    PROCEDURE test_tax_type_es
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('ES')).to_equal('VAT');
    END test_tax_type_es;

    -- 45. NL → VAT
    PROCEDURE test_tax_type_nl
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('NL')).to_equal('VAT');
    END test_tax_type_nl;

    -- 46. BR → CNPJ
    PROCEDURE test_tax_type_br
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('BR')).to_equal('CNPJ');
    END test_tax_type_br;

    -- 47. IN → PAN
    PROCEDURE test_tax_type_in
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('IN')).to_equal('PAN');
    END test_tax_type_in;

    -- 48. AU → ABN
    PROCEDURE test_tax_type_au
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('AU')).to_equal('ABN');
    END test_tax_type_au;

    -- 49. CA → BN
    PROCEDURE test_tax_type_ca
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('CA')).to_equal('BN');
    END test_tax_type_ca;

    -- 50. MX → RFC
    PROCEDURE test_tax_type_mx
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('MX')).to_equal('RFC');
    END test_tax_type_mx;

    -- 51. JP → CN
    PROCEDURE test_tax_type_jp
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('JP')).to_equal('CN');
    END test_tax_type_jp;

    -- 52. SG → UEN
    PROCEDURE test_tax_type_sg
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('SG')).to_equal('UEN');
    END test_tax_type_sg;

    -- 53. ZA → VAT
    PROCEDURE test_tax_type_za
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('ZA')).to_equal('VAT');
    END test_tax_type_za;

    -- 54. Unknown → TIN (default)
    PROCEDURE test_tax_type_unknown
    IS
    BEGIN
        ut.expect(qubiton_validate_pkg.determine_tax_type('XX')).to_equal('TIN');
    END test_tax_type_unknown;

    ---------------------------------------------------------------------------
    -- Suite 7: Country Filter Tests (6 tests)
    ---------------------------------------------------------------------------

    -- 55. NULL filter → all countries enabled
    PROCEDURE test_country_filter_null
    IS
        l_enabled BOOLEAN;
    BEGIN
        l_enabled := qubiton_validate_pkg.is_country_enabled(
            'TEST_MOD', 'BANK', 'FR');
        ut.expect(l_enabled).to_be_true();
    END test_country_filter_null;

    -- 56. US matches US,GB,DE filter
    PROCEDURE test_country_filter_match
    IS
        l_enabled BOOLEAN;
    BEGIN
        l_enabled := qubiton_validate_pkg.is_country_enabled(
            'TEST_MOD', 'TAX', 'US');
        ut.expect(l_enabled).to_be_true();
    END test_country_filter_match;

    -- 57. FR does not match US,GB,DE filter
    PROCEDURE test_country_filter_no_match
    IS
        l_enabled BOOLEAN;
    BEGIN
        l_enabled := qubiton_validate_pkg.is_country_enabled(
            'TEST_MOD', 'TAX', 'FR');
        ut.expect(l_enabled).to_be_false();
    END test_country_filter_no_match;

    -- 58. Single-country filter: US matches US
    PROCEDURE test_country_filter_single
    IS
        l_enabled BOOLEAN;
    BEGIN
        l_enabled := qubiton_validate_pkg.is_country_enabled(
            'TEST_SINGLE', 'TAX', 'US');
        ut.expect(l_enabled).to_be_true();
    END test_country_filter_single;

    -- 59. Case-insensitive: lowercase us,gb matches US
    PROCEDURE test_country_filter_case
    IS
        l_enabled BOOLEAN;
    BEGIN
        l_enabled := qubiton_validate_pkg.is_country_enabled(
            'TEST_CASE', 'TAX', 'US');
        ut.expect(l_enabled).to_be_true();
    END test_country_filter_case;

    -- 60. Spaces in filter are trimmed: 'US, GB, DE' matches GB
    PROCEDURE test_country_filter_spaces
    IS
        l_enabled BOOLEAN;
    BEGIN
        l_enabled := qubiton_validate_pkg.is_country_enabled(
            'TEST_SPACES', 'TAX', 'GB');
        ut.expect(l_enabled).to_be_true();
    END test_country_filter_spaces;

    ---------------------------------------------------------------------------
    -- Suite 8: Input Validation Tests (10 tests)
    --
    -- Each test calls an API function with a NULL required parameter.
    -- The --%throws annotation in the spec declares the expected error codes:
    --   -20011 (qubiton_types.gc_err_validation)
    --   -20101 (qubiton_api_pkg.gc_err_required_param)
    ---------------------------------------------------------------------------

    -- 61. validate_address: NULL country (p_country is required)
    PROCEDURE test_validate_address_requires_country
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.validate_address(
            p_country       => NULL,
            p_address_line1 => '123 Main St');
    END test_validate_address_requires_country;

    -- 62. validate_address: NULL country with no address_line1
    --     (p_address_line1 is now optional, so we test NULL country again
    --      with a different call pattern to ensure country is still enforced)
    PROCEDURE test_validate_address_requires_line1
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.validate_address(
            p_country       => NULL,
            p_address_line1 => NULL);
    END test_validate_address_requires_line1;

    -- 63. validate_tax: NULL tax_number (p_tax_number is required)
    PROCEDURE test_validate_tax_requires_tax_id
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.validate_tax(
            p_tax_number   => NULL,
            p_tax_type     => 'EIN',
            p_country      => 'US',
            p_company_name => 'Test Corp');
    END test_validate_tax_requires_tax_id;

    -- 64. validate_tax: NULL country (p_country is required)
    PROCEDURE test_validate_tax_requires_country
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.validate_tax(
            p_tax_number   => '123456789',
            p_tax_type     => 'EIN',
            p_country      => NULL,
            p_company_name => 'Test Corp');
    END test_validate_tax_requires_country;

    -- 65. validate_bank_account: NULL country (p_country is required)
    PROCEDURE test_validate_bank_requires_country
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.validate_bank_account(
            p_account_number      => '12345678',
            p_business_entity_type => 'CORP',
            p_bank_account_holder  => 'Test Corp',
            p_country              => NULL);
    END test_validate_bank_requires_country;

    -- 66. validate_email: NULL email_address (p_email_address is required)
    PROCEDURE test_validate_email_requires_email
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.validate_email(
            p_email_address => NULL);
    END test_validate_email_requires_email;

    -- 67. validate_phone: NULL phone_number (p_phone_number is required)
    PROCEDURE test_validate_phone_requires_number
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.validate_phone(
            p_phone_number => NULL,
            p_country      => 'US');
    END test_validate_phone_requires_number;

    -- 68. check_sanctions: NULL company_name (p_company_name is required)
    PROCEDURE test_check_sanctions_requires_name
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.check_sanctions(
            p_company_name => NULL,
            p_country      => 'US');
    END test_check_sanctions_requires_name;

    -- 69. check_directors: NULL first_name (p_first_name is required)
    PROCEDURE test_check_directors_requires_name
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.check_directors(
            p_first_name => NULL,
            p_last_name  => 'Smith',
            p_country    => 'GB');
    END test_check_directors_requires_name;

    -- 70. lookup_business_registration: NULL company_name (p_company_name is required)
    PROCEDURE test_lookup_business_requires_name
    IS
        l_result CLOB;
    BEGIN
        l_result := qubiton_api_pkg.lookup_business_registration(
            p_company_name => NULL,
            p_country      => 'US');
    END test_lookup_business_requires_name;

END qubiton_test_pkg;
/
