\set ON_ERROR_STOP on
-- psql -v ON_ERROR_STOP=1 ... < sql/tests/01_schema_tests.sql
-- Fixture rows roll back; identity sequences may advance, as in normal PostgreSQL use.
BEGIN;
CREATE FUNCTION pg_temp.expect_error(statement text, expected_state text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual_state text;
BEGIN
    BEGIN
        EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS actual_state = RETURNED_SQLSTATE;
        IF actual_state = expected_state THEN RETURN; END IF;
        RAISE EXCEPTION 'Expected SQLSTATE %, got % for %: %',
            expected_state, actual_state, statement, SQLERRM;
    END;
    RAISE EXCEPTION 'Expected SQLSTATE %, but statement succeeded: %', expected_state, statement;
END;
$$;
DO $$
DECLARE
    item record;
    relation regclass;
    actual text[];
    file_id bigint;
    raw_key bigint;
    session_key bigint;
    sample_key bigint;
    device_key bigint;
    participant_key bigint;
    task_key bigint;
    fixture_name text := '__schema_test_' || pg_backend_pid() || '_' || txid_current();
BEGIN
    -- Assert exact primary key columns, including the composite eye key.
    FOR item IN SELECT * FROM (VALUES
        ('staging.import_files', ARRAY['import_file_id']),
        ('staging.raw_gaze_data', ARRAY['raw_id']),
        ('processed.devices', ARRAY['device_id']),
        ('processed.participants', ARRAY['participant_id']),
        ('processed.tasks', ARRAY['task_id']),
        ('processed.sessions', ARRAY['session_id']),
        ('processed.gaze_samples', ARRAY['sample_id']),
        ('processed.eye_measurements', ARRAY['sample_id', 'eye'])
    ) AS required(table_name, key_columns)
    LOOP
        relation := to_regclass(item.table_name);
        IF relation IS NULL OR NOT EXISTS (
            SELECT 1 FROM pg_class WHERE oid = relation AND relkind = 'r'
        ) THEN RAISE EXCEPTION 'Missing table %', item.table_name; END IF;
        SELECT array_agg(a.attname::text ORDER BY k.ordinality) INTO actual
        FROM pg_constraint c
        CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY k(attnum, ordinality)
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
        WHERE c.conrelid = relation AND c.contype = 'p';
        IF actual IS DISTINCT FROM item.key_columns THEN
            RAISE EXCEPTION 'Wrong/missing PK on %: %', item.table_name, actual;
        END IF;
    END LOOP;

    -- Check every FK's child column, parent table and parent column, and validation.
    FOR item IN SELECT * FROM (VALUES
        ('staging.raw_gaze_data', 'import_file_id', 'staging.import_files', 'import_file_id'),
        ('processed.sessions', 'import_file_id', 'staging.import_files', 'import_file_id'),
        ('processed.sessions', 'device_id', 'processed.devices', 'device_id'),
        ('processed.sessions', 'participant_id', 'processed.participants', 'participant_id'),
        ('processed.sessions', 'task_id', 'processed.tasks', 'task_id'),
        ('processed.gaze_samples', 'session_id', 'processed.sessions', 'session_id'),
        ('processed.gaze_samples', 'raw_id', 'staging.raw_gaze_data', 'raw_id'),
        ('processed.eye_measurements', 'sample_id', 'processed.gaze_samples', 'sample_id')
    ) AS required(child_table, child_column, parent_table, parent_column)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint c
            JOIN pg_attribute child ON child.attrelid = c.conrelid AND child.attname = item.child_column
            JOIN pg_attribute parent ON parent.attrelid = c.confrelid AND parent.attname = item.parent_column
            WHERE c.contype = 'f' AND c.convalidated
              AND c.conrelid = item.child_table::regclass
              AND c.confrelid = item.parent_table::regclass
              AND c.conkey = ARRAY[child.attnum] AND c.confkey = ARRAY[parent.attnum]
        ) THEN RAISE EXCEPTION 'Missing/wrong FK: % (%) -> % (%)',
            item.child_table, item.child_column, item.parent_table, item.parent_column; END IF;
    END LOOP;

    INSERT INTO staging.import_files(filename) VALUES (fixture_name) RETURNING import_file_id INTO file_id;
    INSERT INTO staging.raw_gaze_data(import_file_id) VALUES (file_id) RETURNING raw_id INTO raw_key;
    INSERT INTO processed.sessions(import_file_id) VALUES (file_id) RETURNING session_id INTO session_key;
    IF NOT EXISTS (SELECT 1 FROM processed.sessions WHERE session_id = session_key
        AND participant_id IS NULL AND device_id IS NULL AND task_id IS NULL
        AND started_at IS NULL AND ended_at IS NULL) THEN
        RAISE EXCEPTION 'Uncollected session metadata must remain optional';
    END IF;
    INSERT INTO processed.gaze_samples(session_id, raw_id) VALUES (session_key, raw_key)
        RETURNING sample_id INTO sample_key;
    INSERT INTO processed.eye_measurements(sample_id, eye) VALUES (sample_key, 'L'), (sample_key, 'R');
    PERFORM pg_temp.expect_error(format('INSERT INTO processed.eye_measurements(sample_id, eye) VALUES (%s, %L)', sample_key, 'X'), '23514');
    PERFORM pg_temp.expect_error(format('INSERT INTO processed.eye_measurements(sample_id, eye) VALUES (%s, %L)', sample_key, 'L'), '23505');
    PERFORM pg_temp.expect_error(format('INSERT INTO processed.eye_measurements(sample_id, eye) VALUES (%s, NULL)', sample_key), '23502');

    -- All eight FK paths reject an absent parent. Each probe rolls back in a subtransaction.
    FOR item IN SELECT * FROM (VALUES
        ('staging.raw_gaze_data', 'import_file_id', 'staging.import_files', 'import_file_id'),
        ('processed.sessions', 'import_file_id', 'staging.import_files', 'import_file_id'),
        ('processed.sessions', 'device_id', 'processed.devices', 'device_id'),
        ('processed.sessions', 'participant_id', 'processed.participants', 'participant_id'),
        ('processed.sessions', 'task_id', 'processed.tasks', 'task_id'),
        ('processed.gaze_samples', 'session_id', 'processed.sessions', 'session_id'),
        ('processed.gaze_samples', 'raw_id', 'staging.raw_gaze_data', 'raw_id'),
        ('processed.eye_measurements', 'sample_id', 'processed.gaze_samples', 'sample_id')
    ) AS required(child_table, child_column, parent_table, parent_column)
    LOOP
        EXECUTE format('SELECT ARRAY[(coalesce(min(%I), 0) - 1)::text] FROM %s',
                       item.parent_column, item.parent_table) INTO actual;
        IF item.child_table = 'staging.raw_gaze_data' THEN
            PERFORM pg_temp.expect_error(format('UPDATE staging.raw_gaze_data SET %I = %s WHERE raw_id = %s', item.child_column, actual[1], raw_key), '23503');
        ELSIF item.child_table = 'processed.sessions' THEN
            PERFORM pg_temp.expect_error(format('UPDATE processed.sessions SET %I = %s WHERE session_id = %s', item.child_column, actual[1], session_key), '23503');
        ELSIF item.child_table = 'processed.gaze_samples' THEN
            PERFORM pg_temp.expect_error(format('UPDATE processed.gaze_samples SET %I = %s WHERE sample_id = %s', item.child_column, actual[1], sample_key), '23503');
        ELSE
            PERFORM pg_temp.expect_error(format('INSERT INTO processed.eye_measurements(sample_id, eye) VALUES (%s, %L)', actual[1], 'L'), '23503');
        END IF;
    END LOOP;
    -- Direct orphan insertion, in addition to testing FK enforcement on updates.
    PERFORM pg_temp.expect_error('INSERT INTO staging.raw_gaze_data(import_file_id) SELECT coalesce(min(import_file_id), 0) - 1 FROM staging.import_files', '23503');
    PERFORM pg_temp.expect_error(format('DELETE FROM staging.import_files WHERE import_file_id = %s', file_id), '23503');

    -- Deduplication keys used by ingestion and ON CONFLICT transformations.
    PERFORM pg_temp.expect_error(format('INSERT INTO staging.import_files(filename) VALUES (%L)', fixture_name), '23505');
    PERFORM pg_temp.expect_error(format('INSERT INTO processed.sessions(import_file_id) VALUES (%s)', file_id), '23505');
    PERFORM pg_temp.expect_error(format('INSERT INTO processed.gaze_samples(session_id, raw_id) VALUES (%s, %s)', session_key, raw_key), '23505');
    INSERT INTO processed.devices(model, serial_number) VALUES ('schema-test', fixture_name) RETURNING device_id INTO device_key;
    INSERT INTO processed.participants(participant_code) VALUES (fixture_name) RETURNING participant_id INTO participant_key;
    INSERT INTO processed.tasks(task_name) VALUES (fixture_name) RETURNING task_id INTO task_key;
    PERFORM pg_temp.expect_error(format('INSERT INTO processed.devices(model, serial_number) VALUES (%L, %L)', 'schema-test', fixture_name), '23505');
    PERFORM pg_temp.expect_error(format('INSERT INTO processed.participants(participant_code) VALUES (%L)', fixture_name), '23505');
    PERFORM pg_temp.expect_error(format('INSERT INTO processed.tasks(task_name) VALUES (%L)', fixture_name), '23505');

    -- Review additions: invalid metadata rejected; unknown metadata remains valid.
    PERFORM pg_temp.expect_error(format('UPDATE staging.import_files SET row_count = -1 WHERE import_file_id = %s', file_id), '23514');
    FOREACH actual SLICE 1 IN ARRAY ARRAY[
        ARRAY['filename', '23514'], ARRAY['status', '23514']
    ] LOOP
        PERFORM pg_temp.expect_error(format('UPDATE staging.import_files SET %I = %L WHERE import_file_id = %s', actual[1], ' ', file_id), actual[2]);
    END LOOP;
    FOR item IN SELECT unnest(ARRAY['filename', 'imported_at', 'row_count', 'status']) AS column_name LOOP
        PERFORM pg_temp.expect_error(format('UPDATE staging.import_files SET %I = NULL WHERE import_file_id = %s', item.column_name, file_id), '23502');
    END LOOP;
    PERFORM pg_temp.expect_error(format('UPDATE processed.devices SET sampling_rate_hz = 0 WHERE device_id = %s', device_key), '23514');
    PERFORM pg_temp.expect_error(format('UPDATE processed.devices SET model = %L WHERE device_id = %s', '', device_key), '23514');
    PERFORM pg_temp.expect_error(format('UPDATE processed.participants SET participant_code = %L WHERE participant_id = %s', '', participant_key), '23514');
    PERFORM pg_temp.expect_error(format('UPDATE processed.tasks SET task_name = %L WHERE task_id = %s', '', task_key), '23514');
    PERFORM pg_temp.expect_error(format('UPDATE processed.sessions SET started_at = %L, ended_at = %L WHERE session_id = %s', '2026-10-27 10:00:00+00', '2026-10-27 09:00:00+00', session_key), '23514');
    RAISE NOTICE 'All schema tests passed: eight tables, exact PKs/FKs, optional metadata and integrity constraints.';
END;
$$;
ROLLBACK;
