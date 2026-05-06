CREATE OR REPLACE PACKAGE qubiton_ebs_pkg
AS
    ---------------------------------------------------------------------------
    -- QubitOn EBS Integration Hooks (Layer 3)
    --
    -- Oracle E-Business Suite integration points designed to be called from:
    --   - Database triggers on AP_SUPPLIERS, HZ_PARTIES tables
    --   - Concurrent programs via FND_REQUEST
    --   - iProcurement customization (POR_CUSTOM_PKG extension pattern)
    --
    -- Dependencies:
    --   qubiton_types         (type definitions)
    --   qubiton_validate_pkg  (validation orchestrator -- Layer 2)
    --   qubiton_api_pkg       (HTTP/JSON layer -- Layer 1)
    --
    -- EBS Dependencies (optional, handled via dynamic SQL):
    --   AP_SUPPLIERS, AP_SUPPLIER_SITES_ALL, AP_BANK_ACCOUNTS (or IBY tables)
    --   HZ_PARTIES, HZ_CUST_ACCOUNTS
    --   PO_REQUISITION_HEADERS_ALL, PO_REQUISITION_LINES_ALL
    --   FND_FILE, FND_REQUEST
    --
    -- Version: 2.0.0
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- Validation hooks (return FALSE to block save)
    ---------------------------------------------------------------------------

    -- Validate AP supplier on create/update.
    -- p_calling_mode: 'TRIGGER' (from DB trigger), 'FORM' (from Forms),
    --                 'API' (from PL/SQL API), 'CONCURRENT' (from batch)
    -- p_module_name : optional override for QUBITON_VALIDATION_CFG lookup.
    --                 Defaults to 'AP_SUPPLIERS'.  Transactional callers
    --                 (PO / AP_INVOICE / AP_PAYMENT) pass their own module
    --                 so admins can tune fail-mode per document type.
    FUNCTION validate_ap_supplier (
        p_vendor_id    NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER',
        p_module_name  VARCHAR2 DEFAULT NULL
    ) RETURN BOOLEAN;

    -- Validate AR customer on create/update.
    FUNCTION validate_ar_customer (
        p_cust_account_id NUMBER,
        p_calling_mode    VARCHAR2 DEFAULT 'TRIGGER'
    ) RETURN BOOLEAN;

    -- Validate iProcurement requisition (suggested vendor screening).
    FUNCTION validate_iprocurement_req (
        p_requisition_header_id NUMBER
    ) RETURN BOOLEAN;

    ---------------------------------------------------------------------------
    -- Concurrent program entry point
    ---------------------------------------------------------------------------

    -- Batch validation of suppliers.  Called by FND_REQUEST.SUBMIT_REQUEST.
    -- Standard concurrent program signature: errbuf/retcode OUT parameters.
    --   retcode: '0' = success, '1' = warning, '2' = error
    PROCEDURE run_batch_validation (
        errbuf             OUT VARCHAR2,
        retcode            OUT VARCHAR2,
        p_module           VARCHAR2,
        p_vendor_id_from   NUMBER   DEFAULT NULL,
        p_vendor_id_to     NUMBER   DEFAULT NULL,
        p_country          VARCHAR2 DEFAULT NULL
    );

    ---------------------------------------------------------------------------
    -- Post-event hooks (non-blocking, warning mode)
    ---------------------------------------------------------------------------

    -- Called from AFTER INSERT trigger on AP_SUPPLIERS.
    PROCEDURE on_supplier_create (p_vendor_id NUMBER);

    -- Called from AFTER UPDATE trigger on AP_SUPPLIERS.
    PROCEDURE on_supplier_update (p_vendor_id NUMBER);

    -- Called from AFTER INSERT trigger on HZ_CUST_ACCOUNTS.
    PROCEDURE on_customer_create (p_cust_account_id NUMBER);

    -- Called from AFTER UPDATE trigger on HZ_CUST_ACCOUNTS.
    PROCEDURE on_customer_update (p_cust_account_id NUMBER);

    ---------------------------------------------------------------------------
    -- Transactional document validation hooks (PO / AP invoice / payment)
    --
    -- These run when a transactional document is saved/submitted, NOT just
    -- when the master record is created.  Re-validates the supplier on the
    -- document because risk posture changes constantly (sanctions lists,
    -- beneficial-owner changes, address moves).
    --
    -- ── On / off control (two layers, no schema changes needed):
    --
    --   1. MASTER KILL SWITCH: QUBITON_CONFIG row with
    --        config_key   = 'TXN_VALIDATION_ENABLED'
    --        config_value = 'Y'  (or 'N' / blank to disable)
    --      Each function below checks this row at the very start; disabled
    --      means RETURN TRUE immediately — no API call, no log write, no
    --      EBS table read.
    --
    --   2. PER-MODULE CONFIG: QUBITON_VALIDATION_CFG rows keyed by
    --      module_name + val_type with active / on_invalid / on_error
    --      columns.  Modules used by these hooks:
    --        'PO'           — purchase orders
    --        'AP_INVOICE'   — AP invoices
    --        'AP_PAYMENT'   — AP outgoing payments
    --        'AP_PAY_BATCH' — payment instruction filtering (F110-equiv)
    --
    --      ACTIVE = 'N' on a row disables just that one check on just
    --      that one module — admin can flip TAX off on AP_INVOICE while
    --      keeping SANCTION on, etc.
    ---------------------------------------------------------------------------

    -- Master on/off check.  Reads QUBITON_CONFIG.TXN_VALIDATION_ENABLED.
    -- Result is cached per session for performance — long-running Apps
    -- Server connections will hold the cached value.  Admins flipping
    -- TXN_VALIDATION_ENABLED in production should call reset_txn_cache
    -- afterwards (or bounce the connection pool) to make the change
    -- effective on already-running sessions.
    FUNCTION is_txn_validation_enabled RETURN BOOLEAN;

    -- Force the next call to is_txn_validation_enabled to re-read
    -- QUBITON_CONFIG.  Use after toggling TXN_VALIDATION_ENABLED in
    -- a long-running session, or schedule a small concurrent program
    -- that calls this for every active session you control.
    PROCEDURE reset_txn_cache;

    -- Validate a PO header on submit (PO_HEADERS_ALL).
    -- Returns FALSE to block the save — caller (typically a BEFORE
    -- INSERT/UPDATE trigger) raises an APPLICATION ERROR to abort the
    -- transaction.  Returns TRUE when validation passes OR when the
    -- master kill switch is off.
    FUNCTION validate_po_header (
        p_po_header_id NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER'
    ) RETURN BOOLEAN;

    -- Validate an AP invoice on validate / post (AP_INVOICES_ALL).
    -- Same FALSE = block contract.
    FUNCTION validate_ap_invoice (
        p_invoice_id   NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER'
    ) RETURN BOOLEAN;

    -- Validate an outgoing AP payment on release.  Wired to
    -- AP_CHECKS_ALL (legacy) or IBY_PAY_INSTRUCTIONS_ALL (modern).
    -- This is the LAST CHANCE check before the bank send.  Recommended
    -- fail-mode is "block on sanctions even when API is down"
    -- (QUBITON_VALIDATION_CFG.on_error = 'E' for AP_PAYMENT/SANCTION).
    FUNCTION validate_ap_payment (
        p_check_id     NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER'
    ) RETURN BOOLEAN;

    -- Filter sanctioned payees out of a payment batch (F110-equivalent
    -- Payments Manager run).  Does NOT abort the run — legitimate payees
    -- proceed; sanctioned ones are written to the audit log table for
    -- AP review and excluded from this run.
    PROCEDURE screen_payment_batch (
        p_payment_instruction_id NUMBER
    );

    ---------------------------------------------------------------------------
    -- Transactional batch concurrent program
    --
    -- Sweeps OPEN POs / unpaid invoices / pending payments from the last
    -- N days and re-validates against the QubitOn API.  Catches drift that
    -- inline triggers missed (API outages, bulk loads, post-save changes,
    -- LSMW data migration).  Recommended: schedule nightly via FND_REQUEST.
    ---------------------------------------------------------------------------
    PROCEDURE run_txn_batch_validation (
        errbuf            OUT VARCHAR2,
        retcode           OUT VARCHAR2,
        p_module          VARCHAR2,                 -- 'PO' / 'AP_INVOICE' / 'AP_PAYMENT'
        p_lookback_days   NUMBER   DEFAULT 30,
        p_country         VARCHAR2 DEFAULT NULL
    );

END qubiton_ebs_pkg;
/
