#!/bin/sh
# install-home — turn the HOME laptop (Arch) into the always-on hub. Idempotent: run it again
# after changing config.sh. Read ~/sys_org/home_hub/overview.org first; it lists what to install before this.
#
#   sh ~/sys_org/home_hub/bin/install-home.sh
#
# What it sets up (all as systemd --user services, running without anyone logged in):
#   lectures-web   the lecture library with saved progress   -> https://<home>.<tailnet>.ts.net/
#   study-web      the study-system site (read-only)          -> https://<home>.<tailnet>.ts.net:8443/
#   tasksync       Taskwarrior 3 sync server                  -> https://<home>.<tailnet>.ts.net:10000/
#   home-refresh   every 10 min: pull, rebuild the site, commit phone progress, sync time/tasks
#   task-keep      daily 03:00: JSON export of every task + a consistent copy of the sync server DB
#   backup-system  (root) daily snapshot of the WHOLE laptop + /mnt/StorageHDD, weekly prune, monthly check
# Everything listens on 127.0.0.1 only; `tailscale serve` publishes it to your tailnet with HTTPS.
# Nothing is reachable from the internet.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
U=$HOME/.config/systemd/user
CONF=$HOME/.config/home-server
mkdir -p "$U" "$CONF" "$SRV_DIR"
say() { printf '\n== %s ==\n' "$*"; }
warn() { echo "  ! $*"; }

say "checking tools"
for c in git python3 tailscale task timew restic rsync; do
  command -v $c >/dev/null || { echo "  missing: $c  (see ~/sys_org/home_hub/overview.org, step 2)"; exit 1; }
done
command -v emacs  >/dev/null || warn "emacs missing: the study site cannot be built"
command -v quarto >/dev/null || warn "quarto missing: the dashboards (week, progress) will not be built"
case $(task --version 2>/dev/null) in 3.*) ;; *) echo "  Taskwarrior 3 is required (task --version)"; exit 1 ;; esac
TCSS=$(command -v taskchampion-sync-server || true)
[ -n "$TCSS" ] || warn "taskchampion-sync-server not found: Taskwarrior sync is skipped this run"
TS_NAME=$(tailnet_name) || { echo "  tailscale is not up: sudo tailscale up"; exit 1; }
echo "  this laptop in the tailnet: $TS_NAME"
[ "${TS_NAME%%.*}" = "$HOME_NODE" ] || warn "HOME_NODE in config.sh is '$HOME_NODE' but this machine is '${TS_NAME%%.*}' — fix config.sh"

say "keeping user services alive without a login"
loginctl show-user "$USER" -p Linger | grep -q yes || sudo loginctl enable-linger "$USER"

say "serving clones in $SRV_DIR (read-only copies; you keep editing ~/learning/...)"
clone() {  # $1 repo name on GitHub, $2 serving dir, $3 your working copy (its remote URL is reused)
  if [ -d "$2/.git" ]; then git -C "$2" pull --ff-only -q && echo "  $2 up to date"; return; fi
  url=$(git -C "$3" remote get-url origin 2>/dev/null || echo "git@github.com:$GITHUB_USER/$1.git")
  git clone -q "$url" "$2" && echo "  cloned $url"
}
clone study_system "$SRV_DIR/study-system" "$HOME/learning/study-system"
clone lectures "$SRV_DIR/lectures" "$HOME/learning/lectures"
[ -x "$SRV_DIR/study-system/.venv/bin/python" ] || (cd "$SRV_DIR/study-system" && sh bin/setup.sh)

say "merge drivers (progress.json, Timewarrior)"
for d in "$SRV_DIR/lectures" "$HOME/learning/lectures"; do
  [ -f "$d/main_lectures/tools/progress-merge.py" ] && python3 "$d/main_lectures/tools/progress-merge.py" install
done
TW=${TIMEWARRIORDB:-$HOME/.timewarrior}
[ -d "$TW/.git" ] && python3 "$HERE/timew-merge.py" install "$TW"

say "Taskwarrior sync credentials"
[ -f "$CONF/task-client-id" ] || python3 -c 'import uuid; print(uuid.uuid4())' > "$CONF/task-client-id"
[ -f "$CONF/task-secret" ] || { umask 077; python3 -c 'import secrets; print(secrets.token_hex(32))' > "$CONF/task-secret"; }
chmod 600 "$CONF/task-secret"
CID=$(cat "$CONF/task-client-id")
umask 077
cat > "$HOME/.taskrc.sync" <<EOF
# written by install-home.sh — the same file goes on every laptop (install-laptop.sh copies it)
sync.server.url=https://$TS_NAME:10000
sync.server.client_id=$CID
sync.encryption_secret=$(cat "$CONF/task-secret")
EOF
umask 022
touch "$HOME/.taskrc"
grep -q 'taskrc.sync' "$HOME/.taskrc" || echo "include $HOME/.taskrc.sync" >> "$HOME/.taskrc"
echo "  ~/.taskrc.sync written; ~/.taskrc includes it"

