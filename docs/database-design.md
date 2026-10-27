# Database Design — Ioana

**Branch:** `feature/database-design`  
**Role:** Database Architect and Integration Lead  
**Project:** EyeTrackDB

## Objective

Design, document, and validate the PostgreSQL relational database used to store and process Tobii Pro Nano eye-tracking data.

The database must support raw data preservation, normalized storage, referential integrity, and reliable ETL execution.

## Current Implementation

The following components have already been created:

- PostgreSQL 17 running in Docker.
- Database `eyetrackdb`.
- Schemas `staging`, `processed`, and `etl`.
- Two staging tables and six processed tables.
- Primary keys, foreign keys, and basic constraints.

Existing file: `sql/create_tables.sql`.

## Task 1 — Database Schema Review

Review all existing tables and relationships.

Verify that:

- Every table has a primary key.
- Foreign keys reference the correct parent tables.
- Data types are appropriate.
- Required fields have `NOT NULL` constraints.
- Unique constraints prevent unintended duplicates.
- Invalid values cannot violate data integrity.
- Session metadata is optional when it was not collected.

Document any required schema changes before modifying tables used by the ETL pipeline.

## Task 2 — Entity-Relationship Diagram

Create an ER diagram containing:

- `staging.import_files`
- `staging.raw_gaze_data`
- `processed.devices`
- `processed.participants`
- `processed.tasks`
- `processed.sessions`
- `processed.gaze_samples`
- `processed.eye_measurements`

Show:

- Primary keys.
- Foreign keys.
- One-to-many and one-to-one relationships where applicable.
- Optional relationships.
- Cardinality constraints.

Deliverable: `docs/er-diagram.png` or a source-based diagram such as `docs/er-diagram.mmd`.

## Task 3 — Database Normalization

Write an explanation of normalization from 1NF to 3NF.

### First Normal Form

Explain how the raw CSV contains separate columns for the left and right eyes, and how the processed schema represents individual eye measurements as rows.

### Second Normal Form

Explain functional dependencies and demonstrate that non-key attributes depend on their entire candidate key.

### Third Normal Form

Explain how participant, device, task, and session information is separated to avoid transitive dependencies and redundant metadata.

Include examples of insertion, update, and deletion anomalies prevented by the design.

## Task 4 — SQL Integrity Tests

Create `sql/tests/01_schema_tests.sql`.

Tests must verify:

1. All required tables exist.
2. Primary keys are defined.
3. Foreign keys are defined.
4. Invalid eye values are rejected.
5. Duplicate measurements for the same sample and eye are rejected.
6. Orphan records cannot be inserted.

Use transactions and rollbacks for tests that intentionally trigger constraint violations.

## Task 5 — Integration

Review the Pull Requests from Georgiana and Luca.

After merging:

- Start the complete Docker environment.
- Execute the ETL pipeline.
- Verify sample counts.
- Verify job scheduling.
- Verify execution logs.
- Test repeated execution without duplicates.
- Update the main README with final setup instructions.

## Files to Deliver

```text
docs/
  database-design.md
  er-diagram.mmd

sql/
  create_tables.sql
  tests/
    01_schema_tests.sql
```

## Acceptance Criteria

- [ ] ER diagram matches the implemented database.
- [ ] Normalization to 3NF is explained and justified.
- [ ] Primary and foreign key constraints are validated.
- [ ] Schema tests execute successfully.
- [ ] ETL and automation changes are integrated.
- [ ] Final Docker setup works on a clean environment.
- [ ] Main README reflects the final implementation.

## Git Commands

```bash
git switch feature/database-design
git add docs/database-design.md docs/er-diagram.mmd sql/tests/01_schema_tests.sql
git commit -m "docs(db): document schema, ER diagram and 3NF normalization"
git push origin feature/database-design
```

Create a Pull Request targeting `main` after testing.

## Task 1 review and schema change plan (2026-10-27)

The original eight tables have primary keys. All eight foreign keys reference the
correct parent primary key: raw rows to files; sessions to files and optional
devices/participants/tasks; samples to sessions and raw rows; eyes to samples.
The default NO ACTION deletion policy preserves provenance by rejecting deletion
of referenced parents. Identity BIGINT keys leave ample room for recordings.

