# Oracle Fusion / Cloud Integration

This guide covers integration patterns for Oracle Fusion Cloud (SaaS), Oracle Autonomous Database, Oracle Integration Cloud (OIC), and Oracle Visual Builder Cloud Service (VBCS).

## Architecture Overview

```
+---------------------------+
|  Oracle Fusion Cloud      |
|                           |
|  +---------------------+ |     +-------------------+
|  | OIC (Integration    |-+---->| api.qubiton.com   |
|  |     Cloud)          | |     | (REST API)        |
|  +---------------------+ |     +-------------------+
|           |               |
|  +---------------------+ |
|  | Supplier Qual. Mgmt | |
|  | (SQM Questionnaire) | |
|  +---------------------+ |
|           |               |
|  +---------------------+ |     +-------------------+
|  | Autonomous DB       |-+---->| api.qubiton.com   |
|  | (PL/SQL direct)     | |     | (via DBMS_CLOUD)  |
|  +---------------------+ |     +-------------------+
|           |               |
|  +---------------------+ |
|  | VBCS               | |
|  | (Visual Builder)    | |
|  +---------------------+ |
+---------------------------+

Integration Patterns:
  A. OIC REST Adapter        -> Direct REST calls to QubitOn API
  B. Autonomous DB PL/SQL    -> qubiton_api_pkg via DBMS_CLOUD
  C. VBCS Service Connection -> REST service for custom UIs
  D. SQM Questionnaire Hook  -> OIC orchestration + QubitOn validation
```

## Pattern A: Oracle Integration Cloud (OIC) REST Adapter

OIC is the standard middleware for Fusion Cloud integrations. Use the REST adapter to call QubitOn API endpoints.

### Step 1: Create REST Connection

In OIC Console, navigate to **Connections > Create**.

| Field | Value |
|-------|-------|
| Adapter | REST |
| Connection Name | `QubitOn API` |
| Identifier | `QUBITON_API` |
| Connection Type | REST API Base URL |
| Connection URL | `https://api.qubiton.com` |
| Security Policy | API Key Based Authentication |
| API Key | Your QubitOn API key |
| API Key Header | `X-API-Key` |

### Step 2: Test Connection

Click **Test** in the connection configuration. Verify you see a green checkmark.

### Step 3: Create Integration Flow

Example: Validate supplier address on creation.

```
Trigger: Fusion Supplier Event (Business Event)
  |
  v
Map: Extract supplier address fields
  |
  v
Invoke: QubitOn API - validate_address (REST POST)
  |
  v
Switch: Check isValid field
  |
  +--[TRUE]--> End (no action)
  |
  +--[FALSE]--> Invoke: Create notification/task for review
```

### OIC Integration Flow — Address Validation

```
+-------------------+     +-------------------+     +-------------------+
| Oracle Fusion     |     | OIC Integration   |     | QubitOn API       |
| Business Event:   |---->| Flow:             |---->| POST /api/        |
| Supplier Created  |     | SupplierValidation|     | address/validate  |
+-------------------+     +-------------------+     +-------------------+
                                   |
                                   v
                          +-------------------+
                          | Response Router   |
                          |                   |
                          | isValid=true  --> | Log success
                          | isValid=false --> | Create BPM task
                          | Error         --> | Send notification
                          +-------------------+
```

### Sample OIC REST Invoke Configuration

**Endpoint:** `/api/address/validate`
**Method:** POST
**Request Payload:**

```json
{
    "country": "${supplier.country}",
    "addressLine1": "${supplier.addressLine1}",
    "city": "${supplier.city}",
    "state": "${supplier.state}",
    "postalCode": "${supplier.postalCode}"
}
```

**Response Mapping:**

| QubitOn Response Field | OIC Variable |
|------------------------|--------------|
| `isValid` | `validationResult` |
| `message` | `validationMessage` |
| `correctedAddress.addressLine1` | `correctedAddress1` |
| `correctedAddress.city` | `correctedCity` |
| `correctedAddress.postalCode` | `correctedPostalCode` |

### OIC Error Handling

Configure fault handling in the integration:

