--------------------------------------------------------------------------------
-- install.sql
-- Master installation script for the QubitOn Oracle PL/SQL Connector.
--
-- Prerequisites:
--   1. Network ACL granted (setup/grant_network_acl.sql — run as DBA)
--   2. Oracle Wallet configured (setup/create_wallet.sh)
--
-- Usage:
--   @install.sql
--
-- Objects created:
--   Tables:   QUBITON_CONFIG, QUBITON_VALIDATION_CFG, QUBITON_API_LOG
--   Packages: QUBITON_TYPES, QUBITON_API_PKG, QUBITON_VALIDATE_PKG, QUBITON_EBS_PKG
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET ECHO OFF
SET FEEDBACK ON

PROMPT ============================================================
PROMPT  QubitOn Oracle PL/SQL Connector — Installation
PROMPT  Version 1.0.0
PROMPT ============================================================
PROMPT

-- Step 1: Tables
PROMPT [1/8] Creating configuration table...
@@tables/qubiton_config.sql

PROMPT [2/8] Creating validation configuration table...
@@tables/qubiton_validation_cfg.sql

PROMPT [3/8] Creating audit log table...
@@tables/qubiton_api_log.sql

-- Step 2: Type definitions
PROMPT [4/8] Creating type definitions...
@@packages/qubiton_types.pks

-- Step 3: Core API client
PROMPT [5/8] Creating core API client...
@@packages/qubiton_api_pkg.pks
@@packages/qubiton_api_pkg.pkb

-- Step 4: Validation orchestrator
PROMPT [6/8] Creating validation orchestrator...
@@packages/qubiton_validate_pkg.pks
@@packages/qubiton_validate_pkg.pkb

-- Step 5: EBS integration hooks
PROMPT [7/8] Creating EBS integration hooks...
@@packages/qubiton_ebs_pkg.pks
@@packages/qubiton_ebs_pkg.pkb

-- Step 6: Seed configuration
PROMPT
PROMPT Seeding default configuration...
@@setup/seed_config.sql

-- Step 7: Unit tests (optional — requires utPLSQL v3)
PROMPT [8/8] Creating unit test package...
@@packages/qubiton_test_pkg.pkb

-- Verify installation
PROMPT
PROMPT ============================================================
PROMPT  Verifying installation...
PROMPT ============================================================

DECLARE
    lv_count   PLS_INTEGER := 0;
    lv_errors  PLS_INTEGER := 0;

    PROCEDURE check_object(p_name VARCHAR2, p_type VARCHAR2) IS
        lv_status VARCHAR2(30);
    BEGIN
        SELECT status INTO lv_status
        FROM user_objects
        WHERE object_name = p_name AND object_type = p_type;

        IF lv_status = 'VALID' THEN
            DBMS_OUTPUT.PUT_LINE('  OK    ' || p_type || ' ' || p_name);
            lv_count := lv_count + 1;
        ELSE
            DBMS_OUTPUT.PUT_LINE('  ERROR ' || p_type || ' ' || p_name || ' (status: ' || lv_status || ')');
            lv_errors := lv_errors + 1;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('  MISS  ' || p_type || ' ' || p_name);
            lv_errors := lv_errors + 1;
    END;
BEGIN
    -- Tables
    check_object('QUBITON_CONFIG',         'TABLE');
    check_object('QUBITON_VALIDATION_CFG', 'TABLE');
    check_object('QUBITON_API_LOG',        'TABLE');

    -- Packages
    check_object('QUBITON_TYPES',          'PACKAGE');
    check_object('QUBITON_API_PKG',        'PACKAGE');
    check_object('QUBITON_API_PKG',        'PACKAGE BODY');
    check_object('QUBITON_VALIDATE_PKG',   'PACKAGE');
    check_object('QUBITON_VALIDATE_PKG',   'PACKAGE BODY');
    check_object('QUBITON_EBS_PKG',        'PACKAGE');
    check_object('QUBITON_EBS_PKG',        'PACKAGE BODY');
    check_object('QUBITON_TEST_PKG',       'PACKAGE');
    check_object('QUBITON_TEST_PKG',       'PACKAGE BODY');

    DBMS_OUTPUT.PUT_LINE('');
    IF lv_errors = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Installation complete: ' || lv_count || ' objects verified.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Installation completed with ' || lv_errors || ' error(s). Check compilation errors:');
        DBMS_OUTPUT.PUT_LINE('  SELECT name, type, line, text FROM user_errors ORDER BY name, type, sequence;');
    END IF;
END;
/

PROMPT
PROMPT ============================================================
PROMPT  Next Steps:
PROMPT  1. Update API key:  UPDATE qubiton_config SET config_value = 'sk_live_xxx' WHERE config_key = 'APIKEY'; COMMIT;
PROMPT  2. Test connection:  SELECT qubiton_api_pkg.test_connection() FROM DUAL;
PROMPT  3. Run tests:        EXEC ut.run('qubiton_test_pkg');
PROMPT ============================================================

SET DEFINE ON