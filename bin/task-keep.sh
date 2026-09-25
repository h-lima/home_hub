#!/bin/sh
# task-keep — daily, version-proof copies of your tasks, so that no failure of Taskwarrior or of the
# sync server can cost you more than a day. Run by the task-keep.timer on the HOME laptop (and it
# can run on any laptop). Keeps 90 days.
#
#   sh task-keep.sh            # now
#   sh task-keep.sh --list     # what is kept
#
# Writes to ~/backups/tasks/ (which the nightly system backup also carries to the Toshiba drive):
#   tasks-YYYY-MM-DD.json            `task export` of this laptop's full task list: plain JSON that
#                                    any Taskwarrior (2.6 or 3) can import. The universal way back.
#   server-YYYY-MM-DD.sqlite3        a consistent copy of the sync server's database (home laptop
#                                    only), made with SQLite's own backup command, so it is never
#                                    caught half-written. Kept 14 days.
# How to use them when something breaks: ~/sys_org/home_hub/recovery.org, scenario 7.
set -eu
OUT=$HOME/backups/tasks
KEEP_JSON=90
KEEP_DB=14
SERVER_DIR=$HOME/.local/share/taskchampion-sync-server
mkdir -p "$OUT"; chmod 700 "$HOME/backups"
[ "${1:-}" = --list ] && { ls -lh "$OUT"; exit 0; }
D=$(date +%F)

if command -v task >/dev/null 2>&1; then
  task rc.hooks=0 rc.verbose=nothing export > "$OUT/.tasks-$D.json.tmp"
  n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$OUT/.tasks-$D.json.tmp")
  if [ "$n" -gt 0 ]; then
    mv "$OUT/.tasks-$D.json.tmp" "$OUT/tasks-$D.json"; echo "task-keep: $n tasks -> $OUT/tasks-$D.json"
  else
    # an empty export means something is wrong NOW — keep yesterday's files untouched and say so
    rm -f "$OUT/.tasks-$D.json.tmp"; echo "task-keep: WARNING — task export returned 0 tasks; nothing replaced" >&2
  fi
fi

if [ -d "$SERVER_DIR" ]; then
  for db in "$SERVER_DIR"/*.sqlite3 "$SERVER_DIR"/*.sqlite "$SERVER_DIR"/*.db; do
    [ -f "$db" ] || continue
    if command -v sqlite3 >/dev/null; then
      sqlite3 "$db" ".backup '$OUT/server-$D.sqlite3'"
    else
      python3 -c 'import sqlite3,sys; s=sqlite3.connect(sys.argv[1]); d=sqlite3.connect(sys.argv[2]); s.backup(d); d.close()' \
        "$db" "$OUT/server-$D.sqlite3"
    fi
    echo "task-keep: sync server database -> $OUT/server-$D.sqlite3"
    break
  done
fi

# rotate (file names are ours: dates only)
# shellcheck disable=SC2012
ls -1 "$OUT"/tasks-*.json 2>/dev/null | sort | head -n -"$KEEP_JSON" | xargs -r rm -f
# shellcheck disable=SC2012
ls -1 "$OUT"/server-*.sqlite3 2>/dev/null | sort | head -n -"$KEEP_DB" | xargs -r rm -f
