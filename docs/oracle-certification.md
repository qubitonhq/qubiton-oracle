# Oracle Cloud Marketplace Certification

This document provides the certification checklist, object inventory, and compliance details required for Oracle Cloud Marketplace listing.

## Object Inventory

### Tables (3)

| Object Name | Type | Tablespace | Partitioned | Description |
|-------------|------|------------|-------------|-------------|
| `QUBITON_CONFIG` | TABLE | Default | No | Connector configuration key-value store |
| `QUBITON_VALIDATION_CFG` | TABLE | Default | No | Per-module validation rules |
| `QUBITON_API_LOG` | TABLE | Default | Yes (monthly) | Audit trail for all API calls |

### Indexes (3)

| Index Name | Table | Columns | Type |
|------------|-------|---------|------|
| `QUBITON_CONFIG_PK` | `QUBITON_CONFIG` | `config_key` | Unique (PK) |
| `QUBITON_API_LOG_TS_IX` | `QUBITON_API_LOG` | `log_timestamp` | Local (partitioned) |
| `QUBITON_API_LOG_MTH_IX` | `QUBITON_API_LOG` | `api_method, log_timestamp` | Local (partitioned) |

### Constraints (5)

| Constraint Name | Table | Type | Details |
|----------------|-------|------|---------|
| `QUBITON_CONFIG_PK` | `QUBITON_CONFIG` | PRIMARY KEY | `config_key` |
| `QUBITON_VAL_CFG_PK` | `QUBITON_VALIDATION_CFG` | PRIMARY KEY | `module_name, val_type` |
| `QUBITON_VAL_CFG_ACTIVE_CK` | `QUBITON_VALIDATION_CFG` | CHECK | `active IN ('Y', 'N')` |
| `QUBITON_VAL_CFG_INVALID_CK` | `QUBITON_VALIDATION_CFG` | CHECK | `on_invalid IN ('E', 'W', 'S')` |
| `QUBITON_VAL_CFG_ERROR_CK` | `QUBITON_VALIDATION_CFG` | CHECK | `on_error IN ('E', 'W', 'S')` |

### Packages (4)

| Package Name | Layer | Spec | Body | Description |
|-------------|-------|------|------|-------------|
| `QUBITON_TYPES` | Shared | Yes | No (spec only) | Type definitions, constants, error codes |
| `QUBITON_API_PKG` | Layer 1 | Yes | Yes | HTTP/JSON client, 41 API methods |
| `QUBITON_VALIDATE_PKG` | Layer 2 | Yes | Yes | Config-driven validation orchestrator |
| `QUBITON_EBS_PKG` | Layer 3 | Yes | Yes | EBS integration hooks, concurrent program |

### Package Dependencies

```
QUBITON_TYPES (standalone — no dependencies)
    ^
    |
QUBITON_API_PKG (depends on: QUBITON_TYPES, UTL_HTTP, QUBITON_CONFIG table)
    ^
    |
QUBITON_VALIDATE_PKG (depends on: QUBITON_TYPES, QUBITON_API_PKG, QUBITON_VALIDATION_CFG table)
    ^
    |
QUBITON_EBS_PKG (depends on: QUBITON_TYPES, QUBITON_VALIDATE_PKG, QUBITON_API_PKG)
    (Optional EBS deps via dynamic SQL: AP_SUPPLIERS, HZ_PARTIES, FND_FILE, FND_REQUEST)
```

### Installation Scripts

| Script | Purpose | Run As |
|--------|---------|--------|
| `install.sql` | Creates all objects and seeds configuration | Schema owner |
| `uninstall.sql` | Drops all QubitOn objects | Schema owner |
| `setup/grant_network_acl.sql` | Grants network ACL | SYS/DBA |
| `setup/create_wallet.sh` | Creates Oracle Wallet with CA certs | OS user (oracle) |

### Test Package

| Package Name | Description |
|-------------|-------------|
| `QUBITON_TEST_PKG` | utPLSQL v3 test suite — connectivity, validation, error handling |

## Security Compliance

### No Hardcoded Credentials

