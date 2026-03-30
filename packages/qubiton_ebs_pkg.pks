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
    FUNCTION validate_ap_supplier (
        p_vendor_id    NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER'
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

END qubiton_ebs_pkg;
/
