--------------------------------------------------------------------------------
-- grant_network_acl.sql
-- Grants network access to api.qubiton.com for the specified schema.
-- Run as SYS or a DBA with DBMS_NETWORK_ACL_ADMIN privilege.
--
-- Usage:
--   @grant_network_acl.sql YOUR_SCHEMA
--   OR set &1 to schema name when prompted
--------------------------------------------------------------------------------

DEFINE schema_name = &1

PROMPT Granting network ACL for &schema_name to api.qubiton.com:443 ...

-- Oracle 12c+ (APPEND_HOST_ACE)
BEGIN
    DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host       => 'api.qubiton.com',
        lower_port => 443,
        upper_port => 443,
        ace        => xs$ace_type(
                        privilege_list => xs$name_list('connect', 'resolve'),
                        principal_name => UPPER('&schema_name'),
                        principal_type => xs_acl.ptype_db
                      )
    );
    DBMS_OUTPUT.PUT_LINE('ACL granted successfully (12c+ method).');
EXCEPTION
    WHEN OTHERS THEN
        -- Fall back to 11g method if 12c types not available
        IF SQLCODE = -6550 THEN
            DBMS_OUTPUT.PUT_LINE('12c+ ACL method not available, trying 11g method...');
        ELSE
            RAISE;
        END IF;
END;
/

-- Oracle 11g fallback (CREATE_ACL / ADD_PRIVILEGE / ASSIGN_ACL)
DECLARE
    lv_acl_exists NUMBER;
BEGIN
    -- Check if 12c method already succeeded by testing access
    -- Only run 11g method if needed
    SELECT COUNT(*) INTO lv_acl_exists
    FROM dba_network_acl_privileges
    WHERE principal = UPPER('&schema_name')
    AND privilege = 'connect'
    AND host = 'api.qubiton.com';

    IF lv_acl_exists = 0 THEN
        BEGIN
            DBMS_NETWORK_ACL_ADMIN.CREATE_ACL(
                acl         => 'qubiton_api_acl.xml',
                description => 'ACL for QubitOn API (api.qubiton.com)',
                principal   => UPPER('&schema_name'),
                is_grant    => TRUE,
                privilege   => 'connect'
            );
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE = -46102 THEN -- ACL already exists
                    NULL;
                ELSE
                    RAISE;
                END IF;
        END;

        DBMS_NETWORK_ACL_ADMIN.ADD_PRIVILEGE(
            acl       => 'qubiton_api_acl.xml',
            principal => UPPER('&schema_name'),
            is_grant  => TRUE,
            privilege => 'resolve'
        );

        DBMS_NETWORK_ACL_ADMIN.ASSIGN_ACL(
            acl        => 'qubiton_api_acl.xml',
            host       => 'api.qubiton.com',
            lower_port => 443,
            upper_port => 443
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('ACL granted successfully (11g method).');
    ELSE
        DBMS_OUTPUT.PUT_LINE('ACL already exists for ' || UPPER('&schema_name') || '.');
    END IF;
END;
/

PROMPT Network ACL setup complete.