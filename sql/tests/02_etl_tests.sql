\set ON_ERROR_STOP on
-- Run against the complete initial dataset after import and transformation.
-- All fixture changes are rolled back, including on assertion failure.
BEGIN;
DO $$
DECLARE
    before_counts bigint[];
    after_counts bigint[];
    source_column text;
    target_column text;
    side text;
    eye_code text;
    mismatch boolean;
    saw_missing boolean := false;
    fixture_file bigint;
    fixture_raw bigint;
    fixture_sample bigint;
BEGIN
    IF (SELECT count(*) FROM staging.import_files) <> 2
       OR (SELECT count(*) FROM staging.raw_gaze_data) <> 103870 THEN
        RAISE EXCEPTION 'Expected two source files and 103870 staging rows';
    END IF;
    IF EXISTS (
        SELECT 1 FROM staging.import_files f
        WHERE f.status <> 'imported' OR f.status IS NULL
           OR f.row_count IS DISTINCT FROM
              (SELECT count(*) FROM staging.raw_gaze_data r WHERE r.import_file_id = f.import_file_id)
    ) THEN
        RAISE EXCEPTION 'File status or recorded row count is incorrect';
    END IF;
    IF (SELECT count(*) FROM processed.sessions) <> 2
       OR (SELECT count(*) FROM processed.gaze_samples) <> 103870
       OR (SELECT count(*) FROM processed.eye_measurements) <> 207740 THEN
        RAISE EXCEPTION 'Processed counts do not match the complete staging dataset';
    END IF;
    IF EXISTS (
        SELECT g.sample_id FROM processed.gaze_samples g
        LEFT JOIN processed.eye_measurements e USING (sample_id)
        GROUP BY g.sample_id HAVING count(e.eye) <> 2
            OR count(*) FILTER (WHERE e.eye = 'L') <> 1
            OR count(*) FILTER (WHERE e.eye = 'R') <> 1
    ) THEN
        RAISE EXCEPTION 'Each sample must have one left and one right measurement';
    END IF;
    IF EXISTS (SELECT raw_id FROM processed.gaze_samples GROUP BY raw_id HAVING count(*) > 1)
       OR EXISTS (SELECT import_file_id FROM processed.sessions GROUP BY import_file_id HAVING count(*) > 1)
       OR EXISTS (SELECT sample_id, eye FROM processed.eye_measurements GROUP BY sample_id, eye HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'Duplicate processed source records';
    END IF;
    IF EXISTS (
        SELECT 1 FROM staging.raw_gaze_data r
        LEFT JOIN staging.import_files f USING (import_file_id)
        LEFT JOIN processed.gaze_samples g USING (raw_id)
        LEFT JOIN processed.sessions s ON s.session_id = g.session_id
        WHERE f.import_file_id IS NULL OR g.sample_id IS NULL
           OR s.import_file_id IS DISTINCT FROM r.import_file_id
    ) OR EXISTS (
        SELECT 1 FROM processed.gaze_samples g
        LEFT JOIN staging.raw_gaze_data r USING (raw_id)
        LEFT JOIN processed.sessions s USING (session_id)
        WHERE r.raw_id IS NULL OR s.session_id IS NULL
    ) OR EXISTS (
        SELECT 1 FROM processed.sessions s LEFT JOIN staging.import_files f USING (import_file_id)
        WHERE f.import_file_id IS NULL
    ) OR EXISTS (
        SELECT 1 FROM processed.eye_measurements e LEFT JOIN processed.gaze_samples g USING (sample_id)
        WHERE g.sample_id IS NULL
    ) THEN
        RAISE EXCEPTION 'Broken source traceability or referential integrity';
    END IF;

    -- Compare every source eye field, including missing values and validity.
    FOREACH side IN ARRAY ARRAY['left', 'right'] LOOP
        eye_code := CASE side WHEN 'left' THEN 'L' ELSE 'R' END;
        FOR source_column, target_column IN
            SELECT * FROM (VALUES
                ('gaze_x', 'gaze_x'), ('gaze_y', 'gaze_y'),
                ('pupil_diameter', 'pupil_diameter'),
                ('gaze_origin_x', 'gaze_origin_x'), ('gaze_origin_y', 'gaze_origin_y'),
                ('gaze_origin_z', 'gaze_origin_z'),
                ('gaze_validity', 'gaze_valid'), ('pupil_validity', 'pupil_valid'),
                ('gaze_origin_validity', 'gaze_origin_valid')
            ) AS columns(source_name, target_name)
        LOOP
            EXECUTE format(
                'SELECT EXISTS (SELECT 1 FROM staging.raw_gaze_data r
                 JOIN processed.gaze_samples g USING (raw_id)
                 JOIN processed.eye_measurements e USING (sample_id)
                 WHERE e.eye = %L AND e.%I IS DISTINCT FROM
                 NULLIF(NULLIF(lower(btrim(r.%I)), ''nan''), '''')::%s)',
                eye_code, target_column, side || '_' || source_column,
                CASE WHEN source_column LIKE '%%validity' THEN 'boolean' ELSE 'double precision' END
            ) INTO mismatch;
            IF mismatch THEN
                RAISE EXCEPTION 'Incorrect conversion of %.%', side, source_column;
            END IF;
        END LOOP;
    END LOOP;
    SELECT EXISTS (SELECT 1 FROM processed.eye_measurements WHERE gaze_x IS NULL)
    INTO saw_missing;
    IF NOT saw_missing THEN
        RAISE EXCEPTION 'Expected missing coordinates in initial data';
    END IF;
    IF EXISTS (
        SELECT 1 FROM processed.gaze_samples g JOIN staging.raw_gaze_data r USING (raw_id)
        WHERE g.system_timestamp IS DISTINCT FROM r.system_time_stamp::bigint
           OR g.device_timestamp IS DISTINCT FROM r.device_time_stamp::bigint
           OR g.callback_timestamp IS DISTINCT FROM to_timestamp(r.timestamp_utc::double precision)
    ) THEN
        RAISE EXCEPTION 'Incorrect timestamp conversion';
    END IF;

    before_counts := ARRAY[(SELECT count(*) FROM processed.sessions),
                           (SELECT count(*) FROM processed.gaze_samples),
                           (SELECT count(*) FROM processed.eye_measurements)];
    CALL etl.run_pipeline();
    CALL etl.run_pipeline();
    after_counts := ARRAY[(SELECT count(*) FROM processed.sessions),
                          (SELECT count(*) FROM processed.gaze_samples),
                          (SELECT count(*) FROM processed.eye_measurements)];
    IF before_counts IS DISTINCT FROM after_counts THEN
        RAISE EXCEPTION 'Repeated transformation changed counts';
    END IF;

    -- Synthetic source: missing fields, valid zeros, false validity and Unix seconds.
    INSERT INTO staging.import_files (filename, row_count, status)
    VALUES ('__etl_test_fixture__', 1, 'imported') RETURNING import_file_id INTO fixture_file;
    INSERT INTO staging.raw_gaze_data
        (import_file_id, system_time_stamp, device_time_stamp, timestamp_utc,
         left_gaze_x, left_gaze_y, left_gaze_validity, left_pupil_diameter,
         right_gaze_x, right_gaze_validity)
    VALUES (fixture_file, '0', '0', '0', '0', 'nan', '0', '', 'NaN', '1')
    RETURNING raw_id INTO fixture_raw;
    CALL etl.run_pipeline();
    SELECT sample_id INTO STRICT fixture_sample FROM processed.gaze_samples WHERE raw_id = fixture_raw;
    IF NOT EXISTS (
        SELECT 1 FROM processed.gaze_samples g
        JOIN processed.sessions s USING (session_id)
        JOIN processed.eye_measurements e USING (sample_id)
        WHERE g.sample_id = fixture_sample AND e.eye = 'L'
          AND g.system_timestamp = 0 AND g.device_timestamp = 0
          AND g.callback_timestamp = to_timestamp(0)
          AND s.device_id IS NULL AND s.participant_id IS NULL AND s.task_id IS NULL
          AND e.gaze_x = 0 AND e.gaze_y IS NULL AND e.pupil_diameter IS NULL
          AND e.gaze_valid = false
    ) THEN
        RAISE EXCEPTION 'Missing values, zero, validity or unknown metadata handled incorrectly';
    END IF;
    DELETE FROM processed.eye_measurements WHERE sample_id = fixture_sample AND eye = 'R';
    CALL etl.run_pipeline();
    IF NOT EXISTS (SELECT 1 FROM processed.eye_measurements
                   WHERE sample_id = fixture_sample AND eye = 'R'
                     AND gaze_x IS NULL AND gaze_valid = true) THEN
        RAISE EXCEPTION 'Missing right measurement was not restored';
    END IF;

    -- A new malformed source must reject the entire transformation without partial rows.
    INSERT INTO staging.raw_gaze_data (import_file_id, timestamp_utc)
    VALUES (fixture_file, 'not-a-timestamp') RETURNING raw_id INTO fixture_raw;
    BEGIN
        CALL etl.run_pipeline();
        RAISE EXCEPTION 'Malformed timestamp was accepted';
    EXCEPTION WHEN data_exception THEN
        IF position('raw_id ' || fixture_raw IN SQLERRM) = 0
           OR position('timestamp_utc' IN SQLERRM) = 0 THEN
            RAISE EXCEPTION 'Malformed timestamp error lacks source context';
        END IF;
    END;
    IF EXISTS (SELECT 1 FROM processed.gaze_samples WHERE raw_id = fixture_raw) THEN
        RAISE EXCEPTION 'Failed transformation left partial data';
    END IF;
    UPDATE staging.raw_gaze_data SET timestamp_utc = '0', right_gaze_x = 'broken'
    WHERE raw_id = fixture_raw;
    BEGIN
        CALL etl.run_pipeline();
        RAISE EXCEPTION 'Malformed eye measurement was accepted';
    EXCEPTION WHEN data_exception THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM processed.gaze_samples WHERE raw_id = fixture_raw) THEN
        RAISE EXCEPTION 'Eye validation failure left a partial sample';
    END IF;
    FOREACH source_column IN ARRAY ARRAY['Infinity', 'oops', '1e9999'] LOOP
        BEGIN
            PERFORM etl.clean_value(source_column, fixture_raw, 'gaze_x', 'double precision');
            RAISE EXCEPTION 'Malformed numeric value was accepted';
        EXCEPTION WHEN data_exception THEN NULL;
        END;
    END LOOP;
    BEGIN
        PERFORM etl.clean_value('2', fixture_raw, 'gaze_validity', 'boolean');
        RAISE EXCEPTION 'Unexpected validity was accepted';
    EXCEPTION WHEN data_exception THEN NULL;
    END;
    RAISE NOTICE 'All ETL tests passed (103870 samples, 207740 eye measurements).';
END;
$$;
ROLLBACK;
