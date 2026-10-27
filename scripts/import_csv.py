#!/usr/bin/env python3
"""Import Tobii CSV files atomically. Requires psycopg >= 3, < 4."""

import argparse
import csv
import logging
import os
from pathlib import Path

import psycopg
from psycopg import sql


COLUMNS = ["system_time_stamp", "device_time_stamp", "timestamp_utc"] + [
    f"{eye}_{field}"
    for eye in ("left", "right")
    for field in (
        "gaze_x", "gaze_y", "gaze_validity", "pupil_diameter",
        "pupil_validity", "gaze_origin_validity", "gaze_origin_x",
        "gaze_origin_y", "gaze_origin_z",
    )
]


def import_file(connection, path):
    with connection.transaction(), path.open(newline="", encoding="utf-8-sig") as source:
        reader = csv.reader(source, strict=True)
        if next(reader, None) != COLUMNS:
            raise ValueError(f"{path.name}: expected the 21 Tobii headers in order")
        with connection.cursor() as cursor:
            cursor.execute(
                "INSERT INTO staging.import_files (filename) VALUES (%s) "
                "ON CONFLICT (filename) DO NOTHING RETURNING import_file_id",
                (path.name,),
            )
            registered = cursor.fetchone()
            if registered is None:
                logging.info("Skipped already registered file: %s", path.name)
                return
            statement = sql.SQL("COPY staging.raw_gaze_data ({}) FROM STDIN").format(
                sql.SQL(", ").join(map(sql.Identifier, ["import_file_id"] + COLUMNS))
            )
            count = 0
            with cursor.copy(statement) as copy:
                for row in reader:
                    if len(row) != len(COLUMNS):
                        raise ValueError(
                            f"{path.name}:{reader.line_num}: expected 21 fields, got {len(row)}"
                        )
                    copy.write_row((registered[0], *row))
                    count += 1
            if count == 0:
                raise ValueError(f"{path.name}: no data rows")
            cursor.execute(
                "UPDATE staging.import_files SET row_count = %s, status = 'imported' "
                "WHERE import_file_id = %s", (count, registered[0]),
            )
            logging.info("Imported %s: %d rows", path.name, count)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=Path(os.getenv("DATA_DIR", "data")))
    parser.add_argument("--dsn", default=os.getenv("DATABASE_URL", ""),
                        help="PostgreSQL DSN; also supports standard PG* environment variables")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    files = sorted(args.data_dir.glob("*.csv")) if args.data_dir.is_dir() else []
    if not files:
        logging.error("No CSV files found in %s", args.data_dir)
        return 1
    failed = False
    try:
        with psycopg.connect(args.dsn, autocommit=True) as connection:
            for path in files:
                try:
                    import_file(connection, path)
                except (OSError, UnicodeError, csv.Error, ValueError, psycopg.Error) as error:
                    logging.error("Import rolled back for %s: %s", path.name, error)
                    failed = True
    except psycopg.Error as error:
        logging.error("Database connection failed: %s", error)
        return 1
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
