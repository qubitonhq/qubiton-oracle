# Oracle E-Business Suite (EBS) Integration

This guide covers integration patterns for Oracle EBS R12 using the Layer 3 `qubiton_ebs_pkg` package.

## Architecture

```
+---------------------+     +-------------------------+     +------------------+
|  EBS Application    |     |  QubitOn Connector       |     |  QubitOn API     |
|                     |     |                         |     |                  |
|  AP_SUPPLIERS ------+---->|  qubiton_ebs_pkg (L3)   |     |                  |
|  HZ_PARTIES   ------+---->|    |                    |     |                  |
|  iProcurement ------+---->|    v                    |     |                  |
|  Concurrent Mgr ----+---->|  qubiton_validate_pkg   |     |                  |
|                     |     |  (L2 - Orchestrator)    |     |                  |
|                     |     |    |                    |     |                  |
|                     |     |    v                    |     |                  |
|                     |     |  qubiton_api_pkg (L1)   +---->|  api.qubiton.com |
|                     |     |  (HTTP/JSON Client)     |     |                  |
+---------------------+     +-------------------------+     +------------------+
                                      |
                                      v
                             QUBITON_VALIDATION_CFG
                             QUBITON_API_LOG
                             QUBITON_CONFIG
```

## AP Supplier Validation

### Trigger-Based Validation (Real-Time)

Create a `BEFORE INSERT OR UPDATE` trigger on `AP_SUPPLIERS` to validate suppliers in real time.

```sql
CREATE OR REPLACE TRIGGER qubiton_ap_supplier_biu_trg
BEFORE INSERT OR UPDATE ON ap_suppliers
FOR EACH ROW
DECLARE
    l_ok BOOLEAN;
BEGIN
    -- Skip if no meaningful change to validated fields
    IF UPDATING AND
       :NEW.vendor_name       = :OLD.vendor_name AND
       :NEW.num_1099          = :OLD.num_1099 AND
       :NEW.vat_registration_num = :OLD.vat_registration_num
    THEN
        RETURN;
    END IF;

    l_ok := qubiton_ebs_pkg.validate_ap_supplier(
        p_vendor_id    => :NEW.vendor_id,
        p_calling_mode => 'TRIGGER'
    );

    IF NOT l_ok THEN
        RAISE_APPLICATION_ERROR(
            -20200,
            'Supplier validation failed. Check the QubitOn API log for details. '
            || 'Vendor: ' || :NEW.vendor_name || ' (ID: ' || :NEW.vendor_id || ')'
        );
    END IF;
END;
/
```

### Post-Event Trigger (Non-Blocking)

For environments where blocking is too disruptive, use `AFTER` triggers that log warnings:

```sql
CREATE OR REPLACE TRIGGER qubiton_ap_supplier_ai_trg
AFTER INSERT ON ap_suppliers
FOR EACH ROW
BEGIN
    qubiton_ebs_pkg.on_supplier_create(p_vendor_id => :NEW.vendor_id);
END;
/

CREATE OR REPLACE TRIGGER qubiton_ap_supplier_au_trg
AFTER UPDATE ON ap_suppliers
FOR EACH ROW
BEGIN
    -- Only fire when validated fields change
    IF :NEW.vendor_name          != :OLD.vendor_name OR
       :NEW.num_1099             != :OLD.num_1099 OR
       :NEW.vat_registration_num != :OLD.vat_registration_num
    THEN
        qubiton_ebs_pkg.on_supplier_update(p_vendor_id => :NEW.vendor_id);
    END IF;
END;
/
```

The `on_supplier_create` and `on_supplier_update` procedures run validations in warning mode (`W`), log results to `QUBITON_API_LOG`, but never block the transaction.

### Supplier Site Validation

To validate supplier sites (bank accounts, addresses per site):

