# Transaction-Level Validation

Inline validation of QubitOn API checks during transactional document entry — purchase orders, AP invoices, AP payments, payment batches — in addition to the supplier/customer master-data hooks already shipped (`AP_SUPPLIERS`, `HZ_PARTIES`).

This guide covers:

- **When to use which hook** (inline vs batch, blocking vs warning)
- **How to wire triggers / concurrent programs per EBS release**
- **The kill switches and per-module config knobs**
- **Reference trigger templates** that you copy and adapt

## Why this exists

The supplier-master triggers (`qubiton_ebs_pkg.on_supplier_create` / `_update`) catch issues when a record is created, but a vendor's risk posture changes constantly:

- A supplier that was clean six months ago may show up on an OFAC sanctions list today
- A vendor's domain may have been compromised since onboarding
- A subcontractor's beneficial owner may have changed

Re-validating at the **point of transaction** (PO submit, invoice posting, payment release) catches these without requiring a re-screening of every active vendor every night. The user's experience is unchanged — they enter the document normally — but the trigger blocks or warns based on the current risk picture.

## On / off control

Two layers, both administrator-controlled, no schema changes:

### 1. Master kill switch — `QUBITON_CONFIG.TXN_VALIDATION_ENABLED`

```sql
-- Turn ON every transactional validator
UPDATE qubiton_config SET config_value = 'Y'
 WHERE config_key   = 'TXN_VALIDATION_ENABLED';
COMMIT;

-- Turn OFF every transactional validator
UPDATE qubiton_config SET config_value = 'N'
 WHERE config_key   = 'TXN_VALIDATION_ENABLED';
COMMIT;
```

Each validator function (`validate_po_header`, `validate_ap_invoice`, `validate_ap_payment`, `screen_payment_batch`) reads this row at the very start of its body. When disabled the function `RETURN TRUE` immediately — no API call, no log write, no EBS table read.

The supplier/customer master-data hooks are **not affected** by this switch — they have their own activation via `QUBITON_VALIDATION_CFG`.

### 2. Per-module config — `QUBITON_VALIDATION_CFG`

Granular control. One row per `(module_name, val_type)` pair.

| MODULE_NAME | VAL_TYPE | ACTIVE | ON_INVALID | ON_ERROR | Use case |
|---|---|:------:|:----------:|:--------:|---|
| PO            | SANCTION | Y | E | W | PO save: block on sanctions, warn on API outage |
| AP_INVOICE    | SANCTION | Y | E | W | Invoice posting: block on sanctions |
| AP_INVOICE    | TAX      | Y | W | S | Invoice posting: re-validate tax ID |
| AP_PAYMENT    | SANCTION | Y | E | **E** | Payment release: block on sanctions AND on API outage (fail closed) |
| AP_PAY_BATCH  | SANCTION | Y | S | S | Payment batch: silently filter sanctioned payees from the run |

The orchestrator (`qubiton_validate_pkg.validate_supplier_all`) currently dispatches `TAX`, `BANK`, `ADDRESS`, and `SANCTION`. Other val_types (e.g. `CYBER`, `RISK`) require both an orchestrator branch AND a matching `validate_supplier_<type>` function — adding only a config row is silently ignored.

Maintain via SQL `UPDATE` against `QUBITON_VALIDATION_CFG`. Default rows are seeded by `setup/seed_config.sql`.

## Inline vs batch — pick the right hook

### Decision matrix

| Stake level | Recommended pattern | Hook | User experience |
|---|---|---|---|
| **Block-the-bad-actor** (sanctions, blacklist) | **Inline blocking** (`ON_INVALID = 'E'`) | DML trigger calling `validate_*` | User sees red error message, save aborts |
| **Warn-and-route** (tax mismatch, address change, beneficial-owner change) | **Inline warning** (`ON_INVALID = 'W'`) + EBS approval workflow | DML trigger writes to a Z-flag column read by approval rules | User sees yellow warning, save proceeds, approval rule kicks in |
| **Telemetry / quality** (address completeness, phone format) | **Inline silent** (`ON_INVALID = 'S'`) | DML trigger logs to `qubiton_api_log` | Save proceeds normally, ops team reviews via report |
| **Cleanup / mass screening** (every-vendor sanctions sweep) | **Batch** | Concurrent program `qubiton_ebs_pkg.run_txn_batch_validation` | No user impact; nightly summary email |