- API key stored in `QUBITON_CONFIG` table, never in package source code
- Wallet password passed as parameter or stored in auto-login wallet
- No credentials in PL/SQL package specs or bodies
- Dynamic SQL used for EBS table access (no compile-time dependency on EBS objects)

**Verification:**

```sql
-- Confirm no hardcoded keys in package source
SELECT name, type, line, text
FROM   user_source
WHERE  UPPER(text) LIKE '%SK_LIVE%'
   OR  UPPER(text) LIKE '%SK_TEST%'
   OR  UPPER(text) LIKE '%API_KEY%PASSWORD%';
-- Expected: 0 rows
```

### Audit Trail

All API calls are logged to `QUBITON_API_LOG` with:

- Timestamp
- Calling user (from `SYS_CONTEXT('USERENV', 'SESSION_USER')`)
- Calling module (from `SYS_CONTEXT('USERENV', 'MODULE')`)
- HTTP status code
- Response time
- Error details (if any)

Logging uses `PRAGMA AUTONOMOUS_TRANSACTION` to survive rollbacks.

**No sensitive data in logs:**

- Request/response bodies are NOT logged
- API keys are NOT logged
- Only method names, status codes, and timing data are recorded

### TLS/HTTPS

- All API communication uses HTTPS (TLS 1.2+)
- CA certificates stored in Oracle Wallet (on-premises) or pre-loaded (ADB)
- No `InsecureSkipVerify` equivalent — certificate validation is always enforced
- Connector sets `User-Agent: qubiton-oracle/1.0.0` on all requests

### Privilege Model

| Privilege | Required By | Purpose |
|-----------|-------------|---------|
| `EXECUTE ON UTL_HTTP` | `QUBITON_API_PKG` | Make HTTPS calls |
| `EXECUTE ON UTL_URL` | `QUBITON_API_PKG` | URL encoding |
| `EXECUTE ON DBMS_OUTPUT` | `QUBITON_VALIDATE_PKG` | Warning mode output |
| Network ACL (connect, resolve) | Schema | Outbound to `api.qubiton.com:443` |
| `CREATE TABLE` | Schema (install only) | Create configuration and log tables |
| `CREATE PROCEDURE` | Schema (install only) | Create packages |

**No SYS privileges required at runtime.** The `grant_network_acl.sql` script is the only step requiring DBA access.

### Data Handling

- No customer data is stored persistently by the connector
- Request data is passed through to the API and not cached
- The `QUBITON_API_LOG` table stores metadata only (method, status, timing), not request/response payloads
- All data in transit is encrypted via TLS

## Version Compatibility Matrix

### Oracle Database Versions

| Oracle Version | Supported | Notes |
|----------------|-----------|-------|
| 11g R2 (11.2.0.4+) | Yes | 11g-style ACL, no interval partitioning for log table |
| 12c R1 (12.1) | Yes | Full feature support |
| 12c R2 (12.2) | Yes | Full feature support |
| 18c (12.2.0.2) | Yes | Full feature support |
| 19c (19.3+) | Yes | Recommended LTS version |
| 21c | Yes | Full feature support |
| 23ai (23.4+) | Yes | Full feature support, JSON duality views compatible |

### Oracle Cloud Versions

| Platform | Supported | Notes |
|----------|-----------|-------|
| Autonomous Database (ATP/ADW) | Yes | No wallet needed, use `DBMS_CLOUD` |
| Autonomous JSON Database | Yes | Full support |
| Base Database Service | Yes | Standard wallet + ACL setup |
| ExaDB-D / ExaDB-C@C | Yes | Standard wallet + ACL setup |

### Oracle Applications

| Application | Version | Integration Method |
|-------------|---------|-------------------|
| EBS R12.1 | 12.1.3+ | Direct PL/SQL (Layer 3) |
| EBS R12.2 | 12.2.x | Direct PL/SQL (Layer 3) |
| Fusion Cloud | 24A+ | OIC REST adapter or ADB extension |
| JD Edwards | 9.2+ | Direct PL/SQL (Layer 1 only) |
| PeopleSoft | 9.2+ | Direct PL/SQL (Layer 1 only) |

