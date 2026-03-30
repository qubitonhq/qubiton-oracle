-- qubiton_validation_cfg.sql
-- Per-module validation configuration for the QubitOn Oracle connector.
-- Controls which validations run for which EBS module or custom context.

CREATE TABLE qubiton_validation_cfg (
    module_name    VARCHAR2(30)  NOT NULL,   -- e.g., AP_SUPPLIERS, HZ_PARTIES, IBY_BANK, CUSTOM
    val_type       VARCHAR2(20)  NOT NULL,   -- TAX, BANK, ADDRESS, SANCTION, EMAIL, PHONE
    active         VARCHAR2(1)   DEFAULT 'Y' NOT NULL,  -- Y=active, N=disabled
    on_invalid     VARCHAR2(1)   DEFAULT 'E' NOT NULL,  -- E=stop, W=warn, S=silent
    on_error       VARCHAR2(1)   DEFAULT 'W' NOT NULL,  -- E=stop, W=warn, S=silent
    country_filter VARCHAR2(500) DEFAULT NULL,           -- Comma-separated ISO codes, NULL=all
    description    VARCHAR2(200),
    updated_by     VARCHAR2(128) DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER'),
    updated_at     TIMESTAMP     DEFAULT SYSTIMESTAMP,
    CONSTRAINT qubiton_val_cfg_pk PRIMARY KEY (module_name, val_type),
    CONSTRAINT qubiton_val_cfg_active_ck  CHECK (active     IN ('Y', 'N')),
    CONSTRAINT qubiton_val_cfg_invalid_ck CHECK (on_invalid IN ('E', 'W', 'S')),
    CONSTRAINT qubiton_val_cfg_error_ck   CHECK (on_error   IN ('E', 'W', 'S'))
);

COMMENT ON TABLE  qubiton_validation_cfg IS 'QubitOn validation rules per EBS module';
COMMENT ON COLUMN qubiton_validation_cfg.module_name    IS 'Oracle module or context identifier';
COMMENT ON COLUMN qubiton_validation_cfg.val_type       IS 'Validation type: TAX, BANK, ADDRESS, SANCTION, EMAIL, PHONE';
COMMENT ON COLUMN qubiton_validation_cfg.active         IS 'Y=enabled, N=disabled';
COMMENT ON COLUMN qubiton_validation_cfg.on_invalid     IS 'Action on validation failure: E=raise error, W=warn, S=silent';
COMMENT ON COLUMN qubiton_validation_cfg.on_error       IS 'Action on API/network error: E=raise error, W=warn, S=silent';
COMMENT ON COLUMN qubiton_validation_cfg.country_filter IS 'Comma-separated ISO country codes (NULL=all countries)';
/
