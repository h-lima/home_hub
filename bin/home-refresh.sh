#!/bin/sh
# home-refresh — run on the HOME laptop every 10 minutes by the home-refresh.timer that
# install-home.sh creates. Keeps what your phone sees current, without touching the copies you edit.
#
#   1. ~/srv/lectures      commit reading progress made on the phone/tablet, pull, push
#   2. ~/srv/study-system  pull; rebuild the site when something changed (or hourly, for the dashboards)
#   3. Timewarrior + Taskwarrior on this laptop: sync, so the dashboards count hours from both laptops
#
# Safe to run by hand:  sh ~/sys_org/home_hub/bin/home-refresh.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
STAMP=$(date '+%F %H:%M')
log() { echo "[home-refresh $STAMP] $*"; }

ahead() { [ -n "$(git log '@{u}..' --oneline 2>/dev/null)" ]; }

# 1. lectures -----------------------------------------------------------------------------------
L=$SRV_DIR/lectures
P=main_lectures/html-books/progress.json
if [ -d "$L/.git" ]; then (
  cd "$L" || exit 0
  if [ -n "$(git status --porcelain -- "$P")" ]; then
    git add -- "$P" && git commit -q -m "progress: read on phone/tablet ($STAMP)" && log "lectures: progress committed"
  fi
  git pull --rebase --autostash -q || { log "lectures: pull failed — look at $L"; exit 0; }
  if ahead; then git push -q && log "lectures: pushed"; fi
) fi

# 2. study system site ------------------------------------------------------------------------
S=$SRV_DIR/study-system
if [ -d "$S/.git" ]; then (
  cd "$S" || exit 0
  before=$(git rev-parse HEAD)
  git pull --ff-only -q || { log "study-system: pull failed — the serving clone must not have local edits"; exit 0; }
  after=$(git rev-parse HEAD)
  stale=1
  [ -f site/index.html ] && [ -z "$(find site/index.html -mmin +60)" ] && stale=0
  if [ "$before" != "$after" ] || [ $stale = 1 ]; then
    log "study-system: rebuilding site ($([ "$before" != "$after" ] && echo 'new commits' || echo hourly))"
    sh bin/build-site.sh > "$SRV_DIR/build-site.log" 2>&1 || log "study-system: build failed, see $SRV_DIR/build-site.log"
  fi
) fi

# 3. time and tasks on this laptop -----------------------------------------------------------
T=${TIMEWARRIORDB:-$HOME/.timewarrior}
[ -d "$T/.git" ] || T=$HOME/.local/share/timewarrior
if [ -d "$T/.git" ]; then (
  cd "$T" || exit 0
  git add -A
  git diff --cached --quiet || git commit -q -m "sync: $STAMP on $(hostname -s) (auto)"
  git pull --rebase -q || { log "timewarrior: pull failed — look at $T"; exit 0; }
  if ahead; then git push -q; fi
) fi
if command -v task >/dev/null 2>&1 && task _get rc.sync.server.url 2>/dev/null | grep -q .; then
  task sync >/dev/null 2>&1 || log "taskwarrior: task sync failed"
fi
exit 0
