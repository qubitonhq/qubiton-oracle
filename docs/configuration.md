# Configuration Guide

The QubitOn Oracle connector uses two configuration tables to control API connectivity and validation behavior.

## QUBITON_CONFIG Table

General connector settings stored as key-value pairs.

### Schema

```sql
CREATE TABLE qubiton_config (
    config_key    VARCHAR2(50)   NOT NULL,   -- Parameter name (PK)
    config_value  VARCHAR2(4000) NOT NULL,   -- Parameter value
    description   VARCHAR2(200),             -- Human-readable description
    updated_by    VARCHAR2(128),             -- Last modified by (auto-set)
    updated_at    TIMESTAMP                  -- Last modified time (auto-set)
);
```

### Configuration Keys

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `APIKEY` | Yes | — | Your QubitOn API key (starts with `sk_live_` or `sk_test_`) |
| `BASE_URL` | No | `https://api.qubiton.com` | API base URL (override for testing or private instances) |
| `WALLET_PATH` | Yes* | — | Oracle Wallet path (e.g., `file:/opt/oracle/wallet`). *Not required on Autonomous DB |
| `WALLET_PASSWORD` | No | — | Wallet password (if not using auto-login wallet) |
| `TIMEOUT` | No | `30` | HTTP request timeout in seconds |
| `ERROR_MODE` | No | `E` | Default error mode: `E`=raise exception, `W`=warn, `S`=silent |
| `LOG_ENABLED` | No | `Y` | Enable API call logging to `QUBITON_API_LOG`: `Y` or `N` |

### Setting Configuration

```sql
-- Set your API key
UPDATE qubiton_config
SET config_value = 'sk_live_abc123def456',
    updated_at   = SYSTIMESTAMP
WHERE config_key = 'APIKEY';

-- Change timeout to 60 seconds
UPDATE qubiton_config
SET config_value = '60',
    updated_at   = SYSTIMESTAMP
WHERE config_key = 'TIMEOUT';

-- Disable logging (not recommended for production)
UPDATE qubiton_config
SET config_value = 'N',
    updated_at   = SYSTIMESTAMP
WHERE config_key = 'LOG_ENABLED';

COMMIT;
```

### Adding Custom Configuration Keys

You can store additional key-value pairs in the same table:

```sql
INSERT INTO qubiton_config (config_key, config_value, description)
VALUES ('CUSTOM_HEADER_X', 'my-value', 'Custom header for internal routing');
COMMIT;
```

### Viewing Current Configuration

```sql
SELECT config_key,
       CASE WHEN config_key = 'APIKEY'
            THEN SUBSTR(config_value, 1, 10) || '****'
            ELSE config_value
       END AS config_value,
       description,
       updated_at
FROM   qubiton_config
ORDER  BY config_key;
```

## QUBITON_VALIDATION_CFG Table

Per-module, per-validation-type rules that control the Layer 2 validation orchestrator (`qubiton_validate_pkg`).

### Schema

```sql
CREATE TABLE qubiton_validation_cfg (
    module_name    VARCHAR2(30)  NOT NULL,  -- Module identifier (PK part 1)
    val_type       VARCHAR2(20)  NOT NULL,  -- Validation type (PK part 2)
    active         VARCHAR2(1)   DEFAULT 'Y' NOT NULL,  -- Y=enabled, N=disabled
    on_invalid     VARCHAR2(1)   DEFAULT 'E' NOT NULL,  -- Action when data is invalid
    on_error       VARCHAR2(1)   DEFAULT 'W' NOT NULL,  -- Action when API call fails
    country_filter VARCHAR2(500) DEFAULT NULL,           -- Comma-separated ISO codes
    description    VARCHAR2(200),
    updated_by     VARCHAR2(128),
    updated_at     TIMESTAMP
);
```

### Column Details

#### module_name

Identifies the Oracle module or business context. The connector ships with two default modules:

| Module | Description |
|--------|-------------|
| `AP_SUPPLIERS` | Accounts Payable supplier validation (EBS AP module) |
| `HZ_PARTIES` | Trading Community Architecture customer validation (EBS AR module) |