### Why batch matters even when inline exists

- **Sanctions lists change every day**, but a vendor used in last month's PO is still in your books. Inline catches new POs; batch catches existing exposure.
- **API outages**: inline triggers degrade to "warn + allow" by default. Batch re-runs catch what was missed during the outage.
- **Bulk-load scenarios** (LSMW, EDI, AP_INVOICES_INTERFACE, OPEN_INTERFACE_LINES) bypass dialog screens — DML triggers catch some of these but **not** when the bulk-load API uses `INSERT /*+ APPEND */` with bypass flags. Catch these via batch.

### Recommended pattern: inline + nightly batch

```text
On-line dialog flow      ┌──────────────────────────────┐
   PO submit ──────────► │ TRIGGER on PO_HEADERS_ALL    │
   AP invoice validate ► │ → qubiton_ebs_pkg.validate_* │
   AP payment release ─► │   (inline; high-stakes only) │
                         └──────────────────────────────┘

Bulk / EDI / migration   ┌──────────────────────────────┐
   AP_INVOICES_INTERFACE │ trigger may not fire or be   │
   PO_HEADERS_INTERFACE  │ deferred (legitimately)      │
                         └──────────────────────────────┘
                                       │
                                       ▼
Nightly concurrent       ┌──────────────────────────────┐
   QUBITON_NIGHTLY_SWEEP │ qubiton_ebs_pkg.             │
   FND_REQUEST scheduled │   run_txn_batch_validation   │
                         │ Walks open POs / unpaid      │
                         │ invoices / pending payments  │
                         │ Re-runs screening; logs hits │
                         └──────────────────────────────┘
```

The reference triggers and batch concurrent program are shipped here; customers register the program via FND.

## Per-document hooks

### Purchase Order — `PO_HEADERS_ALL`

**Trigger event**: `BEFORE INSERT OR UPDATE OF authorization_status`
**Validator**: `qubiton_ebs_pkg.validate_po_header(p_po_header_id, p_calling_mode)`
**Reference template**: [`docs/templates/triggers-transactional.sql`](templates/triggers-transactional.sql)

Reads `vendor_id` from `PO_HEADERS_ALL` via dynamic SQL (so the package compiles outside EBS), then re-runs `validate_ap_supplier` for the supplier on the PO. The existing `AP_SUPPLIERS` config rules apply, plus any `PO`-specific rules in `QUBITON_VALIDATION_CFG`.

Returns `FALSE` to block the save; the trigger turns this into `RAISE_APPLICATION_ERROR(-20991, ...)`.

```sql
-- skeleton (full template in docs/templates/)
CREATE OR REPLACE TRIGGER qubiton_po_headers_validate
    BEFORE INSERT OR UPDATE OF authorization_status ON apps.po_headers_all
    FOR EACH ROW
    WHEN ( :new.authorization_status IN ('APPROVED','IN PROCESS','PRE-APPROVED','REQUIRES REAPPROVAL') )
DECLARE l_ok BOOLEAN;
BEGIN
    l_ok := qubiton_ebs_pkg.validate_po_header(:new.po_header_id, 'TRIGGER');
    IF NOT l_ok THEN
        RAISE_APPLICATION_ERROR(-20991, 'QubitOn: PO ' || :new.segment1 || ' blocked');
    END IF;
END;
/
```

### Vendor invoice — `AP_INVOICES_ALL`

**Trigger event**: `BEFORE UPDATE OF validation_request_id`
**Validator**: `qubiton_ebs_pkg.validate_ap_invoice(p_invoice_id, p_calling_mode)`

Fires when an invoice is submitted for validation. Reads `vendor_id` from `AP_INVOICES_ALL`, re-screens the supplier. The same fail-mode policy applies as PO.

Note: invoice validation fires AFTER the invoice is entered but BEFORE accounting is created. If your operation often reverses invoices (which would re-fire validation), tune `QUBITON_VALIDATION_CFG.AP_INVOICE/SANCTION/ACTIVE` to `'N'` and run a daily batch instead.

### AP payment release — `AP_CHECKS_ALL`

