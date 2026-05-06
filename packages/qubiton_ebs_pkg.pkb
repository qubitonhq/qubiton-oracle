CREATE OR REPLACE PACKAGE BODY qubiton_ebs_pkg
AS
    ---------------------------------------------------------------------------
    -- QubitOn EBS Integration Hooks (Layer 3) -- Implementation
    --
    -- All EBS table access uses EXECUTE IMMEDIATE so the package compiles
    -- even when EBS tables (AP_SUPPLIERS, HZ_PARTIES, etc.) are absent.
    -- FND_FILE calls are wrapped in exception handlers for the same reason.
    --
    -- Version 2.0.0: updated to match qubiton_validate_pkg new signatures
    --   - validate_supplier_all: p_company_name, p_business_entity_type,
    --     p_bank_account_holder, p_tax_type (replaces p_vendor_name, p_routing_number)
    --   - validate_supplier_tax: p_tax_number (was p_tax_id), p_company_name, p_tax_type
    --   - validate_supplier_bank: p_business_entity_type, p_bank_account_holder
    --     (replaces p_routing_number)
    --   - validate_supplier_sanctions: full address fields added
    --   - validate_customer_all / individual: similar changes
    ---------------------------------------------------------------------------

    -- Module name constants matching QUBITON_VALIDATION_CFG.module_name
    gc_module_ap         CONSTANT VARCHAR2(30) := 'AP_SUPPLIERS';
    gc_module_hz         CONSTANT VARCHAR2(30) := 'HZ_PARTIES';
    gc_module_ipro       CONSTANT VARCHAR2(30) := 'IPROCUREMENT';

    ---------------------------------------------------------------------------
    -- Private: safe FND_FILE wrappers
    -- FND_FILE does not exist outside EBS; these silently no-op if absent.
    ---------------------------------------------------------------------------

    PROCEDURE fnd_output (p_text VARCHAR2)
    IS
    BEGIN
        EXECUTE IMMEDIATE
            'BEGIN FND_FILE.PUT_LINE(FND_FILE.OUTPUT, :1); END;'
            USING p_text;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;  -- FND_FILE not available, ignore
    END fnd_output;

    PROCEDURE fnd_log (p_text VARCHAR2)
    IS
    BEGIN
        EXECUTE IMMEDIATE
            'BEGIN FND_FILE.PUT_LINE(FND_FILE.LOG, :1); END;'
            USING p_text;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;  -- FND_FILE not available, ignore
    END fnd_log;

    ---------------------------------------------------------------------------
    -- Private: query AP supplier data via dynamic SQL
    --
    -- Extended to fetch vendor_type (business entity type) and
    -- bank account holder name alongside the original fields.
    ---------------------------------------------------------------------------
    TYPE t_supplier_rec IS RECORD (
        vendor_id            NUMBER,
        vendor_name          VARCHAR2(240),
        vendor_type          VARCHAR2(30),
        country              VARCHAR2(25),
        tax_reference        VARCHAR2(150),
        address_line1        VARCHAR2(240),
        address_line2        VARCHAR2(240),
        city                 VARCHAR2(60),
        state                VARCHAR2(150),
        postal_code          VARCHAR2(30),
        bank_account_holder  VARCHAR2(240),
        account_number       VARCHAR2(100),
        iban                 VARCHAR2(50),
        bank_code            VARCHAR2(30)
    );

    FUNCTION fetch_supplier (p_vendor_id NUMBER) RETURN t_supplier_rec
    IS
        l_rec t_supplier_rec;
        l_sql VARCHAR2(4000);
    BEGIN
        -- Query supplier header for name, type, country, tax reference.
        -- Join to primary site for address details.
        -- Left join to IBY external bank accounts for bank details.
        l_sql := q'[
            SELECT s.vendor_id,
                   s.vendor_name,
                   s.vendor_type_lookup_code             AS vendor_type,
                   NVL(ss.country, s.country_of_origin)  AS country,
                   NVL(s.vat_registration_num, s.num_1099) AS tax_reference,
                   ss.address_line1,
                   ss.address_line2,
                   ss.city,
                   ss.state,
                   ss.zip                                AS postal_code,
                   ieba.bank_account_name                AS bank_account_holder,
                   ieba.bank_account_num                 AS account_number,
                   ieba.iban                             AS iban,
                   ieba.bank_number                      AS bank_code
              FROM ap_suppliers s
              LEFT JOIN (
                  SELECT vendor_id, country,
                         address_line1, address_line2, city, state, zip
                    FROM ap_supplier_sites_all
                   WHERE primary_pay_site_flag = 'Y'
                     AND ROWNUM = 1
              ) ss ON ss.vendor_id = s.vendor_id
              LEFT JOIN (
                  SELECT iepa.payee_party_id,
                         ieba.bank_account_name,
                         ieba.bank_account_num,
                         ieba.iban,
                         iebb.bank_number
                    FROM iby_external_payees_all iepa
                    JOIN iby_pmt_instr_uses_all ipiu
                      ON ipiu.ext_pmt_party_id = iepa.ext_payee_id
                     AND ipiu.instrument_type   = 'BANKACCOUNT'
                    JOIN iby_ext_bank_accounts ieba
                      ON ieba.ext_bank_account_id = ipiu.instrument_id
                    LEFT JOIN iby_ext_banks_v iebb
                      ON iebb.bank_party_id = ieba.bank_id
                   WHERE ipiu.order_of_preference = 1
                     AND ROWNUM = 1
              ) ieba ON ieba.payee_party_id = s.party_id
             WHERE s.vendor_id = :1
        ]';

        EXECUTE IMMEDIATE l_sql
            INTO l_rec.vendor_id,
                 l_rec.vendor_name,
                 l_rec.vendor_type,
                 l_rec.country,
                 l_rec.tax_reference,
                 l_rec.address_line1,
                 l_rec.address_line2,
                 l_rec.city,
                 l_rec.state,
                 l_rec.postal_code,
                 l_rec.bank_account_holder,
                 l_rec.account_number,
                 l_rec.iban,
                 l_rec.bank_code
            USING p_vendor_id;

        RETURN l_rec;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Try a simpler query without bank join (IBY tables may not exist)
            BEGIN
                l_sql := q'[
                    SELECT s.vendor_id,
                           s.vendor_name,
                           s.vendor_type_lookup_code             AS vendor_type,
                           NVL(ss.country, s.country_of_origin)  AS country,
                           NVL(s.vat_registration_num, s.num_1099) AS tax_reference,
                           ss.address_line1,
                           ss.address_line2,
                           ss.city,
                           ss.state,
                           ss.zip                                AS postal_code
                      FROM ap_suppliers s
                      LEFT JOIN (
                          SELECT vendor_id, country,
                                 address_line1, address_line2, city, state, zip
                            FROM ap_supplier_sites_all
                           WHERE primary_pay_site_flag = 'Y'
                             AND ROWNUM = 1
                      ) ss ON ss.vendor_id = s.vendor_id
                     WHERE s.vendor_id = :1
                ]';

                EXECUTE IMMEDIATE l_sql
                    INTO l_rec.vendor_id,
                         l_rec.vendor_name,
                         l_rec.vendor_type,
                         l_rec.country,
                         l_rec.tax_reference,
                         l_rec.address_line1,
                         l_rec.address_line2,
                         l_rec.city,
                         l_rec.state,
                         l_rec.postal_code
                    USING p_vendor_id;

                -- Bank fields remain NULL from record initialization
                RETURN l_rec;
            END;

        WHEN OTHERS THEN
            -- IBY tables may not exist; fall back to supplier-only query
            IF SQLCODE = -942 THEN  -- ORA-00942: table or view does not exist
                l_sql := q'[
                    SELECT s.vendor_id,
                           s.vendor_name,
                           s.vendor_type_lookup_code             AS vendor_type,
                           NVL(ss.country, s.country_of_origin)  AS country,
                           NVL(s.vat_registration_num, s.num_1099) AS tax_reference,
                           ss.address_line1,
                           ss.address_line2,
                           ss.city,
                           ss.state,
                           ss.zip                                AS postal_code
                      FROM ap_suppliers s
                      LEFT JOIN (
                          SELECT vendor_id, country,
                                 address_line1, address_line2, city, state, zip
                            FROM ap_supplier_sites_all
                           WHERE primary_pay_site_flag = 'Y'
                             AND ROWNUM = 1
                      ) ss ON ss.vendor_id = s.vendor_id
                     WHERE s.vendor_id = :1
                ]';

                EXECUTE IMMEDIATE l_sql
                    INTO l_rec.vendor_id,
                         l_rec.vendor_name,
                         l_rec.vendor_type,
                         l_rec.country,
                         l_rec.tax_reference,
                         l_rec.address_line1,
                         l_rec.address_line2,
                         l_rec.city,
                         l_rec.state,
                         l_rec.postal_code
                    USING p_vendor_id;

                RETURN l_rec;
            ELSE
                RAISE;
            END IF;
    END fetch_supplier;

    ---------------------------------------------------------------------------
    -- Private: query AR customer data via dynamic SQL
    --
    -- Extended to fetch party_type (business entity type) and
    -- address_line2 alongside the original fields.
    ---------------------------------------------------------------------------
    TYPE t_customer_rec IS RECORD (
        cust_account_id     NUMBER,
        customer_name       VARCHAR2(360),
        party_type          VARCHAR2(30),
        country             VARCHAR2(60),
        tax_reference       VARCHAR2(150),
        address_line1       VARCHAR2(240),
        address_line2       VARCHAR2(240),
        city                VARCHAR2(60),
        state               VARCHAR2(60),
        postal_code         VARCHAR2(30)
    );

    FUNCTION fetch_customer (p_cust_account_id NUMBER) RETURN t_customer_rec
    IS
        l_rec t_customer_rec;
        l_sql VARCHAR2(4000);
    BEGIN
        l_sql := q'[
            SELECT ca.cust_account_id,
                   hp.party_name,
                   hp.party_type,
                   hp.country,
                   hp.tax_reference,
                   NVL(hl.address1, hp.address1)     AS address_line1,
                   NVL(hl.address2, hp.address2)     AS address_line2,
                   NVL(hl.city, hp.city)             AS city,
                   NVL(hl.state, hp.state)           AS state,
                   NVL(hl.postal_code, hp.postal_code) AS postal_code
              FROM hz_cust_accounts ca
              JOIN hz_parties hp
                ON hp.party_id = ca.party_id
              LEFT JOIN hz_party_sites hps
                ON hps.party_id = hp.party_id
               AND hps.identifying_address_flag = 'Y'
              LEFT JOIN hz_locations hl
                ON hl.location_id = hps.location_id
             WHERE ca.cust_account_id = :1
        ]';

        EXECUTE IMMEDIATE l_sql
            INTO l_rec.cust_account_id,
                 l_rec.customer_name,
                 l_rec.party_type,
                 l_rec.country,
                 l_rec.tax_reference,
                 l_rec.address_line1,
                 l_rec.address_line2,
                 l_rec.city,
                 l_rec.state,
                 l_rec.postal_code
            USING p_cust_account_id;

        RETURN l_rec;
    END fetch_customer;

    ---------------------------------------------------------------------------
    -- Private: query iProcurement requisition suggested vendor
    ---------------------------------------------------------------------------
    TYPE t_req_vendor_rec IS RECORD (
        requisition_header_id NUMBER,
        vendor_id             NUMBER,
        vendor_name           VARCHAR2(240),
        vendor_country        VARCHAR2(25)
    );

    FUNCTION fetch_req_vendor (p_req_header_id NUMBER) RETURN t_req_vendor_rec
    IS
        l_rec t_req_vendor_rec;
        l_sql VARCHAR2(4000);
    BEGIN
        l_sql := q'[
            SELECT prh.requisition_header_id,
                   prl.suggested_vendor_id,
                   prl.suggested_vendor_name,
                   NVL(s.country_of_origin, 'US') AS vendor_country
              FROM po_requisition_headers_all prh
              JOIN po_requisition_lines_all prl
                ON prl.requisition_header_id = prh.requisition_header_id
              LEFT JOIN ap_suppliers s
                ON s.vendor_id = prl.suggested_vendor_id
             WHERE prh.requisition_header_id = :1
               AND prl.suggested_vendor_id IS NOT NULL
               AND ROWNUM = 1
        ]';

        EXECUTE IMMEDIATE l_sql
            INTO l_rec.requisition_header_id,
                 l_rec.vendor_id,
                 l_rec.vendor_name,
                 l_rec.vendor_country
            USING p_req_header_id;

        RETURN l_rec;
    END fetch_req_vendor;

    ---------------------------------------------------------------------------
    -- validate_ap_supplier
    --
    -- Maps EBS supplier fields to the new validate_pkg parameter names:
    --   vendor_name          -> p_company_name
    --   vendor_type          -> p_business_entity_type
    --   bank_account_holder  -> p_bank_account_holder
    --   tax_reference        -> p_tax_number
    --   determine_tax_type() -> p_tax_type
    ---------------------------------------------------------------------------
    FUNCTION validate_ap_supplier (
        p_vendor_id    NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER',
        p_module_name  VARCHAR2 DEFAULT NULL
    ) RETURN BOOLEAN
    IS
        l_sup      t_supplier_rec;
        l_ok       BOOLEAN;
        l_tax_type VARCHAR2(30);
        l_module   VARCHAR2(30);
    BEGIN
        -- Resolve effective module name.  Transactional callers pass
        -- 'PO' / 'AP_INVOICE' / 'AP_PAYMENT' / 'AP_PAY_BATCH' so the
        -- per-document fail-mode rules in QUBITON_VALIDATION_CFG apply.
        -- Master-data callers leave it NULL and fall back to AP_SUPPLIERS.
        l_module := NVL(p_module_name, gc_module_ap);

        -- Fetch supplier data from EBS tables
        BEGIN
            l_sup := fetch_supplier(p_vendor_id);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fnd_log('qubiton_ebs_pkg: vendor ' || p_vendor_id || ' not found in AP_SUPPLIERS');
                RETURN TRUE;  -- Cannot validate; do not block
            WHEN OTHERS THEN
                -- EBS tables may not exist (non-EBS install)
                fnd_log('qubiton_ebs_pkg: error fetching vendor ' || p_vendor_id || ': ' || SQLERRM);
                RETURN TRUE;
        END;

        -- Determine tax type from country for the tax validation
        l_tax_type := qubiton_validate_pkg.determine_tax_type(l_sup.country);

        -- Run all active validations for the resolved module
        -- Maps fetched EBS fields to the new validate_pkg parameter names
        l_ok := qubiton_validate_pkg.validate_supplier_all(
            p_module_name          => l_module,
            p_vendor_id            => l_sup.vendor_id,
            p_vendor_name          => l_sup.vendor_name,
            p_country              => l_sup.country,
            p_company_name         => l_sup.vendor_name,
            p_business_entity_type => l_sup.vendor_type,
            p_tax_number           => l_sup.tax_reference,
            p_address_line1        => l_sup.address_line1,
            p_address_line2        => l_sup.address_line2,
            p_city                 => l_sup.city,
            p_state                => l_sup.state,
            p_postal_code          => l_sup.postal_code,
            p_account_number       => l_sup.account_number,
            p_bank_account_holder  => l_sup.bank_account_holder,
            p_iban                 => l_sup.iban,
            p_bank_code            => l_sup.bank_code
        );

        RETURN l_ok;
    EXCEPTION
        WHEN OTHERS THEN
            fnd_log('qubiton_ebs_pkg.validate_ap_supplier: unhandled error for vendor '
                     || p_vendor_id || ': ' || SQLERRM);
            RETURN TRUE;  -- Fail open
    END validate_ap_supplier;

    ---------------------------------------------------------------------------
    -- validate_ar_customer
    --
    -- Maps EBS customer fields to the new validate_pkg parameter names:
    --   customer_name   -> p_company_name
    --   party_type      -> p_business_entity_type
    --   tax_reference   -> p_tax_number
    --   determine_tax_type() -> p_tax_type
    ---------------------------------------------------------------------------
    FUNCTION validate_ar_customer (
        p_cust_account_id NUMBER,
        p_calling_mode    VARCHAR2 DEFAULT 'TRIGGER'
    ) RETURN BOOLEAN
    IS
        l_cust     t_customer_rec;
        l_ok       BOOLEAN;
        l_tax_type VARCHAR2(30);
    BEGIN
        BEGIN
            l_cust := fetch_customer(p_cust_account_id);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fnd_log('qubiton_ebs_pkg: customer ' || p_cust_account_id
                        || ' not found in HZ_CUST_ACCOUNTS');
                RETURN TRUE;
            WHEN OTHERS THEN
                fnd_log('qubiton_ebs_pkg: error fetching customer '
                        || p_cust_account_id || ': ' || SQLERRM);
                RETURN TRUE;
        END;

        -- Determine tax type from country
        l_tax_type := qubiton_validate_pkg.determine_tax_type(l_cust.country);

        l_ok := qubiton_validate_pkg.validate_customer_all(
            p_module_name          => gc_module_hz,
            p_customer_id          => l_cust.cust_account_id,
            p_customer_name        => l_cust.customer_name,
            p_country              => l_cust.country,
            p_company_name         => l_cust.customer_name,
            p_business_entity_type => l_cust.party_type,
            p_tax_number           => l_cust.tax_reference,
            p_address_line1        => l_cust.address_line1,
            p_address_line2        => l_cust.address_line2,
            p_city                 => l_cust.city,
            p_state                => l_cust.state,
            p_postal_code          => l_cust.postal_code
        );

        RETURN l_ok;
    EXCEPTION
        WHEN OTHERS THEN
            fnd_log('qubiton_ebs_pkg.validate_ar_customer: unhandled error for customer '
                     || p_cust_account_id || ': ' || SQLERRM);
            RETURN TRUE;
    END validate_ar_customer;

    ---------------------------------------------------------------------------
    -- validate_iprocurement_req
    --
    -- iProcurement has minimal data -- vendor name and country only.
    -- Sanctions screening is the primary use case here.
    ---------------------------------------------------------------------------
    FUNCTION validate_iprocurement_req (
        p_requisition_header_id NUMBER
    ) RETURN BOOLEAN
    IS
        l_req    t_req_vendor_rec;
        l_ok     BOOLEAN;
    BEGIN
        BEGIN
            l_req := fetch_req_vendor(p_requisition_header_id);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fnd_log('qubiton_ebs_pkg: requisition ' || p_requisition_header_id
                        || ' has no suggested vendor');
                RETURN TRUE;  -- No vendor to validate
            WHEN OTHERS THEN
                fnd_log('qubiton_ebs_pkg: error fetching requisition '
                        || p_requisition_header_id || ': ' || SQLERRM);
                RETURN TRUE;
        END;

        -- iProcurement validations are typically sanctions-only,
        -- but the config table controls what runs.
        -- Pass vendor_name as p_company_name per new signature.
        l_ok := qubiton_validate_pkg.validate_supplier_all(
            p_module_name  => gc_module_ipro,
            p_vendor_id    => l_req.vendor_id,
            p_vendor_name  => l_req.vendor_name,
            p_country      => l_req.vendor_country,
            p_company_name => l_req.vendor_name
        );

        RETURN l_ok;
    EXCEPTION
        WHEN OTHERS THEN
            fnd_log('qubiton_ebs_pkg.validate_iprocurement_req: unhandled error for req '
                     || p_requisition_header_id || ': ' || SQLERRM);
            RETURN TRUE;
    END validate_iprocurement_req;

    ---------------------------------------------------------------------------
    -- run_batch_validation (concurrent program)
    ---------------------------------------------------------------------------
    PROCEDURE run_batch_validation (
        errbuf             OUT VARCHAR2,
        retcode            OUT VARCHAR2,
        p_module           VARCHAR2,
        p_vendor_id_from   NUMBER   DEFAULT NULL,
        p_vendor_id_to     NUMBER   DEFAULT NULL,
        p_country          VARCHAR2 DEFAULT NULL
    )
    IS
        l_sql          VARCHAR2(4000);
        TYPE t_id_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
        l_vendor_ids   t_id_tab;
        l_cursor       SYS_REFCURSOR;
        l_vendor_id    NUMBER;
        l_total        PLS_INTEGER := 0;
        l_passed       PLS_INTEGER := 0;
        l_failed       PLS_INTEGER := 0;
        l_errors       PLS_INTEGER := 0;
        l_ok           BOOLEAN;
    BEGIN
        fnd_output('==========================================================');
        fnd_output('QubitOn Batch Validation');
        fnd_output('Module: ' || p_module);
        fnd_output('Vendor ID range: '
                   || NVL(TO_CHAR(p_vendor_id_from, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'ALL')
                   || ' - '
                   || NVL(TO_CHAR(p_vendor_id_to, 'TM', 'NLS_NUMERIC_CHARACTERS=''.,'''), 'ALL'));
        fnd_output('Country filter: ' || NVL(p_country, 'ALL'));
        fnd_output('Started: ' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS'));
        fnd_output('==========================================================');

        -- Build dynamic cursor for AP_SUPPLIERS with optional filters (bind variables)
        l_sql := 'SELECT vendor_id FROM ap_suppliers WHERE 1=1';

        IF p_vendor_id_from IS NOT NULL THEN
            l_sql := l_sql || ' AND vendor_id >= :id_from';
        END IF;
        IF p_vendor_id_to IS NOT NULL THEN
            l_sql := l_sql || ' AND vendor_id <= :id_to';
        END IF;
        IF p_country IS NOT NULL THEN
            l_sql := l_sql || ' AND UPPER(country_of_origin) = UPPER(TRIM(:country))';
        END IF;

        l_sql := l_sql || ' ORDER BY vendor_id';

        BEGIN
            IF p_vendor_id_from IS NOT NULL AND p_vendor_id_to IS NOT NULL AND p_country IS NOT NULL THEN
                OPEN l_cursor FOR l_sql USING p_vendor_id_from, p_vendor_id_to, p_country;
            ELSIF p_vendor_id_from IS NOT NULL AND p_vendor_id_to IS NOT NULL THEN
                OPEN l_cursor FOR l_sql USING p_vendor_id_from, p_vendor_id_to;
            ELSIF p_vendor_id_from IS NOT NULL AND p_country IS NOT NULL THEN
                OPEN l_cursor FOR l_sql USING p_vendor_id_from, p_country;
            ELSIF p_vendor_id_to IS NOT NULL AND p_country IS NOT NULL THEN
                OPEN l_cursor FOR l_sql USING p_vendor_id_to, p_country;
            ELSIF p_vendor_id_from IS NOT NULL THEN
                OPEN l_cursor FOR l_sql USING p_vendor_id_from;
            ELSIF p_vendor_id_to IS NOT NULL THEN
                OPEN l_cursor FOR l_sql USING p_vendor_id_to;
            ELSIF p_country IS NOT NULL THEN
                OPEN l_cursor FOR l_sql USING p_country;
            ELSE
                OPEN l_cursor FOR l_sql;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                errbuf  := 'failed to open supplier cursor: ' || SQLERRM;
                retcode := '2';
                fnd_log('ERROR: ' || errbuf);
                RETURN;
        END;

        LOOP
            FETCH l_cursor INTO l_vendor_id;
            EXIT WHEN l_cursor%NOTFOUND;

            l_total := l_total + 1;

            BEGIN
                l_ok := validate_ap_supplier(
                    p_vendor_id    => l_vendor_id,
                    p_calling_mode => 'CONCURRENT'
                );

                IF l_ok THEN
                    l_passed := l_passed + 1;
                    fnd_log('PASS: vendor_id=' || l_vendor_id);
                ELSE
                    l_failed := l_failed + 1;
                    fnd_output('FAIL: vendor_id=' || l_vendor_id);
                    fnd_log('FAIL: vendor_id=' || l_vendor_id);
                END IF;
            EXCEPTION
                WHEN OTHERS THEN
                    l_errors := l_errors + 1;
                    fnd_output('ERROR: vendor_id=' || l_vendor_id || ' - ' || SQLERRM);
                    fnd_log('ERROR: vendor_id=' || l_vendor_id || ' - ' || SQLERRM);
            END;

            -- Commit periodically to avoid long-running transaction issues
            IF MOD(l_total, 100) = 0 THEN
                COMMIT;
                fnd_log('Progress: ' || l_total || ' vendors processed');
            END IF;
        END LOOP;

        CLOSE l_cursor;

        -- Summary
        fnd_output('==========================================================');
        fnd_output('Completed: ' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS'));
        fnd_output('Total:  ' || l_total);
        fnd_output('Passed: ' || l_passed);
        fnd_output('Failed: ' || l_failed);
        fnd_output('Errors: ' || l_errors);
        fnd_output('==========================================================');

        fnd_log('Batch complete: total=' || l_total
                || ' passed=' || l_passed
                || ' failed=' || l_failed
                || ' errors=' || l_errors);

        -- Set return code
        IF l_errors > 0 THEN
            retcode := '2';
            errbuf  := l_errors || ' vendor(s) had errors during validation';
        ELSIF l_failed > 0 THEN
            retcode := '1';
            errbuf  := l_failed || ' vendor(s) failed validation out of ' || l_total;
        ELSE
            retcode := '0';
            errbuf  := l_total || ' vendor(s) validated successfully';
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            IF l_cursor%ISOPEN THEN
                CLOSE l_cursor;
            END IF;
            errbuf  := 'batch validation failed: ' || SQLERRM;
            retcode := '2';
            fnd_log('FATAL: ' || errbuf);
            fnd_output('FATAL: ' || errbuf);
    END run_batch_validation;

    ---------------------------------------------------------------------------
    -- Post-event hooks (non-blocking, warning mode)
    ---------------------------------------------------------------------------

    PROCEDURE on_supplier_create (p_vendor_id NUMBER)
    IS
        l_ok BOOLEAN;
    BEGIN
        -- Override to warning mode for post-event hooks
        qubiton_validate_pkg.init(p_error_mode => qubiton_types.gc_mode_warn);

        l_ok := validate_ap_supplier(
            p_vendor_id    => p_vendor_id,
            p_calling_mode => 'TRIGGER'
        );

        -- Reset to config-driven mode
        qubiton_validate_pkg.init(p_error_mode => NULL);

        IF NOT l_ok THEN
            fnd_log('qubiton_ebs_pkg.on_supplier_create: validation warnings for vendor '
                     || p_vendor_id);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            -- Post-event hooks must never raise
            qubiton_validate_pkg.init(p_error_mode => NULL);
            fnd_log('qubiton_ebs_pkg.on_supplier_create: error for vendor '
                     || p_vendor_id || ': ' || SQLERRM);
    END on_supplier_create;

    PROCEDURE on_supplier_update (p_vendor_id NUMBER)
    IS
        l_ok BOOLEAN;
    BEGIN
        qubiton_validate_pkg.init(p_error_mode => qubiton_types.gc_mode_warn);

        l_ok := validate_ap_supplier(
            p_vendor_id    => p_vendor_id,
            p_calling_mode => 'TRIGGER'
        );

        qubiton_validate_pkg.init(p_error_mode => NULL);

        IF NOT l_ok THEN
            fnd_log('qubiton_ebs_pkg.on_supplier_update: validation warnings for vendor '
                     || p_vendor_id);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            qubiton_validate_pkg.init(p_error_mode => NULL);
            fnd_log('qubiton_ebs_pkg.on_supplier_update: error for vendor '
                     || p_vendor_id || ': ' || SQLERRM);
    END on_supplier_update;

    PROCEDURE on_customer_create (p_cust_account_id NUMBER)
    IS
        l_ok BOOLEAN;
    BEGIN
        qubiton_validate_pkg.init(p_error_mode => qubiton_types.gc_mode_warn);

        l_ok := validate_ar_customer(
            p_cust_account_id => p_cust_account_id,
            p_calling_mode    => 'TRIGGER'
        );

        qubiton_validate_pkg.init(p_error_mode => NULL);

        IF NOT l_ok THEN
            fnd_log('qubiton_ebs_pkg.on_customer_create: validation warnings for customer '
                     || p_cust_account_id);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            qubiton_validate_pkg.init(p_error_mode => NULL);
            fnd_log('qubiton_ebs_pkg.on_customer_create: error for customer '
                     || p_cust_account_id || ': ' || SQLERRM);
    END on_customer_create;

    PROCEDURE on_customer_update (p_cust_account_id NUMBER)
    IS
        l_ok BOOLEAN;
    BEGIN
        qubiton_validate_pkg.init(p_error_mode => qubiton_types.gc_mode_warn);

        l_ok := validate_ar_customer(
            p_cust_account_id => p_cust_account_id,
            p_calling_mode    => 'TRIGGER'
        );

        qubiton_validate_pkg.init(p_error_mode => NULL);

        IF NOT l_ok THEN
            fnd_log('qubiton_ebs_pkg.on_customer_update: validation warnings for customer '
                     || p_cust_account_id);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            qubiton_validate_pkg.init(p_error_mode => NULL);
            fnd_log('qubiton_ebs_pkg.on_customer_update: error for customer '
                     || p_cust_account_id || ': ' || SQLERRM);
    END on_customer_update;

    ---------------------------------------------------------------------------
    -- Transactional document validation hooks (PO / AP invoice / payment)
    --
    -- Each function:
    --   1. Checks the master kill switch (TXN_VALIDATION_ENABLED) — if off,
    --      RETURN TRUE immediately (no API call, no DB read, no log).
    --   2. Looks up the supplier/payee referenced by the document.
    --   3. Delegates to qubiton_validate_pkg for the actual screening.
    --   4. Returns FALSE only on a hard block (sanctions match + on_invalid='E');
    --      warn / silent verdicts return TRUE so the caller's trigger lets
    --      the transaction proceed.
    ---------------------------------------------------------------------------

    -- Cache for the master kill switch to avoid hitting QUBITON_CONFIG on every
    -- call within a session (especially relevant for batch sweeps).
    g_txn_enabled_cached BOOLEAN := NULL;

    FUNCTION is_txn_validation_enabled RETURN BOOLEAN
    IS
        l_value VARCHAR2(10);
    BEGIN
        IF g_txn_enabled_cached IS NOT NULL THEN
            RETURN g_txn_enabled_cached;
        END IF;

        BEGIN
            SELECT UPPER(config_value) INTO l_value
              FROM qubiton_config
             WHERE config_key = 'TXN_VALIDATION_ENABLED';

            g_txn_enabled_cached := (l_value = 'Y');
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                -- Row missing from QUBITON_CONFIG = feature disabled.  Customer
                -- can opt in by running setup/seed_config.sql or inserting the
                -- row manually:
                --   INSERT INTO qubiton_config(config_key, config_value)
                --   VALUES('TXN_VALIDATION_ENABLED', 'Y');
                g_txn_enabled_cached := FALSE;
            WHEN OTHERS THEN
                -- Table missing or other DB error — fail open (validate disabled).
                g_txn_enabled_cached := FALSE;
        END;

        RETURN g_txn_enabled_cached;
    END is_txn_validation_enabled;

    ---------------------------------------------------------------------------
    -- PO header validation
    ---------------------------------------------------------------------------
    FUNCTION validate_po_header (
        p_po_header_id NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER'
    ) RETURN BOOLEAN
    IS
        l_vendor_id NUMBER;
        l_ok        BOOLEAN := TRUE;
    BEGIN
        IF NOT is_txn_validation_enabled THEN
            RETURN TRUE;
        END IF;

        -- Read the vendor referenced by the PO via dynamic SQL so the package
        -- compiles outside EBS (PO_HEADERS_ALL only exists on EBS).
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT vendor_id FROM po_headers_all WHERE po_header_id = :1'
                INTO l_vendor_id
                USING p_po_header_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                fnd_log('validate_po_header: PO ' || p_po_header_id || ' not found');
                RETURN TRUE;   -- not our concern
            WHEN OTHERS THEN
                fnd_log('validate_po_header: cannot read po_headers_all - ' || SQLERRM);
                RETURN TRUE;   -- fail open
        END;

        IF l_vendor_id IS NULL THEN
            -- Stock transfer / no vendor — skip
            RETURN TRUE;
        END IF;

        -- Re-screen the supplier on the PO for sanctions and any other
        -- val_types active under module='PO' in QUBITON_VALIDATION_CFG.
        -- The orchestrator honours the per-row on_invalid / on_error rules
        -- (e.g. block on sanctions, warn-allow on API outage) so we do
        -- NOT call init() here — overriding the global error mode would
        -- defeat the per-module policy seeded in setup/seed_config.sql.
        l_ok := validate_ap_supplier(
                    p_vendor_id    => l_vendor_id,
                    p_calling_mode => p_calling_mode,
                    p_module_name  => 'PO');

        IF NOT l_ok THEN
            fnd_log('validate_po_header: BLOCKED PO ' || p_po_header_id ||
                    ' — supplier ' || l_vendor_id || ' failed validation');
        END IF;

        RETURN l_ok;
    EXCEPTION
        WHEN OTHERS THEN
            fnd_log('validate_po_header: error for PO ' || p_po_header_id ||
                    ': ' || SQLERRM);
            -- Fail open: when the QubitOn API is down, allow PO save
            -- (override by setting QUBITON_VALIDATION_CFG.on_error='E' for
            -- module='PO' if your policy is strict-fail-closed).
            RETURN TRUE;
    END validate_po_header;

    ---------------------------------------------------------------------------
    -- AP invoice validation
    ---------------------------------------------------------------------------
    FUNCTION validate_ap_invoice (
        p_invoice_id   NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER'
    ) RETURN BOOLEAN
    IS
        l_vendor_id NUMBER;
        l_ok        BOOLEAN := TRUE;
    BEGIN
        IF NOT is_txn_validation_enabled THEN
            RETURN TRUE;
        END IF;

        BEGIN
            EXECUTE IMMEDIATE
                'SELECT vendor_id FROM ap_invoices_all WHERE invoice_id = :1'
                INTO l_vendor_id
                USING p_invoice_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN TRUE;
            WHEN OTHERS THEN
                fnd_log('validate_ap_invoice: cannot read ap_invoices_all - ' || SQLERRM);
                RETURN TRUE;
        END;

        IF l_vendor_id IS NULL THEN RETURN TRUE; END IF;

        l_ok := validate_ap_supplier(
                    p_vendor_id    => l_vendor_id,
                    p_calling_mode => p_calling_mode,
                    p_module_name  => 'AP_INVOICE');

        IF NOT l_ok THEN
            fnd_log('validate_ap_invoice: BLOCKED invoice ' || p_invoice_id ||
                    ' — supplier ' || l_vendor_id || ' failed validation');
        END IF;
        RETURN l_ok;
    EXCEPTION
        WHEN OTHERS THEN
            fnd_log('validate_ap_invoice: error for invoice ' || p_invoice_id ||
                    ': ' || SQLERRM);
            RETURN TRUE;   -- fail open
    END validate_ap_invoice;

    ---------------------------------------------------------------------------
    -- AP payment validation (last-chance check before bank send)
    ---------------------------------------------------------------------------
    FUNCTION validate_ap_payment (
        p_check_id     NUMBER,
        p_calling_mode VARCHAR2 DEFAULT 'TRIGGER'
    ) RETURN BOOLEAN
    IS
        l_vendor_id NUMBER;
        l_ok        BOOLEAN := TRUE;
    BEGIN
        IF NOT is_txn_validation_enabled THEN
            RETURN TRUE;
        END IF;

        BEGIN
            EXECUTE IMMEDIATE
                'SELECT vendor_id FROM ap_checks_all WHERE check_id = :1'
                INTO l_vendor_id
                USING p_check_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN TRUE;
            WHEN OTHERS THEN
                fnd_log('validate_ap_payment: cannot read ap_checks_all - ' || SQLERRM);
                RETURN TRUE;
        END;

        IF l_vendor_id IS NULL THEN RETURN TRUE; END IF;

        l_ok := validate_ap_supplier(
                    p_vendor_id    => l_vendor_id,
                    p_calling_mode => p_calling_mode,
                    p_module_name  => 'AP_PAYMENT');

        IF NOT l_ok THEN
            fnd_log('validate_ap_payment: BLOCKED check ' || p_check_id ||
                    ' — supplier ' || l_vendor_id || ' on sanctions list');
        END IF;
        RETURN l_ok;
    EXCEPTION
        WHEN OTHERS THEN
            fnd_log('validate_ap_payment: error for check ' || p_check_id ||
                    ': ' || SQLERRM);
            -- Per-rule fail-CLOSED policy lives in QUBITON_VALIDATION_CFG
            -- (AP_PAYMENT/SANCTION on_error='E').  This handler only runs
            -- on truly unexpected errors that escape the orchestrator's
            -- own WHEN OTHERS — fail open here to avoid blocking on
            -- bugs unrelated to the sanctions verdict itself.
            RETURN TRUE;
    END validate_ap_payment;

    ---------------------------------------------------------------------------
    -- Payment-batch screening (filter, do NOT abort the run)
    ---------------------------------------------------------------------------
    PROCEDURE screen_payment_batch (
        p_payment_instruction_id NUMBER
    )
    IS
        TYPE t_pmt_rec IS RECORD (
            payment_id NUMBER,
            vendor_id  NUMBER
        );
        TYPE t_pmts IS TABLE OF t_pmt_rec;
        l_pmts t_pmts;
        l_ok   BOOLEAN;
        l_filtered NUMBER := 0;
    BEGIN
        IF NOT is_txn_validation_enabled THEN
            RETURN;
        END IF;

        -- Pull every payment in the instruction.  IBY_PAYMENTS_ALL stores
        -- the payee as a party_id (HZ_PARTIES.party_id), so we join to
        -- AP_SUPPLIERS to resolve the AP vendor_id that validate_ap_supplier
        -- expects.  Dynamic SQL keeps the package compilable outside EBS.
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT pmt.payment_id, sup.vendor_id ' ||
                '  FROM iby_payments_all pmt ' ||
                '  JOIN ap_suppliers sup ON sup.party_id = pmt.payee_party_id ' ||
                ' WHERE pmt.payment_instruction_id = :1 ' ||
                '   AND pmt.payment_status NOT IN (''VOIDED'',''REJECTED_BY_BANK'')'
                BULK COLLECT INTO l_pmts
                USING p_payment_instruction_id;
        EXCEPTION
            WHEN OTHERS THEN
                fnd_log('screen_payment_batch: cannot read iby_payments_all - ' || SQLERRM);
                RETURN;
        END;

        FOR i IN 1..l_pmts.COUNT LOOP
            l_ok := validate_ap_supplier(
                        p_vendor_id    => l_pmts(i).vendor_id,
                        p_calling_mode => 'CONCURRENT',
                        p_module_name  => 'AP_PAY_BATCH');

            IF NOT l_ok THEN
                -- Mark the payment as held; the standard Payments Manager
                -- run skips HELD payments.  Customer extends with a
                -- QUBITON_PAYMENT_BLOCK_LOG insert for AP visibility.
                BEGIN
                    EXECUTE IMMEDIATE
                        'UPDATE iby_payments_all ' ||
                        '   SET payment_status = ''HELD'', ' ||
                        '       hold_reason    = ''QUBITON_SANCTIONS'' ' ||
                        ' WHERE payment_id     = :1'
                        USING l_pmts(i).payment_id;
                    l_filtered := l_filtered + 1;
                    fnd_log('screen_payment_batch: HELD payment ' ||
                            l_pmts(i).payment_id || ' (vendor ' ||
                            l_pmts(i).vendor_id || ' sanctioned)');
                EXCEPTION
                    WHEN OTHERS THEN
                        fnd_log('screen_payment_batch: failed to hold payment ' ||
                                l_pmts(i).payment_id || ' - ' || SQLERRM);
                END;
            END IF;
        END LOOP;

        fnd_log('screen_payment_batch: instruction ' || p_payment_instruction_id ||
                ' — filtered ' || l_filtered || ' of ' || l_pmts.COUNT || ' payments');
        IF l_filtered > 0 THEN COMMIT; END IF;
    EXCEPTION
        WHEN OTHERS THEN
            fnd_log('screen_payment_batch: error - ' || SQLERRM);
    END screen_payment_batch;

    ---------------------------------------------------------------------------
    -- Concurrent program: nightly batch sweep
    ---------------------------------------------------------------------------
    PROCEDURE run_txn_batch_validation (
        errbuf            OUT VARCHAR2,
        retcode           OUT VARCHAR2,
        p_module          VARCHAR2,
        p_lookback_days   NUMBER   DEFAULT 30,
        p_country         VARCHAR2 DEFAULT NULL
    )
    IS
        l_count_ok    NUMBER := 0;
        l_count_block NUMBER := 0;
        l_vendor_id   NUMBER;
        l_doc_id      NUMBER;
        l_sql         VARCHAR2(4000);
        TYPE t_doc_rec IS RECORD (doc_id NUMBER, vendor_id NUMBER);
        TYPE t_docs    IS TABLE OF t_doc_rec;
        l_docs t_docs;
        l_ok   BOOLEAN;
    BEGIN
        retcode := '0';

        IF NOT is_txn_validation_enabled THEN
            errbuf  := 'TXN_VALIDATION_ENABLED is off — sweep skipped (set to Y in QUBITON_CONFIG to activate)';
            retcode := '1';
            fnd_output(errbuf);
            RETURN;
        END IF;

        -- Pick the source query per module.  Each grabs (doc_id, vendor_id)
        -- for documents created/updated in the last p_lookback_days.
        CASE UPPER(p_module)
            WHEN 'PO' THEN
                l_sql := 'SELECT po_header_id, vendor_id FROM po_headers_all ' ||
                         ' WHERE creation_date >= SYSDATE - :1 ' ||
                         '   AND closed_code IN (''OPEN'',''APPROVED'') ' ||
                         '   AND vendor_id IS NOT NULL';
            WHEN 'AP_INVOICE' THEN
                l_sql := 'SELECT invoice_id, vendor_id FROM ap_invoices_all ' ||
                         ' WHERE invoice_date >= SYSDATE - :1 ' ||
                         '   AND payment_status_flag IN (''N'',''P'') ' ||
                         '   AND vendor_id IS NOT NULL';
            WHEN 'AP_PAYMENT' THEN
                l_sql := 'SELECT check_id, vendor_id FROM ap_checks_all ' ||
                         ' WHERE check_date >= SYSDATE - :1 ' ||
                         '   AND status_lookup_code IN (''NEGOTIABLE'',''ISSUED'') ' ||
                         '   AND vendor_id IS NOT NULL';
            ELSE
                errbuf  := 'Unknown module: ' || p_module ||
                           ' (expected PO / AP_INVOICE / AP_PAYMENT)';
                retcode := '2';
                RETURN;
        END CASE;

        BEGIN
            EXECUTE IMMEDIATE l_sql BULK COLLECT INTO l_docs USING p_lookback_days;
        EXCEPTION
            WHEN OTHERS THEN
                errbuf  := 'Failed to read source table for ' || p_module ||
                           ': ' || SQLERRM;
                retcode := '2';
                fnd_output(errbuf);
                RETURN;
        END;

        fnd_output('QubitOn nightly sweep — module=' || p_module ||
                   ' lookback=' || p_lookback_days || 'd' ||
                   ' candidates=' || l_docs.COUNT);

        FOR i IN 1..l_docs.COUNT LOOP
            l_doc_id    := l_docs(i).doc_id;
            l_vendor_id := l_docs(i).vendor_id;

            -- Route to per-module rules so the sweep honours the same
            -- on_invalid / on_error policy the inline trigger would.
            l_ok := validate_ap_supplier(
                        p_vendor_id    => l_vendor_id,
                        p_calling_mode => 'CONCURRENT',
                        p_module_name  => UPPER(p_module));

            IF l_ok THEN
                l_count_ok := l_count_ok + 1;
            ELSE
                l_count_block := l_count_block + 1;
                fnd_output('  BLOCK  ' || p_module || ' doc=' || l_doc_id ||
                           ' vendor=' || l_vendor_id);
            END IF;
        END LOOP;

        fnd_output('Sweep complete: ' || l_count_ok || ' clean, ' ||
                   l_count_block || ' flagged');

        IF l_count_block > 0 THEN
            errbuf  := l_count_block || ' ' || p_module ||
                       ' document(s) flagged — review the log';
            retcode := '1';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            errbuf  := 'Unexpected error in sweep: ' || SQLERRM;
            retcode := '2';
            fnd_output(errbuf);
    END run_txn_batch_validation;

END qubiton_ebs_pkg;
/