### PL/SQL Feature Requirements

| Feature | Min Version | Used By | Fallback |
|---------|-------------|---------|----------|
| `UTL_HTTP` | 11g R2 | Layer 1 (API calls) | None (required) |
| Identity columns | 12c | `QUBITON_API_LOG` | Sequence + trigger on 11g |
| Interval partitioning | 12c | `QUBITON_API_LOG` | Simple table on 11g |
| `JSON_OBJECT` SQL | 12c R2 | Examples/docs only | `build_json()` function |
| `DBMS_CLOUD` | ADB only | Autonomous DB pattern | `UTL_HTTP` with wallet |

## Performance Characteristics

### Response Times (p50 / p95 / p99)

Measured from PL/SQL call to return, including network round-trip to `api.qubiton.com`:

| API Method | p50 | p95 | p99 |
|------------|-----|-----|-----|
| `validate_address` | 150ms | 350ms | 800ms |
| `validate_tax` | 120ms | 280ms | 600ms |
| `validate_bank_account` | 130ms | 300ms | 650ms |
| `check_sanctions` | 180ms | 400ms | 900ms |
| `validate_email` | 200ms | 500ms | 1200ms |
| `validate_phone` | 100ms | 250ms | 500ms |
| `test_connection` | 50ms | 120ms | 250ms |

### Throughput

| Configuration | Calls/sec | Notes |
|---------------|-----------|-------|
| Single session | 5-10 | Sequential calls, single HTTP connection |
| 10 concurrent sessions | 40-80 | Each session maintains its own connection |
| Batch with parallel hint | 50-100 | Using `DBMS_PARALLEL_EXECUTE` |

### Resource Usage

| Resource | Usage | Notes |
|----------|-------|-------|
| SGA/PGA per session | ~100 KB | Package state + CLOB buffers |
| Table storage (config) | <1 KB | 7 rows default |
| Table storage (log) | ~200 bytes/row | ~5.8 MB per 100K calls |
| Network | 1-5 KB per request | JSON payload size |

### Optimization Recommendations

1. **Connection reuse:** PL/SQL sessions reuse HTTP connections automatically via `UTL_HTTP` persistent connections
2. **Batch processing:** Use cursor-based loops with exception handling per record to prevent one failure from stopping the batch
3. **Parallel execution:** Use `DBMS_PARALLEL_EXECUTE` for large-volume processing
4. **Partition maintenance:** Drop old `QUBITON_API_LOG` partitions monthly to prevent unbounded growth
5. **Index maintenance:** The two local indexes on `QUBITON_API_LOG` are partition-aligned and self-maintaining

## Error Handling Documentation

### Error Code Ranges

| Code Range | Source | Description |
|------------|--------|-------------|
| `-20001` to `-20011` | `qubiton_types` | Connector-level errors |
| `-20100` to `-20108` | `qubiton_api_pkg` | API client errors |
| `-20200` to `-20299` | Application triggers | Custom application errors |

### Error Code Reference

| Code | Constant | Description | Recovery |
|------|----------|-------------|----------|
| `-20001` | `gc_err_connection` | Network/connection failure | Check network, firewall, DNS |
| `-20002` | `gc_err_timeout` | HTTP timeout | Increase timeout, check network latency |
| `-20003` | `gc_err_auth` | 401 Unauthorized | Verify API key in `QUBITON_CONFIG` |
| `-20004` | `gc_err_forbidden` | 403 Forbidden | Check API plan permissions |
| `-20005` | `gc_err_rate_limit` | 429 Too Many Requests | Reduce call frequency, upgrade plan |
| `-20006` | `gc_err_server` | 5xx Server Error | Retry after delay, contact support if persistent |
| `-20007` | `gc_err_json` | JSON parse/build error | Check request parameters, report bug |
| `-20008` | `gc_err_wallet` | Oracle Wallet error | Verify wallet path and certificates |
| `-20009` | `gc_err_acl` | Network ACL denied | Run `grant_network_acl.sql` as DBA |
| `-20010` | `gc_err_authz` | Application authorization error | Check schema privileges |
| `-20011` | `gc_err_validation` | Input validation error | Fix input parameters |
| `-20100` | `gc_err_not_initialized` | Package not initialized | Call `init()` or verify `QUBITON_CONFIG` |
| `-20101` | `gc_err_required_param` | Required parameter missing | Provide all required parameters |
| `-20102` | `gc_err_http_request` | HTTP request failed | Check network connectivity |
| `-20103` | `gc_err_http_status` | Unexpected HTTP status | Check API response details |
| `-20104` | `gc_err_rate_limited` | Rate limit exceeded | Wait and retry |
| `-20105` | `gc_err_config_missing` | Configuration key missing | Insert required config key |
| `-20106` | `gc_err_validation_failed` | Validation check failed | Review validation result details |
| `-20107` | `gc_err_parse_failed` | Response parsing failed | Check raw JSON response |
| `-20108` | `gc_err_timeout` | Request timeout | Increase timeout or retry |

