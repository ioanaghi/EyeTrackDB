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
| pg_cron | Automated database jobs (planned) |
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

Reserved for data transformation procedures, job execution logs, scheduling, and monitoring.

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

### 1. Clone the repository

```bash
git clone https://github.com/ioanaghi/EyeTrackDB.git
cd EyeTrackDB
```

### 2. Start PostgreSQL

```bash
docker compose up -d
```

### 3. Verify the container

```bash
docker compose ps
```

The PostgreSQL service should report a healthy status.

### 4. Connect to PostgreSQL

```bash
docker compose exec postgres psql -U eyetrack -d eyetrackdb
```

### 5. Create database schemas

Execute the following SQL statements:

```sql
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS processed;
CREATE SCHEMA IF NOT EXISTS etl;
```

Exit PostgreSQL using `\q`.

### 6. Create database tables

Run the following command from the project root:

```bash
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U eyetrack -d eyetrackdb < sql/create_tables.sql
```

### 7. Verify the tables

```bash
docker compose exec postgres psql -U eyetrack -d eyetrackdb -c "\dt staging.*"
docker compose exec postgres psql -U eyetrack -d eyetrackdb -c "\dt processed.*"
```

The initial database contains eight tables across the staging and processed schemas.

**Current status:** Docker deployment and database table creation have been tested. ETL ingestion and automated scheduling are under development.

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
- [ ] Implement CSV ingestion
- [ ] Implement ETL transformations
- [ ] Validate data quality and prevent duplicate imports
- [ ] Document normalization to 3NF
- [ ] Create an Entity-Relationship diagram
- [ ] Configure automated scheduling using pg_cron
- [ ] Implement ETL execution logging
- [ ] Add SQL validation and integration tests
- [ ] Perform end-to-end testing
- [ ] Complete final project documentation

## Data Privacy

Eye-tracking recordings may contain participant-related information. Raw datasets should only be shared when the appropriate permissions and privacy requirements have been satisfied.

Credentials, environment configuration files, and local database backups must not be committed to the repository.

## License

A software license has not yet been selected.

---

EyeTrackDB — From raw eye movements to structured data.