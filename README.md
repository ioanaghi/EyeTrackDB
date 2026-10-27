# EyeTrackDB

### Eye-Tracking Data Management and Automated ETL Pipeline

EyeTrackDB is a PostgreSQL-based relational database project designed to store, process, validate, and analyze eye-tracking data collected using the Tobii Pro Nano eye tracker.

**Database Design Project | PostgreSQL 17 | Docker | Python | SQL**

---

## About the Project

EyeTrackDB transforms raw eye-tracking recordings into structured and normalized relational data through an Extract, Transform, Load (ETL) pipeline.

The project focuses on relational database design, data integrity, normalization, automated processing, and reproducible deployment.

### Main Objectives

- Design a relational database normalized up to Third Normal Form (3NF).
- Preserve original recordings in a staging schema.
- Import and transform CSV recordings into relational tables.
- Validate gaze coordinates, pupil measurements, and timestamps.
- Handle missing and invalid measurements.
- Prevent duplicate records during repeated imports.
- Automate ETL execution using PostgreSQL job scheduling.
- Provide a reproducible environment using Docker Compose.

## Technology Stack

| Technology | Purpose |
|---|---|
| PostgreSQL 17 | Relational database management |
| Docker Compose | Containerized deployment |
| Python | Dataset inspection and CSV ingestion |
| SQL / PL/pgSQL | Database schema and data transformations |
| pg_cron | Daily ETL scheduling and execution history |
| Git and GitHub | Version control and team collaboration |

## Dataset

The project uses eye-tracking recordings collected with a Tobii Pro Nano device.

| Metric | Value |
|---|---|
| Recording sessions | 2 |
| Total gaze samples | 103,870 |
| Total recording duration | Approximately 28 minutes 51 seconds |
| Data format | CSV |
| Columns per record | 21 |

Each recording contains system and device timestamps, gaze coordinates, pupil diameters, gaze origin coordinates, and validity indicators for both eyes.

Raw recordings should only be distributed when the necessary permissions have been obtained. Local CSV files are excluded from new Git commits by default.

## Database Architecture

The database is organized into three PostgreSQL schemas.

### Staging Schema

Stores original data before transformation.

| Table | Description |
|---|---|
| `staging.import_files` | Metadata about imported CSV files |
| `staging.raw_gaze_data` | Raw eye-tracking measurements |

### Processed Schema

Stores structured relational data.

| Table | Description |
|---|---|
| `processed.devices` | Eye-tracking devices |
| `processed.participants` | Anonymized participant identifiers |
| `processed.tasks` | Recording activities |
| `processed.sessions` | Eye-tracking recording sessions |
| `processed.gaze_samples` | Individual gaze samples and timestamps |
| `processed.eye_measurements` | Measurements for the left and right eyes |

### ETL Schema

Contains the ETL cleaning function, transformation and logging procedures, and execution logs. The pg_cron extension stores scheduling metadata and history in the cron schema.

### Data Processing Flow

```text
Tobii Pro Nano
      |
      v
Raw CSV Recordings
      |
      v
STAGING
  import_files
  raw_gaze_data
      |
      v
ETL Pipeline
  Validation
  Cleaning
  Transformation
      |
      v
PROCESSED
  devices
  participants
  tasks
  sessions
  gaze_samples
  eye_measurements
      |
      v
SQL Queries and Analysis
```

## Getting Started

### Prerequisites

- Docker Desktop
- Docker Compose
- Git
- Python 3.10+ (CSV importer)

### 1. Clone the repository

```bash
git clone https://github.com/ioanaghi/EyeTrackDB.git
cd EyeTrackDB
```

### 2. Start PostgreSQL

```bash
docker compose up -d --build --wait
```

### 3. Verify the container

```bash
docker compose ps
```

The PostgreSQL service should report a healthy status. The image builds from
PostgreSQL 17 Bookworm and installs pg_cron from PGDG, requiring internet access
on the first build. Compose explicitly preloads pg_cron and selects eyetrackdb,
Europe/Bucharest, and background workers, including on existing database volumes.

### 4. Connect to PostgreSQL

```bash
docker compose exec postgres psql -U eyetrack -d eyetrackdb
```

### 5. Install the database schema

Run from the repository root. This script creates the three schemas and all eight
tables atomically on a new database:

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/create_tables.sql
```

For a database created with the original schema, apply the integrity migration
instead. Re-running CREATE TABLE IF NOT EXISTS does not upgrade existing tables:

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/migrations/01_schema_integrity.sql
```

The migration aborts atomically if existing metadata violates the new constraints.
Review the reported rows before retrying; it does not rewrite source recordings.

### 6. Install the ETL procedure

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/03_etl_transform.sql
```

### 7. Install logging and scheduling

Apply the extension, logging wrapper, and schedule in this order:

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/04_enable_pg_cron.sql
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/06_etl_logging.sql
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/05_schedule_jobs.sql
```

The single named job `eyetrackdb-daily-etl` runs at **02:00 Europe/Bucharest**
(`0 2 * * *`). It invokes `etl.run_pipeline_logged()`, which calls the ETL and
records the outcome. Reapplying the schedule replaces the named job without
creating duplicates. Configuration changes require recreating the container with
`docker compose up -d --build --wait`; keep the named data volume.

### 8. Import the recordings

