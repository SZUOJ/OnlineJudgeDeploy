#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE=${ENV_FILE:-"$SCRIPT_DIR/../.env"}
DB_USER=$(sed -n 's/^DB_USER=//p' "$ENV_FILE" | tail -n 1)

if [ -z "$DB_USER" ]; then
    echo "DB_USER is not configured in $ENV_FILE" >&2
    exit 1
fi

umask 077
BACKUP_FILE="$SCRIPT_DIR/db_backup_$(date +%Y_%m_%d_%H_%M_%S).sql"
TEMP_FILE="$BACKUP_FILE.tmp"
trap 'rm -f -- "$TEMP_FILE"' EXIT HUP INT TERM
docker exec oj-postgres pg_dumpall --clean --if-exists --username "$DB_USER" > "$TEMP_FILE"
mv -- "$TEMP_FILE" "$BACKUP_FILE"
trap - EXIT HUP INT TERM
echo "Database backup written to $BACKUP_FILE"
