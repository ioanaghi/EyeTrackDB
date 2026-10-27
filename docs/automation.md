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

## Task 2 — Enable pg_cron

Create `sql/04_enable_pg_cron.sql`.

The configuration must support:

```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

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