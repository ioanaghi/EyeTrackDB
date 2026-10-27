\set ON_ERROR_STOP on

-- Run after sql/03_etl_transform.sql, sql/04_enable_pg_cron.sql,
-- sql/05_schedule_jobs.sql and sql/06_etl_logging.sql.
-- Synthetic staging data and execution logs are rolled back at the end.
BEGIN;

DO $$
DECLARE
    matching_jobs integer;
    history_rows bigint;
    scheduled_job_id bigint;
    latest_execution_id bigint;
    successful_file_id bigint;
    successful_raw_id bigint;
    failed_file_id bigint;
    failed_raw_id bigint;
    failure_status text;
    failure_detail text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        RAISE EXCEPTION 'pg_cron extension is not installed';
    END IF;
    IF current_database() <> 'eyetrackdb'
       OR current_setting('cron.database_name') <> current_database() THEN
        RAISE EXCEPTION 'pg_cron is not configured for the intended database';
    END IF;
    IF current_setting('cron.timezone') <> 'Europe/Bucharest' THEN
        RAISE EXCEPTION 'Expected cron.timezone Europe/Bucharest, got %',
            current_setting('cron.timezone');
    END IF;

    SELECT count(*), min(jobid)
    INTO matching_jobs, scheduled_job_id
    FROM cron.job
    WHERE jobname = 'eyetrackdb-daily-etl';
    IF matching_jobs <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one daily ETL job; found %', matching_jobs;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM cron.job
        WHERE jobid = scheduled_job_id
          AND schedule = '0 2 * * *'
          AND command = 'CALL etl.run_pipeline_logged()'
          AND active
          AND database = current_database()
    ) THEN
        RAISE EXCEPTION 'Daily ETL job schedule, command, database or active state is incorrect';
    END IF;
    IF to_regclass('cron.job_run_details') IS NULL THEN
        RAISE EXCEPTION 'pg_cron execution history relation is unavailable';
    END IF;
    SELECT count(*) INTO history_rows FROM cron.job_run_details;

    INSERT INTO staging.import_files (filename, row_count, status)
    VALUES ('__automation_success_' || txid_current(), 1, 'imported')
    RETURNING import_file_id INTO successful_file_id;
    INSERT INTO staging.raw_gaze_data
        (import_file_id, system_time_stamp, device_time_stamp, timestamp_utc)
    VALUES (successful_file_id, '0', '0', '0')
    RETURNING raw_id INTO successful_raw_id;

    -- This is the manual ETL integration check. The logger delegates to the
    -- existing etl.run_pipeline() procedure without changing its implementation.
    CALL etl.run_pipeline_logged();
    SELECT execution_id INTO STRICT latest_execution_id
    FROM etl.execution_logs
    WHERE pipeline_name = 'etl.run_pipeline'
    ORDER BY execution_id DESC
    LIMIT 1;
    IF NOT EXISTS (
        SELECT 1 FROM etl.execution_logs
        WHERE execution_id = latest_execution_id
          AND status = 'succeeded'
          AND ended_at IS NOT NULL
          AND processed_records >= 1
    ) THEN
        RAISE EXCEPTION 'Successful manual pipeline execution was not logged';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM processed.gaze_samples WHERE raw_id = successful_raw_id) THEN
        RAISE EXCEPTION 'Manual pipeline execution did not materialize the fixture';
    END IF;

    -- A malformed source should roll back pipeline writes but preserve a failed
    -- execution log entry with contextual error details.
    INSERT INTO staging.import_files (filename, row_count, status)
    VALUES ('__automation_failure_' || txid_current(), 1, 'imported')
    RETURNING import_file_id INTO failed_file_id;
    INSERT INTO staging.raw_gaze_data
        (import_file_id, system_time_stamp, device_time_stamp, timestamp_utc)
    VALUES (failed_file_id, '0', '0', 'not-a-timestamp')
    RETURNING raw_id INTO failed_raw_id;

    CALL etl.run_pipeline_logged();
    SELECT status, error_detail
    INTO STRICT failure_status, failure_detail
    FROM etl.execution_logs
    WHERE pipeline_name = 'etl.run_pipeline'
    ORDER BY execution_id DESC
    LIMIT 1;
    IF failure_status <> 'failed'
       OR failure_detail IS NULL
       OR position('raw_id ' || failed_raw_id IN failure_detail) = 0 THEN
        RAISE EXCEPTION 'Failure log is missing status or raw-row error context';
    END IF;
    IF EXISTS (SELECT 1 FROM processed.gaze_samples WHERE raw_id = failed_raw_id) THEN
        RAISE EXCEPTION 'Failed pipeline left a partial processed sample';
    END IF;

    RAISE NOTICE 'Automation tests passed; % scheduler-history rows visible. No scheduled run is claimed by this test.',
        history_rows;
END;
$$;

ROLLBACK;
