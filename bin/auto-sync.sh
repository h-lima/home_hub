#!/bin/sh
# auto-sync — sync-all without you: every 10 minutes, on BOTH laptops, a systemd timer commits what is
# saved, pulls the other laptop's commits and pushes. You edit notes at home, Claude edits aids/ and
# bin/ on the work laptop; both copies meet on GitHub within minutes.
#
#   sh ~/sys_org/home_hub/bin/auto-sync.sh            # one round now (what the timer runs)
#   sh ~/sys_org/home_hub/bin/auto-sync.sh install    # once per laptop: the 10-minute timer
#   sh ~/sys_org/home_hub/bin/auto-sync.sh status     # last runs, and anything that needs you
#   sh ~/sys_org/home_hub/bin/auto-sync.sh uninstall  # back to sync-all by hand only
#
# The repositories are sync-all's list (~/.config/sync-all/repos, or its defaults), except:
#   - Timewarrior's folder: home-refresh (home) and sync-all keep doing it, with their merge driver
#   - the study system: committed like the others, but the phone inbox is NOT filed (sync-all does)
#   - mode "pull": only pulled, as in sync-all
# Safe by design:
#   - commits only files saved to disk; an editor buffer you have not saved stays where it is
#   - a repository in the middle of a rebase or merge (you are fixing something) is left alone
#   - a real conflict (both laptops changed the same lines): the pull is undone, your files stay
#     exactly as they were, nothing is pushed, and you get a desktop notice + a line in
#     ~/.local/state/auto-sync/attention. Fix it by hand with sync-all, as before.
#   - no network (commuting, asleep): it says so in the log and tries again in 10 minutes
set -u
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/auto-sync
ATTN=$STATE/attention
mkdir -p "$STATE"
HOST=$(hostname -s 2>/dev/null || hostname)
STAMP=$(date '+%F %H:%M')
log() { echo "[auto-sync] $*"; }

UNIT_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
HERE=$(cd "$(dirname "$0")" && pwd)

case "${1:-run}" in
  install)
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_DIR/auto-sync.service" <<EOF
[Unit]
Description=Commit, pull and push the study repositories (auto-sync)
[Service]
Type=oneshot
ExecStart=/bin/sh $HERE/auto-sync.sh
Nice=10
EOF
    cat > "$UNIT_DIR/auto-sync.timer" <<EOF
[Unit]
Description=auto-sync every 10 minutes (and soon after boot or waking up)
[Timer]
OnBootSec=2min
OnCalendar=*:0/10
Persistent=true
[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload && systemctl --user enable --now auto-sync.timer \
      && echo "auto-sync.timer enabled: every 10 minutes. First run now…" \
      && systemctl --user start auto-sync.service
    echo "Look at it: journalctl --user -u auto-sync -n 30"
    exit 0 ;;
  uninstall)
    systemctl --user disable --now auto-sync.timer 2>/dev/null
    rm -f "$UNIT_DIR/auto-sync.service" "$UNIT_DIR/auto-sync.timer"
    systemctl --user daemon-reload; echo "auto-sync removed (sync-all still works by hand)"; exit 0 ;;
  status)
    systemctl --user list-timers auto-sync.timer --no-pager 2>/dev/null
    journalctl --user -u auto-sync -n 15 --no-pager 2>/dev/null
    if [ -s "$ATTN" ]; then echo; echo "Needs you:"; cat "$ATTN"; else echo; echo "Nothing needs you."; fi
    exit 0 ;;
  run) ;;
  *) sed -n '2,24p' "$0"; exit 1 ;;
esac

# --- the repositories: the same list as sync-all ------------------------------------------------
TIMEW_DIR=${TIMEWARRIORDB:-$HOME/.timewarrior}
[ -d "$TIMEW_DIR" ] || TIMEW_DIR=$HOME/.local/share/timewarrior
CONF=${SYNC_ALL_REPOS:-$HOME/.config/sync-all/repos}
if [ -f "$CONF" ]; then LIST=$(sed -e 's/#.*//' -e "s|^~|$HOME|" "$CONF" | grep -v '^[[:space:]]*$')
else LIST="$HOME/learning/study-system study
$HOME/learning/lectures all
$HOME/sys_org/org_roam org
$HOME/sys_org/home_hub all"
fi