| HTTP Status | OIC Action |
|-------------|------------|
| 200 | Process response normally |
| 401 | Raise fault — API key invalid, alert admin |
| 429 | Wait and retry (use OIC retry policy, max 3 attempts) |
| 5xx | Log error, create incident, continue processing |

## Pattern B: Autonomous Database (PL/SQL Direct)

Oracle Autonomous Database can call REST APIs directly using `DBMS_CLOUD.SEND_REQUEST` or `UTL_HTTP` with pre-loaded certificates.

### Using DBMS_CLOUD (Recommended for ADB)

No Oracle Wallet setup needed — ADB has pre-loaded CA certificates.

#### Step 1: Create credential

```sql
BEGIN
    DBMS_CLOUD.CREATE_CREDENTIAL(
        credential_name => 'QUBITON_API_CRED',
        username        => 'api_key',
        password        => 'sk_live_your_api_key_here'
    );
END;
/
```

#### Step 2: Call the API

```sql
DECLARE
    l_response DBMS_CLOUD_TYPES.resp;
    l_body     CLOB;
    l_url      VARCHAR2(500) := 'https://api.qubiton.com/api/address/validate';
BEGIN
    l_response := DBMS_CLOUD.SEND_REQUEST(
        credential_name => 'QUBITON_API_CRED',
        uri             => l_url,
        method          => DBMS_CLOUD.METHOD_POST,
        headers         => JSON_OBJECT(
            'Content-Type' VALUE 'application/json',
            'X-API-Key'    VALUE 'sk_live_your_api_key_here'
        ),
        body            => UTL_RAW.CAST_TO_RAW(
            JSON_OBJECT(
                'country'      VALUE 'US',
                'addressLine1' VALUE '123 Main St',
                'city'         VALUE 'Springfield',
                'state'        VALUE 'IL',
                'postalCode'   VALUE '62701'
            )
        )
    );

    l_body := DBMS_CLOUD.GET_RESPONSE_TEXT(l_response);
    DBMS_OUTPUT.PUT_LINE('Status: ' || DBMS_CLOUD.GET_RESPONSE_STATUS_CODE(l_response));
    DBMS_OUTPUT.PUT_LINE('Response: ' || l_body);
END;
/
```

#### Step 3: Install the full connector on ADB

The QubitOn PL/SQL connector works on ADB with one change — set `WALLET_PATH` to `NULL` in `QUBITON_CONFIG`:

```sql
-- Install normally
@install.sql

-- Override wallet path (ADB handles TLS internally)
UPDATE qubiton_config SET config_value = 'NONE' WHERE config_key = 'WALLET_PATH';
COMMIT;

-- Test
SELECT qubiton_api_pkg.test_connection() FROM DUAL;
```

### Using UTL_HTTP on ADB

If `UTL_HTTP` is granted to your schema:

```sql
-- No wallet needed on ADB
SELECT UTL_HTTP.REQUEST(
    url => 'https://api.qubiton.com/api/health'
) FROM DUAL;
```

The connector auto-detects ADB and omits the wallet parameter.

## Pattern C: Oracle VBCS (Visual Builder Cloud Service)

Use VBCS to build custom supplier onboarding UIs with built-in QubitOn validation.

### Step 1: Create Service Connection

In VBCS, navigate to **Services > + Service Connection > Define by Endpoint**.

| Field | Value |
|-------|-------|
| URL | `https://api.qubiton.com/api/address/validate` |
| Method | POST |
| Authentication | Custom Header: `X-API-Key` |

Repeat for each endpoint you need (tax, bank, sanctions, etc.).

### Step 2: Create an Action Chain

In your VBCS page, create an action chain triggered by a button click:

```
Button Click
  |
  v
Call REST: QubitOn validate_address
  |
  v
If (response.isValid === true)
  |
  +--[Yes]--> Show success notification
  |
  +--[No]---> Show error notification with response.message
              Highlight invalid fields in red
```

### Step 3: Sample Page Variable Mapping