Raw values deliberately remain nullable TEXT, including malformed numbers. The
staging boundary preserves the CSV rather than imposing processed validation.
Processed timestamps use BIGINT for device/system counters and TIMESTAMPTZ for
Unix-second callback time converted by ETL. DOUBLE PRECISION and nullable BOOLEAN
represent numeric measurements and validity without replacing missing values by
zero. Screen coordinates may lie outside [0,1]; no range constraint is assumed.
Invalid validity flags and non-finite numbers are rejected by ETL before casting.

Existing uniqueness is intentional: filename, non-null device serial number,
participant code, task name, session import_file_id, sample raw_id, and the
(sample_id, eye) primary key. A NULL serial number is unknown, so multiple devices
may lack one. Filename-only deduplication cannot detect renamed copies or changed
content under an existing filename. Identical raw rows can be legitimate samples;
no uniqueness is imposed on their values or timestamps.

Changes specified before modifying the running schema:

- Require import timestamp, row count and status; reject negative row counts and
  blank filenames/statuses. Keep status vocabulary open for ETL/automation.
- Reject blank device models, participant codes and task names; require positive
  sampling rates when provided.
- Reject session end times earlier than start times when both are known.
- Preserve nullable session participant_id, device_id, task_id, started_at and
  ended_at; never manufacture uncollected metadata.
- Keep the existing L/R CHECK and composite eye primary key. They allow zero to
  two measurements per sample; exactly two is an ETL postcondition, not a FK rule.

`sql/create_tables.sql` installs the reviewed schema on a fresh database, including
all three schemas in one transaction. `sql/migrations/01_schema_integrity.sql`
applies the same additional constraints to the original schema atomically and
can be re-run. It does not silently repair invalid metadata: existing violations
abort the migration and require investigation. CREATE TABLE IF NOT EXISTS alone
cannot upgrade existing tables. No ETL column, key, conflict target or procedure
interface changes. Referencing FK indexes beyond idx_gaze_session can be added
after measuring query/deletion workloads.

Cross-table consistency between a sample's session file and raw row's file is
verified by integration tests; the two independent FKs alone do not enforce this
business rule. Raw data and processed identifiers must be treated as immutable
by the ETL interface. Stronger cross-table enforcement would require coordinated
schema/procedure changes and is not claimed here.


## Task 2 — Implemented ER diagram

The source diagram is [er-diagram.mmd](er-diagram.mmd). Open it with a Mermaid
renderer. Entity names use underscores in place of schema dots for portability;
`staging_import_files` denotes `staging.import_files`, for example.

All eight tables and every implemented column are shown, with PK, FK and UK
markers. `||` means exactly one, `o|` zero or one, and `o{` zero or many.
Each raw row belongs to one file. A file may have no processed session yet, or
one session because import_file_id is unique. Each sample belongs to one session
and one raw row; a raw row may have no sample yet or one because raw_id is unique.
An optional device, participant or task may serve many sessions. Samples may have
zero, one or two eye rows during loading; L/R and the composite primary key cap
this relationship at two. ETL completion requires both eyes. No database CHECK
requires two children, so the diagram explicitly distinguishes that postcondition.

## Task 3 — Normalization from 1NF to 3NF

### First normal form (1NF)

Each column stores one scalar value and each row has a key. The source CSV uses
separate left_* and right_* columns. This wide scalar layout need not formally
violate 1NF, but repeats the same measurement structure for two eyes. Staging
retains that representation for source fidelity. The processed representation
unifies it as rows keyed by (sample_id, eye): a CSV sample with left_gaze_x=0.25
and right_gaze_x=0.30 becomes (sample, L, 0.25) and (sample, R, 0.30).
There are no lists of eye values in a cell. All other eye properties follow the
same mapping. Unknown measurements remain SQL NULL; false validity and numeric
zero remain meaningful scalar values.

### Second normal form (2NF)

