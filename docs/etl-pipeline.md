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

- [ ] Both CSV files import successfully.
- [ ] All original records are preserved in staging.
- [ ] Invalid numeric measurements are handled correctly.
- [ ] Session and eye measurement relationships are correct.
- [ ] `etl.run_pipeline()` is implemented.
- [ ] Repeated imports and transformations do not create duplicates.
- [ ] SQL tests pass.
- [ ] Import and transformation instructions are documented.

## Git Commands

```bash
git switch feature/etl-pipeline
git add scripts/import_csv.py sql/03_etl_transform.sql sql/tests/02_etl_tests.sql docs/etl-pipeline.md
git commit -m "feat(etl): implement CSV ingestion, transformations and validation tests"
git push origin feature/etl-pipeline
```

Create a Pull Request targeting `main`.

Do not modify the existing table definitions without coordinating with the database architect.