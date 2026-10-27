# ETL Pipeline — Georgiana

**Branch:** `feature/etl-pipeline`  
**Role:** ETL Developer  
**Project:** EyeTrackDB

## Objective

Implement a reliable and repeatable ETL pipeline that imports Tobii Pro Nano CSV recordings into PostgreSQL and transforms them into normalized relational data.

The pipeline must preserve raw records, validate measurements, and prevent duplicate imports.

## Input Dataset

The initial dataset consists of two CSV recordings containing 103,870 gaze samples in total.

Each CSV contains 21 columns, including:

- System and device timestamps.
- Callback timestamps (`timestamp_utc`, stored as Unix seconds).
- Left and right gaze coordinates.
- Gaze validity indicators.
- Pupil diameters and validity indicators.
- Gaze origin coordinates and validity indicators.

The local dataset is mounted inside the PostgreSQL container at `/data`.

Raw CSV files should not be committed without permission.

## Task 1 — CSV Import

Create `scripts/import_csv.py`.

The script must:

1. Connect to PostgreSQL using configurable connection parameters.
2. Discover CSV files in the configured data directory.
3. Validate the expected CSV headers.
4. Register each file in `staging.import_files`.
5. Import all 21 columns into `staging.raw_gaze_data`.
6. Preserve the original raw values.
7. Record the number of imported rows.
8. Handle missing files and malformed input.
9. Prevent duplicate imports.

Use a transaction per file so that a failed import does not leave a partially imported recording.

The existing `filename` unique constraint may be used for the initial version. Document that filename-only deduplication does not detect modified content under the same name.

## Task 2 — SQL Transformation

Create `sql/03_etl_transform.sql`.

Implement a PostgreSQL procedure:

```sql
CALL etl.run_pipeline();
```

The procedure must transform staged records into the processed schema.

### Session Creation

Create one `processed.sessions` record per imported CSV file.

Associate each session with its source `import_file_id`.

Do not invent participant, task, or device metadata. Leave optional metadata unknown until it is provided.

### Gaze Samples

Populate `processed.gaze_samples` with:

- Session identifier.
- Source raw record identifier.
- System timestamp.
- Device timestamp.
- Callback timestamp converted from Unix seconds.

Use `to_timestamp()` for Unix-second conversion.

### Eye Measurements

For each gaze sample, create two records in `processed.eye_measurements`:

- `L` — left eye.
- `R` — right eye.

Transform gaze coordinates, pupil measurements, origin coordinates, and validity indicators into the correct SQL data types.

## Task 3 — Data Cleaning

Implement the following rules:

- Convert `nan` and empty numeric values to SQL `NULL`.
- Preserve original validity indicators.
- Do not replace missing coordinates with zero.
- Do not silently discard invalid eye measurements.
- Reject or log malformed timestamps and unexpected values.
- Preserve source-to-processed traceability using `raw_id`.

The ETL should distinguish missing measurements from valid numeric zero values.

## Task 4 — Idempotency

The ETL must be safe to execute multiple times.

Running:

```sql
CALL etl.run_pipeline();
CALL etl.run_pipeline();
```

must not create duplicate sessions, gaze samples, or eye measurements.

Use appropriate uniqueness constraints and conflict handling.

## Task 5 — Testing

Create `sql/tests/02_etl_tests.sql`.

Test the following conditions:

1. The initial staging dataset contains 103,870 records.
2. Processed gaze samples match the staged sample count.
3. Each gaze sample has exactly two eye measurement records.
4. No duplicate source records exist in processed data.
5. Missing numeric measurements are represented as `NULL`.
6. Referential integrity is maintained.
7. Re-running the ETL does not increase the number of processed records.

For the complete initial dataset, expected results are:

| Table | Expected rows |
|---|---:|
| `staging.import_files` | 2 |
| `staging.raw_gaze_data` | 103,870 |
| `processed.sessions` | 2 |
| `processed.gaze_samples` | 103,870 |
| `processed.eye_measurements` | 207,740 |

These counts apply when both source files have been imported once and the complete ETL has succeeded.

## Files to Deliver

```text
scripts/
  import_csv.py

sql/
  03_etl_transform.sql
  tests/
    02_etl_tests.sql

docs/
  etl-pipeline.md
```

## Acceptance Criteria

