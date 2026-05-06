--------------------------------------------------------------------------------
-- seed_config.sql
-- Seed default configuration values for the QubitOn Oracle connector.
-- Run after creating tables (tables/*.sql).
--
-- IMPORTANT: Replace 'YOUR_API_KEY' with your actual QubitOn API key.
-- Get your API key at https://www.qubiton.com
--------------------------------------------------------------------------------

PROMPT Seeding QubitOn configuration...

-- Core settings
MERGE INTO qubiton_config dst
USING (
    SELECT 'APIKEY'          AS config_key, 'YOUR_API_KEY'                AS config_value, 'QubitOn API key (required)'                   AS description FROM DUAL UNION ALL
    SELECT 'BASE_URL',                      'https://api.qubiton.com',                     'QubitOn API base URL'                         FROM DUAL UNION ALL
    SELECT 'WALLET_PATH',                   'file:/opt/oracle/wallet',                     'Oracle Wallet path for TLS'                   FROM DUAL UNION ALL
    SELECT 'WALLET_PASSWORD',               '',                                             'Wallet password (blank for auto-login)'       FROM DUAL UNION ALL
    SELECT 'TIMEOUT',                       '30',                                           'HTTP timeout in seconds'                      FROM DUAL UNION ALL
    SELECT 'ERROR_MODE',                    'E',                                            'Default error mode: E=stop, W=warn, S=silent' FROM DUAL UNION ALL
    SELECT 'LOG_ENABLED',                   'Y',                                            'Enable API call audit logging: Y/N'           FROM DUAL UNION ALL
    -- Transactional-validation feature flags (added v2.1).  Disabled by
    -- default so installing the connector has zero runtime impact until
    -- an admin explicitly opts in.
    SELECT 'TXN_VALIDATION_ENABLED',        'N',                                            'Master kill switch for transactional hooks (PO/AP_INVOICE/AP_PAYMENT). Set to Y to enable.' FROM DUAL UNION ALL
    SELECT 'TXN_FAIL_MODE',                 'OPEN',                                         'On API outage during txn validation: OPEN=allow save with warning; CLOSED=block.' FROM DUAL
) src
ON (dst.config_key = src.config_key)
WHEN NOT MATCHED THEN
    INSERT (config_key, config_value, description)
    VALUES (src.config_key, src.config_value, src.description);

PROMPT Seeding validation configuration...

-- Default validation rules (AP Suppliers)
MERGE INTO qubiton_validation_cfg dst
USING (
    SELECT 'AP_SUPPLIERS' AS module_name, 'TAX'      AS val_type, 'Y' AS active, 'E' AS on_invalid, 'W' AS on_error, NULL AS country_filter, 'Tax ID validation for AP suppliers'         AS description FROM DUAL UNION ALL
    SELECT 'AP_SUPPLIERS',                'BANK',                  'Y',           'E',               'W',             NULL,                   'Bank account validation for AP suppliers'   FROM DUAL UNION ALL
    SELECT 'AP_SUPPLIERS',                'ADDRESS',               'Y',           'W',               'W',             NULL,                   'Address validation for AP suppliers'        FROM DUAL UNION ALL
    SELECT 'AP_SUPPLIERS',                'SANCTION',              'Y',           'E',               'W',             NULL,                   'Sanctions screening for AP suppliers'       FROM DUAL UNION ALL
    -- AR Customers
    SELECT 'HZ_PARTIES',                  'TAX',                   'Y',           'W',               'W',             NULL,                   'Tax ID validation for AR customers'         FROM DUAL UNION ALL
    SELECT 'HZ_PARTIES',                  'ADDRESS',               'Y',           'W',               'W',             NULL,                   'Address validation for AR customers'        FROM DUAL UNION ALL
    SELECT 'HZ_PARTIES',                  'SANCTION',              'Y',           'E',               'W',             NULL,                   'Sanctions screening for AR customers'       FROM DUAL UNION ALL
    -- iProcurement
    SELECT 'IPROCUREMENT',                'TAX',                   'Y',           'E',               'W',             NULL,                   'Tax ID validation for iProcurement vendors' FROM DUAL UNION ALL
    SELECT 'IPROCUREMENT',                'SANCTION',              'Y',           'E',               'W',             NULL,                   'Sanctions screening for iProcurement'       FROM DUAL UNION ALL
    -- Bank (iPayments)
    SELECT 'IBY_BANK',                    'BANK',                  'Y',           'E',               'W',             NULL,                   'Bank account validation for iPayments'      FROM DUAL UNION ALL
    -- ── Transactional document hooks (added v2.1) ─────────────────────
    -- All start ACTIVE='Y' so when the master TXN_VALIDATION_ENABLED is
    -- flipped to Y, sane defaults apply immediately.  Customers tune per
    -- module via SQL update on this table.
    --
    -- Recommended fail-mode policy:
    --   PO save           — block on sanctions, warn on cyber, warn-allow on API outage
    --   AP invoice post   — block on sanctions, silent on cyber (already validated upstream)
    --   AP payment release — BLOCK on sanctions AND on API outage (last chance)
    --   AP payment batch  — silent (filter, don't abort the run)
    SELECT 'PO',                          'SANCTION',              'Y',           'E',               'W',             NULL,                   'PO save: block on sanctions match'              FROM DUAL UNION ALL
    SELECT 'PO',                          'CYBER',                 'Y',           'W',               'S',             NULL,                   'PO save: warn on poor cyber score'              FROM DUAL UNION ALL
    SELECT 'AP_INVOICE',                  'SANCTION',              'Y',           'E',               'W',             NULL,                   'AP invoice: block on sanctions match'           FROM DUAL UNION ALL
    SELECT 'AP_INVOICE',                  'TAX',                   'Y',           'W',               'S',             NULL,                   'AP invoice: re-validate tax ID'                 FROM DUAL UNION ALL
    SELECT 'AP_PAYMENT',                  'SANCTION',              'Y',           'E',               'E',             NULL,                   'AP payment: block on sanctions; fail closed on API outage' FROM DUAL UNION ALL
    SELECT 'AP_PAY_BATCH',                'SANCTION',              'Y',           'S',               'S',             NULL,                   'AP payment batch: filter sanctioned payees silently'       FROM DUAL
) src
ON (dst.module_name = src.module_name AND dst.val_type = src.val_type)
WHEN NOT MATCHED THEN
    INSERT (module_name, val_type, active, on_invalid, on_error, country_filter, description)
    VALUES (src.module_name, src.val_type, src.active, src.on_invalid, src.on_error, src.country_filter, src.description);

COMMIT;

PROMPT Configuration seeded successfully.
PROMPT IMPORTANT: Update APIKEY in QUBITON_CONFIG with your actual API key:
PROMPT   UPDATE qubiton_config SET config_value = 'sk_live_xxx' WHERE config_key = 'APIKEY';
PROMPT   COMMIT;