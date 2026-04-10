#!/bin/sh
# Runs once on first PostgreSQL data volume init (docker-entrypoint-initdb.d).
# Strips PG 17+ psql meta-command \restrict so restore works reliably.

set -eu

DUMP="/docker-entrypoint-initdb.d/seed/DB.sql"
if [ ! -f "$DUMP" ]; then
  echo "restore.sh: no dump at $DUMP — skip"
  exit 0
fi

echo "restore.sh: restoring database $POSTGRES_DB from DB.sql ..."
# Remove \restrict lines (pg_dump 17 security token) before piping to psql
sed '/^\\restrict/d' "$DUMP" | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"
echo "restore.sh: done."