A relation in 1NF is in 2NF when every non-prime attribute depends on the whole
of each candidate key, with no dependency on a proper subset. In eye_measurements,
(sample_id, eye) determines gaze_x, gaze_y, gaze_valid, pupil_diameter, pupil_valid,
gaze_origin_valid and all three gaze origin coordinates. sample_id alone cannot
determine them because left and right may differ; eye alone cannot determine
them because recordings contain many samples. Session identifiers and shared
timestamps belong to gaze_samples because they depend on the sample alone.

All other relations have single-column candidate keys, so partial dependencies
cannot arise. The functional dependencies under the current business rules are:

- import_files: import_file_id or filename -> imported_at, row_count, status
  and the remaining identifier.
- raw_gaze_data: raw_id -> import_file_id and the 21 raw values. Timestamp
  values are not assumed unique.
- devices: device_id -> model, serial_number, sampling_rate_hz.
- participants: participant_id or participant_code -> the other identifier.
- tasks: task_id or task_name -> description and the other identifier.
- sessions: session_id or import_file_id -> device_id, participant_id, task_id,
  started_at, ended_at and the other identifier.
- gaze_samples: sample_id or raw_id -> session_id, system_timestamp,
  device_timestamp, callback_timestamp and the other identifier.

Nullable serial_number is a conditional identifier when known, not a formal
candidate key across all rows: PostgreSQL permits multiple NULLs in a UNIQUE
column. It cannot be used to identify an unknown device. These dependencies
assume a device row describes one configured sampling rate; historical changes
would require separate configuration/version records if that becomes a need.

### Third normal form (3NF)

For the stated dependencies, each determinant of a nontrivial dependency is a
candidate key (or the dependent attribute is prime). Non-key attributes do not
determine other non-key attributes inside a relation. A session stores foreign
keys rather than participant codes, device model/serial/rate or task names and
descriptions. That metadata resides in its own parent relation, preventing a
session -> device -> model dependency within the sessions table. Samples store
session_id without duplicating session dates or participant details. Eye rows
store sample_id without duplicating sample timestamps. This separation avoids
transitive dependencies and repeated metadata across thousands of samples.

Insertion anomaly prevented: a device or task can be registered before any
recording exists, without inventing a sample or participant. A recording can
also be loaded when participant/device/task information was not collected,
because those session references are optional.

Update anomaly prevented: changing a task description updates one tasks row,
rather than each session or every eye measurement. All referencing sessions see
the same metadata. Per-session dates remain on the session, so a correction is
not repeated across its samples.

Deletion anomaly prevented: removing an unreferenced task does not remove
recordings; deleting a session's samples (explicitly deleting eyes first) does
not erase the separately stored task, participant or device. Referenced parents
cannot be deleted accidentally because FKs use NO ACTION. Removing a referenced
file likewise fails rather than orphaning raw or processed records.

Staging is intentionally a source archive rather than the analysis model.
Its row_count is a stored import audit aggregate; equality with the number of
raw rows is an ETL/integration invariant, not a row-local normalization rule.
The processed relations meet 3NF for the documented dependencies. This claim
does not imply completeness, exactly two eyes, filename content deduplication,
or cross-file provenance correctness; those require the explicit ETL tests.

## Task 4 — Integrity test execution

Run from the repository root after installing the reviewed schema or applying the
migration to an existing installation:

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/tests/01_schema_tests.sql
```

The script asserts all eight tables, exact PK column lists, and all eight FK
mappings with validated constraints. It exercises invalid eye values, duplicate
(sample_id, eye), all orphan FK paths, parent deletion protection, deduplication
keys, metadata checks and NULL handling. Expected failures are caught in PL/pgSQL
subtransactions and checked by SQLSTATE; an unexpectedly successful statement
fails the suite. The outer transaction always rolls back on success, while
ON_ERROR_STOP and connection closure roll back on failure. No fixture rows
remain. Identity sequences may advance, as PostgreSQL sequences are not rolled
back. Run in an isolated test database when sequence gaps matter.

Validation on 2026-10-27: passed on the existing PostgreSQL 17 Docker database
after migration and on a separate empty database (`eyetrackdb_schema_review`)
created with the final create_tables.sql. Applying the migration after that fresh
installation also succeeded, confirming it tolerates already-installed checks.
