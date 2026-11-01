-- ============================================================
-- sql/04_create_audit_log.sql
-- Stage 3 Step 1: Create the ETL audit log table and helpers.
--
-- HOW TO RUN (from the project root):
--   sqlplus projectuser/<password>@localhost:1521/XEPDB1 @sql\04_create_audit_log.sql
--
-- WHAT THIS FILE CREATES
--   1. etl_audit_log  : one row per ETL step (cleaning procedure call).
--   2. p_log_start    : inserts a RUNNING row; returns the log_id.
--   3. p_log_end      : updates that row with SUCCESS/ERROR and counts.
--
-- WHY PRAGMA AUTONOMOUS_TRANSACTION?
--   Imagine a cleaning procedure cleans 90,000 rows, then fails on row
--   90,001 and rolls back. Without autonomous transactions, the log row
--   would also roll back and we would lose all evidence of the failure.
--   An autonomous transaction commits to the log table independently of
--   the main transaction, so the log row is always visible even after
--   a rollback. This is the standard Oracle pattern for audit logging.
-- ============================================================

-- ---- Drop the table if it exists from a previous run -------
-- ORA-00942 = "table or view does not exist" -- safe to ignore.
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE etl_audit_log PURGE';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -942 THEN NULL;
        ELSE RAISE;
        END IF;
END;
/

-- ---- Create the audit log table ----------------------------
CREATE TABLE etl_audit_log (
    log_id          NUMBER          GENERATED ALWAYS AS IDENTITY,
    step_name       VARCHAR2(100)   NOT NULL,
    rows_read       NUMBER,                       -- rows in the source table
    rows_loaded     NUMBER,                       -- rows actually inserted
    rows_rejected   NUMBER,                       -- rows skipped (read - loaded)
    start_time      TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
    end_time        TIMESTAMP,
    status          VARCHAR2(20)    DEFAULT 'RUNNING',  -- RUNNING | SUCCESS | ERROR
    message         VARCHAR2(4000),               -- rule notes or error text
    CONSTRAINT pk_etl_audit_log PRIMARY KEY (log_id)
);

COMMENT ON TABLE etl_audit_log IS 'One row per ETL cleaning step. Written by autonomous transactions so log rows survive a rollback in the main procedure.';


-- ============================================================
-- Procedure p_log_start
-- Call this at the TOP of every cleaning procedure.
-- It inserts a RUNNING row and hands back its log_id.
-- ============================================================
CREATE OR REPLACE PROCEDURE p_log_start (
    p_step_name  IN  VARCHAR2,
    p_log_id     OUT NUMBER
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
    -- ^ This procedure has its OWN transaction separate from the caller.
    --   The COMMIT inside here does NOT commit the caller's work.
BEGIN
    INSERT INTO etl_audit_log (step_name, start_time, status)
    VALUES (p_step_name, SYSTIMESTAMP, 'RUNNING')
    RETURNING log_id INTO p_log_id;
    COMMIT;
    -- The row is now permanently visible in etl_audit_log even if the
    -- caller's transaction later rolls back.
END p_log_start;
/

SHOW ERRORS PROCEDURE p_log_start

-- ============================================================
-- Procedure p_log_end
-- Call this at the BOTTOM of every cleaning procedure (both
-- in the normal path and in the EXCEPTION handler).
-- It fills in the final status, row counts, and end time.
-- ============================================================
CREATE OR REPLACE PROCEDURE p_log_end (
    p_log_id        IN NUMBER,
    p_status        IN VARCHAR2,       -- 'SUCCESS' or 'ERROR'
    p_rows_read     IN NUMBER   DEFAULT NULL,
    p_rows_loaded   IN NUMBER   DEFAULT NULL,
    p_rows_rejected IN NUMBER   DEFAULT NULL,
    p_message       IN VARCHAR2 DEFAULT NULL
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    UPDATE etl_audit_log
    SET    status        = p_status,
           end_time      = SYSTIMESTAMP,
           rows_read     = p_rows_read,
           rows_loaded   = p_rows_loaded,
           rows_rejected = p_rows_rejected,
           message       = SUBSTR(p_message, 1, 4000)  -- guard against oversized messages
    WHERE  log_id = p_log_id;
    COMMIT;
END p_log_end;
/

SHOW ERRORS PROCEDURE p_log_end

