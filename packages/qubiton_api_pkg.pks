--------------------------------------------------------------------------------
-- QUBITON_API_PKG — Layer 1 API Client (Package Specification)
--
-- Oracle PL/SQL package for calling the QubitOn API.
-- Wraps all 42 API endpoints across address, tax, bank, email, phone,
-- business registration, peppol, sanctions, compliance, EPA, healthcare,
-- risk, ESG, cybersecurity, corporate structure, industry, certification,
-- classification, financial ops, supplier, gender, and reference categories.
--
-- Prerequisites:
--   1. QUBITON_CONFIG table populated with API key and connection settings
--   2. QUBITON_API_LOG table for call logging (optional but recommended)
--   3. Oracle Wallet configured for HTTPS (see setup scripts)
--   4. ACL granting connect privilege to the executing schema
--   5. QUBITON_TYPES package installed (type definitions)
--
-- Usage:
--   -- Auto-init from QUBITON_CONFIG table:
--   SELECT qubiton_api_pkg.validate_address('US', '123 Main St', 'Springfield')
--     FROM DUAL;
--
--   -- Manual init:
--   BEGIN
--     qubiton_api_pkg.init(p_api_key => 'your-key-here');
--   END;
--
-- Error modes:
--   'E' = raise exception on API/validation errors (default)
--   'W' = DBMS_OUTPUT warning, return NULL
--   'S' = silent, return NULL
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE qubiton_api_pkg
AUTHID CURRENT_USER
AS
    ---------------------------------------------------------------------------
    -- Types
    ---------------------------------------------------------------------------

    -- Name/value pair for building JSON payloads
    TYPE t_name_value IS RECORD (
        name   VARCHAR2(200),
        value  VARCHAR2(4000),
        vtype  VARCHAR2(1) DEFAULT 'S'  -- S=string, N=number, B=boolean
    );
    TYPE tt_name_value IS TABLE OF t_name_value INDEX BY PLS_INTEGER;

    -- Parsed result from JSON response
    TYPE t_result IS RECORD (
        success       BOOLEAN,
        is_valid      BOOLEAN,
        message       VARCHAR2(4000),
        field_missing BOOLEAN,
        blocked       BOOLEAN
    );

    ---------------------------------------------------------------------------
    -- Error codes (RAISE_APPLICATION_ERROR range -20000..-20999)
    ---------------------------------------------------------------------------
    gc_err_not_initialized   CONSTANT PLS_INTEGER := -20100;
    gc_err_required_param    CONSTANT PLS_INTEGER := -20101;
    gc_err_http_request      CONSTANT PLS_INTEGER := -20102;
    gc_err_http_status       CONSTANT PLS_INTEGER := -20103;
    gc_err_rate_limited      CONSTANT PLS_INTEGER := -20104;
    gc_err_config_missing    CONSTANT PLS_INTEGER := -20105;
    gc_err_validation_failed CONSTANT PLS_INTEGER := -20106;
    gc_err_parse_failed      CONSTANT PLS_INTEGER := -20107;
    gc_err_timeout           CONSTANT PLS_INTEGER := -20108;

    ---------------------------------------------------------------------------
    -- Initialization
    ---------------------------------------------------------------------------

    -- Initialize from QUBITON_CONFIG table and/or explicit parameters.
    -- Explicit parameters override table values when provided.
    PROCEDURE init(
        p_api_key         IN VARCHAR2 DEFAULT NULL,
        p_base_url        IN VARCHAR2 DEFAULT NULL,
        p_wallet_path     IN VARCHAR2 DEFAULT NULL,
        p_wallet_password IN VARCHAR2 DEFAULT NULL,
        p_timeout         IN PLS_INTEGER DEFAULT NULL,
        p_error_mode      IN VARCHAR2 DEFAULT NULL,
        p_log_enabled     IN BOOLEAN DEFAULT NULL
    );

    ---------------------------------------------------------------------------
    -- Utility functions (public)
    ---------------------------------------------------------------------------

    -- Build a JSON object string from a name/value collection
    FUNCTION build_json(
        p_pairs IN tt_name_value
    ) RETURN VARCHAR2;

    -- Parse a specific field from a JSON response into t_result
    FUNCTION parse_result(
        p_json       IN CLOB,
        p_field_name IN VARCHAR2 DEFAULT 'isValid'
    ) RETURN qubiton_types.t_result;

    -- Parse result and apply error mode handling
    FUNCTION handle_result(
        p_json       IN CLOB,
        p_field_name IN VARCHAR2 DEFAULT 'isValid',
        p_error_mode IN VARCHAR2 DEFAULT NULL  -- NULL = use package default
    ) RETURN qubiton_types.t_result;

    -- Test API connectivity
    FUNCTION test_connection RETURN VARCHAR2;

    ---------------------------------------------------------------------------
    -- Address (1)
    ---------------------------------------------------------------------------

    -- POST /api/address/validate
    FUNCTION validate_address(
        p_country       IN VARCHAR2,
        p_address_line1 IN VARCHAR2 DEFAULT NULL,
        p_address_line2 IN VARCHAR2 DEFAULT NULL,
        p_city          IN VARCHAR2 DEFAULT NULL,
        p_state         IN VARCHAR2 DEFAULT NULL,
        p_postal_code   IN VARCHAR2 DEFAULT NULL,
        p_company_name  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Tax (2)
    ---------------------------------------------------------------------------

    -- POST /api/tax/validate
    FUNCTION validate_tax(
        p_tax_number          IN VARCHAR2,
        p_tax_type            IN VARCHAR2,
        p_country             IN VARCHAR2,
        p_company_name        IN VARCHAR2,
        p_business_entity_type IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/tax/format-validate
    FUNCTION validate_tax_format(
        p_tax_number IN VARCHAR2,
        p_tax_type   IN VARCHAR2,
        p_country    IN VARCHAR2
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Bank (2)
    ---------------------------------------------------------------------------

    -- POST /api/bankaccount/validate
    FUNCTION validate_bank_account(
        p_business_entity_type IN VARCHAR2,
        p_country              IN VARCHAR2,
        p_bank_account_holder  IN VARCHAR2,
        p_account_number       IN VARCHAR2 DEFAULT NULL,
        p_business_name        IN VARCHAR2 DEFAULT NULL,
        p_tax_id_number        IN VARCHAR2 DEFAULT NULL,
        p_tax_type             IN VARCHAR2 DEFAULT NULL,
        p_bank_code            IN VARCHAR2 DEFAULT NULL,
        p_iban                 IN VARCHAR2 DEFAULT NULL,
        p_swift_code           IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/bankaccount/pro/validate
    FUNCTION validate_bank_pro(
        p_business_entity_type IN VARCHAR2,
        p_country              IN VARCHAR2,
        p_bank_account_holder  IN VARCHAR2,
        p_account_number       IN VARCHAR2 DEFAULT NULL,
        p_bank_code            IN VARCHAR2 DEFAULT NULL,
        p_iban                 IN VARCHAR2 DEFAULT NULL,
        p_swift_code           IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Email & Phone (2)
    ---------------------------------------------------------------------------

    -- POST /api/email/validate
    FUNCTION validate_email(
        p_email_address IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/phone/validate
    FUNCTION validate_phone(
        p_phone_number    IN VARCHAR2,
        p_country         IN VARCHAR2,
        p_phone_extension IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Business Registration (1)
    ---------------------------------------------------------------------------

    -- POST /api/businessregistration/lookup
    FUNCTION lookup_business_registration(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2,
        p_state        IN VARCHAR2 DEFAULT NULL,
        p_city         IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Peppol (1)
    ---------------------------------------------------------------------------

    -- POST /api/peppol/validate
    FUNCTION validate_peppol(
        p_participant_id    IN VARCHAR2,
        p_directory_lookup  IN VARCHAR2 DEFAULT 'Y'
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Sanctions & Compliance (3)
    ---------------------------------------------------------------------------

    -- POST /api/prohibited/lookup
    FUNCTION check_sanctions(
        p_company_name  IN VARCHAR2,
        p_country       IN VARCHAR2,
        p_address_line1 IN VARCHAR2 DEFAULT NULL,
        p_address_line2 IN VARCHAR2 DEFAULT NULL,
        p_city          IN VARCHAR2 DEFAULT NULL,
        p_state         IN VARCHAR2 DEFAULT NULL,
        p_postal_code   IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/pep/lookup
    FUNCTION screen_pep(
        p_name    IN VARCHAR2,
        p_country IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/disqualifieddirectors/validate
    FUNCTION check_directors(
        p_first_name  IN VARCHAR2,
        p_last_name   IN VARCHAR2,
        p_country     IN VARCHAR2,
        p_middle_name IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- EPA (2)
    ---------------------------------------------------------------------------

    -- POST /api/criminalprosecution/validate
    FUNCTION check_epa_prosecution(
        p_name        IN VARCHAR2 DEFAULT NULL,
        p_state       IN VARCHAR2 DEFAULT NULL,
        p_fiscal_year IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/criminalprosecution/lookup
    FUNCTION lookup_epa_prosecution(
        p_name        IN VARCHAR2 DEFAULT NULL,
        p_state       IN VARCHAR2 DEFAULT NULL,
        p_fiscal_year IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Healthcare (2)
    ---------------------------------------------------------------------------

    -- POST /api/providerexclusion/validate
    FUNCTION check_healthcare_exclusion(
        p_health_care_type IN VARCHAR2,
        p_entity_name      IN VARCHAR2 DEFAULT NULL,
        p_last_name        IN VARCHAR2 DEFAULT NULL,
        p_first_name       IN VARCHAR2 DEFAULT NULL,
        p_address          IN VARCHAR2 DEFAULT NULL,
        p_city             IN VARCHAR2 DEFAULT NULL,
        p_state            IN VARCHAR2 DEFAULT NULL,
        p_zip_code         IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/providerexclusion/lookup
    FUNCTION lookup_healthcare_exclusion(
        p_health_care_type IN VARCHAR2,
        p_entity_name      IN VARCHAR2 DEFAULT NULL,
        p_last_name        IN VARCHAR2 DEFAULT NULL,
        p_first_name       IN VARCHAR2 DEFAULT NULL,
        p_address          IN VARCHAR2 DEFAULT NULL,
        p_city             IN VARCHAR2 DEFAULT NULL,
        p_state            IN VARCHAR2 DEFAULT NULL,
        p_zip_code         IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Risk & Financial (5)
    ---------------------------------------------------------------------------

    -- POST /api/risk/lookup (category=Bankruptcy)
    FUNCTION check_bankruptcy_risk(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/risk/lookup (category=Credit Score)
    FUNCTION lookup_credit_score(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/risk/lookup (category=Fail Rate)
    FUNCTION lookup_fail_rate(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/entity/fraud/lookup
    FUNCTION assess_entity_risk(
        p_company_name              IN VARCHAR2,
        p_country_of_incorporation  IN VARCHAR2 DEFAULT NULL,
        p_category                  IN VARCHAR2 DEFAULT NULL,
        p_url                       IN VARCHAR2 DEFAULT NULL,
        p_business_entity_type      IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/creditanalysis/lookup
    FUNCTION lookup_credit_analysis(
        p_company_name  IN VARCHAR2,
        p_address_line1 IN VARCHAR2,
        p_city          IN VARCHAR2,
        p_state         IN VARCHAR2,
        p_country       IN VARCHAR2,
        p_duns_number   IN VARCHAR2 DEFAULT NULL,
        p_postal_code   IN VARCHAR2 DEFAULT NULL,
        p_address_line2 IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- ESG & Cybersecurity (3)
    ---------------------------------------------------------------------------

    -- POST /api/esg/Scores
    FUNCTION lookup_esg_score(
        p_company_name IN VARCHAR2,
        p_country      IN VARCHAR2,
        p_domain       IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/itsecurity/domainreport
    FUNCTION domain_security_report(
        p_domain IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/ipquality/validate
    FUNCTION check_ip_quality(
        p_ip_address  IN VARCHAR2,
        p_user_agent  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Corporate Structure (4)
    ---------------------------------------------------------------------------

    -- POST /api/beneficialownership/lookup
    FUNCTION lookup_beneficial_ownership(
        p_company_name  IN VARCHAR2,
        p_country_iso2  IN VARCHAR2,
        p_ubo_threshold IN VARCHAR2 DEFAULT NULL,
        p_max_layers    IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/corporatehierarchy/lookup
    FUNCTION lookup_corporate_hierarchy(
        p_company_name  IN VARCHAR2,
        p_address_line1 IN VARCHAR2,
        p_city          IN VARCHAR2,
        p_state         IN VARCHAR2,
        p_zip_code      IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/duns-number-lookup
    FUNCTION lookup_duns(
        p_duns_number IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/company/hierarchy/lookup
    FUNCTION lookup_hierarchy(
        p_identifier      IN VARCHAR2,
        p_identifier_type IN VARCHAR2,
        p_country         IN VARCHAR2 DEFAULT NULL,
        p_options         IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Industry (4)
    ---------------------------------------------------------------------------

    -- POST /api/nationalprovideridentifier/validate
    FUNCTION validate_npi(
        p_npi               IN VARCHAR2,
        p_organization_name IN VARCHAR2 DEFAULT NULL,
        p_last_name         IN VARCHAR2 DEFAULT NULL,
        p_first_name        IN VARCHAR2 DEFAULT NULL,
        p_middle_name       IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/medpass/validate
    FUNCTION validate_medpass(
        p_id                   IN VARCHAR2,
        p_business_entity_type IN VARCHAR2,
        p_company_name         IN VARCHAR2 DEFAULT NULL,
        p_tax_id               IN VARCHAR2 DEFAULT NULL,
        p_country              IN VARCHAR2 DEFAULT NULL,
        p_state                IN VARCHAR2 DEFAULT NULL,
        p_city                 IN VARCHAR2 DEFAULT NULL,
        p_postal_code          IN VARCHAR2 DEFAULT NULL,
        p_address_line1        IN VARCHAR2 DEFAULT NULL,
        p_address_line2        IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/dot/fmcsa/lookup
    FUNCTION lookup_dot_carrier(
        p_dot_number   IN VARCHAR2,
        p_entity_name  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/inidentity/validate
    FUNCTION validate_india_identity(
        p_identity_number      IN VARCHAR2,
        p_identity_number_type IN VARCHAR2,
        p_entity_name          IN VARCHAR2 DEFAULT NULL,
        p_dob                  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Certification (2)
    ---------------------------------------------------------------------------

    -- POST /api/certification/validate
    FUNCTION validate_certification(
        p_company_name        IN VARCHAR2,
        p_country             IN VARCHAR2,
        p_city                IN VARCHAR2 DEFAULT NULL,
        p_state               IN VARCHAR2 DEFAULT NULL,
        p_zip_code            IN VARCHAR2 DEFAULT NULL,
        p_address_line1       IN VARCHAR2 DEFAULT NULL,
        p_address_line2       IN VARCHAR2 DEFAULT NULL,
        p_identity_type       IN VARCHAR2 DEFAULT NULL,
        p_certification_type  IN VARCHAR2 DEFAULT NULL,
        p_certification_group IN VARCHAR2 DEFAULT NULL,
        p_certification_number IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/certification/lookup
    FUNCTION lookup_certification(
        p_company_name  IN VARCHAR2,
        p_country       IN VARCHAR2,
        p_city          IN VARCHAR2 DEFAULT NULL,
        p_state         IN VARCHAR2 DEFAULT NULL,
        p_zip_code      IN VARCHAR2 DEFAULT NULL,
        p_address_line1 IN VARCHAR2 DEFAULT NULL,
        p_address_line2 IN VARCHAR2 DEFAULT NULL,
        p_identity_type IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Classification (1)
    ---------------------------------------------------------------------------

    -- POST /api/businessclassification/lookup
    FUNCTION lookup_business_classification(
        p_company_name IN VARCHAR2,
        p_city         IN VARCHAR2,
        p_state        IN VARCHAR2,
        p_country      IN VARCHAR2,
        p_address1     IN VARCHAR2 DEFAULT NULL,
        p_address2     IN VARCHAR2 DEFAULT NULL,
        p_phone        IN VARCHAR2 DEFAULT NULL,
        p_postal_code  IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Financial Ops (2)
    ---------------------------------------------------------------------------

    -- POST /api/paymentterms/validate
    FUNCTION analyze_payment_terms(
        p_current_pay_term IN VARCHAR2,
        p_annual_spend     IN NUMBER,
        p_avg_days_pay     IN NUMBER,
        p_savings_rate     IN NUMBER,
        p_threshold        IN NUMBER,
        p_vendor_name      IN VARCHAR2 DEFAULT NULL,
        p_country          IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    -- POST /api/currency/exchange-rates/{baseCurrency}
    FUNCTION lookup_exchange_rates(
        p_base_currency IN VARCHAR2,
        p_dates         IN VARCHAR2
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Supplier (2)
    ---------------------------------------------------------------------------

    -- POST /api/aribasupplierprofile/lookup
    FUNCTION lookup_ariba_supplier(
        p_anid IN VARCHAR2
    ) RETURN CLOB;

    -- POST /api/aribasupplierprofile/validate
    FUNCTION validate_ariba_supplier(
        p_anid IN VARCHAR2
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Gender (1)
    ---------------------------------------------------------------------------

    -- POST /api/genderize/identifygender
    FUNCTION identify_gender(
        p_name    IN VARCHAR2,
        p_country IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Reference (2)
    ---------------------------------------------------------------------------

    -- GET /api/tax/format-validate/countries
    FUNCTION get_supported_tax_formats RETURN CLOB;

    -- GET /api/peppol/schemes
    FUNCTION get_peppol_schemes RETURN CLOB;

    ---------------------------------------------------------------------------
    -- Utility
    ---------------------------------------------------------------------------

    -- Extract a top-level scalar value from a JSON CLOB by key name.
    -- Returns NULL if key is not found or value is JSON null.
    -- Works on Oracle 11g+ (INSTR/SUBSTR, no JSON_VALUE dependency).
    FUNCTION extract_json_value(
        p_json IN CLOB,
        p_key  IN VARCHAR2
    ) RETURN VARCHAR2;

END qubiton_api_pkg;
/
