\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS etl;

CREATE TABLE IF NOT EXISTS etl.execution_logs (
    execution_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pipeline_name text NOT NULL,
    started_at timestamptz NOT NULL,
    ended_at timestamptz,
    status text NOT NULL CHECK (status IN ('running', 'succeeded', 'failed')),
    processed_records bigint CHECK (processed_records IS NULL OR processed_records >= 0),
    error_detail text,
    CHECK ((status = 'running' AND ended_at IS NULL)
        OR (status IN ('succeeded', 'failed') AND ended_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS execution_logs_started_at_idx
    ON etl.execution_logs (started_at DESC);

-- Keep etl.run_pipeline() owned by the ETL implementation. This wrapper records
-- its outcome and leaves processed_records NULL if the ETL call fails.
CREATE OR REPLACE PROCEDURE etl.run_pipeline_logged()
LANGUAGE plpgsql
AS $$
DECLARE
    current_execution_id bigint;
    samples_before bigint;
    samples_after bigint;
    error_message text;
    error_detail_text text;
    error_hint text;
    error_state text;
BEGIN
    INSERT INTO etl.execution_logs (pipeline_name, started_at, status)
    VALUES ('etl.run_pipeline', clock_timestamp(), 'running')
    RETURNING execution_id INTO current_execution_id;

    BEGIN
        SELECT count(*) INTO samples_before FROM processed.gaze_samples;
        CALL etl.run_pipeline();
        SELECT count(*) INTO samples_after FROM processed.gaze_samples;

        UPDATE etl.execution_logs
        SET ended_at = clock_timestamp(),
            status = 'succeeded',
            processed_records = samples_after - samples_before
        WHERE execution_id = current_execution_id;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            error_message = MESSAGE_TEXT,
            error_detail_text = PG_EXCEPTION_DETAIL,
            error_hint = PG_EXCEPTION_HINT,
            error_state = RETURNED_SQLSTATE;

        -- The exception block rolls back the pipeline's partial work; this log
        -- row was inserted outside that subtransaction and can record the error.
        UPDATE etl.execution_logs
        SET ended_at = clock_timestamp(),
            status = 'failed',
            error_detail = concat_ws(E'\n',
                format('SQLSTATE %s: %s', error_state, error_message),
                NULLIF(error_detail_text, ''),
                CASE WHEN error_hint IS NULL OR error_hint = ''
                    THEN NULL ELSE 'HINT: ' || error_hint END)
        WHERE execution_id = current_execution_id;

        RAISE WARNING 'ETL execution % failed: % (SQLSTATE %)',
            current_execution_id, error_message, error_state;
    END;
END;
$$;