```sql
CREATE OR REPLACE TRIGGER qubiton_ap_site_biu_trg
BEFORE INSERT OR UPDATE ON ap_supplier_sites_all
FOR EACH ROW
DECLARE
    l_result qubiton_types.t_result;
    l_vendor_name ap_suppliers.vendor_name%TYPE;
BEGIN
    SELECT vendor_name INTO l_vendor_name
    FROM   ap_suppliers
    WHERE  vendor_id = :NEW.vendor_id;

    -- Validate site address
    IF :NEW.address_line1 IS NOT NULL THEN
        l_result := qubiton_validate_pkg.validate_supplier_address(
            p_vendor_id     => :NEW.vendor_id,
            p_country       => :NEW.country,
            p_address_line1 => :NEW.address_line1,
            p_city          => :NEW.city,
            p_state         => :NEW.state,
            p_postal_code   => :NEW.zip
        );

        IF l_result.blocked THEN
            RAISE_APPLICATION_ERROR(
                -20201,
                'Site address validation failed: ' || l_result.message
            );
        END IF;
    END IF;
END;
/
```

## iProcurement Hook (POR_CUSTOM_PKG Extension)

Oracle iProcurement allows customization through `POR_CUSTOM_PKG`. Extend it to screen suggested vendors during requisition creation.

### Step 1: Create the custom package body

```sql
CREATE OR REPLACE PACKAGE BODY por_custom_pkg AS

    PROCEDURE validate_requisition(
        p_requisition_header_id IN NUMBER,
        x_return_status         OUT VARCHAR2,
        x_error_message         OUT VARCHAR2
    )
    IS
        l_ok BOOLEAN;
    BEGIN
        x_return_status := 'S';  -- Success by default

        l_ok := qubiton_ebs_pkg.validate_iprocurement_req(
            p_requisition_header_id => p_requisition_header_id
        );

        IF NOT l_ok THEN
            x_return_status := 'E';
            x_error_message := 'One or more suggested vendors failed compliance screening. '
                            || 'Review the QubitOn validation log before approving.';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            -- iProcurement custom hooks must not crash the application
            x_return_status := 'S';
            x_error_message := NULL;
    END validate_requisition;

END por_custom_pkg;
/
```

### Step 2: Register in iProcurement workflow

The `validate_requisition` procedure is called during the approval workflow. Configure the iProcurement Approval Workflow (AME rules) to invoke this validation step.

## AR Customer Validation

### Trigger on HZ_CUST_ACCOUNTS

```sql
CREATE OR REPLACE TRIGGER qubiton_hz_cust_biu_trg
BEFORE INSERT OR UPDATE ON hz_cust_accounts
FOR EACH ROW
DECLARE
    l_ok BOOLEAN;
BEGIN
    IF UPDATING AND
       :NEW.account_name = :OLD.account_name
    THEN
        RETURN;
    END IF;

    l_ok := qubiton_ebs_pkg.validate_ar_customer(
        p_cust_account_id => :NEW.cust_account_id,
        p_calling_mode    => 'TRIGGER'
    );

    IF NOT l_ok THEN
        RAISE_APPLICATION_ERROR(
            -20202,
            'Customer validation failed. Check the QubitOn API log for details. '
            || 'Customer: ' || :NEW.account_name
        );
    END IF;
END;
/
```

### Post-Event (Non-Blocking)

```sql
CREATE OR REPLACE TRIGGER qubiton_hz_cust_ai_trg
AFTER INSERT ON hz_cust_accounts
FOR EACH ROW
BEGIN
    qubiton_ebs_pkg.on_customer_create(p_cust_account_id => :NEW.cust_account_id);
END;
/

CREATE OR REPLACE TRIGGER qubiton_hz_cust_au_trg
AFTER UPDATE ON hz_cust_accounts
FOR EACH ROW
BEGIN
    IF :NEW.account_name != :OLD.account_name THEN
        qubiton_ebs_pkg.on_customer_update(p_cust_account_id => :NEW.cust_account_id);
    END IF;
END;
/
```

## Batch Validation Concurrent Program

### Concurrent Program PL/SQL Entry Point

The `qubiton_ebs_pkg.run_batch_validation` procedure follows the standard EBS concurrent program signature:

```sql
PROCEDURE run_batch_validation (
    errbuf             OUT VARCHAR2,
    retcode            OUT VARCHAR2,
    p_module           VARCHAR2,        -- 'AP_SUPPLIERS' or 'HZ_PARTIES'
    p_vendor_id_from   NUMBER   DEFAULT NULL,  -- Range filter (start)
    p_vendor_id_to     NUMBER   DEFAULT NULL,  -- Range filter (end)
    p_country          VARCHAR2 DEFAULT NULL    -- Country filter
);
```