say "systemd user services"
cat > "$U/lectures-web.service" <<EOF
[Unit]
Description=Lecture library (serve.py) for the tailnet
[Service]
Environment=LIBRARY_HOSTS=$TS_NAME
ExecStart=/usr/bin/env python3 $SRV_DIR/lectures/main_lectures/html-books/serve.py --no-browser --port $LECTURES_PORT
Restart=on-failure
[Install]
WantedBy=default.target
EOF
cat > "$U/study-web.service" <<EOF
[Unit]
Description=Study-system site (static) for the tailnet
[Service]
ExecStart=/usr/bin/env python3 -m http.server $STUDY_PORT --bind 127.0.0.1 --directory $SRV_DIR/study-system/site
Restart=on-failure
[Install]
WantedBy=default.target
EOF
cat > "$U/home-refresh.service" <<EOF
[Unit]
Description=Pull, rebuild and sync what the phone sees
[Service]
Type=oneshot
ExecStart=/bin/sh $HERE/home-refresh.sh
Nice=10
EOF
cat > "$U/home-refresh.timer" <<EOF
[Unit]
Description=home-refresh every 10 minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF
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
Description=task-keep once a day
[Timer]
OnCalendar=*-*-* 03:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
UNITS="lectures-web.service study-web.service home-refresh.timer task-keep.timer"
if [ -n "$TCSS" ]; then
  mkdir -p "$HOME/.local/share/taskchampion-sync-server"
  cat > "$U/tasksync.service" <<EOF
[Unit]
Description=Taskwarrior 3 sync server (taskchampion)
[Service]
ExecStart=$TCSS --listen 127.0.0.1:$TASKSYNC_PORT --data-dir $HOME/.local/share/taskchampion-sync-server --allow-client-id $CID
Restart=on-failure
[Install]
WantedBy=default.target
EOF
  UNITS="$UNITS tasksync.service"
fi
[ -f "$SRV_DIR/study-system/site/index.html" ] || sh "$HERE/home-refresh.sh"
systemctl --user daemon-reload
# shellcheck disable=SC2086
systemctl --user enable --now $UNITS
# shellcheck disable=SC2086
systemctl --user is-active $UNITS | paste -d' ' - - - - 2>/dev/null || true

say "publishing to the tailnet (tailscale serve, HTTPS, your devices only)"
# (without sudo once you have run: sudo tailscale set --operator=$USER)
ts() { tailscale "$@" 2>/dev/null || sudo tailscale "$@"; }
ts serve --bg --https=443   "http://127.0.0.1:$LECTURES_PORT"
ts serve --bg --https=8443  "http://127.0.0.1:$STUDY_PORT"
[ -z "$TCSS" ] || ts serve --bg --https=10000 "http://127.0.0.1:$TASKSYNC_PORT"
ts serve status

say "backups (whole system + /mnt/StorageHDD, as root: backup-system.sh)"
grep -qs '^IS_HOME_LAPTOP=1' "$HOME/.config/home-server.conf" || echo 'IS_HOME_LAPTOP=1' >> "$HOME/.config/home-server.conf"
if mountpoint -q "$BACKUP_DRIVE"; then
  if [ -f "$RESTIC_PASSWORD_FILE" ] || sudo test -f /etc/restic/password; then
    sudo sh "$HERE/backup-system.sh" install
    echo "  first snapshot (long the first time): sudo backup-system run"
  else warn "no restic password yet — create $RESTIC_PASSWORD_FILE (guide step 9), then run this again"; fi
else warn "$BACKUP_DRIVE is not mounted — see step 1 of the guide (fstab), then run this again"; fi

mkdir -p "$HOME/.local/bin" && ln -sf "$HERE/sync-all.sh" "$HOME/.local/bin/sync-all"
chmod +x "$HERE"/*.sh "$HERE"/*.py

cat <<EOF

Done. On your phone (Tailscale app on, same account):
  lectures      https://$TS_NAME/
  study system  https://$TS_NAME:8443/        (the week: https://$TS_NAME:8443/notes/week.html)
Logs: journalctl --user -u lectures-web -u study-web -u home-refresh -u tasksync   ·   backups: journalctl -u backup-system -u backup-prune -u backup-check
EOF