attention() {   # $1 repo name, $2 what happened — remembered until the repo syncs cleanly again
  new=1; grep -q "^$1: $2 (" "$ATTN" 2>/dev/null && new=0      # the desktop notice only the first time
  grep -v "^$1:" "$ATTN" 2>/dev/null > "$ATTN.new"; echo "$1: $2 ($STAMP)" >> "$ATTN.new"; mv "$ATTN.new" "$ATTN"
  log "$1: NEEDS YOU — $2"
  [ $new = 1 ] && command -v notify-send >/dev/null 2>&1 && notify-send -u critical "auto-sync: $1" "$2" 2>/dev/null
  return 0
}
clear_attention() { [ -f "$ATTN" ] && { grep -v "^$1:" "$ATTN" > "$ATTN.new"; mv "$ATTN.new" "$ATTN"; }; return 0; }

busy() {   # a rebase, merge or cherry-pick in progress, or another git command running
  g=$(git rev-parse --git-dir)
  [ -d "$g/rebase-merge" ] || [ -d "$g/rebase-apply" ] || [ -f "$g/MERGE_HEAD" ] \
    || [ -f "$g/CHERRY_PICK_HEAD" ] || [ -f "$g/index.lock" ]
}

sync_one() {   # $1 path, $2 mode
  dir=$1; mode=$2; name=$(basename "$dir")
  [ -d "$dir/.git" ] || return 0
  [ "$(cd "$dir" && pwd -P)" = "$(cd "$TIMEW_DIR" 2>/dev/null && pwd -P)" ] && return 0
  cd "$dir" || return 0
  if busy; then attention "$name" "a rebase/merge is in progress in $dir — finish it (git status), then sync-all"; return 0; fi

  # 1. commit what is saved
  if [ "$mode" != pull ]; then
    case $mode in
      org) git add -u
           git ls-files -o --exclude-standard -- '*.org' '*.bib' | while IFS= read -r f; do git add -- "$f"; done ;;
      *)   git add -A ;;
    esac
    git diff --cached --quiet || git commit -q -m "auto-sync: $STAMP on $HOST" || { attention "$name" "commit failed in $dir"; return 0; }
  fi

  git remote | grep -q . || return 0
  # 2. fetch (no network = try later, quietly)
  if ! git fetch -q 2>"$STATE/fetch.err"; then
    if grep -qiE 'permission denied|host key verification|could not read from remote|authentication' "$STATE/fetch.err" \
       && ! grep -qiE 'could not resolve|network is unreachable|timed out' "$STATE/fetch.err"; then
      attention "$name" "GitHub refused the timer's SSH login — a key with a passphrase needs an agent the timer can see (helpers.org, auto-sync)"
    else
      log "$name: no network or remote unreachable, next try in 10 min ($(head -1 "$STATE/fetch.err"))"
    fi
    return 0
  fi
  # 3. put our commits on top of the other laptop's
  if [ -n "$(git log '..@{u}' --oneline 2>/dev/null)" ]; then
    if ! git rebase -q --autostash '@{u}' >/dev/null 2>&1; then
      git rebase --abort >/dev/null 2>&1          # back exactly where we were (autostash restored)
      attention "$name" "both laptops changed the same lines — nothing was lost; run sync-all in $dir and keep both versions"
      return 0
    fi
    log "$name: pulled"
  fi
  # 4. push
  if [ "$mode" != pull ] && [ -n "$(git log '@{u}..' --oneline 2>/dev/null)" ]; then
    if git push -q 2>"$STATE/push.err"; then log "$name: pushed"
    else log "$name: push failed, next try in 10 min ($(head -1 "$STATE/push.err"))"; return 0; fi
  fi
  clear_attention "$name"
}

while read -r path mode; do (sync_one "$path" "${mode:-all}") </dev/null; done <<EOF
$LIST
EOF
exit 0
