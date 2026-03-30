CREATE OR REPLACE PACKAGE qubiton_validate_pkg
AS
    ---------------------------------------------------------------------------
    -- QubitOn Validation Orchestrator (Layer 2)
    --
    -- Config-driven validation that reads QUBITON_VALIDATION_CFG and
    -- dispatches to qubiton_api_pkg functions.  Maps Oracle EBS fields
    -- to API parameters.
    --
    -- Dependencies:
    --   qubiton_types      (type definitions, error constants)
    --   qubiton_api_pkg    (HTTP/JSON layer -- Layer 1)
    --   QUBITON_VALIDATION_CFG table
    --
    -- Version: 2.0.0
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    -- Initialisation
    ---------------------------------------------------------------------------

    -- Initialise the package, optionally overriding the default error mode
    -- for the current session.  Pass NULL to reset to config-driven mode.
    PROCEDURE init (p_error_mode VARCHAR2 DEFAULT NULL);

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
    ) RETURN qubiton_types.t_result;

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
    ) RETURN qubiton_types.t_result;

    FUNCTION validate_supplier_address (
        p_vendor_id      NUMBER,
        p_country        VARCHAR2,
        p_address_line1  VARCHAR2 DEFAULT NULL,
        p_address_line2  VARCHAR2 DEFAULT NULL,
        p_city           VARCHAR2 DEFAULT NULL,
        p_state          VARCHAR2 DEFAULT NULL,
        p_postal_code    VARCHAR2 DEFAULT NULL,
        p_company_name   VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result;

    FUNCTION validate_supplier_sanctions (
        p_vendor_id      NUMBER,
        p_vendor_name    VARCHAR2,
        p_country        VARCHAR2 DEFAULT NULL,
        p_address_line1  VARCHAR2 DEFAULT NULL,
        p_address_line2  VARCHAR2 DEFAULT NULL,
        p_city           VARCHAR2 DEFAULT NULL,
        p_state          VARCHAR2 DEFAULT NULL,
        p_postal_code    VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result;

    -- Run every active validation for a module.
    -- Returns FALSE if any validation blocked (on_invalid = 'E' and failed).
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
    ) RETURN BOOLEAN;

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
    ) RETURN qubiton_types.t_result;

    FUNCTION validate_customer_address (
        p_customer_id    NUMBER,
        p_country        VARCHAR2,
        p_address_line1  VARCHAR2 DEFAULT NULL,
        p_address_line2  VARCHAR2 DEFAULT NULL,
        p_city           VARCHAR2 DEFAULT NULL,
        p_state          VARCHAR2 DEFAULT NULL,
        p_postal_code    VARCHAR2 DEFAULT NULL,
        p_company_name   VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result;

    FUNCTION validate_customer_sanctions (
        p_customer_id    NUMBER,
        p_customer_name  VARCHAR2,
        p_country        VARCHAR2 DEFAULT NULL,
        p_address_line1  VARCHAR2 DEFAULT NULL,
        p_address_line2  VARCHAR2 DEFAULT NULL,
        p_city           VARCHAR2 DEFAULT NULL,
        p_state          VARCHAR2 DEFAULT NULL,
        p_postal_code    VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_result;

    -- Run every active validation for a module.
    -- Returns FALSE if any validation blocked.
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
    ) RETURN BOOLEAN;

    ---------------------------------------------------------------------------
    -- Address comparison
    ---------------------------------------------------------------------------

    -- Validate an address and return both original and standardized versions
    -- so the caller can compare before/after and choose which to keep.
    -- Returns t_address_comparison with has_changes = TRUE when the API
    -- returned a different (corrected) address.
    FUNCTION compare_address (
        p_country       VARCHAR2,
        p_address_line1 VARCHAR2 DEFAULT NULL,
        p_address_line2 VARCHAR2 DEFAULT NULL,
        p_city          VARCHAR2 DEFAULT NULL,
        p_state         VARCHAR2 DEFAULT NULL,
        p_postal_code   VARCHAR2 DEFAULT NULL
    ) RETURN qubiton_types.t_address_comparison;

    ---------------------------------------------------------------------------
    -- Utility functions
    ---------------------------------------------------------------------------

    -- Map ISO-3166 alpha-2 country code to the standard tax type code.
    FUNCTION determine_tax_type (p_country VARCHAR2) RETURN VARCHAR2;

    -- Check whether a country passes the filter defined in config.
    FUNCTION is_country_enabled (
        p_module_name VARCHAR2,
        p_val_type    VARCHAR2,
        p_country     VARCHAR2
    ) RETURN BOOLEAN;

    -- Return active validation configs for a given module.
    FUNCTION get_active_config (
        p_module_name VARCHAR2
    ) RETURN qubiton_types.tt_val_config;

END qubiton_validate_pkg;
/
