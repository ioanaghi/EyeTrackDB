-- Fresh installations. Existing installations: sql/migrations/01_schema_integrity.sql.
BEGIN;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS processed;
CREATE SCHEMA IF NOT EXISTS etl;

-- STAGING: evidenta fisierelor CSV
CREATE TABLE IF NOT EXISTS staging.import_files (
    import_file_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    filename TEXT NOT NULL UNIQUE CONSTRAINT import_files_filename_nonempty CHECK (btrim(filename) <> ''),
    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    row_count INTEGER NOT NULL DEFAULT 0 CONSTRAINT import_files_row_count_nonnegative CHECK (row_count >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CONSTRAINT import_files_status_nonempty CHECK (btrim(status) <> '')
);

-- STAGING: date brute Tobii
CREATE TABLE IF NOT EXISTS staging.raw_gaze_data (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    import_file_id BIGINT NOT NULL
        REFERENCES staging.import_files(import_file_id),

    system_time_stamp TEXT,
    device_time_stamp TEXT,
    timestamp_utc TEXT,

    left_gaze_x TEXT,
    left_gaze_y TEXT,
    left_gaze_validity TEXT,
    left_pupil_diameter TEXT,
    left_pupil_validity TEXT,
    left_gaze_origin_validity TEXT,
    left_gaze_origin_x TEXT,
    left_gaze_origin_y TEXT,
    left_gaze_origin_z TEXT,

    right_gaze_x TEXT,
    right_gaze_y TEXT,
    right_gaze_validity TEXT,
    right_pupil_diameter TEXT,
    right_pupil_validity TEXT,
    right_gaze_origin_validity TEXT,
    right_gaze_origin_x TEXT,
    right_gaze_origin_y TEXT,
    right_gaze_origin_z TEXT
);

-- PROCESSED: dispozitive
CREATE TABLE IF NOT EXISTS processed.devices (
    device_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model TEXT NOT NULL CONSTRAINT devices_model_nonempty CHECK (btrim(model) <> ''),
    serial_number TEXT UNIQUE,
    sampling_rate_hz INTEGER CONSTRAINT devices_sampling_rate_positive CHECK (sampling_rate_hz > 0)
);

-- PROCESSED: participanti anonimi
CREATE TABLE IF NOT EXISTS processed.participants (
    participant_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    participant_code TEXT NOT NULL UNIQUE CONSTRAINT participants_code_nonempty CHECK (btrim(participant_code) <> '')
);

-- PROCESSED: activitati
CREATE TABLE IF NOT EXISTS processed.tasks (
    task_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    task_name TEXT NOT NULL UNIQUE CONSTRAINT tasks_name_nonempty CHECK (btrim(task_name) <> ''),
    description TEXT
);

-- PROCESSED: sesiuni
CREATE TABLE IF NOT EXISTS processed.sessions (
    session_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    import_file_id BIGINT NOT NULL UNIQUE
        REFERENCES staging.import_files(import_file_id),
    device_id BIGINT REFERENCES processed.devices(device_id),
    participant_id BIGINT REFERENCES processed.participants(participant_id),
    task_id BIGINT REFERENCES processed.tasks(task_id),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    CONSTRAINT sessions_time_order CHECK (ended_at >= started_at)
);

-- PROCESSED: esantioane
CREATE TABLE IF NOT EXISTS processed.gaze_samples (
    sample_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id BIGINT NOT NULL
        REFERENCES processed.sessions(session_id),
    raw_id BIGINT NOT NULL UNIQUE
        REFERENCES staging.raw_gaze_data(raw_id),
    system_timestamp BIGINT,
    device_timestamp BIGINT,
    callback_timestamp TIMESTAMPTZ
);

-- PROCESSED: masuratori separate pentru fiecare ochi
CREATE TABLE IF NOT EXISTS processed.eye_measurements (
    sample_id BIGINT NOT NULL
        REFERENCES processed.gaze_samples(sample_id),
    eye CHAR(1) NOT NULL CHECK (eye IN ('L', 'R')),
    gaze_x DOUBLE PRECISION,
    gaze_y DOUBLE PRECISION,
    gaze_valid BOOLEAN,
    pupil_diameter DOUBLE PRECISION,
    pupil_valid BOOLEAN,
    gaze_origin_valid BOOLEAN,
    gaze_origin_x DOUBLE PRECISION,
    gaze_origin_y DOUBLE PRECISION,
    gaze_origin_z DOUBLE PRECISION,
    PRIMARY KEY (sample_id, eye)
);

CREATE INDEX IF NOT EXISTS idx_gaze_session
    ON processed.gaze_samples(session_id);

COMMIT;