**Trigger event**: `BEFORE UPDATE OF status_lookup_code` (when payment moves to `NEGOTIABLE`)
**Validator**: `qubiton_ebs_pkg.validate_ap_payment(p_check_id, p_calling_mode)`

**Recommended fail-mode**: **strict-fail-closed**. Set `QUBITON_VALIDATION_CFG.AP_PAYMENT/SANCTION/on_error = 'E'` so an API outage HOLDS the payment instead of releasing it. The reference trigger template re-raises `RAISE_APPLICATION_ERROR(-20994, ...)` on any unexpected error — this is the last chance to stop a sanctioned payment from leaving the bank.

### Payment batch — `IBY_PAY_INSTRUCTIONS_ALL` / `AP_CHECKS_ALL`

**Procedure**: `qubiton_ebs_pkg.screen_payment_batch(p_payment_instruction_id)`

Unlike PO/invoice/payment-release, the right pattern here is **silent filter**, not block:

```pl/sql
BEGIN
    qubiton_ebs_pkg.screen_payment_batch(p_payment_instruction_id => :payment_instruction_id);
END;
/
```

The procedure walks `IBY_PAYMENTS_ALL` for the instruction, screens each payee, and `UPDATE`s the row to `payment_status='HELD'` with `hold_reason='QUBITON_SANCTIONS'` for any match. The standard Payments Manager run skips HELD payments. The batch run completes; sanctioned vendors are simply excluded; AP gets a daily report of who was dropped via the FND log.

Wire this into your Payments Manager workflow either via the standard "Validate" action customisation or as a pre-step in your scheduled run.

## Best-practice fail-mode policy

Different transactions have different risk tolerances. The defaults below are seeded by `setup/seed_config.sql`; tune them for your business:

| Module | SANCTION on_invalid | TAX on_invalid | API on_error | Rationale |
|---|:---:|:---:|:---:|---|
| PO save | E (block) | — | W (warn, allow) | PO is reversible. Allow save when API is down; manual review later. |
| AP invoice | E (block) | W (warn) | W (warn, allow) | Block sanctioned payees. Re-validate tax ID as a soft warning. |
| AP payment release | E (block) | — | **E (block)** | Last chance. Even if API is down, hold the payment. |
| AP payment batch | filter (S) | — | filter (drop) | Filter pattern — never abort the run. |
| Mass batch sweep | log only | log only | log only | Off-line — log everything, alert ops. |

## Caching

The validator package caches the master kill switch result per session in `g_txn_enabled_cached` so a batch sweep over 10,000 POs makes one `QUBITON_CONFIG` read, not 10,000.

The QubitOn API itself caches results server-side for 24 hours per (vendor, validation type). Re-running the nightly sweep is cheap.

