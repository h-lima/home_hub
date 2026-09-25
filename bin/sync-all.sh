#!/bin/sh
# sync-all — one command that brings every machine up to date through GitHub
# (and Taskwarrior through the home laptop's sync server).
#
#   sh ~/sys_org/home_hub/bin/sync-all.sh   # pull, commit, push every repository, then `task sync`
#   sh ~/sys_org/home_hub/bin/sync-all.sh -n # dry run: show what would be synced, touch nothing
#   sync-all                                 # once install-home.sh / install-laptop.sh linked it into ~/.local/bin
#
# Run it when you sit down at a machine and when you get up — the same rule as bin/sync.sh,
# which it calls for the study system itself.
#
# The repositories come from ~/.config/sync-all/repos (one "path mode" per line), or from the
# default list below when that file does not exist. Modes:
#   study  the study system: delegates to its own bin/sync.sh (files the phone inbox, etc.)
#   all    `git add -A` — for repositories whose .gitignore is trustworthy
#   org    tracked files + new *.org / *.bib only — org-roam, where LaTeX debris lives beside the notes
#   pull   pull only, never commit (a clone you only read, e.g. on an HPC cluster)
# A path that does not exist on this machine is skipped silently, so the same list works on
# the home laptop, the work laptop and a cluster login node.
set -u
DRY=0
[ "${1:-}" = "-n" ] && DRY=1

TIMEW_DIR=${TIMEWARRIORDB:-$HOME/.timewarrior}
[ -d "$TIMEW_DIR" ] || TIMEW_DIR=$HOME/.local/share/timewarrior

CONF=${SYNC_ALL_REPOS:-$HOME/.config/sync-all/repos}
default_list() {
  cat <<EOF
$HOME/learning/study-system study
$HOME/learning/lectures     all
$HOME/sys_org/org_roam      org
$HOME/sys_org/home_hub      all
$TIMEW_DIR                  all
EOF
}
if [ -f "$CONF" ]; then LIST=$(sed -e 's/#.*//' -e "s|^~|$HOME|" "$CONF" | grep -v '^[[:space:]]*$')
else LIST=$(default_list); fi

HOST=$(hostname -s 2>/dev/null || hostname)
STAMP=$(date '+%F %H:%M')
FAILED=""

sync_repo() {  # $1 path, $2 mode
  dir=$1; mode=$2; name=$(basename "$dir")
  [ -d "$dir/.git" ] || return 0
  printf '\n== %s (%s) ==\n' "$name" "$mode"
  if [ $DRY = 1 ]; then git -C "$dir" status --short --branch | head -15; return 0; fi

  if [ "$mode" = study ] && [ -f "$dir/bin/sync.sh" ]; then
    sh "$dir/bin/sync.sh" || FAILED="$FAILED $name"
    return 0
  fi

  if git -C "$dir" remote | grep -q .; then
    git -C "$dir" pull --rebase --autostash -q || {
      echo "  !! pull stopped in $dir — resolve it there (git status), then: git rebase --continue"
      FAILED="$FAILED $name"; return 0; }
  fi

  case $mode in
    all)  git -C "$dir" add -A ;;
    org)  git -C "$dir" add -u
          git -C "$dir" ls-files -o --exclude-standard -- '*.org' '*.bib' | while IFS= read -r f; do
            git -C "$dir" add -- "$f"; done ;;
    pull) ;;
  esac
  if [ "$mode" != pull ] && ! git -C "$dir" diff --cached --quiet; then
    if git -C "$dir" commit -q -m "sync: $STAMP on $HOST"; then echo "  committed"
    else FAILED="$FAILED $name"; return 0; fi
  fi
  if [ "$mode" != pull ] && git -C "$dir" remote | grep -q . \
     && [ -n "$(git -C "$dir" log '@{u}..' --oneline 2>/dev/null)" ]; then
    git -C "$dir" push -q && echo "  pushed" || FAILED="$FAILED $name"
  else
    echo "  up to date"
  fi
}

# (a here-document, not a pipe, so FAILED survives the loop)
while read -r path mode; do sync_repo "$path" "${mode:-all}" </dev/null; done <<EOF
$LIST
EOF

# Taskwarrior 3 syncs through the home laptop (see ~/sys_org/home_hub/overview.org). Skipped quietly where
# Taskwarrior is absent (a cluster) or has no sync server configured.
if command -v task >/dev/null 2>&1 && task _get rc.sync.server.url 2>/dev/null | grep -q .; then
  printf '\n== taskwarrior ==\n'
  if [ $DRY = 1 ]; then echo "  would run: task sync"
  else
    out=$(task sync 2>&1) || FAILED="$FAILED taskwarrior"
    echo "$out" | sed 's/^/  /'
  fi
fi

if [ -n "$FAILED" ]; then echo; echo "Needs attention:$FAILED"; exit 1; fi
echo; echo "All synced."
