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