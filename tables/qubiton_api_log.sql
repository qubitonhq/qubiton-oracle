-- qubiton_api_log.sql
-- Audit log for all QubitOn API calls.
-- Logged via PRAGMA AUTONOMOUS_TRANSACTION so entries survive rollbacks.
-- Requires Oracle 12c+ (IDENTITY column, INTERVAL partitioning).
--
-- For Oracle 11g: replace IDENTITY with a sequence + trigger:
--   CREATE SEQUENCE qubiton_api_log_seq START WITH 1 INCREMENT BY 1 NOCACHE;
--   Then change "NUMBER GENERATED ALWAYS AS IDENTITY" to just "NUMBER NOT NULL"
--   and add a BEFORE INSERT trigger to populate log_id from the sequence.
--   Also remove the INTERVAL and PARTITION clauses (use a non-partitioned table).

CREATE TABLE qubiton_api_log (
    log_id         NUMBER GENERATED ALWAYS AS IDENTITY,
    log_timestamp  TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    api_method     VARCHAR2(100)  NOT NULL,
    http_method    VARCHAR2(10)   DEFAULT 'POST',
    endpoint_path  VARCHAR2(500)  NOT NULL,
    http_status    NUMBER(3),
    elapsed_ms     NUMBER(10),
    request_bytes  NUMBER(10),
    response_bytes NUMBER(10),
    error_code     NUMBER(6),
    error_message  VARCHAR2(4000),
    calling_user   VARCHAR2(128)  DEFAULT SYS_CONTEXT('USERENV', 'SESSION_USER'),
    calling_module VARCHAR2(100)  DEFAULT SYS_CONTEXT('USERENV', 'MODULE'),
    client_info    VARCHAR2(100)  DEFAULT SYS_CONTEXT('USERENV', 'CLIENT_INFO'),
    CONSTRAINT qubiton_api_log_pk PRIMARY KEY (log_id)
)
PARTITION BY RANGE (log_timestamp)
INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'))
(
    PARTITION p_initial VALUES LESS THAN (TIMESTAMP '2026-01-01 00:00:00')
);

CREATE INDEX qubiton_api_log_ts_ix  ON qubiton_api_log (log_timestamp) LOCAL;
CREATE INDEX qubiton_api_log_mth_ix ON qubiton_api_log (api_method, log_timestamp) LOCAL;

COMMENT ON TABLE  qubiton_api_log IS 'Audit trail for all QubitOn API calls';
COMMENT ON COLUMN qubiton_api_log.log_id         IS 'Auto-generated sequence';
COMMENT ON COLUMN qubiton_api_log.api_method      IS 'PL/SQL function name (e.g., validate_address)';
COMMENT ON COLUMN qubiton_api_log.http_status     IS 'HTTP response status code';
COMMENT ON COLUMN qubiton_api_log.elapsed_ms      IS 'Round-trip time in milliseconds';
COMMENT ON COLUMN qubiton_api_log.error_code      IS 'Oracle error code if call failed';
COMMENT ON COLUMN qubiton_api_log.error_message   IS 'Error description (truncated to 4000 chars)';
COMMENT ON COLUMN qubiton_api_log.calling_user    IS 'Database user who made the call';
COMMENT ON COLUMN qubiton_api_log.calling_module  IS 'Application module (from DBMS_APPLICATION_INFO)';
/