Place the two Tobii CSV recordings in `data/`. Run the importer on the host; the
PostgreSQL container sees the same directory at `/data`.

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
export PGHOST=127.0.0.1 PGPORT=5433 PGDATABASE=eyetrackdb PGUSER=eyetrack
read -s PGPASSWORD
export PGPASSWORD
.venv/bin/python scripts/import_csv.py --data-dir data
```

Enter the development password configured in docker-compose.yml at the password
prompt. Do not commit a real deployment password. Connections can also be set
with `DATABASE_URL` or `--dsn`; `DATA_DIR` changes the default CSV directory.
Each file is imported in one transaction. Failures return a nonzero exit code and
roll back that file. Existing filenames are skipped, including files whose content
changed under the same name; this is filename-based deduplication.

### 9. Transform and validate

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb -c 'CALL etl.run_pipeline_logged();'
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/tests/01_schema_tests.sql
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/tests/02_etl_tests.sql
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/tests/03_automation_tests.sql
```

The schema suite works with an empty or populated database. The ETL suite requires
the complete original dataset: 2 files, 103,870 raw rows, 2 sessions, 103,870 gaze
samples and 207,740 eye measurements. All three suites roll back their fixtures; identity
sequences can still advance. Use an isolated database for tests when that matters.

Re-run the importer and procedure to confirm repeatability: the same filenames,
raw source IDs and sample/eye pairs do not create duplicates. Missing numeric
measurements become NULL, numeric zero and validity flags are preserved, and
malformed values abort transformation with source context. Uncollected session
metadata remains NULL. See [ETL instructions](docs/etl-pipeline.md),
[schema review and normalization](docs/database-design.md) and the
[ER diagram source](docs/er-diagram.mmd).

### 10. Inspect scheduler and pipeline outcomes

```bash
docker compose exec -T postgres psql -U eyetrack -d eyetrackdb -c "SELECT jobid, jobname, schedule, active FROM cron.job;"
docker compose exec -T postgres psql -U eyetrack -d eyetrackdb -c "SELECT jobid, status, return_message, start_time, end_time FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;"
docker compose exec -T postgres psql -U eyetrack -d eyetrackdb -c "SELECT execution_id, status, processed_records, error_detail FROM etl.execution_logs ORDER BY execution_id DESC LIMIT 10;"
```

Check `etl.execution_logs.status` for the pipeline result. The wrapper catches
ETL errors, rolls back partial ETL writes, stores a failure and returns a warning.
Therefore a successful scheduler invocation or psql exit code alone does not mean
the pipeline succeeded. The log persists when the outer transaction commits;
an explicit outer ROLLBACK also removes it. `processed_records` counts newly added
gaze samples, so a repeatable rerun can correctly report zero. Direct
`CALL etl.run_pipeline()` remains available and raises errors directly, without
writing the wrapper log. More queries and timezone details are in
[automation operations](docs/automation.md).

**Validated on 2026-10-27:** PostgreSQL 17 with pg_cron on a new Docker volume,
complete CSV import, schema/ETL/automation suites, repeated imports and transforms,
idempotent scheduling, persisted success/failure logs, and a real scheduler run
using a temporary one-second smoke job. That test job was removed; the daily
02:00 job remains configured. The 02:00 daily invocation itself was not awaited.
The Docker image was built and tested on ARM64; AMD64 was not exercised locally.

### Stopping and restarting

```bash
docker compose down
docker compose up -d --wait
```

The named volume preserves the database. Schema creation and ETL installation are
explicit setup steps, so a new volume needs steps 5–9. Reuse the existing volume
without re-importing files. If port 5433 is occupied, adjust the host mapping in a
local Compose override and set PGPORT to the matching host port.

### Existing-volume collation compatibility

A volume initialized by a different Linux distribution can report a collation
version mismatch after switching to the Bookworm image. Before continuing normal
use, rebuild the affected database indexes, then refresh the recorded version:

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb -c 'REINDEX DATABASE eyetrackdb;' -c 'ALTER DATABASE eyetrackdb REFRESH COLLATION VERSION;'
```

Perform this maintenance without concurrent application writes; reindexing may
lock tables. Apply the same maintenance separately to any other database you
retain that reports a mismatch. Do not merely refresh the version before rebuilding
the indexes. A fresh volume created with the final image needs no such step.

## Development Team

| Team Member | Responsibility | Branch |
|---|---|---|
| Ioana | Database Design, Normalization and Integration | `feature/database-design` |
| Georgiana | CSV Ingestion, ETL and Data Validation | `feature/etl-pipeline` |
| Luca | Automation, Scheduling and Monitoring | `feature/automation` |

## Git Workflow

The `main` branch contains the stable, integrated version of the project.

Each team member develops their assigned functionality on a dedicated feature branch.

### Update the local branch

```bash
git fetch origin
git switch YOUR_BRANCH
git pull --ff-only origin YOUR_BRANCH
```

### Commit and push changes

```bash
git add PATH_TO_CHANGED_FILES
git commit -m "feat: describe implemented functionality"
git push origin YOUR_BRANCH
```

After completing a feature, open a Pull Request targeting `main`.

All changes should be reviewed and tested before merging.

## Project Roadmap

- [x] Collect eye-tracking recordings
- [x] Inspect and analyze the initial dataset
- [x] Configure PostgreSQL using Docker Compose
- [x] Create staging and processed schemas
- [x] Create relational database tables
- [x] Implement CSV ingestion
- [x] Implement ETL transformations
- [x] Validate data quality and prevent duplicate imports
- [x] Document normalization to 3NF
- [x] Create an Entity-Relationship diagram
- [x] Configure automated scheduling using pg_cron
- [x] Implement ETL execution logging
- [x] Add SQL validation and integration tests
- [x] Perform end-to-end testing
- [x] Complete final project documentation

## Data Privacy

Eye-tracking recordings may contain participant-related information. Raw datasets should only be shared when the appropriate permissions and privacy requirements have been satisfied.

Credentials, environment configuration files, and local database backups must not be committed to the repository.

## License

A software license has not yet been selected.

---

EyeTrackDB — From raw eye movements to structured data.