You can add custom modules for any business context (see [Adding Custom Modules](#adding-custom-modules)).

#### val_type

The type of validation to perform:

| Type | API Method Called | Description |
|------|-------------------|-------------|
| `TAX` | `validate_tax` | Tax ID validation |
| `BANK` | `validate_bank_account` | Bank account validation |
| `ADDRESS` | `validate_address` | Address validation |
| `SANCTION` | `check_sanctions` | Global sanctions screening |
| `EMAIL` | `validate_email` | Email address validation |
| `PHONE` | `validate_phone` | Phone number validation |

#### active

- `Y` — validation is active and will be executed
- `N` — validation is skipped (useful for temporary disablement without deleting the row)

#### on_invalid

What happens when the API returns a successful response but the data fails validation (e.g., invalid tax ID):

| Value | Constant | Behavior |
|-------|----------|----------|
| `E` | `qubiton_types.gc_mode_stop` | Set `t_result.blocked := TRUE` — caller should prevent the save/transaction |
| `W` | `qubiton_types.gc_mode_warn` | Write warning to `DBMS_OUTPUT`, set `blocked := FALSE` — allow save |
| `S` | `qubiton_types.gc_mode_silent` | Return `blocked := FALSE` silently — no output, allow save |

#### on_error

What happens when the API call itself fails (network error, timeout, 5xx response):

| Value | Constant | Behavior |
|-------|----------|----------|
| `E` | `qubiton_types.gc_mode_stop` | Set `blocked := TRUE` — prevent save on API failure |
| `W` | `qubiton_types.gc_mode_warn` | Write warning, allow save — **recommended for production** |
| `S` | `qubiton_types.gc_mode_silent` | Allow save silently — useful for non-critical validations |

#### country_filter

Comma-separated ISO 3166-1 alpha-2 country codes. When set, the validation only runs for the listed countries.

| Value | Behavior |
|-------|----------|
| `NULL` | All countries enabled (no filter) |
| `'US'` | Only US |
| `'US,CA,MX'` | North America only |
| `'GB,DE,FR,IT,ES,NL,BE,AT'` | Selected European countries |

### Default Configuration

The installer seeds these defaults:

```sql
-- AP_SUPPLIERS: validate tax, bank, address, sanctions
INSERT INTO qubiton_validation_cfg VALUES ('AP_SUPPLIERS', 'TAX',      'Y', 'E', 'W', NULL, 'Supplier tax ID validation');
INSERT INTO qubiton_validation_cfg VALUES ('AP_SUPPLIERS', 'BANK',     'Y', 'E', 'W', NULL, 'Supplier bank account validation');
INSERT INTO qubiton_validation_cfg VALUES ('AP_SUPPLIERS', 'ADDRESS',  'Y', 'W', 'W', NULL, 'Supplier address validation');
INSERT INTO qubiton_validation_cfg VALUES ('AP_SUPPLIERS', 'SANCTION', 'Y', 'E', 'W', NULL, 'Supplier sanctions screening');

-- HZ_PARTIES: validate tax, address, sanctions
INSERT INTO qubiton_validation_cfg VALUES ('HZ_PARTIES', 'TAX',      'Y', 'E', 'W', NULL, 'Customer tax ID validation');
INSERT INTO qubiton_validation_cfg VALUES ('HZ_PARTIES', 'ADDRESS',  'Y', 'W', 'W', NULL, 'Customer address validation');
INSERT INTO qubiton_validation_cfg VALUES ('HZ_PARTIES', 'SANCTION', 'Y', 'E', 'W', NULL, 'Customer sanctions screening');
```

### Customizing Error Modes Per Module

Different modules often need different strictness levels:

```sql
-- AP_SUPPLIERS: strict — block on invalid tax/bank, warn on invalid address
UPDATE qubiton_validation_cfg SET on_invalid = 'E' WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'TAX';
UPDATE qubiton_validation_cfg SET on_invalid = 'E' WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'BANK';
UPDATE qubiton_validation_cfg SET on_invalid = 'W' WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'ADDRESS';

-- HZ_PARTIES: lenient — warn on everything, never block customers
UPDATE qubiton_validation_cfg SET on_invalid = 'W' WHERE module_name = 'HZ_PARTIES' AND val_type = 'TAX';
UPDATE qubiton_validation_cfg SET on_invalid = 'W' WHERE module_name = 'HZ_PARTIES' AND val_type = 'ADDRESS';
UPDATE qubiton_validation_cfg SET on_invalid = 'W' WHERE module_name = 'HZ_PARTIES' AND val_type = 'SANCTION';

COMMIT;
```

### Restricting Validations by Country

```sql
-- Only validate tax for US and EU suppliers
UPDATE qubiton_validation_cfg
SET country_filter = 'US,DE,FR,IT,ES,NL,BE,AT,PT,FI,SE,DK,NO,PL,CZ,SK,HU,RO,BG,HR,SI,EE,LV,LT,LU,MT,CY,GR,IE,GB'
WHERE module_name = 'AP_SUPPLIERS'
  AND val_type    = 'TAX';

-- Sanctions screening for all countries (NULL = no filter)
UPDATE qubiton_validation_cfg
SET country_filter = NULL
WHERE module_name = 'AP_SUPPLIERS'
  AND val_type    = 'SANCTION';

COMMIT;
```

### Adding Custom Modules

You can create validation rules for any business context beyond the default EBS modules.

#### Example: iProcurement Vendor Screening

```sql
INSERT INTO qubiton_validation_cfg (module_name, val_type, active, on_invalid, on_error, country_filter, description)
VALUES ('IPROCUREMENT', 'SANCTION', 'Y', 'E', 'W', NULL, 'Screen iProcurement suggested vendors');

INSERT INTO qubiton_validation_cfg (module_name, val_type, active, on_invalid, on_error, country_filter, description)
VALUES ('IPROCUREMENT', 'TAX', 'Y', 'W', 'S', 'US,CA', 'Validate iProcurement vendor tax (N.America)');
COMMIT;
```

#### Example: Custom Onboarding Application

```sql
INSERT INTO qubiton_validation_cfg (module_name, val_type, active, on_invalid, on_error, country_filter, description)
VALUES ('VENDOR_PORTAL', 'TAX',      'Y', 'E', 'E', NULL, 'Tax validation during self-service onboarding');

INSERT INTO qubiton_validation_cfg (module_name, val_type, active, on_invalid, on_error, country_filter, description)
VALUES ('VENDOR_PORTAL', 'BANK',     'Y', 'E', 'E', NULL, 'Bank validation during self-service onboarding');

INSERT INTO qubiton_validation_cfg (module_name, val_type, active, on_invalid, on_error, country_filter, description)
VALUES ('VENDOR_PORTAL', 'ADDRESS',  'Y', 'E', 'W', NULL, 'Address validation during self-service onboarding');

INSERT INTO qubiton_validation_cfg (module_name, val_type, active, on_invalid, on_error, country_filter, description)
VALUES ('VENDOR_PORTAL', 'SANCTION', 'Y', 'E', 'W', NULL, 'Sanctions screening during self-service onboarding');

INSERT INTO qubiton_validation_cfg (module_name, val_type, active, on_invalid, on_error, country_filter, description)
VALUES ('VENDOR_PORTAL', 'EMAIL',    'Y', 'W', 'S', NULL, 'Email validation during self-service onboarding');

INSERT INTO qubiton_validation_cfg (module_name, val_type, active, on_invalid, on_error, country_filter, description)
VALUES ('VENDOR_PORTAL', 'PHONE',    'Y', 'W', 'S', NULL, 'Phone validation during self-service onboarding');
COMMIT;
```

Then call from your custom PL/SQL:

```sql
DECLARE
    l_ok BOOLEAN;
BEGIN
    l_ok := qubiton_validate_pkg.validate_supplier_all(
        p_module_name   => 'VENDOR_PORTAL',
        p_vendor_id     => :new_vendor_id,
        p_vendor_name   => :new_vendor_name,
        p_country       => :new_country,
        p_tax_id        => :new_tax_id,
        p_address_line1 => :new_address_line1,
        p_city          => :new_city,
        p_state         => :new_state,
        p_postal_code   => :new_postal_code,
        p_account_number => :new_acct_num,
        p_routing_number => :new_routing_num
    );

    IF NOT l_ok THEN
        RAISE_APPLICATION_ERROR(-20200, 'Vendor validation failed. Check QubitOn API log for details.');
    END IF;
END;
```

## Error Modes — Detailed Behavior

### How parse_result Works

`qubiton_api_pkg.parse_result` extracts a structured result from the raw JSON response:

```sql
DECLARE
    l_json   CLOB;
    l_result qubiton_api_pkg.t_result;
BEGIN
    l_json := qubiton_api_pkg.validate_tax(
        p_tax_id  => '123456789',
        p_country => 'US'
    );

    l_result := qubiton_api_pkg.parse_result(l_json);

    DBMS_OUTPUT.PUT_LINE('Success:       ' || CASE WHEN l_result.success       THEN 'TRUE' ELSE 'FALSE' END);
    DBMS_OUTPUT.PUT_LINE('Is Valid:      ' || CASE WHEN l_result.is_valid      THEN 'TRUE' ELSE 'FALSE' END);
    DBMS_OUTPUT.PUT_LINE('Message:       ' || l_result.message);
    DBMS_OUTPUT.PUT_LINE('Field Missing: ' || CASE WHEN l_result.field_missing THEN 'TRUE' ELSE 'FALSE' END);
END;
```

The `p_field_name` parameter (default `'isValid'`) controls which JSON field is checked for the `is_valid` flag. Most endpoints use `isValid`, but some use different field names:

| Endpoint Category | Field Name | Notes |
|-------------------|------------|-------|
| Address, Tax, Bank, Email, Phone, Peppol, NPI, Certification | `isValid` | Standard validation field |
| Sanctions (`check_sanctions`) | `isMatch` | TRUE means entity was found on a sanctions list |
| PEP (`screen_pep`) | `isMatch` | TRUE means entity is a politically exposed person |
| Business Registration | `isRegistered` | TRUE means company is registered |
| Risk (`assess_entity_risk`) | `riskLevel` | Not boolean — use `message` field for interpretation |

### How handle_result Works

`qubiton_api_pkg.handle_result` wraps `parse_result` and applies error mode logic:

```sql
DECLARE
    l_json   CLOB;
    l_result qubiton_api_pkg.t_result;
BEGIN
    l_json := qubiton_api_pkg.validate_tax(
        p_tax_id  => '123456789',
        p_country => 'US'
    );

    -- Use warning mode regardless of package default
    l_result := qubiton_api_pkg.handle_result(
        p_json       => l_json,
        p_error_mode => 'W'
    );

    IF NOT l_result.is_valid THEN
        -- Data is invalid, but we chose 'W' so no exception was raised
        DBMS_OUTPUT.PUT_LINE('Warning: ' || l_result.message);
    END IF;
END;
```

### Error Mode Precedence

The effective error mode is resolved in this order (first non-NULL wins):

1. **Session override** — set via `qubiton_validate_pkg.init(p_error_mode => 'W')`
2. **Per-call override** — passed to `handle_result(p_error_mode => 'S')`
3. **Per-config setting** — `on_invalid` or `on_error` column in `QUBITON_VALIDATION_CFG`
4. **Package default** — `ERROR_MODE` value in `QUBITON_CONFIG` table
5. **Hardcoded fallback** — `'W'` (warn)

### Session-Level Override

Override the error mode for all validations in the current database session:

```sql
-- Set all validations to warning mode for this session
EXEC qubiton_validate_pkg.init(p_error_mode => 'W');

-- Run validations (all use 'W' regardless of config)
...

-- Reset to config-driven mode
EXEC qubiton_validate_pkg.init(p_error_mode => NULL);
```

This is useful for:
- Data migration scripts (use `'S'` to log without blocking)
- Testing (use `'W'` to see warnings without exceptions)
- Emergency bypass (use `'S'` if the API is experiencing issues)

## QUBITON_API_LOG Table

All API calls are logged (when `LOG_ENABLED = 'Y'`) to the `QUBITON_API_LOG` table via `PRAGMA AUTONOMOUS_TRANSACTION`, so log entries persist even if the calling transaction rolls back.

### Schema

| Column | Type | Description |
|--------|------|-------------|
| `log_id` | `NUMBER` (identity) | Auto-generated sequence |
| `log_timestamp` | `TIMESTAMP` | When the call was made |
| `api_method` | `VARCHAR2(100)` | PL/SQL function name (e.g., `validate_address`) |
| `http_method` | `VARCHAR2(10)` | HTTP method (`POST` or `GET`) |
| `endpoint_path` | `VARCHAR2(500)` | API endpoint path |
| `http_status` | `NUMBER(3)` | HTTP response status code |
| `elapsed_ms` | `NUMBER(10)` | Round-trip time in milliseconds |
| `request_bytes` | `NUMBER(10)` | Request body size |
| `response_bytes` | `NUMBER(10)` | Response body size |
| `error_code` | `NUMBER(6)` | Oracle error code (if call failed) |
| `error_message` | `VARCHAR2(4000)` | Error description |
| `calling_user` | `VARCHAR2(128)` | Database user who made the call |
| `calling_module` | `VARCHAR2(100)` | Application module (from `DBMS_APPLICATION_INFO`) |

### Useful Queries

```sql
-- Recent failures
SELECT log_timestamp, api_method, http_status, error_message
FROM   qubiton_api_log
WHERE  (http_status >= 400 OR error_code IS NOT NULL)
ORDER  BY log_timestamp DESC
FETCH  FIRST 20 ROWS ONLY;

-- Average response time by method (last 24h)
SELECT api_method,
       COUNT(*)           AS call_count,
       ROUND(AVG(elapsed_ms))  AS avg_ms,
       ROUND(MAX(elapsed_ms))  AS max_ms,
       MIN(http_status)   AS min_status,
       MAX(http_status)   AS max_status
FROM   qubiton_api_log
WHERE  log_timestamp > SYSTIMESTAMP - INTERVAL '1' DAY
GROUP  BY api_method
ORDER  BY call_count DESC;

-- Rate limit hits
SELECT log_timestamp, api_method, calling_user
FROM   qubiton_api_log
WHERE  http_status = 429
ORDER  BY log_timestamp DESC;
```

### Log Maintenance

The table is partitioned by month (Oracle 12c+). Drop old partitions to reclaim space:

```sql
-- Drop partitions older than 6 months
ALTER TABLE qubiton_api_log DROP PARTITION SYS_P00042;

-- Or use automated partition management (12c+)
-- The INTERVAL partitioning creates new partitions automatically
```

On Oracle 11g (no interval partitioning), create partitions manually or use a scheduled job.