```javascript
// Page variables
$page.variables.supplierAddress = {
    country: "US",
    addressLine1: "123 Main St",
    city: "Springfield",
    state: "IL",
    postalCode: "62701"
};

// REST call body maps to these variables
// Response maps to:
$page.variables.validationResult = response.isValid;
$page.variables.validationMessage = response.message;
$page.variables.correctedAddress = response.correctedAddress;
```

### VBCS Validation Flow Diagram

```
+-------------------+     +-----------------------+
| VBCS Page         |     | Action Chain          |
|                   |     |                       |
| [Address Form]    |     | 1. Validate inputs    |
| [Validate Button] +---->| 2. Call QubitOn API   |
|                   |     | 3. Check response     |
| [Results Panel]   |<----+ 4. Update UI          |
+-------------------+     +-----------------------+
```

## Pattern D: Supplier Qualification Management (SQM)

Oracle SQM uses qualification questionnaires during supplier onboarding. Integrate QubitOn validation into the qualification workflow via OIC.

### Architecture

```
+-------------------+     +-------------------+     +-------------------+
| Fusion SQM        |     | OIC Orchestration |     | QubitOn API       |
|                   |     |                   |     |                   |
| Questionnaire     |     | 1. Receive event  |     | validate_tax      |
| submitted by      +---->| 2. Extract fields |---->| validate_bank     |
| supplier          |     | 3. Call QubitOn   |     | check_sanctions   |
|                   |     | 4. Update status  |     | validate_address  |
|                   |<----+ 5. Return result  |     |                   |
+-------------------+     +-------------------+     +-------------------+
```

### OIC Integration for SQM

**Trigger:** Fusion Business Event — `oracle.apps.prc.sqm.qualificationSubmitted`

**Flow:**

1. Extract supplier data from the qualification response (tax ID, address, bank details, company name)
2. Execute validations in parallel using OIC parallel branch:
   - Branch 1: `POST /api/tax/validate`
   - Branch 2: `POST /api/address/validate`
   - Branch 3: `POST /api/bank/validate`
   - Branch 4: `POST /api/prohibited/lookup`
3. Aggregate results
4. If all pass: update qualification status to "Qualified"
5. If any fail: update qualification status to "Under Review" with failure details
6. Create a BPM task for procurement team if sanctions match is found

### SQM Field Mapping

| SQM Questionnaire Field | QubitOn API Parameter |
|--------------------------|----------------------|
| Tax Registration Number | `taxId` |
| Country of Incorporation | `country` |
| Registered Address Line 1 | `addressLine1` |
| City | `city` |
| State/Province | `state` |
| Postal Code | `postalCode` |
| Bank Account Number | `accountNumber` |
| IBAN | `iban` |
| SWIFT/BIC | `swiftCode` |
| Company Legal Name | `entityName` |

## Pattern E: Fusion Custom PL/SQL (via Autonomous DB)

For Fusion customers using Autonomous Database for extensions, deploy the connector directly:

### Architecture

```
+-------------------+     +-------------------+     +-------------------+
| Fusion Cloud      |     | Autonomous DB     |     | QubitOn API       |
|                   |     | (Extension Schema)|     |                   |
| Supplier Master   |     | qubiton_api_pkg   |     |                   |
| Business Event    +---->| qubiton_validate  +---->| api.qubiton.com   |
|                   |     | _pkg              |     |                   |
| or                |     |                   |     |                   |
| FBDI Import       +---->| Custom validation |     |                   |
|                   |     | procedure         |     |                   |
+-------------------+     +-------------------+     +-------------------+
```

### Implementation

```sql
-- Deploy connector to ADB extension schema
@install.sql

-- Create custom validation procedure
CREATE OR REPLACE PROCEDURE validate_fusion_supplier(
    p_supplier_name    VARCHAR2,
    p_country          VARCHAR2,
    p_tax_id           VARCHAR2,
    p_address_line1    VARCHAR2,
    p_city             VARCHAR2,
    p_state            VARCHAR2,
    p_postal_code      VARCHAR2,
    p_result           OUT VARCHAR2,
    p_message          OUT VARCHAR2
)
IS
    l_ok BOOLEAN;
BEGIN
    l_ok := qubiton_validate_pkg.validate_supplier_all(
        p_module_name   => 'FUSION_SUPPLIERS',
        p_vendor_id     => 0,  -- Fusion uses different IDs
        p_vendor_name   => p_supplier_name,
        p_country       => p_country,
        p_tax_id        => p_tax_id,
        p_address_line1 => p_address_line1,
        p_city          => p_city,
        p_state         => p_state,
        p_postal_code   => p_postal_code
    );

    IF l_ok THEN
        p_result  := 'PASS';
        p_message := 'All validations passed';
    ELSE
        p_result  := 'FAIL';
        p_message := 'One or more validations failed — check QUBITON_API_LOG';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        p_result  := 'ERROR';
        p_message := SQLERRM;
END;
/
```