If you need stronger client-side caching (e.g., a session-level cache so the same vendor on a 50-line PO doesn't get re-validated 50 times), add a `g_vendor_verdict_cache` PL/SQL associative array around `validate_ap_supplier`.

## Approval routing instead of hard-block

For warning-tier validations (tax mismatch, address change, beneficial-owner change since last screening), prefer **routing the document into an additional approval tier** rather than hard-blocking. EBS's standard PO Approval Hierarchy and AP Holds framework cover this:

- **PO**: write a Z-flag onto the PO header (e.g., `attribute15`) when validation produces a warning verdict; PO Approval Hierarchy reads the flag and routes to a higher-tier approver
- **AP invoice**: place a `QUBITON_RISK` invoice hold via `AP_HOLDS_ALL`; AP Holds workflow routes the invoice to the right approver
- **AP payment**: hold via `payment_status='HELD'` (same mechanism as the batch screening)

This is the right pattern for "scary but not deal-breaking" signals. It keeps the connector out of the procurement-policy debate.

## Concurrent program: nightly sweep

Register `qubiton_ebs_pkg.run_txn_batch_validation` in FND:

```pl/sql
-- Step 1: Create the executable
fnd_program.executable(
    executable      => 'QUBITON_TXN_SWEEP',
    application     => 'QubitOn',
    short_name      => 'QUBITON_TXN_SWEEP',
    description     => 'QubitOn nightly transactional sweep',
    execution_method => 'PL/SQL Stored Procedure',
    execution_file_name => 'qubiton_ebs_pkg.run_txn_batch_validation'
);

-- Step 2: Create the concurrent program with parameters
--   p_module          (PO / AP_INVOICE / AP_PAYMENT)
--   p_lookback_days   (default 30)
--   p_country         (optional ISO2 filter)

-- Step 3: Schedule via FND_REQUEST.SUBMIT_REQUEST or via UI
DECLARE
    l_request_id NUMBER;
BEGIN
    l_request_id := fnd_request.submit_request(
        application => 'QUBITON',
        program     => 'QUBITON_TXN_SWEEP',
        argument1   => 'PO',
        argument2   => '30',
        argument3   => NULL
    );
    COMMIT;
END;
/
```

Schedule daily; consume the output via FND log files.

## Per-version compatibility

| EBS Release | Triggers | Concurrent program | Notes |
|---|:---:|:---:|---|
| 11i (11.5.10.2) | ✅ | ✅ | Use `apps.po_headers_all` / `ap_invoices_all` / `ap_checks_all` table names |
| R12.0.x | ✅ | ✅ | Same |
| R12.1.x | ✅ | ✅ | Add `IBY_PAY_INSTRUCTIONS_ALL` / `IBY_PAYMENTS_ALL` for the modern Payments architecture |
| R12.2.x | ✅ | ✅ | Online Patching may require triggers in custom schema with synonyms; consult your DBA |
| **Oracle Cloud ERP / Fusion Financials** | ❌ — different runtime | ⚠️ via OIC iFlows | Use the patterns documented in [`fusion-integration.md`](fusion-integration.md) instead — Fusion has no `apps.po_headers_all` table and no FND request engine |

For Oracle Cloud ERP / Fusion, transactional validation runs through:

- **Oracle Integration Cloud (OIC)** iFlows that subscribe to ERP business events (PO Approved, Invoice Validated)
- **REST API extensions** that prevalidate vendor data before invoice / payment submission
- **Custom Lookup Code** values in the standard ERP that route documents to additional approvals

See [Fusion Integration](fusion-integration.md) for the OIC-based pattern.

## See also

- [EBS Integration](ebs-integration.md) — supplier / customer master-data hooks (already shipped)
- [Fusion Integration](fusion-integration.md) — Oracle Cloud ERP patterns
- [Configuration](configuration.md) — package init parameters, error modes
- [Setup](setup.md) — installation order, wallet, network ACL

## FAQ-style quick answers

### Will this slow down PO save?

Added latency is one HTTP roundtrip per PO save (~200–500 ms) plus ~10 ms PL/SQL overhead. For high-volume batch entry this can be noticeable; turn it off via the kill switch during mass loads, or set `QUBITON_VALIDATION_CFG.PO/SANCTION/active = 'N'` and rely on the nightly sweep.

### Can I run inline triggers AND batch on the same documents?

Yes, and it's recommended. Inline catches new entries; batch catches what slipped through (API outages, bulk loads, post-save changes). They use the same underlying `qubiton_api_pkg` so the wire contract is identical.

### How do I disable just one validation on just one transaction?

`UPDATE qubiton_validation_cfg SET active = 'N' WHERE module_name = 'PO' AND val_type = 'SANCTION';`. Other transactions are unaffected.

### What if the API is down during PO save?

Default behaviour is **fail-open** (warn, allow save). Override per-module with `on_error = 'E'` if your policy requires fail-closed. The reference trigger templates demonstrate both patterns (PO/invoice = fail-open; payment release = fail-closed).

### Does this work in Oracle Cloud ERP / Fusion Financials?

No — Fusion has no `APPS.PO_HEADERS_ALL` and no FND concurrent-program engine. Use the patterns in [Fusion Integration](fusion-integration.md): OIC iFlows on ERP business events.

### How do I see who got blocked / warned?

Every validation call logs to `QUBITON_API_LOG` with the method name, HTTP status, elapsed time, and calling_mode. Block decisions write a row to the FND log via `fnd_log` so EBS-standard log viewers see them.

### Local validation — can I test this without an EBS database?

The package compiles against `qubiton_validate_pkg` and uses `EXECUTE IMMEDIATE` for all EBS table reads, so it compiles on any 19c+ database without EBS schemas. You can run unit tests against `qubiton_test_pkg` on a plain Oracle XE / Cloud Free Tier instance. Real trigger behaviour requires an EBS sandbox.
