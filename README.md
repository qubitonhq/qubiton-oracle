# QubitOn Oracle PL/SQL Connector

![Oracle 11g+](https://img.shields.io/badge/Oracle-11g%2B-red?logo=oracle)
![PL/SQL](https://img.shields.io/badge/Language-PL%2FSQL-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)
![API Methods](https://img.shields.io/badge/API%20Methods-41-orange)

Native Oracle PL/SQL connector for the [QubitOn API](https://www.qubiton.com) — validate addresses, tax IDs, bank accounts, sanctions lists, and 37 more data quality endpoints directly from your Oracle database without middleware.

## Quick Start

```sql
-- 1. Create Oracle Wallet (skip on Autonomous DB)
--    $ cd setup/ && ./create_wallet.sh /opt/oracle/wallet

-- 2. Grant network ACL (run as DBA)
@setup/grant_network_acl.sql YOUR_SCHEMA

-- 3. Install connector
@install.sql

-- 4. Set your API key
UPDATE qubiton_config SET config_value = 'sk_live_your_key_here' WHERE config_key = 'APIKEY';
COMMIT;

-- 5. Validate!
SELECT qubiton_api_pkg.validate_address('US', '1600 Pennsylvania Ave NW', 'Washington', 'DC', '20500') FROM DUAL;
```

Get your API key at [www.qubiton.com](https://www.qubiton.com).

## Architecture

The connector is organized in three layers:

```
+-------------------------------------------------------+
|  Layer 3: EBS Integration (qubiton_ebs_pkg)           |
|  Triggers, concurrent programs, iProcurement hooks    |
+-------------------------------------------------------+
|  Layer 2: Validation Orchestrator (qubiton_validate_pkg)|
|  Config-driven, per-module rules, country filtering   |
+-------------------------------------------------------+
|  Layer 1: API Client (qubiton_api_pkg)                |
|  HTTP/JSON, 41 methods, logging, error handling       |
+-------------------------------------------------------+
|  Shared: Type Definitions (qubiton_types)             |
|  Records, constants, error codes                      |
+-------------------------------------------------------+
```

- **Layer 1 — API Client:** Direct HTTP calls to the QubitOn API. Use this for ad-hoc queries, custom integrations, or non-EBS Oracle databases.
- **Layer 2 — Validation Orchestrator:** Reads rules from `QUBITON_VALIDATION_CFG` and dispatches validations. Supports per-module error modes and country filters.
- **Layer 3 — EBS Integration:** Pre-built hooks for AP Suppliers, AR Customers, iProcurement, and concurrent programs.

## API Methods

### Address (1)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 1 | `validate_address` | `POST /api/address/validate` | Validate postal address (249 countries, USPS-certified for US) |

### Tax (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 2 | `validate_tax` | `POST /api/tax/validate` | Validate tax ID against government registries |
| 3 | `validate_tax_format` | `POST /api/tax/format-validate` | Validate tax ID format only |

### Bank (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 4 | `validate_bank_account` | `POST /api/bankaccount/validate` | Validate bank account (routing, IBAN, SWIFT) |
| 5 | `validate_bank_pro` | `POST /api/bankaccount/pro/validate` | Enhanced bank validation with account name matching |

### Email and Phone (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 6 | `validate_email` | `POST /api/email/validate` | Email deliverability and domain validation |
| 7 | `validate_phone` | `POST /api/phone/validate` | Phone number validation and formatting |

### Business Registration (1)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 8 | `lookup_business_registration` | `POST /api/businessregistration/lookup` | Company registration lookup |

### Peppol (1)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 9 | `validate_peppol` | `POST /api/peppol/validate` | Peppol participant ID validation |

### Sanctions and Compliance (3)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 10 | `check_sanctions` | `POST /api/prohibited/lookup` | Global sanctions screening (OFAC, EU, UN, UK HMT) |
| 11 | `screen_pep` | `POST /api/pep/lookup` | Politically Exposed Person screening |
| 12 | `check_directors` | `POST /api/disqualifieddirectors/validate` | Disqualified director check |

### EPA (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 13 | `check_epa_prosecution` | `POST /api/criminalprosecution/validate` | EPA enforcement action check |
| 14 | `lookup_epa_prosecution` | `POST /api/criminalprosecution/lookup` | Detailed EPA prosecution records |

### Healthcare (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 15 | `check_healthcare_exclusion` | `POST /api/providerexclusion/validate` | Healthcare exclusion list check |
| 16 | `lookup_healthcare_exclusion` | `POST /api/providerexclusion/lookup` | Detailed healthcare exclusion records |

### Risk and Financial (5)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 17 | `check_bankruptcy_risk` | `POST /api/risk/lookup` | Bankruptcy filing check |
| 18 | `lookup_credit_score` | `POST /api/risk/lookup` | Company credit score |
| 19 | `lookup_fail_rate` | `POST /api/risk/lookup` | Payment failure rate data |
| 20 | `assess_entity_risk` | `POST /api/entity/fraud/lookup` | Comprehensive entity risk assessment |
| 21 | `lookup_credit_analysis` | `POST /api/creditanalysis/lookup` | Detailed credit analysis report |

### ESG and Cybersecurity (3)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 22 | `lookup_esg_score` | `POST /api/esg/Scores` | ESG score lookup |
| 23 | `domain_security_report` | `POST /api/itsecurity/domainreport` | Domain cybersecurity report |
| 24 | `check_ip_quality` | `POST /api/ipquality/validate` | IP address reputation check |

### Corporate Structure (4)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 25 | `lookup_beneficial_ownership` | `POST /api/beneficialownership/lookup` | Beneficial ownership information |
| 26 | `lookup_corporate_hierarchy` | `POST /api/corporatehierarchy/lookup` | Corporate parent/subsidiary structure |
| 27 | `lookup_duns` | `POST /api/duns-number-lookup` | D-U-N-S number lookup |
| 28 | `lookup_hierarchy` | `POST /api/company/hierarchy/lookup` | Corporate hierarchy tree |

### Industry (4)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 29 | `validate_npi` | `POST /api/nationalprovideridentifier/validate` | National Provider Identifier validation |
| 30 | `validate_medpass` | `POST /api/medpass/validate` | MedPASS database validation |
| 31 | `lookup_dot_carrier` | `POST /api/dot/fmcsa/lookup` | DOT motor carrier lookup |
| 32 | `validate_india_identity` | `POST /api/inidentity/validate` | Indian ID validation (PAN, Aadhaar, GSTIN) |

### Certification (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 33 | `validate_certification` | `POST /api/certification/validate` | Certification number validation |
| 34 | `lookup_certification` | `POST /api/certification/lookup` | Certification search by company |

### Classification (1)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 35 | `lookup_business_classification` | `POST /api/businessclassification/lookup` | SIC/NAICS/UNSPSC classification lookup |

### Financial Ops (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 36 | `analyze_payment_terms` | `POST /api/paymentterms/validate` | Payment terms analysis |
| 37 | `lookup_exchange_rates` | `POST /api/currency/exchange-rates/{baseCurrency}` | Currency exchange rates |

### Supplier (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 38 | `lookup_ariba_supplier` | `POST /api/aribasupplierprofile/lookup` | SAP Business Network supplier search |
| 39 | `validate_ariba_supplier` | `POST /api/aribasupplierprofile/validate` | SAP Business Network ID validation |

### Gender (1)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 40 | `identify_gender` | `POST /api/genderize/identifygender` | Gender identification from name |

### Reference (2)

| # | Method | API Endpoint | Description |
|---|--------|-------------|-------------|
| 41 | `get_supported_tax_formats` | `GET /api/tax/format-validate/countries` | Supported tax ID formats by country |
| 42 | `get_peppol_schemes` | `GET /api/peppol/schemes` | Supported Peppol scheme identifiers |

## Platform Compatibility

| Platform | Version | Support Level |
|----------|---------|--------------|
| Oracle Database | 11g R2+ | Full |
| Oracle Database | 19c, 21c, 23ai | Full (recommended) |
| Oracle Autonomous DB (ATP/ADW) | All | Full (no wallet needed) |
| Oracle EBS | R12.1, R12.2 | Full (Layer 3 hooks) |
| Oracle Fusion Cloud | Via OIC or ADB extension | Full |
| Oracle JD Edwards | 9.2+ | Layer 1 only |
| Oracle PeopleSoft | 9.2+ | Layer 1 only |

## Configuration

All configuration is stored in database tables — no external config files required.

| Table | Purpose |
|-------|---------|
| `QUBITON_CONFIG` | API key, base URL, wallet path, timeout, error mode |
| `QUBITON_VALIDATION_CFG` | Per-module validation rules (which validations run, error behavior, country filters) |

See [docs/configuration.md](docs/configuration.md) for detailed configuration options.

## EBS Integration

Pre-built hooks for Oracle E-Business Suite:

- **AP Supplier validation** — trigger-based or concurrent program
- **AR Customer validation** — trigger-based
- **iProcurement** — POR_CUSTOM_PKG extension for vendor screening
- **Batch validation** — FND concurrent program with range and country filters

See [docs/ebs-integration.md](docs/ebs-integration.md) for trigger code, concurrent program registration, and rollout strategy.

## Fusion Cloud Integration

Integration patterns for Oracle Fusion / Cloud:

- **OIC REST Adapter** — event-driven validation flows
- **Autonomous DB** — direct PL/SQL with `DBMS_CLOUD`
- **VBCS** — custom UI with service connections
- **SQM** — supplier qualification questionnaire hooks

See [docs/fusion-integration.md](docs/fusion-integration.md) for architecture diagrams and implementation details.

## Testing

### Quick Connectivity Test

```sql
SELECT qubiton_api_pkg.test_connection() FROM DUAL;
```

### Unit Tests (utPLSQL v3)

```sql
@packages/qubiton_test_pkg.pkb
EXEC ut.run('qubiton_test_pkg');
```

### Manual Validation Test

```sql
DECLARE
    l_result qubiton_api_pkg.t_result;
BEGIN
    l_result := qubiton_api_pkg.parse_result(
        qubiton_api_pkg.validate_address('US', '123 Main St', 'Springfield', 'IL', '62701')
    );
    DBMS_OUTPUT.PUT_LINE(CASE WHEN l_result.is_valid THEN 'PASS' ELSE 'FAIL: ' || l_result.message END);
END;
/
```

## Documentation

| Document | Description |
|----------|-------------|
| [Setup Guide](docs/setup.md) | Prerequisites, installation, wallet, ACL, troubleshooting |
| [Configuration](docs/configuration.md) | All config options, validation rules, custom modules |
| [API Examples](docs/examples.md) | Code examples for all 41 API methods |
| [EBS Integration](docs/ebs-integration.md) | AP, AR, iProcurement, concurrent programs |
| [Fusion Integration](docs/fusion-integration.md) | OIC, ADB, VBCS, SQM patterns |
| [Oracle Certification](docs/oracle-certification.md) | Object inventory, security, compatibility matrix |

## Project Structure

```
qubiton-oracle/
  packages/
    qubiton_types.pks          -- Type definitions and constants
    qubiton_api_pkg.pks        -- Layer 1: API client (spec)
    qubiton_validate_pkg.pks   -- Layer 2: Validation orchestrator (spec)
    qubiton_validate_pkg.pkb   -- Layer 2: Validation orchestrator (body)
    qubiton_ebs_pkg.pks        -- Layer 3: EBS integration hooks (spec)
  tables/
    qubiton_config.sql         -- Configuration table
    qubiton_validation_cfg.sql -- Validation rules table
    qubiton_api_log.sql        -- Audit log table (partitioned)
  setup/
    grant_network_acl.sql      -- Network ACL grant (DBA)
  docs/
    setup.md                   -- Setup guide
    configuration.md           -- Configuration reference
    examples.md                -- API usage examples
    ebs-integration.md         -- EBS integration patterns
    fusion-integration.md      -- Fusion Cloud integration
    oracle-certification.md    -- Marketplace certification
  LICENSE                      -- MIT License
  README.md                    -- This file
```

## Other Integrations

QubitOn provides native connectors and SDKs for other platforms:

| Connector | Platform | Language | Repo |
|-----------|----------|----------|------|
| **Go SDK** | Any platform | Go | [qubiton-go](https://github.com/qubitonhq/qubiton-go) |
| **SAP S/4HANA** | SAP ECC, S/4HANA, BTP | ABAP | [qubiton-sap](https://github.com/qubitonhq/qubiton-sap) |
| **NetSuite** | All NetSuite editions | SuiteScript 2.1 | [qubiton-netsuite](https://github.com/qubitonhq/qubiton-netsuite) |
| **QuickBooks Online** | QuickBooks Online | TypeScript | [qubiton-quickbooks](https://github.com/qubitonhq/qubiton-quickbooks) |

Plus 30+ pre-built integrations for Salesforce, HubSpot, Snowflake, Databricks, Zapier, Make, and more at [www.qubiton.com/integrations](https://www.qubiton.com/integrations).

## License

MIT License. Copyright (c) 2026 [apexanalytix, Inc.](https://www.apexanalytix.com)

See [LICENSE](LICENSE) for the full license text.

---

Built by [apexanalytix](https://www.apexanalytix.com) | API documentation at [www.qubiton.com](https://www.qubiton.com)