Return codes follow the EBS convention:

| retcode | Meaning |
|---------|---------|
| `'0'` | Success — all validations passed |
| `'1'` | Warning — some validations failed but none blocked |
| `'2'` | Error — one or more validations blocked or program error |

### Registering the Concurrent Program in FND

#### Step 1: Create the executable

Navigate to: **System Administrator > Concurrent > Program > Executable**

| Field | Value |
|-------|-------|
| Executable | `QUBITON_BATCH_VALIDATE` |
| Short Name | `QUBITON_BATCH_VAL` |
| Application | Your custom application |
| Execution Method | `PL/SQL Stored Procedure` |
| Execution File Name | `qubiton_ebs_pkg.run_batch_validation` |

#### Step 2: Create the concurrent program

Navigate to: **System Administrator > Concurrent > Program > Define**

| Field | Value |
|-------|-------|
| Program | `QubitOn Batch Validation` |
| Short Name | `QUBITON_BATCH_VAL` |
| Application | Your custom application |
| Executable Name | `QUBITON_BATCH_VAL` |
| Output Format | `Text` |

#### Step 3: Define parameters

| Seq | Parameter | Value Set | Default | Required |
|-----|-----------|-----------|---------|----------|
| 10 | Module | `FND_STANDARD_YES_NO` with custom VS: `AP_SUPPLIERS`, `HZ_PARTIES` | `AP_SUPPLIERS` | Yes |
| 20 | Vendor ID From | `FND_NUMBER` | — | No |
| 30 | Vendor ID To | `FND_NUMBER` | — | No |
| 40 | Country | `FND_TERRITORY` | — | No |

#### Step 4: Add to request group

Navigate to: **System Administrator > Security > Responsibility > Request**

Add `QUBITON_BATCH_VAL` to the appropriate request group.

### Running the Batch Program

#### From EBS UI

Navigate to: **View > Requests > Submit a New Request**

Select "QubitOn Batch Validation" and provide parameters.

#### From PL/SQL

```sql
DECLARE
    l_request_id NUMBER;
BEGIN
    FND_GLOBAL.APPS_INITIALIZE(
        user_id      => 1234,
        resp_id      => 20420,    -- Payables responsibility
        resp_appl_id => 200
    );

    l_request_id := FND_REQUEST.SUBMIT_REQUEST(
        application => 'XXCUST',
        program     => 'QUBITON_BATCH_VAL',
        description => 'QubitOn batch supplier validation',
        start_time  => NULL,
        sub_request => FALSE,
        argument1   => 'AP_SUPPLIERS',    -- Module
        argument2   => NULL,              -- Vendor ID from
        argument3   => NULL,              -- Vendor ID to
        argument4   => 'US'              -- Country filter
    );

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Request ID: ' || l_request_id);
END;
/
```

### Scheduling Nightly Batch Validation

Use EBS Concurrent Manager scheduling:

1. Submit the program as above
2. In the Schedule tab, set:
   - **Run the job** = On specific days
   - **Start at** = 02:00 AM
   - **Repeat every** = 1 day
   - **End date** = (leave blank for indefinite)

Or use DBMS_SCHEDULER for non-EBS environments:

```sql
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'QUBITON_NIGHTLY_VALIDATION',
        job_type        => 'PLSQL_BLOCK',
        job_action      => q'[
            DECLARE
                l_errbuf  VARCHAR2(4000);
                l_retcode VARCHAR2(1);
            BEGIN
                qubiton_ebs_pkg.run_batch_validation(
                    errbuf   => l_errbuf,
                    retcode  => l_retcode,
                    p_module => 'AP_SUPPLIERS'
                );
            END;
        ]',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=DAILY;BYHOUR=2;BYMINUTE=0',
        enabled         => TRUE,
        comments        => 'Nightly QubitOn supplier validation'
    );
END;
/
```

## Configuring Per-Module Validation Rules

### Default AP_SUPPLIERS Rules

| Validation | Active | On Invalid | On Error | Countries |
|------------|--------|------------|----------|-----------|
| TAX | Y | E (block) | W (warn) | All |
| BANK | Y | E (block) | W (warn) | All |
| ADDRESS | Y | W (warn) | W (warn) | All |
| SANCTION | Y | E (block) | W (warn) | All |

