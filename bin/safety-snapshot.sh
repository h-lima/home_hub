#!/bin/sh
# safety-snapshot — a verified copy of the things that must not be lost, taken BEFORE any step that
# could damage them (upgrading Taskwarrior, merging tasks or time, replacing ~/.task or ~/.timewarrior).
#
#   sh safety-snapshot.sh            # on each laptop, before phase G/H of the runbook (and whenever unsure)
#   sh safety-snapshot.sh --list     # show the snapshots taken so far
#
# It writes ~/safety/<date-time>/ with:
#   task-export.json      every task (pending, completed, deleted, recurring) as JSON
#   task-export.ok        proof the export is usable: it was imported into a throw-away Taskwarrior
#                         and exported again, with the same number of tasks
#   dot-task.tar.gz       the whole ~/.task folder (database + hooks), exactly as it is now
#   taskrc/               ~/.taskrc and everything it includes from your home folder (dot-taskrc, …)
#   timew-export.json     every Timewarrior interval as JSON, and timewarrior.tar.gz (data + config)
#   notes.tar.gz          ~/learning/study-system (without .venv/site) and ~/sys_org (org-roam, home_hub), incl. uncommitted edits
#   SHA256SUMS            checksums of all of the above
# and then copies the folder to the Toshiba drive (backups/safety/<host>/), directly on the home
# laptop, over ssh from any other laptop. Nothing existing is modified.
#
# To roll back tasks from a snapshot S:   mv ~/.task ~/.task.broken && tar xzf S/dot-task.tar.gz -C ~
# (with the same Taskwarrior version that was installed when S was taken — see S/versions.txt)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
TS=$(date +%Y-%m-%d_%H%M%S)
HOST=$(hostname -s)
BASE=$HOME/safety
if [ "${1:-}" = --list ]; then ls -1d "$BASE"/*/ 2>/dev/null || echo "none yet"; exit 0; fi
OUT=$BASE/$TS
mkdir -p "$OUT"; chmod 700 "$BASE"
say() { printf '%s\n' "$*"; }
fail() { say "!! $*"; say "!! The snapshot in $OUT is INCOMPLETE — do not continue with risky steps."; exit 1; }
count_json() { python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$1"; }

{ echo "host: $HOST"; date -Iseconds
  echo "task: $(task --version 2>/dev/null || echo none)"
  echo "timew: $(timew --version 2>/dev/null || echo none)"; } > "$OUT/versions.txt"

# --- Taskwarrior -------------------------------------------------------------------------------
if command -v task >/dev/null 2>&1; then
  TDATA=$(task _get rc.data.location 2>/dev/null || echo "$HOME/.task")
  TDATA=${TDATA:-$HOME/.task}; TDATA=$(eval echo "$TDATA")
  task rc.hooks=0 rc.verbose=nothing export > "$OUT/task-export.json" 2>/dev/null || fail "task export failed"
  N=$(count_json "$OUT/task-export.json") || fail "task-export.json is not valid JSON"
  say "tasks exported: $N"
  # prove it can be imported back: a throw-away database, no taskrc, no hooks
  SCR=$(mktemp -d); : > "$SCR/rc"
  TASKRC=$SCR/rc task rc.data.location="$SCR" rc.hooks=0 rc.confirmation=0 rc.verbose=nothing \
       import "$OUT/task-export.json" >/dev/null 2>&1 || fail "the export could not be imported into a scratch Taskwarrior"
  TASKRC=$SCR/rc task rc.data.location="$SCR" rc.hooks=0 rc.verbose=nothing export > "$SCR/re.json" 2>/dev/null
  N2=$(count_json "$SCR/re.json")
  rm -rf "$SCR"
  [ "$N" = "$N2" ] || fail "re-import gave $N2 tasks, export had $N"
  echo "$N tasks exported and re-imported into a scratch database: OK" > "$OUT/task-export.ok"
  say "export verified (re-imported $N2 tasks into a scratch database)"
  [ -d "$TDATA" ] && tar czf "$OUT/dot-task.tar.gz" -C "$(dirname "$TDATA")" "$(basename "$TDATA")"
  mkdir -p "$OUT/taskrc"
  keep() { [ -f "$1" ] && cp -a "$1" "$OUT/taskrc/$(basename "$1" | sed 's/^\./dot-/')"; return 0; }   # dot-taskrc: visible to ls
  keep "$HOME/.taskrc"
  grep -hE '^\s*include\s' "$HOME/.taskrc" 2>/dev/null | awk '{print $2}' | while read -r f; do
    f=$(eval echo "$f"); case $f in "$HOME"/*) keep "$f" ;; esac
  done
  keep "$HOME/.taskrc.sync"
else
  say "Taskwarrior not installed here — skipped"
fi

# --- Timewarrior -------------------------------------------------------------------------------
if command -v timew >/dev/null 2>&1; then
  if timew export > "$OUT/timew-export.json" 2>/dev/null; then
    say "intervals exported: $(count_json "$OUT/timew-export.json")"
  elif [ -d "${TIMEWARRIORDB:-$HOME/.timewarrior}" ] || [ -d "$HOME/.local/share/timewarrior" ]; then
    fail "timew export failed although Timewarrior data exists"
  else
    rm -f "$OUT/timew-export.json"; say "no Timewarrior database here — skipped"
  fi
  set --
  for d in "${TIMEWARRIORDB:-}" "$HOME/.timewarrior" "$HOME/.local/share/timewarrior" "$HOME/.config/timewarrior"; do
    [ -n "$d" ] && [ -d "$d" ] && set -- "$@" "${d#"$HOME"/}"
  done
  [ $# -gt 0 ] && tar czf "$OUT/timewarrior.tar.gz" -C "$HOME" "$@"
fi

# --- notes and the study system (small; includes edits not yet committed) --------------------
set --
[ -d "$HOME/learning/study-system" ] && set -- "$@" learning/study-system
[ -d "$HOME/sys_org" ] && set -- "$@" sys_org
[ $# -gt 0 ] && tar czf "$OUT/notes.tar.gz" -C "$HOME" --exclude=.venv --exclude=site --exclude='*_cache' "$@"

# shellcheck disable=SC2094
( cd "$OUT" && find . -type f ! -name SHA256SUMS -exec sha256sum {} + > SHA256SUMS )
say "local copy: $OUT ($(du -sh "$OUT" | cut -f1))"

# --- a second copy on the Toshiba drive ------------------------------------------------------
DEST=$BACKUP_ROOT/safety/$HOST
if mountpoint -q "$BACKUP_DRIVE" 2>/dev/null; then
  mkdir -p "$DEST" && cp -a "$OUT" "$DEST/" && say "copied to the drive: $DEST/$TS"
elif ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOME_USER@$HOME_NODE" "mountpoint -q '$BACKUP_DRIVE'" 2>/dev/null; then
  ssh "$HOME_USER@$HOME_NODE" "mkdir -p '$DEST'" && scp -rq "$OUT" "$HOME_USER@$HOME_NODE:$DEST/" \
    && say "copied to the drive on $HOME_NODE: $DEST/$TS"
else
  say "note: the Toshiba drive is not reachable from here yet — the copy is only local."
  say "      Also copy it somewhere else by hand (a USB stick, or: tar czf - -C ~ safety | ssh …)."
fi
say "SAFETY SNAPSHOT COMPLETE."
