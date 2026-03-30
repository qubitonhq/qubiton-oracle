# Setup Guide

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Oracle Database | 11g R2+ (12c+ recommended) | PL/SQL execution |
| Oracle Wallet | Any | TLS certificates for HTTPS |
| Network ACL | 12c+ or 11g format | Allow outbound HTTPS to api.qubiton.com |
| QubitOn API key | — | Authentication (get at www.qubiton.com) |

## Step 1: Create Oracle Wallet

The wallet stores CA certificates needed for HTTPS connections.

### Automated (recommended)

```bash
cd setup/
chmod +x create_wallet.sh
./create_wallet.sh /opt/oracle/wallet
```

### Manual

```bash
# Create wallet
orapki wallet create -wallet /opt/oracle/wallet -pwd YourPassword123 -auto_login

# Download CA bundle
curl -o /tmp/cacert.pem https://curl.se/ca/cacert.pem

# Add certificates (repeat for each CA cert)
orapki wallet add -wallet /opt/oracle/wallet -trusted_cert -cert /tmp/cacert.pem -pwd YourPassword123
```

### Oracle Autonomous Database

No wallet setup needed — DBMS_CLOUD has pre-loaded certificates.

### Verify wallet

```sql
SELECT UTL_HTTP.REQUEST(
    url         => 'https://api.qubiton.com/api/health',
    wallet_path => 'file:/opt/oracle/wallet'
) FROM DUAL;
```

## Step 2: Grant Network ACL

Run as SYS or DBA:

```sql
@setup/grant_network_acl.sql YOUR_SCHEMA
```

### Manual (Oracle 12c+)

```sql
BEGIN
    DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host       => 'api.qubiton.com',
        lower_port => 443,
        upper_port => 443,
        ace        => xs$ace_type(
                        privilege_list => xs$name_list('connect', 'resolve'),
                        principal_name => 'YOUR_SCHEMA',
                        principal_type => xs_acl.ptype_db
                      )
    );
END;
/
```

### Manual (Oracle 11g)

```sql
BEGIN
    DBMS_NETWORK_ACL_ADMIN.CREATE_ACL(
        acl         => 'qubiton_api_acl.xml',
        description => 'ACL for QubitOn API',
        principal   => 'YOUR_SCHEMA',
        is_grant    => TRUE,
        privilege   => 'connect'
    );
    DBMS_NETWORK_ACL_ADMIN.ADD_PRIVILEGE(
        acl       => 'qubiton_api_acl.xml',
        principal => 'YOUR_SCHEMA',
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
END;
/
```

## Step 3: Install Connector

```sql
@install.sql
```

This creates all tables, packages, and seeds default configuration.

## Step 4: Configure API Key

```sql
UPDATE qubiton_config
SET config_value = 'sk_live_your_actual_key_here'
WHERE config_key = 'APIKEY';
COMMIT;
```

## Step 5: Test Connection

```sql
-- Quick connectivity test
SELECT qubiton_api_pkg.test_connection() FROM DUAL;

-- Full validation test
SELECT qubiton_api_pkg.validate_address(
    p_country       => 'US',
    p_address_line1 => '123 Main St',
    p_city          => 'Springfield',
    p_state         => 'IL',
    p_postal_code   => '62701'
) FROM DUAL;
```

## Step 6: Run Unit Tests

```sql
-- Requires utPLSQL v3
@packages/qubiton_test_pkg.pkb
EXEC ut.run('qubiton_test_pkg');
```

## Troubleshooting

### ORA-24247: network access denied by access control list (ACL)

The schema doesn't have network access. Run `grant_network_acl.sql` as DBA.

### ORA-29273: HTTP request failed / ORA-12535: TNS operation timed out

Wallet not configured or certificates missing. Re-run `create_wallet.sh`.

### ORA-28759: failure to open file

Wallet path incorrect. Verify the wallet directory exists and the Oracle process can read it.

### ORA-29024: Certificate validation failure

CA certificates in wallet are outdated. Re-download the CA bundle and re-import.

### ORA-06512: UTL_HTTP related errors

Common causes and fixes:

| Error | Cause | Fix |
|-------|-------|-----|
| ORA-29273 | Network unreachable | Check firewall rules for outbound HTTPS (port 443) |
| ORA-12535 | Connection timeout | Increase `TIMEOUT` in `QUBITON_CONFIG` or check DNS resolution |
| ORA-29259 | End-of-input reached | API returned empty response; check API key validity |
| ORA-06502 | Value too large | Response exceeded buffer; connector handles via CLOB but check custom code |

### API Key Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| HTTP 401 | Invalid or expired API key | Verify key at www.qubiton.com, update `QUBITON_CONFIG` |
| HTTP 403 | Key lacks permission for endpoint | Upgrade plan or contact support |
| HTTP 429 | Rate limit exceeded | Reduce call frequency or upgrade plan |

### Performance Issues

If API calls are slow (>5s):

1. Check wallet location — network-mounted paths add latency
2. Verify DNS resolution: `SELECT UTL_INADDR.GET_HOST_ADDRESS('api.qubiton.com') FROM DUAL;`
3. Check the `QUBITON_API_LOG` table for `elapsed_ms` trends
4. Consider connection pooling via `UTL_HTTP.SET_PERSISTENT_CONN_SUPPORT(TRUE)`

### Oracle Autonomous Database (ADB)

ADB uses `DBMS_CLOUD` for HTTPS. If `UTL_HTTP` is restricted:

```sql
-- Use DBMS_CLOUD.SEND_REQUEST instead
-- The connector auto-detects ADB and switches methods
SELECT qubiton_api_pkg.test_connection() FROM DUAL;
```

If you see `ORA-01031: insufficient privileges` on ADB, request the DBA to grant:

```sql
GRANT EXECUTE ON UTL_HTTP TO your_schema;
-- OR use DBMS_CLOUD (no grant needed for ADB users)
```

## Uninstall

```sql
@uninstall.sql
```

Removes all QubitOn objects (tables, packages, data). Export audit logs first if needed.

### Manual uninstall

```sql
-- Drop packages (order matters: Layer 3 → 2 → 1)
DROP PACKAGE qubiton_ebs_pkg;
DROP PACKAGE qubiton_validate_pkg;
DROP PACKAGE qubiton_api_pkg;
DROP PACKAGE qubiton_types;

-- Drop tables
DROP TABLE qubiton_api_log   PURGE;
DROP TABLE qubiton_validation_cfg PURGE;
DROP TABLE qubiton_config    PURGE;
```

## Upgrading

1. Back up current configuration:

```sql
CREATE TABLE qubiton_config_bak AS SELECT * FROM qubiton_config;
CREATE TABLE qubiton_val_cfg_bak AS SELECT * FROM qubiton_validation_cfg;
```

2. Run the new installer:

```sql
@install.sql
```

The installer uses `CREATE OR REPLACE` for packages, so existing table data is preserved. New configuration keys are inserted only if missing (merge semantics).

3. Verify:

```sql
SELECT qubiton_api_pkg.test_connection() FROM DUAL;
```