### Graceful Degradation

The connector follows these principles:

1. **Layer 2 never crashes the caller:** `validate_supplier_all` and `validate_customer_all` catch all exceptions and return `TRUE` (allow) on unhandled errors
2. **Autonomous logging:** Log entries persist via `PRAGMA AUTONOMOUS_TRANSACTION` even if the calling transaction rolls back
3. **Configurable strictness:** Each validation can independently choose to block, warn, or stay silent on failures
4. **Session override:** Emergency bypass available via `qubiton_validate_pkg.init(p_error_mode => 'S')`

## Installation Verification Checklist

Run after installation to verify all objects are created correctly:

```sql
-- 1. Verify tables
SELECT table_name, num_rows, partitioned
FROM   user_tables
WHERE  table_name LIKE 'QUBITON%'
ORDER  BY table_name;
-- Expected: 3 tables

-- 2. Verify packages
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name LIKE 'QUBITON%'
  AND  object_type IN ('PACKAGE', 'PACKAGE BODY')
ORDER  BY object_name, object_type;
-- Expected: 4 PACKAGE + 3 PACKAGE BODY (qubiton_types has no body), all VALID

-- 3. Verify constraints
SELECT constraint_name, table_name, constraint_type, status
FROM   user_constraints
WHERE  constraint_name LIKE 'QUBITON%'
ORDER  BY table_name, constraint_name;
-- Expected: 5 constraints, all ENABLED

-- 4. Verify indexes
SELECT index_name, table_name, uniqueness, status
FROM   user_indexes
WHERE  index_name LIKE 'QUBITON%'
ORDER  BY index_name;
-- Expected: 3 indexes (1 unique PK + 2 non-unique)

-- 5. Verify configuration
SELECT config_key, LENGTH(config_value) AS val_len
FROM   qubiton_config
ORDER  BY config_key;
-- Expected: 7 rows (APIKEY, BASE_URL, ERROR_MODE, LOG_ENABLED, TIMEOUT, WALLET_PASSWORD, WALLET_PATH)

-- 6. Verify connectivity
SELECT qubiton_api_pkg.test_connection() FROM DUAL;
-- Expected: 'OK' or similar success message

-- 7. Verify no invalid objects
SELECT object_name, object_type
FROM   user_objects
WHERE  object_name LIKE 'QUBITON%'
  AND  status = 'INVALID';
-- Expected: 0 rows
```

## Marketplace Listing Metadata

| Field | Value |
|-------|-------|
| Product Name | QubitOn Oracle PL/SQL Connector |
| Version | 1.0.0 |
| Publisher | apexanalytix, Inc. |
| License | MIT |
| Category | Data Quality, Compliance, Integration |
| Supported Platforms | Oracle Database 11g R2+, Autonomous Database, EBS R12, Fusion Cloud |
| Languages | PL/SQL |
| Dependencies | Oracle Wallet (on-premises), Network ACL |
| Runtime Dependencies | None (self-contained PL/SQL) |
| External Services | QubitOn API (`api.qubiton.com`, HTTPS port 443) |
| Support URL | https://www.qubiton.com/support |
| Documentation URL | https://www.qubiton.com/docs/oracle |
