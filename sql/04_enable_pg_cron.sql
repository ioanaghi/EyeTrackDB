\set ON_ERROR_STOP on

-- Run after starting PostgreSQL with pg_cron in shared_preload_libraries.
-- Compose sets POSTGRES_DB=eyetrackdb; pg_cron only manages jobs in this DB.
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
    IF current_database() <> current_setting('cron.database_name') THEN
        RAISE EXCEPTION 'pg_cron must be installed in cron.database_name (%), current database is %',
            current_setting('cron.database_name'), current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        RAISE EXCEPTION 'pg_cron extension was not installed in database %', current_database();
    END IF;
END;
$$;

SELECT current_database() AS extension_database, extname, extversion
FROM pg_extension
WHERE extname = 'pg_cron';
