#!/bin/sh
# install-laptop — connect a laptop that is NOT the home laptop (the work laptop) to the hub.
# Idempotent. Run after install-home.sh has run on the home laptop (~/sys_org/home_hub/overview.org, step 6).
#
#   sh ~/sys_org/home_hub/bin/install-laptop.sh
#
#   * checks that it can reach the home laptop over Tailscale (ssh)
#   * copies the Taskwarrior sync settings from it (~/.taskrc.sync) and includes them in ~/.taskrc
#   * registers the merge drivers for lecture progress and Timewarrior data
#   * creates this laptop's restic repository on the home drive and a daily backup timer
#   * a twice-daily JSON export of all tasks (task-keep)
#   * links `sync-all` into ~/.local/bin
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
say() { printf '\n== %s ==\n' "$*"; }
H="$HOME_USER@$HOME_NODE"

say "reaching the home laptop ($H)"
ssh -o BatchMode=yes -o ConnectTimeout=15 "$H" true \
  || { echo "  cannot ssh to $H — is Tailscale up here (tailscale status) and your key on the home laptop?"; exit 1; }
echo "  ok"

say "Taskwarrior"
case $(task --version 2>/dev/null) in
  3.*)
    umask 077; ssh "$H" cat .taskrc.sync > "$HOME/.taskrc.sync"; umask 022
    touch "$HOME/.taskrc"
    grep -q 'taskrc.sync' "$HOME/.taskrc" || echo "include $HOME/.taskrc.sync" >> "$HOME/.taskrc"
    echo "  sync settings copied; run 'task sync' once the old data is handled (guide, step 8)" ;;
  *) echo "  ! Taskwarrior here is $(task --version 2>/dev/null || echo 'missing') — install 3.x first (guide, step 3)" ;;
esac

say "merge drivers"
[ -f "$HOME/learning/lectures/main_lectures/tools/progress-merge.py" ] \
  && python3 "$HOME/learning/lectures/main_lectures/tools/progress-merge.py" install
TW=${TIMEWARRIORDB:-$HOME/.timewarrior}
if [ -d "$TW/.git" ]; then python3 "$HERE/timew-merge.py" install "$TW"
else echo "  ! $TW is not a git clone yet (guide, step 9)"; fi

say "backups to the home drive"
if [ -f "$RESTIC_PASSWORD_FILE" ]; then
  if ! ssh "$H" "test -f '$BACKUP_ROOT/restic/$(hostname -s)/config'"; then sh "$HERE/backup.sh" init; fi
  sh "$HERE/backup.sh" install-timer
else
  echo "  ! put the restic password in $RESTIC_PASSWORD_FILE (chmod 600), then run this again"
fi

say "twice-daily task export (task-keep)"
U=$HOME/.config/systemd/user; mkdir -p "$U"
# daily task-keep (JSON export of all tasks + sync-server DB copy), ~/sys_org/home_hub/recovery.org scenario 7
cat > "$U/task-keep.service" <<EOF
[Unit]
Description=Daily JSON export of all tasks (and a copy of the sync server database)
[Service]
Type=oneshot
ExecStart=/bin/sh $HERE/task-keep.sh
EOF
cat > "$U/task-keep.timer" <<EOF
[Unit]
Description=task-keep twice a day
[Timer]
OnCalendar=*-*-* 03:00
OnCalendar=*-*-* 12:45
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload && systemctl --user enable --now task-keep.timer && echo "  task-keep.timer enabled"

say "commands"
mkdir -p "$HOME/.local/bin"
ln -sf "$HERE/sync-all.sh" "$HOME/.local/bin/sync-all"
chmod +x "$HERE/sync-all.sh" "$HERE"/*.sh "$HERE"/*.py
echo "  sync-all -> $HERE/sync-all.sh"
echo; echo "Done. From now on: sync-all when you sit down and when you get up."
