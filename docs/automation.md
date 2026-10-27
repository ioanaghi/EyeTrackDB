# Database Automation and Monitoring — Luca

**Branch:** `feature/automation`  
**Role:** Automation Developer  
**Project:** EyeTrackDB

## Objective

Implement scheduled execution and monitoring of the EyeTrackDB ETL pipeline using PostgreSQL and `pg_cron`.

The solution must run in Docker and support reproducible setup across development environments.

## Task 1 — PostgreSQL Docker Image

Create `docker/Dockerfile`.

The image must:

1. Use PostgreSQL 17.
2. Install a compatible `pg_cron` extension.
3. Enable `pg_cron` using `shared_preload_libraries`.
4. Configure the target database for scheduling.
5. Work on ARM64 and AMD64 systems where supported.

Use a compatible PostgreSQL package source and document build requirements.

Do not replace PostgreSQL 17 with a different major version without approval.

The existing `docker-compose.yml` is managed by Ioana. Document the changes required to use the custom image so they can be integrated centrally.

Implementation: `docker/Dockerfile` extends the official `postgres:17-bookworm`
image and installs `postgresql-17-cron` from the PostgreSQL Apt (PGDG)
repository. PGDG provides packages for supported AMD64 and ARM64 Debian
architectures. Build it with `docker build -f docker/Dockerfile -t eyetrackdb-postgres:17-cron .`
on a supported architecture (or use Docker Buildx for cross-platform builds).
The image preloads `pg_cron` and sets `cron.database_name` to `eyetrackdb`.

Compose integration for Ioana: change the `postgres` service from
`image: postgres:17` to `build: { context: ., dockerfile: docker/Dockerfile }`
or tag/use `eyetrackdb-postgres:17-cron`. Keep the current database environment,
ports, volumes, and healthcheck. Recreate/restart the PostgreSQL container after
changing `shared_preload_libraries`; PostgreSQL only loads that library at
server startup. This change does not require deleting the existing volume.

## Task 2 — Enable pg_cron

Create `sql/04_enable_pg_cron.sql`.

The configuration must support:

```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

`sql/04_enable_pg_cron.sql` installs and verifies the extension in
`cron.database_name` (configured as `eyetrackdb` by the custom image). Run it
as a database superuser after connecting to `eyetrackdb`. `pg_cron` must be in
`shared_preload_libraries`; changing that setting requires a PostgreSQL
container restart before the extension can be created. Verify with
`SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_cron';`.

Document the required PostgreSQL configuration and container restart behavior.

Verify that the extension is installed in the intended database.

## Task 3 — Scheduled ETL Job

Create `sql/05_schedule_jobs.sql`.

Configure a scheduled job that executes:

```sql
CALL etl.run_pipeline();
```

The job must run daily at 02:00.

Use an explicit timezone and document the behavior across daylight saving time changes.

The job must be installed idempotently, without creating duplicate scheduled jobs each time the setup script runs.

The ETL procedure itself is implemented by Georgiana.

`sql/05_schedule_jobs.sql` replaces any existing job named
`eyetrackdb-daily-etl` before creating the single daily job. It runs
`CALL etl.run_pipeline()` at 02:00 in the explicitly configured
`Europe/Bucharest` timezone. The setup script must be run as a PostgreSQL
superuser in `eyetrackdb` after the procedure is installed. Under current
Bucharest daylight-saving rules, clock changes happen at 03:00/04:00, so this
02:00 wall-clock schedule occurs once each local calendar day; its UTC time
shifts by one hour between EET and EEST. Future time-zone rule changes follow
the installed IANA time-zone data.

The scheduler calls `etl.run_pipeline_logged()`, which delegates to
`etl.run_pipeline()` and records the pipeline outcome. Apply
`sql/06_etl_logging.sql` before installing/updating the scheduled job.

## Task 4 — ETL Execution Logging

`sql/06_etl_logging.sql` creates `etl.execution_logs` and the logging wrapper
`etl.run_pipeline_logged()`. The wrapper inserts a running record, invokes
Georgiana's unchanged `etl.run_pipeline()`, then records end time, status, and
the increase in `processed.gaze_samples` as `processed_records`. That count is
the number of newly materialized samples, so an idempotent rerun may correctly
report zero.

PostgreSQL rolls back statements inside the wrapper's exception subtransaction
when the ETL call fails. The wrapper catches that error, stores its SQLSTATE,
message, detail, and hint in the outer execution log row, and emits a warning.
The wrapper therefore returns normally after a logged failure; inspect
`etl.execution_logs.status` to determine pipeline success. As with any normal
transactional table, an outer transaction rollback or server failure before
commit can still remove the log. `cron.job_run_details` independently records
whether the scheduled wrapper invocation ran, but its success status does not
replace the pipeline status in `etl.execution_logs`.

