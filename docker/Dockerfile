FROM postgres:17-bookworm

# PGDG publishes PostgreSQL extension packages for both amd64 and arm64.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
       -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
       > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends postgresql-17-cron \
    && rm -rf /var/lib/apt/lists/*

RUN echo "shared_preload_libraries = 'pg_cron'" \
        >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "cron.database_name = 'eyetrackdb'" \
        >> /usr/share/postgresql/postgresql.conf.sample \
    && echo "cron.timezone = 'Europe/Bucharest'" \
        >> /usr/share/postgresql/postgresql.conf.sample