### Recommended Production Configuration

```sql
-- Block on invalid tax/bank, warn on address
-- Never block on API errors (graceful degradation)
UPDATE qubiton_validation_cfg SET on_invalid = 'E', on_error = 'W'
WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'TAX';

UPDATE qubiton_validation_cfg SET on_invalid = 'E', on_error = 'W'
WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'BANK';

UPDATE qubiton_validation_cfg SET on_invalid = 'W', on_error = 'S'
WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'ADDRESS';

-- Sanctions: always block on match, warn on error
UPDATE qubiton_validation_cfg SET on_invalid = 'E', on_error = 'W'
WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'SANCTION';

COMMIT;
```

### Phased Rollout Strategy

**Phase 1 — Monitor (Week 1-2):**
Set all `on_invalid` to `'W'` (warn). Review `QUBITON_API_LOG` for false positive rates.

```sql
UPDATE qubiton_validation_cfg SET on_invalid = 'W' WHERE module_name = 'AP_SUPPLIERS';
COMMIT;
```

**Phase 2 — Enforce Critical (Week 3-4):**
Enable blocking for sanctions and tax only.

```sql
UPDATE qubiton_validation_cfg SET on_invalid = 'E'
WHERE module_name = 'AP_SUPPLIERS' AND val_type IN ('TAX', 'SANCTION');
COMMIT;
```

**Phase 3 — Full Enforcement (Week 5+):**
Enable blocking for bank accounts.

```sql
UPDATE qubiton_validation_cfg SET on_invalid = 'E'
WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'BANK';
COMMIT;
```

### Country-Specific Configuration

```sql
-- Tax validation only for US, Canada, and EU
UPDATE qubiton_validation_cfg
SET country_filter = 'US,CA,DE,FR,IT,ES,NL,BE,AT,PT,FI,SE,DK,NO,PL,CZ,SK,HU,RO,BG,HR,SI,EE,LV,LT,LU,MT,CY,GR,IE,GB'
WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'TAX';

-- Bank validation for US and IBAN countries
UPDATE qubiton_validation_cfg
SET country_filter = 'US,DE,FR,IT,ES,NL,BE,AT,PT,FI,SE,DK,NO,PL,CZ,SK,HU,RO,BG,HR,SI,EE,LV,LT,LU,MT,CY,GR,IE,GB,CH'
WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'BANK';

-- Sanctions screening: all countries (no filter)
UPDATE qubiton_validation_cfg
SET country_filter = NULL
WHERE module_name = 'AP_SUPPLIERS' AND val_type = 'SANCTION';

COMMIT;
```

## Monitoring and Diagnostics

### Check Validation Status

```sql
-- Recent validation results by module
SELECT l.log_timestamp,
       l.api_method,
       l.http_status,
       l.elapsed_ms,
       l.error_message,
       l.calling_module
FROM   qubiton_api_log l
WHERE  l.calling_module LIKE '%EBS%'
ORDER  BY l.log_timestamp DESC
FETCH  FIRST 50 ROWS ONLY;
```

### Validation Summary Report

```sql
SELECT api_method,
       COUNT(*)                                    AS total_calls,
       SUM(CASE WHEN http_status = 200 THEN 1 END) AS success_count,
       SUM(CASE WHEN http_status != 200 THEN 1 END) AS error_count,
       ROUND(AVG(elapsed_ms))                       AS avg_ms,
       ROUND(MAX(elapsed_ms))                       AS max_ms
FROM   qubiton_api_log
WHERE  log_timestamp > SYSTIMESTAMP - INTERVAL '7' DAY
GROUP  BY api_method
ORDER  BY total_calls DESC;
```

### Disable All Validations (Emergency)

```sql
-- Emergency kill switch: disable all validations
UPDATE qubiton_validation_cfg SET active = 'N';
COMMIT;

-- Re-enable when ready
UPDATE qubiton_validation_cfg SET active = 'Y';
COMMIT;
```

Alternatively, use the session-level override:

```sql
-- Set all validations to silent for this session
EXEC qubiton_validate_pkg.init(p_error_mode => 'S');
```
