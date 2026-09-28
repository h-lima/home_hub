#!/bin/sh
# backup — encrypted, deduplicated snapshots of this machine's home folder onto the external
# drive of the home laptop (restic). For the WORK laptop (and any other laptop): home folder only.
# The home laptop itself uses backup-system.sh instead (whole system + /mnt/StorageHDD, as root).
#   * restic writes over SFTP to the home laptop, through Tailscale — from
#     home or from work. When the home laptop (or its drive) is not reachable it skips quietly and
#     the timer tries again next time (Persistent=true catches up missed runs).
#
#   sh backup.sh init            # once per machine: create its repository on the drive
#   sh backup.sh                 # take a snapshot now
#   sh backup.sh snapshots       # list this machine's snapshots
#   sh backup.sh restore <snapshot|latest> <path-inside-home> <target-dir>
#   sh backup.sh prune           # HOME LAPTOP ONLY: thin every machine's snapshots (timer does it weekly)
#   sh backup.sh install-timer   # daily systemd --user timer (+ weekly prune on the home laptop)
#
# What is left out: ~/.config/restic/excludes (created with sensible defaults on first run).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
command -v restic >/dev/null || { echo "restic is not installed (Arch: pacman -S restic · Ubuntu: apt install restic)"; exit 1; }

MACHINE=$(hostname -s)
EXCLUDES=$HOME/.config/restic/excludes
export RESTIC_PASSWORD_FILE

is_home() {   # this machine is the one with the drive
  [ "${IS_HOME_LAPTOP:-}" = 1 ] && return 0
  [ "$MACHINE" = "$HOME_NODE" ] && return 0
  n=$(tailnet_name 2>/dev/null || true); [ "${n%%.*}" = "$HOME_NODE" ]
}

if is_home; then
  mountpoint -q "$BACKUP_DRIVE" || { echo "backup: $BACKUP_DRIVE is not mounted — nothing written"; exit 0; }
  REPO_BASE=$BACKUP_ROOT/restic
else
  if ! echo "ls $BACKUP_ROOT/restic" | sftp -b - -o ConnectTimeout=15 "$BACKUP_SSH_HOST" >/dev/null 2>&1; then
    echo "backup: home laptop '$HOME_NODE' or its drive not reachable (via $BACKUP_SSH_HOST) — skipped, will retry"; exit 0
  fi
  REPO_BASE=sftp:$BACKUP_SSH_HOST:$BACKUP_ROOT/restic
fi
export RESTIC_REPOSITORY="$REPO_BASE/$MACHINE"

if [ ! -f "$EXCLUDES" ]; then
  mkdir -p "$(dirname "$EXCLUDES")"
  cat > "$EXCLUDES" <<'EOF'
# restic excludes (one pattern per line; see `restic help backup`)
$HOME/.cache
$HOME/.local/share/Trash
$HOME/snap
$HOME/.npm
$HOME/py_venv
$HOME/srv
$HOME/Downloads/*.iso
**/node_modules
**/.venv
**/__pycache__
**/.ipynb_checkpoints
**/*_cache
**/.quarto
EOF
  echo "wrote default excludes to $EXCLUDES — edit it to taste"
fi

if is_home; then
  case ${1:-backup} in
    backup|init|install-timer|prune)
      echo "On the home laptop, backups are done by backup-system.sh (root): the whole system,"
      echo "your home folder and /mnt/StorageHDD. Use:  sudo backup-system run   (install: sudo sh $HERE/backup-system.sh install)"
      exit 0 ;;
  esac
fi

case ${1:-backup} in
  init)
    [ -f "$RESTIC_PASSWORD_FILE" ] || { echo "Put the restic password in $RESTIC_PASSWORD_FILE (chmod 600) first"; exit 1; }
    is_home || echo "-mkdir $BACKUP_ROOT/restic" | sftp -b - "$BACKUP_SSH_HOST" >/dev/null
    restic init ;;
  backup)
    # the list of software you installed, so a replacement laptop can be rebuilt (home-recovery.org, scenario 5)
    command -v apt-mark >/dev/null && apt-mark showmanual > "$HOME/.config/pkglist-apt.txt" 2>/dev/null || true
    restic backup "$HOME" --exclude-file="$EXCLUDES" --exclude-caches --one-file-system \
      --tag auto --host "$MACHINE" ;;
  snapshots)
    restic snapshots ;;
  restore)
    [ $# -eq 4 ] || { echo "usage: backup.sh restore <snapshot|latest> <path> <target-dir>"; exit 2; }
    restic restore "$2" --include "$3" --target "$4" ;;
  prune)
    is_home || { echo "prune runs on the home laptop only (local disk, no network)"; exit 1; }
    for r in "$BACKUP_ROOT"/restic/*/; do
      [ -f "$r/config" ] || continue
      echo "== pruning $r =="
      RESTIC_REPOSITORY=$r restic forget --keep-daily 7 --keep-weekly 8 --keep-monthly 24 --keep-yearly 5 --prune
    done ;;
  install-timer)
    U=$HOME/.config/systemd/user; mkdir -p "$U"
    cat > "$U/backup.service" <<EOF
[Unit]
Description=restic backup of $HOME to the home laptop's drive
[Service]
Type=oneshot
ExecStart=/bin/sh $HERE/backup.sh backup
Nice=10
IOSchedulingClass=idle
EOF
    cat > "$U/backup.timer" <<EOF
[Unit]
Description=Daily restic backup (01:30: at night, from home; after task-keep at 01:00)
[Timer]
OnCalendar=*-*-* 01:30
Persistent=true
RandomizedDelaySec=10min
[Install]
WantedBy=timers.target
EOF
    if is_home; then
      cat > "$U/backup-prune.service" <<EOF
[Unit]
Description=Thin old restic snapshots on the backup drive
[Service]
Type=oneshot
ExecStart=/bin/sh $HERE/backup.sh prune
EOF
      cat > "$U/backup-prune.timer" <<EOF
[Unit]
Description=Weekly restic prune
[Timer]
OnCalendar=Sun 05:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
    fi
    systemctl --user daemon-reload
    systemctl --user enable --now backup.timer
    is_home && systemctl --user enable --now backup-prune.timer
    systemctl --user list-timers | grep -E 'backup|NEXT' ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
