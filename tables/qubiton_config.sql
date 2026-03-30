-- qubiton_config.sql
-- General configuration table for the QubitOn Oracle connector.
-- Stores API key, base URL, wallet path, timeout, error mode, etc.
--
-- Maintenance: INSERT/UPDATE via SQL or your preferred admin tool.

CREATE TABLE qubiton_config (
    config_key    VARCHAR2(50)   NOT NULL,
    config_value  VARCHAR2(4000) NOT NULL,
    description   VARCHAR2(200),
    updated_by    VARCHAR2(128)  DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER'),
    updated_at    TIMESTAMP      DEFAULT SYSTIMESTAMP,
    CONSTRAINT qubiton_config_pk PRIMARY KEY (config_key)
);

COMMENT ON TABLE  qubiton_config IS 'QubitOn API connector configuration';
COMMENT ON COLUMN qubiton_config.config_key   IS 'Configuration parameter name';
COMMENT ON COLUMN qubiton_config.config_value IS 'Configuration parameter value';
COMMENT ON COLUMN qubiton_config.description  IS 'Human-readable description';
COMMENT ON COLUMN qubiton_config.updated_by   IS 'Last modified by (DB user)';
COMMENT ON COLUMN qubiton_config.updated_at   IS 'Last modified timestamp';
/
