#!/usr/bin/env bash
# Downloads a consistent snapshot of the production SQLite database for local inspection.
#
# Usage: scripts/fetch_prod_db.sh [local_destination_path]

set -euo pipefail

APP="speechwave"
REMOTE_DB="/data/speechwave.db"
REMOTE_BACKUP="/data/tmp_backup_$(date +%Y%m%d%H%M%S).db"
LOCAL_DEST="${1:-./speechwave_prod_$(date +%Y%m%d%H%M%S).db}"

cleanup() {
  flyctl ssh console --app "$APP" --command "/bin/sh -c 'rm -f $REMOTE_BACKUP $REMOTE_BACKUP-wal $REMOTE_BACKUP-shm'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Taking consistent backup on $APP ($REMOTE_DB -> $REMOTE_BACKUP)..."
# The SQL string needs the target path quoted (VACUUM INTO '<path>'). We build
# the quotes from their char code (<<39>>) so the whole expression can be
# shell-quoted with plain single quotes without any nested-quote escaping.
flyctl ssh console --app "$APP" --command "/app/bin/speechwave rpc 'Ecto.Adapters.SQL.query!(Speechwave.Repo, \"VACUUM INTO \" <> <<39>> <> \"$REMOTE_BACKUP\" <> <<39>>)'"

echo "Downloading to $LOCAL_DEST..."
flyctl ssh sftp get "$REMOTE_BACKUP" "$LOCAL_DEST" --app "$APP"

echo "Done: $LOCAL_DEST"
