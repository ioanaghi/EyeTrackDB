\set ON_ERROR_STOP on
-- Upgrade original installations atomically. Invalid metadata aborts the migration.
BEGIN;
ALTER TABLE staging.import_files
    ALTER COLUMN imported_at SET NOT NULL,
    ALTER COLUMN row_count SET NOT NULL,
    ALTER COLUMN status SET NOT NULL;
DO $$
DECLARE rule record;
BEGIN
    FOR rule IN SELECT * FROM (VALUES
        ('staging.import_files', 'import_files_filename_nonempty', $c$btrim(filename) <> ''$c$),
        ('staging.import_files', 'import_files_row_count_nonnegative', 'row_count >= 0'),
        ('staging.import_files', 'import_files_status_nonempty', $c$btrim(status) <> ''$c$),
        ('processed.devices', 'devices_model_nonempty', $c$btrim(model) <> ''$c$),
        ('processed.devices', 'devices_sampling_rate_positive', 'sampling_rate_hz > 0'),
        ('processed.participants', 'participants_code_nonempty', $c$btrim(participant_code) <> ''$c$),
        ('processed.tasks', 'tasks_name_nonempty', $c$btrim(task_name) <> ''$c$),
        ('processed.sessions', 'sessions_time_order', 'ended_at >= started_at')
    ) AS rules(table_name, constraint_name, expression)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_constraint
                       WHERE conrelid = rule.table_name::regclass
                         AND conname = rule.constraint_name) THEN
            EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I CHECK (%s)',
                           rule.table_name, rule.constraint_name, rule.expression);
        END IF;
    END LOOP;
END;
$$;
COMMIT;
