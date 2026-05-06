--------------------------------------------------------------------------------
-- TEMPLATES — DO NOT RUN AS-IS IN PRODUCTION
--
-- Reference DML triggers that wire qubiton_ebs_pkg into the EBS
-- transactional document tables (PO_HEADERS_ALL, AP_INVOICES_ALL,
-- AP_CHECKS_ALL).  Each trigger calls one of the validate_* functions
-- and aborts the transaction (RAISE_APPLICATION_ERROR) when the
-- function returns FALSE.
--
-- THIS IS A REFERENCE — read it, adapt it, then deploy in YOUR EBS
-- environment under YOUR change-management process.  Don't apply
-- directly without:
--
--   1. Reviewing each trigger's WHEN clause against your EBS release —
--      column names and authorization-status values vary across
--      11i / R12.0 / R12.1 / R12.2.
--   2. Granting the QUBITON schema SELECT/EXECUTE privileges it needs
--      (typically a custom role: GRANT EXECUTE ON qubiton_ebs_pkg TO apps;)
--      and creating the triggers in the AP/PO schema, or via INSTEAD OF
--      triggers on a view if your governance forbids triggers on the
--      shipped EBS tables.
--   3. Capturing the triggers on a customizing transport / change
--      request and promoting through DEV → SIT → UAT → PRD with
--      the standard EBS change pipeline.
--
-- ── Pre-requisites before activating any of these ─────────────────────
--
--   * The qubiton_ebs_pkg package must be installed (see install.sql).
--   * The master kill switch must be ON (defaults to OFF):
--        UPDATE qubiton_config SET config_value = 'Y'
--         WHERE config_key   = 'TXN_VALIDATION_ENABLED';
--        COMMIT;
--     Until this is set, the validators return TRUE immediately.  Triggers
--     fire but do nothing — they're effectively no-ops, safe to leave in
--     place.
--
-- ── Disabling without dropping triggers ───────────────────────────────
--
--   The validators all check is_txn_validation_enabled first.  Flip
--   TXN_VALIDATION_ENABLED to 'N' to instantly disable everything
--   without dropping objects:
--     UPDATE qubiton_config SET config_value = 'N' WHERE config_key = 'TXN_VALIDATION_ENABLED';
--     COMMIT;
--   Per-flow disable: ACTIVE='N' on the matching qubiton_validation_cfg
--   row (e.g. module='PO', val_type='SANCTION').
--
--------------------------------------------------------------------------------

-- TEMPLATE 1: PO header validation
-- TABLE:    apps.po_headers_all
-- FIRES:    BEFORE INSERT OR UPDATE OF authorization_status
-- BLOCKS:   sanctions hit (per QUBITON_VALIDATION_CFG with module='PO')
-- POLICY:   fail open on API outage (allow PO save with warning)
--
-- Skips changes that don't move the PO into APPROVED/IN_PROCESS state
-- to avoid noise on header-only edits.

/*
CREATE OR REPLACE TRIGGER qubiton_po_headers_validate
    BEFORE INSERT OR UPDATE OF authorization_status ON apps.po_headers_all
    FOR EACH ROW
    WHEN (
        :new.authorization_status IN ('APPROVED','IN_PROCESS','PRE-APPROVED')
        AND :new.vendor_id IS NOT NULL
    )
DECLARE
    l_ok BOOLEAN;
BEGIN
    l_ok := qubiton_ebs_pkg.validate_po_header(
        p_po_header_id => :new.po_header_id,
        p_calling_mode => 'TRIGGER'
    );

    IF NOT l_ok THEN
        RAISE_APPLICATION_ERROR(
            -20991,
            'QubitOn: PO ' || :new.segment1 ||
            ' blocked — supplier failed risk validation. ' ||
            'Review qubiton_api_log for details.'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20991 THEN RAISE; END IF;
        NULL;
END qubiton_po_headers_validate;
/
*/

-- TEMPLATE 2: AP invoice validation
-- TABLE:    apps.ap_invoices_all
-- FIRES:    BEFORE UPDATE of validation_request_id (when invoice is submitted to validate)
-- POLICY:   fail open on API outage

/*
CREATE OR REPLACE TRIGGER qubiton_ap_invoices_validate
    BEFORE UPDATE OF validation_request_id ON apps.ap_invoices_all
    FOR EACH ROW
    WHEN (
        :new.validation_request_id IS NOT NULL
        AND :old.validation_request_id IS NULL
        AND :new.vendor_id IS NOT NULL
    )
DECLARE
    l_ok BOOLEAN;
BEGIN
    l_ok := qubiton_ebs_pkg.validate_ap_invoice(
        p_invoice_id   => :new.invoice_id,
        p_calling_mode => 'TRIGGER'
    );

    IF NOT l_ok THEN
        RAISE_APPLICATION_ERROR(
            -20992,
            'QubitOn: AP invoice ' || :new.invoice_num ||
            ' blocked — supplier failed risk validation.'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20992 THEN RAISE; END IF;
        NULL;     -- fail open on unexpected errors
END qubiton_ap_invoices_validate;
/
*/

-- TEMPLATE 3: AP payment release (last chance before bank send)
-- TABLE:    apps.ap_checks_all
-- FIRES:    BEFORE UPDATE OF status_lookup_code when payment moves to NEGOTIABLE
-- POLICY:   FAIL CLOSED — any validation failure (including API outage) holds
--           the payment.  This is intentional; it's the last defence.

/*
CREATE OR REPLACE TRIGGER qubiton_ap_checks_validate
    BEFORE UPDATE OF status_lookup_code ON apps.ap_checks_all
    FOR EACH ROW
    WHEN (
        :new.status_lookup_code = 'NEGOTIABLE'
        AND :old.status_lookup_code <> 'NEGOTIABLE'
        AND :new.vendor_id IS NOT NULL
    )
DECLARE
    l_ok BOOLEAN;
BEGIN
    l_ok := qubiton_ebs_pkg.validate_ap_payment(
        p_check_id     => :new.check_id,
        p_calling_mode => 'TRIGGER'
    );

    IF NOT l_ok THEN
        RAISE_APPLICATION_ERROR(
            -20993,
            'QubitOn: AP payment ' || :new.check_number ||
            ' blocked — payee failed sanctions screening.'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -20993 THEN RAISE; END IF;
        RAISE_APPLICATION_ERROR(
            -20994,
            'QubitOn: AP payment ' || :new.check_number ||
            ' held — validation could not complete. Error: ' || SQLERRM
        );
END qubiton_ap_checks_validate;
/
*/

-- ── Uninstall (after enabling the templates above) ──────────────────────
--
--   DROP TRIGGER apps.qubiton_po_headers_validate;
--   DROP TRIGGER apps.qubiton_ap_invoices_validate;
--   DROP TRIGGER apps.qubiton_ap_checks_validate;
--
-- Uninstalling triggers does NOT remove the qubiton_ebs_pkg package or
-- its config — those remain available for the concurrent-program batch
-- sweep and any custom hooks you build.
