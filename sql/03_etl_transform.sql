-- Apply after sql/create_tables.sql; existing table definitions are unchanged.
CREATE SCHEMA IF NOT EXISTS etl;

CREATE OR REPLACE PROCEDURE etl.run_pipeline()
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO processed.sessions (import_file_id)
    SELECT import_file_id FROM staging.import_files WHERE status = 'imported';

    INSERT INTO processed.gaze_samples
        (session_id, raw_id, system_timestamp, device_timestamp, callback_timestamp)
    SELECT s.session_id, r.raw_id,
        NULLIF(NULLIF(lower(btrim(r.system_time_stamp)), 'nan'), '')::bigint,
        NULLIF(NULLIF(lower(btrim(r.device_time_stamp)), 'nan'), '')::bigint,
        to_timestamp(NULLIF(NULLIF(lower(btrim(r.timestamp_utc)), 'nan'), '')::double precision)
    FROM staging.raw_gaze_data r
    JOIN processed.sessions s USING (import_file_id);

    INSERT INTO processed.eye_measurements
        (sample_id, eye, gaze_x, gaze_y, gaze_valid, pupil_diameter,
         pupil_valid, gaze_origin_valid, gaze_origin_x, gaze_origin_y, gaze_origin_z)
    SELECT g.sample_id, 'L',
            NULLIF(NULLIF(lower(btrim(r.left_gaze_x)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.left_gaze_y)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.left_gaze_validity)), 'nan'), '')::boolean,
            NULLIF(NULLIF(lower(btrim(r.left_pupil_diameter)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.left_pupil_validity)), 'nan'), '')::boolean,
            NULLIF(NULLIF(lower(btrim(r.left_gaze_origin_validity)), 'nan'), '')::boolean,
            NULLIF(NULLIF(lower(btrim(r.left_gaze_origin_x)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.left_gaze_origin_y)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.left_gaze_origin_z)), 'nan'), '')::double precision
        FROM staging.raw_gaze_data r
        JOIN processed.gaze_samples g USING (raw_id)
    UNION ALL
    SELECT g.sample_id, 'R',
            NULLIF(NULLIF(lower(btrim(r.right_gaze_x)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.right_gaze_y)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.right_gaze_validity)), 'nan'), '')::boolean,
            NULLIF(NULLIF(lower(btrim(r.right_pupil_diameter)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.right_pupil_validity)), 'nan'), '')::boolean,
            NULLIF(NULLIF(lower(btrim(r.right_gaze_origin_validity)), 'nan'), '')::boolean,
            NULLIF(NULLIF(lower(btrim(r.right_gaze_origin_x)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.right_gaze_origin_y)), 'nan'), '')::double precision,
            NULLIF(NULLIF(lower(btrim(r.right_gaze_origin_z)), 'nan'), '')::double precision
        FROM staging.raw_gaze_data r
        JOIN processed.gaze_samples g USING (raw_id);
END;
$$;
