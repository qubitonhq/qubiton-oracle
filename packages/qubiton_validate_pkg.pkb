CREATE OR REPLACE PACKAGE BODY qubiton_validate_pkg
AS
    ---------------------------------------------------------------------------
    -- QubitOn Validation Orchestrator (Layer 2) -- Implementation
    ---------------------------------------------------------------------------

    -- Session-level error mode override (NULL = use per-config setting)
    g_error_mode_override  VARCHAR2(1) := NULL;

    ---------------------------------------------------------------------------
    -- Private helpers
    ---------------------------------------------------------------------------

    -- Apply error mode logic to a result.
    -- If the validation failed (is_valid = FALSE), set blocked according to
    -- the effective error mode.
    PROCEDURE apply_error_mode (
        p_result     IN OUT qubiton_types.t_result,
        p_error_mode IN     VARCHAR2
    )
    IS
        l_mode VARCHAR2(1);
    BEGIN
        l_mode := COALESCE(g_error_mode_override, p_error_mode, qubiton_types.gc_mode_warn);

        IF p_result.success AND NOT p_result.is_valid THEN
            -- Validation ran successfully but the data is invalid
            IF l_mode = qubiton_types.gc_mode_stop THEN
                p_result.blocked := TRUE;
            ELSE
                p_result.blocked := FALSE;
            END IF;
        ELSIF NOT p_result.success THEN
            -- API call itself failed
            IF l_mode = qubiton_types.gc_mode_stop THEN
                p_result.blocked := TRUE;
            ELSE
                p_result.blocked := FALSE;
            END IF;
        ELSE
            p_result.blocked := FALSE;
        END IF;
    END apply_error_mode;

    -- Look up on_invalid or on_error mode for a specific config entry.
    FUNCTION get_error_mode (
        p_config    IN qubiton_types.t_val_config,
        p_api_ok    IN BOOLEAN
    ) RETURN VARCHAR2
    IS
    BEGIN
        IF p_api_ok THEN
            RETURN COALESCE(g_error_mode_override, p_config.on_invalid, qubiton_types.gc_mode_warn);
        ELSE
            RETURN COALESCE(g_error_mode_override, p_config.on_error, qubiton_types.gc_mode_warn);
        END IF;
    END get_error_mode;

    -- Parse a comma-separated country filter string and check membership.
    FUNCTION country_in_filter (
        p_filter  IN VARCHAR2,
        p_country IN VARCHAR2
    ) RETURN BOOLEAN
    IS
        l_upper_filter  VARCHAR2(500);
        l_upper_country VARCHAR2(10);
        l_pos           PLS_INTEGER;
        l_start         PLS_INTEGER := 1;
        l_token         VARCHAR2(10);
    BEGIN
        IF p_filter IS NULL THEN
            RETURN TRUE;  -- NULL filter means all countries enabled
        END IF;

        IF p_country IS NULL THEN
            RETURN FALSE;
        END IF;

        l_upper_filter  := UPPER(TRIM(p_filter));
        l_upper_country := UPPER(TRIM(p_country));

        -- Walk through comma-separated tokens
        LOOP
            l_pos := INSTR(l_upper_filter, ',', l_start);
            IF l_pos = 0 THEN
                l_token := TRIM(SUBSTR(l_upper_filter, l_start));
            ELSE
                l_token := TRIM(SUBSTR(l_upper_filter, l_start, l_pos - l_start));
            END IF;

            IF l_token = l_upper_country THEN
                RETURN TRUE;
            END IF;

            EXIT WHEN l_pos = 0;
            l_start := l_pos + 1;
        END LOOP;

        RETURN FALSE;
    END country_in_filter;

    ---------------------------------------------------------------------------
    -- init
    ---------------------------------------------------------------------------
    PROCEDURE init (p_error_mode VARCHAR2 DEFAULT NULL)
    IS
    BEGIN
        IF p_error_mode IS NOT NULL
           AND p_error_mode NOT IN (
               qubiton_types.gc_mode_stop,
               qubiton_types.gc_mode_warn,
               qubiton_types.gc_mode_silent
           )
        THEN
            RAISE_APPLICATION_ERROR(
                qubiton_types.gc_err_validation,
                'invalid error mode: ' || p_error_mode
                    || ' (expected E, W, or S)'
            );
        END IF;
        g_error_mode_override := p_error_mode;
    END init;

    ---------------------------------------------------------------------------
    -- determine_tax_type
    ---------------------------------------------------------------------------
    FUNCTION determine_tax_type (p_country VARCHAR2) RETURN VARCHAR2
    IS
        l_country VARCHAR2(10);
    BEGIN
        l_country := UPPER(TRIM(p_country));

        RETURN CASE l_country
            -- North America
            WHEN 'US' THEN 'EIN'
            WHEN 'CA' THEN 'BN'
            WHEN 'MX' THEN 'RFC'
            -- United Kingdom & Ireland
            WHEN 'GB' THEN 'VAT'
            WHEN 'IE' THEN 'PPS'
            -- EU member states -> VAT
            WHEN 'DE' THEN 'UST'
            WHEN 'FR' THEN 'TVA'
            WHEN 'IT' THEN 'PARTITAIVA'
            WHEN 'ES' THEN 'VAT'
            WHEN 'NL' THEN 'VAT'
            WHEN 'BE' THEN 'VAT'
            WHEN 'AT' THEN 'VAT'
            WHEN 'PT' THEN 'VAT'
            WHEN 'FI' THEN 'VAT'
            WHEN 'SE' THEN 'VAT'
            WHEN 'DK' THEN 'VAT'
            WHEN 'NO' THEN 'VAT'
            WHEN 'PL' THEN 'VAT'
            WHEN 'CZ' THEN 'VAT'
            WHEN 'SK' THEN 'VAT'
            WHEN 'HU' THEN 'VAT'
            WHEN 'RO' THEN 'VAT'
            WHEN 'BG' THEN 'VAT'
            WHEN 'HR' THEN 'VAT'
            WHEN 'SI' THEN 'VAT'
            WHEN 'EE' THEN 'VAT'
            WHEN 'LV' THEN 'VAT'
            WHEN 'LT' THEN 'VAT'
            WHEN 'LU' THEN 'VAT'
            WHEN 'MT' THEN 'VAT'
            WHEN 'CY' THEN 'VAT'
            WHEN 'GR' THEN 'VAT'
            -- Asia-Pacific
            WHEN 'AU' THEN 'ABN'
            WHEN 'NZ' THEN 'IRD'
            WHEN 'IN' THEN 'GSTIN'
            WHEN 'JP' THEN 'CN'
            WHEN 'KR' THEN 'BRN'
            WHEN 'SG' THEN 'UEN'
            WHEN 'HK' THEN 'BRN'
            WHEN 'CN' THEN 'USCC'
            -- South America
            WHEN 'BR' THEN 'CNPJ'
            WHEN 'AR' THEN 'CUIT'
            WHEN 'CL' THEN 'RUT'
            WHEN 'CO' THEN 'NIT'
            -- Africa
            WHEN 'ZA' THEN 'VAT'
            WHEN 'NG' THEN 'TIN'
            WHEN 'KE' THEN 'KRA'
            -- Middle East
            WHEN 'AE' THEN 'TRN'
            WHEN 'SA' THEN 'VAT'
            -- Default
            ELSE 'TIN'
        END;
    END determine_tax_type;

    ---------------------------------------------------------------------------
    -- is_country_enabled
    ---------------------------------------------------------------------------
    FUNCTION is_country_enabled (
        p_module_name VARCHAR2,
        p_val_type    VARCHAR2,
        p_country     VARCHAR2
    ) RETURN BOOLEAN
    IS
        l_filter VARCHAR2(500);
    BEGIN
        BEGIN
            SELECT country_filter
              INTO l_filter
              FROM qubiton_validation_cfg
             WHERE module_name = UPPER(TRIM(p_module_name))
               AND val_type    = UPPER(TRIM(p_val_type))
               AND active      = 'Y';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN FALSE;  -- No active config = not enabled
        END;

        RETURN country_in_filter(l_filter, p_country);
    END is_country_enabled;

    ---------------------------------------------------------------------------
    -- get_active_config
    ---------------------------------------------------------------------------
    FUNCTION get_active_config (
        p_module_name VARCHAR2
    ) RETURN qubiton_types.tt_val_config
    IS
        l_configs qubiton_types.tt_val_config;
        l_idx     PLS_INTEGER := 0;

        CURSOR c_cfg IS
            SELECT module_name,
                   val_type,
                   active,
                   on_invalid,
                   on_error,
                   country_filter
              FROM qubiton_validation_cfg
             WHERE module_name = UPPER(TRIM(p_module_name))
               AND active = 'Y'
             ORDER BY val_type;
    BEGIN
        FOR r IN c_cfg LOOP
            l_idx := l_idx + 1;
            l_configs(l_idx).module_name    := r.module_name;
            l_configs(l_idx).val_type       := r.val_type;
            l_configs(l_idx).active         := r.active;
            l_configs(l_idx).on_invalid     := r.on_invalid;
            l_configs(l_idx).on_error       := r.on_error;
            l_configs(l_idx).country_filter := r.country_filter;
        END LOOP;

        RETURN l_configs;
    END get_active_config;

    ---------------------------------------------------------------------------
    -- Supplier validations (individual)
    ---------------------------------------------------------------------------

    FUNCTION validate_supplier_tax (
        p_vendor_id             NUMBER,
        p_country               VARCHAR2,
        p_tax_number            VARCHAR2,
        p_company_name          VARCHAR2,
        p_tax_type              VARCHAR2 DEFAULT NULL,
        p_business_entity_type  VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result
    IS
        l_result    qubiton_types.t_result;
        l_tax_type  VARCHAR2(20);
        l_response  CLOB;
    BEGIN
        l_tax_type := COALESCE(p_tax_type, determine_tax_type(p_country));

        -- Call Layer 1 API
        l_response := qubiton_api_pkg.validate_tax(
            p_tax_number            => p_tax_number,
            p_tax_type              => l_tax_type,
            p_country               => p_country,
            p_company_name          => p_company_name,
            p_business_entity_type  => p_business_entity_type
        );

        -- Parse response into result record
        l_result := qubiton_api_pkg.parse_result(
            p_json => l_response
        );

        RETURN l_result;
    EXCEPTION
        WHEN OTHERS THEN
            l_result.success       := FALSE;
            l_result.is_valid      := FALSE;
            l_result.message       := 'tax validation error for vendor '
                                      || p_vendor_id || ': ' || SQLERRM;
            l_result.field_missing := FALSE;
            l_result.blocked       := FALSE;
            RETURN l_result;
    END validate_supplier_tax;

    FUNCTION validate_supplier_bank (
        p_vendor_id             NUMBER,
        p_country               VARCHAR2,
        p_business_entity_type  VARCHAR2,
        p_bank_account_holder   VARCHAR2,
        p_account_number        VARCHAR2 DEFAULT NULL,
        p_business_name         VARCHAR2 DEFAULT NULL,
        p_tax_id_number         VARCHAR2 DEFAULT NULL,
        p_tax_type              VARCHAR2 DEFAULT NULL,
        p_bank_code             VARCHAR2 DEFAULT NULL,
        p_iban                  VARCHAR2 DEFAULT NULL,
        p_swift_code            VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result
    IS
        l_result   qubiton_types.t_result;
        l_response CLOB;
    BEGIN
        l_response := qubiton_api_pkg.validate_bank_account(
            p_business_entity_type  => p_business_entity_type,
            p_country               => p_country,
            p_bank_account_holder   => p_bank_account_holder,
            p_account_number        => p_account_number,
            p_business_name         => p_business_name,
            p_tax_id_number         => p_tax_id_number,
            p_tax_type              => p_tax_type,
            p_bank_code             => p_bank_code,
            p_iban                  => p_iban,
            p_swift_code            => p_swift_code
        );

        l_result := qubiton_api_pkg.parse_result(
            p_json => l_response
        );

        RETURN l_result;
    EXCEPTION
        WHEN OTHERS THEN
            l_result.success       := FALSE;
            l_result.is_valid      := FALSE;
            l_result.message       := 'bank validation error for vendor '
                                      || p_vendor_id || ': ' || SQLERRM;
            l_result.field_missing := FALSE;
            l_result.blocked       := FALSE;
            RETURN l_result;
    END validate_supplier_bank;

    FUNCTION validate_supplier_address (
        p_vendor_id      NUMBER,
        p_country        VARCHAR2,
        p_address_line1  VARCHAR2 DEFAULT NULL,
        p_address_line2  VARCHAR2 DEFAULT NULL,
        p_city           VARCHAR2 DEFAULT NULL,
        p_state          VARCHAR2 DEFAULT NULL,
        p_postal_code    VARCHAR2 DEFAULT NULL,
        p_company_name   VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result
    IS
        l_result   qubiton_types.t_result;
        l_response CLOB;
    BEGIN
        l_response := qubiton_api_pkg.validate_address(
            p_country        => p_country,
            p_address_line1  => p_address_line1,
            p_address_line2  => p_address_line2,
            p_city           => p_city,
            p_state          => p_state,
            p_postal_code    => p_postal_code,
            p_company_name   => p_company_name
        );

        l_result := qubiton_api_pkg.parse_result(
            p_json => l_response
        );

        RETURN l_result;
    EXCEPTION
        WHEN OTHERS THEN
            l_result.success       := FALSE;
            l_result.is_valid      := FALSE;
            l_result.message       := 'address validation error for vendor '
                                      || p_vendor_id || ': ' || SQLERRM;
            l_result.field_missing := FALSE;
            l_result.blocked       := FALSE;
            RETURN l_result;
    END validate_supplier_address;

    FUNCTION validate_supplier_sanctions (
        p_vendor_id      NUMBER,
        p_vendor_name    VARCHAR2,
        p_country        VARCHAR2 DEFAULT NULL,
        p_address_line1  VARCHAR2 DEFAULT NULL,
        p_address_line2  VARCHAR2 DEFAULT NULL,
        p_city           VARCHAR2 DEFAULT NULL,
        p_state          VARCHAR2 DEFAULT NULL,
        p_postal_code    VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result
    IS
        l_result   qubiton_types.t_result;
        l_response CLOB;
    BEGIN
        l_response := qubiton_api_pkg.check_sanctions(
            p_company_name   => p_vendor_name,
            p_country        => p_country,
            p_address_line1  => p_address_line1,
            p_address_line2  => p_address_line2,
            p_city           => p_city,
            p_state          => p_state,
            p_postal_code    => p_postal_code
        );

        l_result := qubiton_api_pkg.parse_result(
            p_json       => l_response,
            p_field_name => 'hasMatches'
        );

        -- IMPORTANT: hasMatches=true means entity IS on a sanctions list,
        -- so is_valid should be FALSE (not safe).  parse_result sets
        -- is_valid=TRUE when the field is true, so we invert.
        IF l_result.success THEN
            l_result.is_valid := NOT l_result.is_valid;
        END IF;

        RETURN l_result;
    EXCEPTION
        WHEN OTHERS THEN
            l_result.success       := FALSE;
            l_result.is_valid      := FALSE;
            l_result.message       := 'sanctions screening error for vendor '
                                      || p_vendor_id || ': ' || SQLERRM;
            l_result.field_missing := FALSE;
            l_result.blocked       := FALSE;
            RETURN l_result;
    END validate_supplier_sanctions;

    ---------------------------------------------------------------------------
    -- validate_supplier_all
    ---------------------------------------------------------------------------
    FUNCTION validate_supplier_all (
        p_module_name           VARCHAR2,
        p_vendor_id             NUMBER,
        p_vendor_name           VARCHAR2,
        p_country               VARCHAR2,
        p_company_name          VARCHAR2 DEFAULT NULL,
        p_business_entity_type  VARCHAR2 DEFAULT NULL,
        p_tax_number            VARCHAR2 DEFAULT NULL,
        p_address_line1         VARCHAR2 DEFAULT NULL,
        p_address_line2         VARCHAR2 DEFAULT NULL,
        p_city                  VARCHAR2 DEFAULT NULL,
        p_state                 VARCHAR2 DEFAULT NULL,
        p_postal_code           VARCHAR2 DEFAULT NULL,
        p_account_number        VARCHAR2 DEFAULT NULL,
        p_bank_account_holder   VARCHAR2 DEFAULT NULL,
        p_iban                  VARCHAR2 DEFAULT NULL,
        p_bank_code             VARCHAR2 DEFAULT NULL,
        p_swift_code            VARCHAR2 DEFAULT NULL
    ) RETURN BOOLEAN
    IS
        l_configs  qubiton_types.tt_val_config;
        l_result   qubiton_types.t_result;
        l_mode     VARCHAR2(1);
        l_blocked  BOOLEAN := FALSE;
    BEGIN
        l_configs := get_active_config(p_module_name);

        IF l_configs.COUNT = 0 THEN
            RETURN TRUE;  -- No active validations configured
        END IF;

        FOR i IN 1 .. l_configs.COUNT LOOP
            -- Skip if country is filtered out
            IF NOT country_in_filter(l_configs(i).country_filter, p_country) THEN
                CONTINUE;
            END IF;

            CASE l_configs(i).val_type
                WHEN 'TAX' THEN
                    IF p_tax_number IS NOT NULL THEN
                        l_result := validate_supplier_tax(
                            p_vendor_id             => p_vendor_id,
                            p_country               => p_country,
                            p_tax_number            => p_tax_number,
                            p_company_name          => p_company_name,
                            p_business_entity_type  => p_business_entity_type
                        );
                        l_mode := get_error_mode(l_configs(i), l_result.success);
                        apply_error_mode(l_result, l_mode);
                        IF l_result.blocked THEN
                            l_blocked := TRUE;
                        END IF;
                    END IF;

                WHEN 'BANK' THEN
                    IF p_account_number IS NOT NULL OR p_iban IS NOT NULL THEN
                        l_result := validate_supplier_bank(
                            p_vendor_id             => p_vendor_id,
                            p_country               => p_country,
                            p_business_entity_type  => p_business_entity_type,
                            p_bank_account_holder   => p_bank_account_holder,
                            p_account_number        => p_account_number,
                            p_business_name         => p_company_name,
                            p_tax_id_number         => p_tax_number,
                            p_iban                  => p_iban,
                            p_bank_code             => p_bank_code,
                            p_swift_code            => p_swift_code
                        );
                        l_mode := get_error_mode(l_configs(i), l_result.success);
                        apply_error_mode(l_result, l_mode);
                        IF l_result.blocked THEN
                            l_blocked := TRUE;
                        END IF;
                    END IF;

                WHEN 'ADDRESS' THEN
                    IF p_address_line1 IS NOT NULL THEN
                        l_result := validate_supplier_address(
                            p_vendor_id      => p_vendor_id,
                            p_country        => p_country,
                            p_address_line1  => p_address_line1,
                            p_address_line2  => p_address_line2,
                            p_city           => p_city,
                            p_state          => p_state,
                            p_postal_code    => p_postal_code,
                            p_company_name   => p_company_name
                        );
                        l_mode := get_error_mode(l_configs(i), l_result.success);
                        apply_error_mode(l_result, l_mode);
                        IF l_result.blocked THEN
                            l_blocked := TRUE;
                        END IF;
                    END IF;

                WHEN 'SANCTION' THEN
                    IF p_vendor_name IS NOT NULL THEN
                        l_result := validate_supplier_sanctions(
                            p_vendor_id      => p_vendor_id,
                            p_vendor_name    => p_vendor_name,
                            p_country        => p_country,
                            p_address_line1  => p_address_line1,
                            p_address_line2  => p_address_line2,
                            p_city           => p_city,
                            p_state          => p_state,
                            p_postal_code    => p_postal_code
                        );
                        l_mode := get_error_mode(l_configs(i), l_result.success);
                        apply_error_mode(l_result, l_mode);
                        IF l_result.blocked THEN
                            l_blocked := TRUE;
                        END IF;
                    END IF;

                ELSE
                    NULL;  -- Unknown val_type, skip gracefully
            END CASE;
        END LOOP;

        RETURN NOT l_blocked;
    EXCEPTION
        WHEN OTHERS THEN
            -- Orchestrator must never crash the caller
            RETURN TRUE;
    END validate_supplier_all;

    ---------------------------------------------------------------------------
    -- Customer validations (individual)
    ---------------------------------------------------------------------------

    FUNCTION validate_customer_tax (
        p_customer_id           NUMBER,
        p_country               VARCHAR2,
        p_tax_number            VARCHAR2,
        p_company_name          VARCHAR2,
        p_tax_type              VARCHAR2 DEFAULT NULL,
        p_business_entity_type  VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result
    IS
        l_result    qubiton_types.t_result;
        l_tax_type  VARCHAR2(20);
        l_response  CLOB;
    BEGIN
        l_tax_type := COALESCE(p_tax_type, determine_tax_type(p_country));

        l_response := qubiton_api_pkg.validate_tax(
            p_tax_number            => p_tax_number,
            p_tax_type              => l_tax_type,
            p_country               => p_country,
            p_company_name          => p_company_name,
            p_business_entity_type  => p_business_entity_type
        );

        l_result := qubiton_api_pkg.parse_result(
            p_json => l_response
        );

        RETURN l_result;
    EXCEPTION
        WHEN OTHERS THEN
            l_result.success       := FALSE;
            l_result.is_valid      := FALSE;
            l_result.message       := 'tax validation error for customer '
                                      || p_customer_id || ': ' || SQLERRM;
            l_result.field_missing := FALSE;
            l_result.blocked       := FALSE;
            RETURN l_result;
    END validate_customer_tax;

    FUNCTION validate_customer_address (
        p_customer_id    NUMBER,
        p_country        VARCHAR2,
        p_address_line1  VARCHAR2 DEFAULT NULL,
        p_address_line2  VARCHAR2 DEFAULT NULL,
        p_city           VARCHAR2 DEFAULT NULL,
        p_state          VARCHAR2 DEFAULT NULL,
        p_postal_code    VARCHAR2 DEFAULT NULL,
        p_company_name   VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result
    IS
        l_result   qubiton_types.t_result;
        l_response CLOB;
    BEGIN
        l_response := qubiton_api_pkg.validate_address(
            p_country        => p_country,
            p_address_line1  => p_address_line1,
            p_address_line2  => p_address_line2,
            p_city           => p_city,
            p_state          => p_state,
            p_postal_code    => p_postal_code,
            p_company_name   => p_company_name
        );

        l_result := qubiton_api_pkg.parse_result(
            p_json => l_response
        );

        RETURN l_result;
    EXCEPTION
        WHEN OTHERS THEN
            l_result.success       := FALSE;
            l_result.is_valid      := FALSE;
            l_result.message       := 'address validation error for customer '
                                      || p_customer_id || ': ' || SQLERRM;
            l_result.field_missing := FALSE;
            l_result.blocked       := FALSE;
            RETURN l_result;
    END validate_customer_address;

    FUNCTION validate_customer_sanctions (
        p_customer_id    NUMBER,
        p_customer_name  VARCHAR2,
        p_country        VARCHAR2 DEFAULT NULL,
        p_address_line1  VARCHAR2 DEFAULT NULL,
        p_address_line2  VARCHAR2 DEFAULT NULL,
        p_city           VARCHAR2 DEFAULT NULL,
        p_state          VARCHAR2 DEFAULT NULL,
        p_postal_code    VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result
    IS
        l_result   qubiton_types.t_result;
        l_response CLOB;
    BEGIN
        l_response := qubiton_api_pkg.check_sanctions(
            p_company_name   => p_customer_name,
            p_country        => p_country,
            p_address_line1  => p_address_line1,
            p_address_line2  => p_address_line2,
            p_city           => p_city,
            p_state          => p_state,
            p_postal_code    => p_postal_code
        );

        l_result := qubiton_api_pkg.parse_result(
            p_json       => l_response,
            p_field_name => 'hasMatches'
        );

        -- IMPORTANT: hasMatches=true means entity IS on a sanctions list,
        -- so is_valid should be FALSE (not safe).  parse_result sets
        -- is_valid=TRUE when the field is true, so we invert.
        IF l_result.success THEN
            l_result.is_valid := NOT l_result.is_valid;
        END IF;

        RETURN l_result;
    EXCEPTION
        WHEN OTHERS THEN
            l_result.success       := FALSE;
            l_result.is_valid      := FALSE;
            l_result.message       := 'sanctions screening error for customer '
                                      || p_customer_id || ': ' || SQLERRM;
            l_result.field_missing := FALSE;
            l_result.blocked       := FALSE;
            RETURN l_result;
    END validate_customer_sanctions;

    ---------------------------------------------------------------------------
    -- validate_customer_all
    ---------------------------------------------------------------------------
    FUNCTION validate_customer_all (
        p_module_name           VARCHAR2,
        p_customer_id           NUMBER,
        p_customer_name         VARCHAR2,
        p_country               VARCHAR2,
        p_company_name          VARCHAR2 DEFAULT NULL,
        p_business_entity_type  VARCHAR2 DEFAULT NULL,
        p_tax_number            VARCHAR2 DEFAULT NULL,
        p_address_line1         VARCHAR2 DEFAULT NULL,
        p_address_line2         VARCHAR2 DEFAULT NULL,
        p_city                  VARCHAR2 DEFAULT NULL,
        p_state                 VARCHAR2 DEFAULT NULL,
        p_postal_code           VARCHAR2 DEFAULT NULL
    ) RETURN BOOLEAN
    IS
        l_configs  qubiton_types.tt_val_config;
        l_result   qubiton_types.t_result;
        l_mode     VARCHAR2(1);
        l_blocked  BOOLEAN := FALSE;
    BEGIN
        l_configs := get_active_config(p_module_name);

        IF l_configs.COUNT = 0 THEN
            RETURN TRUE;
        END IF;

        FOR i IN 1 .. l_configs.COUNT LOOP
            IF NOT country_in_filter(l_configs(i).country_filter, p_country) THEN
                CONTINUE;
            END IF;

            CASE l_configs(i).val_type
                WHEN 'TAX' THEN
                    IF p_tax_number IS NOT NULL THEN
                        l_result := validate_customer_tax(
                            p_customer_id           => p_customer_id,
                            p_country               => p_country,
                            p_tax_number            => p_tax_number,
                            p_company_name          => p_company_name,
                            p_business_entity_type  => p_business_entity_type
                        );
                        l_mode := get_error_mode(l_configs(i), l_result.success);
                        apply_error_mode(l_result, l_mode);
                        IF l_result.blocked THEN
                            l_blocked := TRUE;
                        END IF;
                    END IF;

                WHEN 'ADDRESS' THEN
                    IF p_address_line1 IS NOT NULL THEN
                        l_result := validate_customer_address(
                            p_customer_id    => p_customer_id,
                            p_country        => p_country,
                            p_address_line1  => p_address_line1,
                            p_address_line2  => p_address_line2,
                            p_city           => p_city,
                            p_state          => p_state,
                            p_postal_code    => p_postal_code,
                            p_company_name   => p_company_name
                        );
                        l_mode := get_error_mode(l_configs(i), l_result.success);
                        apply_error_mode(l_result, l_mode);
                        IF l_result.blocked THEN
                            l_blocked := TRUE;
                        END IF;
                    END IF;

                WHEN 'SANCTION' THEN
                    IF p_customer_name IS NOT NULL THEN
                        l_result := validate_customer_sanctions(
                            p_customer_id    => p_customer_id,
                            p_customer_name  => p_customer_name,
                            p_country        => p_country,
                            p_address_line1  => p_address_line1,
                            p_address_line2  => p_address_line2,
                            p_city           => p_city,
                            p_state          => p_state,
                            p_postal_code    => p_postal_code
                        );
                        l_mode := get_error_mode(l_configs(i), l_result.success);
                        apply_error_mode(l_result, l_mode);
                        IF l_result.blocked THEN
                            l_blocked := TRUE;
                        END IF;
                    END IF;

                ELSE
                    NULL;  -- Unknown val_type, skip gracefully
            END CASE;
        END LOOP;

        RETURN NOT l_blocked;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN TRUE;
    END validate_customer_all;

    ---------------------------------------------------------------------------
    -- compare_address: call API, parse standardized fields, flag changes
    ---------------------------------------------------------------------------
    FUNCTION compare_address (
        p_country       VARCHAR2,
        p_address_line1 VARCHAR2 DEFAULT NULL,
        p_address_line2 VARCHAR2 DEFAULT NULL,
        p_city          VARCHAR2 DEFAULT NULL,
        p_state         VARCHAR2 DEFAULT NULL,
        p_postal_code   VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_address_comparison
    IS
        l_result  qubiton_types.t_address_comparison;
        l_json    CLOB;

        -- Helper: extract a top-level value from JSON, wrapper for readability
        FUNCTION jval(p_key VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            RETURN qubiton_api_pkg.extract_json_value(l_json, p_key);
        END;

        -- Helper: extract value from nested standardizedAddress object
        -- Uses simple string search for "standardizedAddress":{..."key":"val"...}
        FUNCTION std_val(p_key VARCHAR2) RETURN VARCHAR2
        IS
            l_sa_start PLS_INTEGER;
            l_sa_end   PLS_INTEGER;
            l_inner    VARCHAR2(4000);
            l_search   VARCHAR2(200);
            l_pos      PLS_INTEGER;
            l_vstart   PLS_INTEGER;
            l_vend     PLS_INTEGER;
            l_char     VARCHAR2(1);
        BEGIN
            IF l_json IS NULL THEN RETURN NULL; END IF;

            -- Find "standardizedAddress":{ ... }
            l_sa_start := DBMS_LOB.INSTR(l_json, '"standardizedAddress"', 1, 1);
            IF l_sa_start = 0 THEN RETURN NULL; END IF;

            -- Find the opening brace
            l_sa_start := DBMS_LOB.INSTR(l_json, '{', l_sa_start, 1);
            IF l_sa_start = 0 THEN RETURN NULL; END IF;

            -- Find matching closing brace (simple: no nested objects expected)
            l_sa_end := DBMS_LOB.INSTR(l_json, '}', l_sa_start, 1);
            IF l_sa_end = 0 THEN RETURN NULL; END IF;

            l_inner := DBMS_LOB.SUBSTR(l_json, l_sa_end - l_sa_start + 1, l_sa_start);

            -- Find "key":"value" within the inner object
            l_search := '"' || p_key || '"';
            l_pos := INSTR(l_inner, l_search);
            IF l_pos = 0 THEN RETURN NULL; END IF;

            -- Skip past key, colon, whitespace to value
            l_vstart := l_pos + LENGTH(l_search);
            LOOP
                l_char := SUBSTR(l_inner, l_vstart, 1);
                EXIT WHEN l_char IS NULL OR l_char NOT IN (':', ' ', CHR(9));
                l_vstart := l_vstart + 1;
            END LOOP;

            IF l_char = '"' THEN
                l_vstart := l_vstart + 1;
                l_vend := INSTR(l_inner, '"', l_vstart);
                IF l_vend = 0 THEN RETURN NULL; END IF;
                RETURN SUBSTR(l_inner, l_vstart, l_vend - l_vstart);
            ELSE
                -- Non-string value
                l_vend := l_vstart;
                LOOP
                    l_char := SUBSTR(l_inner, l_vend, 1);
                    EXIT WHEN l_char IS NULL OR l_char IN (',', '}', ' ');
                    l_vend := l_vend + 1;
                END LOOP;
                RETURN TRIM(SUBSTR(l_inner, l_vstart, l_vend - l_vstart));
            END IF;
        END std_val;

    BEGIN
        -- Populate original address
        l_result.original.country       := p_country;
        l_result.original.address_line1 := p_address_line1;
        l_result.original.address_line2 := p_address_line2;
        l_result.original.city          := p_city;
        l_result.original.state         := p_state;
        l_result.original.postal_code   := p_postal_code;

        -- Call the API
        l_json := qubiton_api_pkg.validate_address(
            p_country       => p_country,
            p_address_line1 => p_address_line1,
            p_address_line2 => p_address_line2,
            p_city          => p_city,
            p_state         => p_state,
            p_postal_code   => p_postal_code
        );

        IF l_json IS NULL THEN
            l_result.is_valid     := FALSE;
            l_result.has_changes  := FALSE;
            RETURN l_result;
        END IF;

        l_result.raw_response := l_json;

        -- Parse isValid
        DECLARE
            l_parsed qubiton_types.t_result;
        BEGIN
            l_parsed := qubiton_api_pkg.parse_result(l_json, 'isValid');
            l_result.is_valid := l_parsed.is_valid;
        END;

        -- Parse confidenceScore
        DECLARE
            l_score_str VARCHAR2(100);
        BEGIN
            l_score_str := jval('confidenceScore');
            IF l_score_str IS NOT NULL THEN
                l_result.confidence_score := TO_NUMBER(l_score_str);
            END IF;
        EXCEPTION
            WHEN VALUE_ERROR THEN
                l_result.confidence_score := NULL;
        END;

        -- Parse standardized address fields
        l_result.standardized.country       := NVL(std_val('country'), p_country);
        l_result.standardized.address_line1 := std_val('addressLine1');
        l_result.standardized.address_line2 := std_val('addressLine2');
        l_result.standardized.city          := std_val('city');
        l_result.standardized.state         := std_val('state');
        l_result.standardized.postal_code   := std_val('postalCode');

        -- Determine if the API changed anything
        l_result.has_changes :=
            NVL(UPPER(l_result.standardized.address_line1), '~') <> NVL(UPPER(p_address_line1), '~')
            OR NVL(UPPER(l_result.standardized.address_line2), '~') <> NVL(UPPER(p_address_line2), '~')
            OR NVL(UPPER(l_result.standardized.city), '~') <> NVL(UPPER(p_city), '~')
            OR NVL(UPPER(l_result.standardized.state), '~') <> NVL(UPPER(p_state), '~')
            OR NVL(UPPER(l_result.standardized.postal_code), '~') <> NVL(UPPER(p_postal_code), '~');

        RETURN l_result;

    EXCEPTION
        WHEN OTHERS THEN
            l_result.is_valid    := FALSE;
            l_result.has_changes := FALSE;
            IF l_json IS NOT NULL AND DBMS_LOB.ISTEMPORARY(l_json) = 1 THEN
                DBMS_LOB.FREETEMPORARY(l_json);
            END IF;
            RETURN l_result;
    END compare_address;

END qubiton_validate_pkg;
/
