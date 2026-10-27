-- Apply after sql/create_tables.sql; existing table definitions are unchanged.
CREATE SCHEMA IF NOT EXISTS etl;

-- Validate before casting; malformed values abort the entire CALL.
CREATE OR REPLACE FUNCTION etl.clean_value(value text, source_id bigint, field_name text, kind text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    cleaned text := lower(btrim(value));
    number double precision;
BEGIN
    IF cleaned IS NULL OR cleaned IN ('', 'nan') THEN
        RETURN NULL;
    END IF;
    IF kind = 'boolean' THEN
        IF cleaned NOT IN ('0', '1', 'true', 'false') THEN
            RAISE EXCEPTION 'expected 0, 1, true or false';
        END IF;
    ELSIF kind = 'bigint' THEN
        IF cleaned !~ '^[+-]?[0-9]+$' THEN
            RAISE EXCEPTION 'expected an integer timestamp';
        END IF;
        PERFORM cleaned::bigint;
    ELSE
        number := cleaned::double precision;
        IF number IN ('Infinity'::double precision, '-Infinity'::double precision)
           OR number = 'NaN'::double precision THEN
            RAISE EXCEPTION 'expected a finite number';
        END IF;
        IF kind = 'timestamp' THEN
            PERFORM to_timestamp(number);
        END IF;
    END IF;
    RETURN cleaned;
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'raw_id %, column %, value %: %', source_id, field_name, value, SQLERRM
        USING ERRCODE = '22000';
END;
$$;

CREATE OR REPLACE PROCEDURE etl.run_pipeline()
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO processed.sessions (import_file_id)
    SELECT import_file_id FROM staging.import_files WHERE status = 'imported'
    ON CONFLICT (import_file_id) DO NOTHING;

    INSERT INTO processed.gaze_samples
        (session_id, raw_id, system_timestamp, device_timestamp, callback_timestamp)
    SELECT s.session_id, r.raw_id,
        etl.clean_value(r.system_time_stamp, r.raw_id, 'system_time_stamp', 'bigint')::bigint,
        etl.clean_value(r.device_time_stamp, r.raw_id, 'device_time_stamp', 'bigint')::bigint,
        to_timestamp(etl.clean_value(r.timestamp_utc, r.raw_id, 'timestamp_utc', 'timestamp')::double precision)
    FROM staging.raw_gaze_data r
    JOIN processed.sessions s USING (import_file_id)
    WHERE NOT EXISTS (SELECT 1 FROM processed.gaze_samples g WHERE g.raw_id = r.raw_id)
    ON CONFLICT (raw_id) DO NOTHING;

    INSERT INTO processed.eye_measurements
        (sample_id, eye, gaze_x, gaze_y, gaze_valid, pupil_diameter,
         pupil_valid, gaze_origin_valid, gaze_origin_x, gaze_origin_y, gaze_origin_z)
    SELECT g.sample_id, 'L',
            etl.clean_value(r.left_gaze_x, r.raw_id, 'left_gaze_x', 'double precision')::double precision,
            etl.clean_value(r.left_gaze_y, r.raw_id, 'left_gaze_y', 'double precision')::double precision,
            etl.clean_value(r.left_gaze_validity, r.raw_id, 'left_gaze_validity', 'boolean')::boolean,
            etl.clean_value(r.left_pupil_diameter, r.raw_id, 'left_pupil_diameter', 'double precision')::double precision,
            etl.clean_value(r.left_pupil_validity, r.raw_id, 'left_pupil_validity', 'boolean')::boolean,
            etl.clean_value(r.left_gaze_origin_validity, r.raw_id, 'left_gaze_origin_validity', 'boolean')::boolean,
            etl.clean_value(r.left_gaze_origin_x, r.raw_id, 'left_gaze_origin_x', 'double precision')::double precision,
            etl.clean_value(r.left_gaze_origin_y, r.raw_id, 'left_gaze_origin_y', 'double precision')::double precision,
            etl.clean_value(r.left_gaze_origin_z, r.raw_id, 'left_gaze_origin_z', 'double precision')::double precision
        FROM staging.raw_gaze_data r
        JOIN processed.gaze_samples g USING (raw_id)
        WHERE NOT EXISTS (
            SELECT 1 FROM processed.eye_measurements e
            WHERE e.sample_id = g.sample_id AND e.eye = 'L'
        )
    UNION ALL
    SELECT g.sample_id, 'R',
            etl.clean_value(r.right_gaze_x, r.raw_id, 'right_gaze_x', 'double precision')::double precision,
            etl.clean_value(r.right_gaze_y, r.raw_id, 'right_gaze_y', 'double precision')::double precision,
            etl.clean_value(r.right_gaze_validity, r.raw_id, 'right_gaze_validity', 'boolean')::boolean,
            etl.clean_value(r.right_pupil_diameter, r.raw_id, 'right_pupil_diameter', 'double precision')::double precision,
            etl.clean_value(r.right_pupil_validity, r.raw_id, 'right_pupil_validity', 'boolean')::boolean,
            etl.clean_value(r.right_gaze_origin_validity, r.raw_id, 'right_gaze_origin_validity', 'boolean')::boolean,
            etl.clean_value(r.right_gaze_origin_x, r.raw_id, 'right_gaze_origin_x', 'double precision')::double precision,
            etl.clean_value(r.right_gaze_origin_y, r.raw_id, 'right_gaze_origin_y', 'double precision')::double precision,
            etl.clean_value(r.right_gaze_origin_z, r.raw_id, 'right_gaze_origin_z', 'double precision')::double precision
        FROM staging.raw_gaze_data r
        JOIN processed.gaze_samples g USING (raw_id)
        WHERE NOT EXISTS (
            SELECT 1 FROM processed.eye_measurements e
            WHERE e.sample_id = g.sample_id AND e.eye = 'R'
        )
    ON CONFLICT (sample_id, eye) DO NOTHING;
END;
$$;