Add the Fusion module configuration:

```sql
INSERT INTO qubiton_validation_cfg VALUES ('FUSION_SUPPLIERS', 'TAX',      'Y', 'E', 'W', NULL, 'Fusion supplier tax validation');
INSERT INTO qubiton_validation_cfg VALUES ('FUSION_SUPPLIERS', 'ADDRESS',  'Y', 'W', 'W', NULL, 'Fusion supplier address validation');
INSERT INTO qubiton_validation_cfg VALUES ('FUSION_SUPPLIERS', 'SANCTION', 'Y', 'E', 'W', NULL, 'Fusion supplier sanctions screening');
COMMIT;
```

## Security Considerations

### API Key Management

| Platform | Recommended Storage |
|----------|---------------------|
| OIC | Connection credential (encrypted at rest) |
| ADB | `DBMS_CLOUD.CREATE_CREDENTIAL` (encrypted in wallet) |
| VBCS | Service Connection credential |
| PL/SQL direct | `QUBITON_CONFIG` table (restrict SELECT to connector schema only) |

### Network Security

| Platform | Network Path |
|----------|--------------|
| OIC | Direct outbound HTTPS (no ACL needed) |
| ADB (public) | Direct outbound HTTPS (pre-configured) |
| ADB (private) | Requires NAT gateway or service gateway for outbound |
| Fusion PL/SQL | Via ADB extension schema (see above) |

### Audit Trail

All calls are logged to `QUBITON_API_LOG` when using the PL/SQL connector. For OIC-based integrations, enable OIC Activity Stream logging and configure a log analytics integration.

## Performance Recommendations

| Integration Pattern | Latency | Throughput | Best For |
|---------------------|---------|------------|----------|
| OIC REST Adapter | 200-500ms per call | 10-50 TPS | Event-driven, low volume |
| ADB PL/SQL Direct | 100-300ms per call | 50-100 TPS | Batch processing, high volume |
| VBCS Service Call | 200-400ms per call | 5-20 TPS | Interactive UI validation |
| SQM via OIC | 500-2000ms (orchestrated) | 5-20 TPS | Supplier onboarding |

### Batch Processing on ADB

For high-volume batch validation, use `DBMS_PARALLEL_EXECUTE`:

```sql
DECLARE
    l_task_name VARCHAR2(30) := 'QUBITON_BATCH_VAL';
BEGIN
    DBMS_PARALLEL_EXECUTE.CREATE_TASK(l_task_name);

    DBMS_PARALLEL_EXECUTE.CREATE_CHUNKS_BY_SQL(
        task_name => l_task_name,
        sql_stmt  => 'SELECT DISTINCT vendor_id FROM ap_suppliers WHERE enabled_flag = ''Y''',
        by_rowid  => FALSE
    );

    DBMS_PARALLEL_EXECUTE.RUN_TASK(
        task_name      => l_task_name,
        sql_stmt       => q'[
            DECLARE
                l_ok BOOLEAN;
            BEGIN
                l_ok := qubiton_validate_pkg.validate_supplier_all(
                    p_module_name => 'AP_SUPPLIERS',
                    p_vendor_id   => :start_id,
                    p_vendor_name => NULL,
                    p_country     => NULL
                );
            END;
        ]',
        language_flag  => DBMS_SQL.NATIVE,
        parallel_level => 4
    );

    DBMS_PARALLEL_EXECUTE.DROP_TASK(l_task_name);
END;
/
```