The integration interface for Georgiana is to keep `etl.run_pipeline()` as the
ETL entry point; automation invokes it through `etl.run_pipeline_logged()`.
This avoids modifying or duplicating the ETL transformation.

## Task 5 — Monitoring

Check that the named job exists, is active, and see its most recent scheduler
run:

```sql
SELECT j.jobid, j.jobname, j.schedule, j.command, j.active,
       r.start_time AS last_started_at, r.end_time AS last_ended_at,
       r.status AS last_scheduler_status, r.return_message
FROM cron.job AS j
LEFT JOIN LATERAL (
    SELECT start_time, end_time, status, return_message
    FROM cron.job_run_details
    WHERE jobid = j.jobid
    ORDER BY start_time DESC NULLS LAST
    LIMIT 1
) AS r ON true
WHERE j.jobname = 'eyetrackdb-daily-etl';
```

Inspect recent scheduler history (including reported errors):

```sql
SELECT jobid, runid, database, username, command, status,
       return_message, start_time, end_time
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 10;
```

Inspect pipeline-level results and failures recorded by the wrapper:

```sql
SELECT execution_id, pipeline_name, started_at, ended_at, status,
       processed_records, error_detail
FROM etl.execution_logs
ORDER BY started_at DESC
LIMIT 20;
```

Filter to pipeline failures:

```sql
SELECT execution_id, started_at, ended_at, error_detail
FROM etl.execution_logs
WHERE status = 'failed'
ORDER BY started_at DESC;
```

`cron.job_run_details` describes the scheduled wrapper process; the execution
log table is the source of truth for whether the ETL pipeline itself succeeded.

## Task 4 — ETL Execution Logging

Create `sql/06_etl_logging.sql`.

Design a logging mechanism that records:

- Execution identifier.
- Job or pipeline name.
- Start timestamp.
- End timestamp.
- Execution status.
- Number of processed records, when available.
- Error details, when available.

Suggested table:

```text
etl.execution_logs
```

Coordinate the logging interface with Georgiana so the ETL procedure can report execution results consistently.

Important: PostgreSQL transaction rollback can also roll back log inserts. Document and test the chosen approach to failure logging.

## Task 5 — Monitoring

Provide SQL queries to inspect scheduled jobs and their execution history.

Examples:

```sql
SELECT * FROM cron.job;
```

```sql
SELECT *
FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 10;
```

The solution must make it possible to determine:

- Whether the scheduled job exists.
- Whether it is active.
- When it last ran.
- Whether the execution succeeded.
- Whether errors were recorded.

## Task 6 — Manual Execution

Provide a documented way to execute the ETL without waiting until 02:00.

The expected interface is:

```sql
CALL etl.run_pipeline();
```

Document how to verify the outcome.

## Task 7 — Automation Tests

Create `sql/tests/03_automation_tests.sql`.

Tests must verify:

1. The `pg_cron` extension is installed.
2. The scheduled ETL job exists.
3. The schedule is configured correctly.
4. No duplicate scheduled jobs exist.
5. The job is active.
6. Manual pipeline execution succeeds after ETL integration.
7. Execution history can be queried.
8. Logging behaves as documented.

Do not mark an actual scheduled execution as successful until it has been observed.

## Files to Deliver

```text
docker/
  Dockerfile

sql/
  04_enable_pg_cron.sql
  05_schedule_jobs.sql
  06_etl_logging.sql
  tests/
    03_automation_tests.sql

docs/
  automation.md
```

## Acceptance Criteria

- [ ] PostgreSQL Docker image builds successfully.
- [ ] `pg_cron` extension is installed and enabled.
- [ ] Daily ETL job is scheduled for 02:00.
- [ ] Scheduling setup is idempotent.
- [ ] Job history can be inspected.
- [ ] Execution logging is implemented.
- [ ] Manual ETL execution works after integration.
- [ ] Automation tests pass.
- [ ] Docker setup and troubleshooting are documented.

## Git Commands

```bash
git switch feature/automation
git add docker/Dockerfile sql/04_enable_pg_cron.sql sql/05_schedule_jobs.sql sql/06_etl_logging.sql sql/tests/03_automation_tests.sql docs/automation.md
git commit -m "feat(automation): implement pg_cron scheduling and ETL monitoring"
git push origin feature/automation
```

Create a Pull Request targeting `main`.

Coordinate with Georgiana before integrating the scheduled ETL procedure.