- [x] Both CSV files import successfully.
- [x] All original records are preserved in staging.
- [x] Invalid numeric measurements are handled correctly.
- [x] Session and eye measurement relationships are correct.
- [x] `etl.run_pipeline()` is implemented.
- [x] Repeated imports and transformations do not create duplicates.
- [x] SQL tests pass.
- [x] Import and transformation instructions are documented.

## Git Commands

```bash
git switch feature/etl-pipeline
git add scripts/import_csv.py sql/03_etl_transform.sql sql/tests/02_etl_tests.sql docs/etl-pipeline.md
git commit -m "feat(etl): implement CSV ingestion, transformations and validation tests"
git push origin feature/etl-pipeline
```

Create a Pull Request targeting `main`.

Do not modify the existing table definitions without coordinating with the database architect.

## Running the implementation

### Task 1 — Import

Create the schemas and tables using the README setup instructions first.
Run the importer on the host, where the container's `/data` mount is `./data`:

```bash
python3 -m venv .venv
.venv/bin/pip install 'psycopg[binary]>=3,<4'
export PGHOST=127.0.0.1 PGPORT=5433 PGDATABASE=eyetrackdb PGUSER=eyetrack
read -s PGPASSWORD
export PGPASSWORD
.venv/bin/python scripts/import_csv.py --data-dir ./data
```

`--dsn` or `DATABASE_URL` can also configure the connection; `DATA_DIR`
sets the default source directory. Each file is registered and copied in one
transaction. Failed files are rolled back, other files continue, and any failure
returns a nonzero exit code. Empty files, wrong headers, malformed CSV and wrong
field counts are rejected. Numeric strings, including empty strings and `nan`,
are preserved verbatim for transformation.

Deduplication uses the unique filename. Modified content with the same filename
is skipped too; filename-only deduplication does not detect content changes.
Existing registrations are skipped rather than overwritten.

### Task 2 — Transformation

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb -f /sql/03_etl_transform.sql
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb -c 'CALL etl.run_pipeline();'
```

Each imported file produces one session, each raw row one gaze sample, and each
sample two eye measurements. Optional session metadata remains unknown (`NULL`).
Callback timestamps use `to_timestamp()` on Unix seconds; source links use `raw_id`.

### Task 3 — Cleaning

Empty numeric fields and case-insensitive `nan` become `NULL`, while zero remains
zero. Validity accepts `0`/`1` and `false`/`true`; missing validity remains unknown.
Invalid measurements are retained even when their validity indicator is false.
Malformed integers, timestamps, booleans, nonnumeric values and infinities reject
the whole transformation atomically, with an error identifying `raw_id`, column
and original value. Staging values remain unchanged for investigation.

### Task 4 — Repeatable execution

Re-run the importer and `CALL etl.run_pipeline();` as needed. The existing unique
constraints on filename, session source file, sample raw source and `(sample_id,
eye)` enforce deduplication. Inserts use explicit conflict targets; already
processed samples and eye measurements are skipped. Missing eye records can be
filled on a later run. Existing processed values are not overwritten.

### Task 5 — Validation

After importing both files and running the transformation:

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb -f /sql/tests/02_etl_tests.sql
```

The suite requires the complete initial dataset. It checks exact counts, source
links, duplicate prevention, both eyes, timestamp conversion, all measurement and
validity conversions, missing values, numeric zero, repeat execution, missing-eye
recovery and atomic rejection of malformed timestamps and measurements. Synthetic
fixtures run in a transaction that is rolled back; failure stops `psql` with a
nonzero exit code. Run this suite without concurrent imports or transformations.

Verified locally on PostgreSQL 16 with the two original CSV files: 2 imported
files, 103,870 staging rows, 2 sessions, 103,870 gaze samples and 207,740 eye
measurements. Every raw field was compared against the source CSV values.
Repeated imports were skipped, and malformed headers, empty files, incorrect
field counts and broken CSV quoting left no partial registrations or raw rows.
Missing directories produced a nonzero exit code. The SQL suite passed.
The configured Docker PostgreSQL 17 instance was unavailable during verification
because Docker was not running; the commands above run the same suite there.

Delivery uses one commit and push per task on `feature/etl-pipeline`. A single
Pull Request targets `main` after all five tasks; no push or merge to `main`.
