\set ON_ERROR_STOP on

-- Run as a PostgreSQL superuser in eyetrackdb after installing pg_cron and
-- applying the ETL procedure and logging wrapper:
-- sql/03_etl_transform.sql, then sql/06_etl_logging.sql.
DO $$
DECLARE
    existing_job_id bigint;
BEGIN
    -- Replace this named job so repeated setup never accumulates duplicates.
    FOR existing_job_id IN
        SELECT jobid FROM cron.job WHERE jobname = 'eyetrackdb-daily-etl'
    LOOP
        PERFORM cron.unschedule(existing_job_id);
    END LOOP;

    PERFORM cron.schedule(
        'eyetrackdb-daily-etl',
        '0 2 * * *',
        'CALL etl.run_pipeline_logged()'
    );
END;
$$;

SELECT jobid, jobname, schedule, command, active, database, username
FROM cron.job
WHERE jobname = 'eyetrackdb-daily-etl';
