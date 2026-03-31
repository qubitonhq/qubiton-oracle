--------------------------------------------------------------------------------
-- uninstall.sql
-- Removes all QubitOn Oracle connector objects.
-- Run this to cleanly uninstall the connector.
--
-- Usage:
--   @uninstall.sql
--
-- WARNING: This drops all QubitOn tables (including audit logs) and packages.
--          Export any needed data before running.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

PROMPT ============================================================
PROMPT  QubitOn Oracle PL/SQL Connector — Uninstall
PROMPT ============================================================
PROMPT
PROMPT WARNING: This will remove ALL QubitOn objects and data.
PROMPT Press Ctrl+C to cancel, or Enter to continue...
PAUSE

-- Step 1: Drop packages (reverse dependency order)
PROMPT Dropping packages...

BEGIN
    EXECUTE IMMEDIATE 'DROP PACKAGE qubiton_ebs_pkg';
    DBMS_OUTPUT.PUT_LINE('  Dropped QUBITON_EBS_PKG');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  QUBITON_EBS_PKG not found (skipped)');
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP PACKAGE qubiton_validate_pkg';
    DBMS_OUTPUT.PUT_LINE('  Dropped QUBITON_VALIDATE_PKG');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  QUBITON_VALIDATE_PKG not found (skipped)');
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP PACKAGE qubiton_api_pkg';
    DBMS_OUTPUT.PUT_LINE('  Dropped QUBITON_API_PKG');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  QUBITON_API_PKG not found (skipped)');
END;
/

-- Drop test package (depends on types, api_pkg, validate_pkg)
BEGIN
    EXECUTE IMMEDIATE 'DROP PACKAGE qubiton_test_pkg';
    DBMS_OUTPUT.PUT_LINE('  Dropped QUBITON_TEST_PKG');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  QUBITON_TEST_PKG not found (skipped)');
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP PACKAGE qubiton_types';
    DBMS_OUTPUT.PUT_LINE('  Dropped QUBITON_TYPES');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  QUBITON_TYPES not found (skipped)');
END;
/

-- Step 2: Drop tables
PROMPT Dropping tables...

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE qubiton_api_log PURGE';
    DBMS_OUTPUT.PUT_LINE('  Dropped QUBITON_API_LOG');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  QUBITON_API_LOG not found (skipped)');
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE qubiton_validation_cfg PURGE';
    DBMS_OUTPUT.PUT_LINE('  Dropped QUBITON_VALIDATION_CFG');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  QUBITON_VALIDATION_CFG not found (skipped)');
END;
/

BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE qubiton_config PURGE';
    DBMS_OUTPUT.PUT_LINE('  Dropped QUBITON_CONFIG');
EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  QUBITON_CONFIG not found (skipped)');
END;
/

PROMPT
PROMPT ============================================================
PROMPT  Uninstall complete. All QubitOn objects have been removed.
PROMPT ============================================================

SET DEFINE ON