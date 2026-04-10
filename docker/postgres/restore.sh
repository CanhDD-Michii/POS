#!/bin/sh
# Runs once on first PostgreSQL data volume init (docker-entrypoint-initdb.d).
# Drops pg_dump 17+ \restrict lines (awk — portable on Alpine/BusyBox vs sed quirks).

set -eu

DUMP="/docker-entrypoint-initdb.d/seed/DB.sql"
if [ ! -f "$DUMP" ]; then
  echo "restore.sh: no dump at $DUMP — skip"
  exit 0
fi

echo "restore.sh: restoring database $POSTGRES_DB from DB.sql (this may take several minutes) ..."
# Skip any line that starts with the psql meta-command \restrict
awk '!/^\\restrict/' "$DUMP" | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"
echo "restore.sh: done."
