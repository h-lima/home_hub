#!/bin/sh
# backup-system — the HOME laptop's backup: the whole system, your home folder and /mnt/StorageHDD,
# into one encrypted restic repository on the Toshiba drive, plus everything needed to rebuild the
# laptop from nothing (~/sys_org/home_hub/recovery.org). Runs as root, because /etc, /var and /root are
# only readable by root. The work laptop keeps using backup.sh (its home folder only).
#
#   sudo sh backup-system.sh install    # copy itself to /usr/local/sbin, write config + timers (run again after edits)
#   sudo backup-system run              # manifest + snapshot now (the daily timer runs this)
#   sudo backup-system manifest         # only write the system manifest (packages, disks, boot, services)
#   sudo backup-system snapshots        # list this laptop's snapshots
#   sudo backup-system prune            # thin + check EVERY repository on the drive (weekly timer)
#   sudo backup-system check-all        # read back 10% of the data of every repository (monthly timer)
#
# What is backed up: every mounted local filesystem that holds the system (/, /boot or /efi, /home,
# /var if separate) plus EXTRA_PATHS (/mnt/StorageHDD), each with --one-file-system, so /proc, /sys,
# /run, other disks and the backup drive itself are never walked. Caches and rebuildable things are
# left out (EXCLUDES in /etc/restic/backup-system.conf).
set -eu
CONF=/etc/restic/backup-system.conf
SELF=/usr/local/sbin/backup-system

defaults() {
  BACKUP_DRIVE=/run/media/archx/Toshiba_4T
  BACKUP_ROOT=$BACKUP_DRIVE/backups
  HOME_USER=archx
  EXTRA_PATHS="/mnt/StorageHDD"
  RESTIC_PASSWORD_FILE=/etc/restic/password
  KEEP="--keep-daily 7 --keep-weekly 8 --keep-monthly 24 --keep-yearly 10"
}
defaults
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"
export RESTIC_PASSWORD_FILE
HOST=$(hostname -s)
REPO=$BACKUP_ROOT/restic/$HOST
MANIFEST=/var/backups/system-manifest
KIT=$BACKUP_ROOT/RECOVERY

need_root() { [ "$(id -u)" = 0 ] || { echo "run as root: sudo $0 $*"; exit 1; }; }
drive_ok()  { mountpoint -q "$BACKUP_DRIVE" || { echo "backup-system: $BACKUP_DRIVE is not mounted — nothing written"; exit 0; }; }
log() { echo "[backup-system] $*"; }

targets() {   # the system's own filesystems + EXTRA_PATHS, never the backup drive
  findmnt -rn -o TARGET,FSTYPE | while read -r t fs; do
    case $fs in ext2|ext3|ext4|btrfs|xfs|f2fs|vfat|jfs|reiserfs) ;; *) continue ;; esac
    case $t in /|/boot|/boot/efi|/efi|/home|/var|/usr|/opt|/srv) echo "$t" ;; esac
  done
  for p in $EXTRA_PATHS; do
    if mountpoint -q "$p" 2>/dev/null; then echo "$p"
    else echo "[backup-system] WARNING: $p is not mounted — left out of this snapshot" >&2; fi
  done
}

write_manifest() {
  umask 022; mkdir -p "$MANIFEST"; cd "$MANIFEST"
  { echo "host: $HOST"; date -Iseconds; uname -a; cat /etc/os-release 2>/dev/null
    [ -d /sys/firmware/efi ] && echo "firmware: UEFI" || echo "firmware: BIOS/legacy"
  } > system.txt
  pacman -Qqen > pkglist-native.txt 2>/dev/null || true         # official repo packages you installed
  pacman -Qqem > pkglist-aur.txt    2>/dev/null || true         # AUR / foreign packages
  pacman -Q    > pkglist-all-versions.txt 2>/dev/null || true
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS > disks-lsblk.txt
  blkid > disks-blkid.txt 2>/dev/null || true
  for d in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}'); do
    sfdisk -d "/dev/$d" > "partitions-$d.sfdisk" 2>/dev/null || rm -f "partitions-$d.sfdisk"
  done
  findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS > mounts.txt
  cp /etc/fstab fstab
  { command -v bootctl >/dev/null && bootctl status 2>/dev/null
    [ -f /boot/grub/grub.cfg ] && echo "GRUB present: /boot/grub/grub.cfg"
    command -v efibootmgr >/dev/null && efibootmgr -v 2>/dev/null
    ls /boot 2>/dev/null
  } > boot.txt || true
  systemctl list-unit-files --state=enabled --no-legend > services-system.txt || true
  uid=$(id -u "$HOME_USER" 2>/dev/null || echo 1000)
  runuser -u "$HOME_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user list-unit-files --state=enabled --no-legend \
    > services-user.txt 2>/dev/null || true
  getent passwd "$HOME_USER" > user.txt; id "$HOME_USER" >> user.txt
  crontab -l > crontab-root.txt 2>/dev/null || true
  crontab -u "$HOME_USER" -l > crontab-user.txt 2>/dev/null || true
  if command -v smartctl >/dev/null; then
    : > smart.txt
    for d in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}'); do
      h=$(smartctl -H "/dev/$d" 2>/dev/null | grep -iE 'overall-health|SMART Health Status' || true)
      echo "$d: ${h:-no SMART data}" >> smart.txt
      echo "$h" | grep -qiE 'FAIL' && log "WARNING: SMART says /dev/$d is failing — replace it and check the latest snapshot"
    done
  fi
  df -h > df.txt
  log "manifest written to $MANIFEST"
}

recovery_kit() {   # readable WITHOUT restic: instructions, the restic program, the latest manifest
  mkdir -p "$KIT/manifest-$HOST"
  cp -a "$MANIFEST/." "$KIT/manifest-$HOST/"
  cp "$(command -v restic)" "$KIT/restic-linux-$(uname -m)"
  [ -f /etc/restic/home-recovery.org ] && cp /etc/restic/home-recovery.org "$KIT/README-home-recovery.org"
  date -Iseconds > "$KIT/last-updated.txt"
}

case ${1:-run} in
  install)
    need_root "$@"
    here=$(cd "$(dirname "$0")" && pwd)
    install -m 755 "$here/backup-system.sh" "$SELF"
    mkdir -p /etc/restic && chmod 700 /etc/restic
    [ -f "$here/../recovery.org" ] && install -m 644 "$here/../recovery.org" /etc/restic/home-recovery.org
    if [ ! -f "$CONF" ]; then
      cat > "$CONF" <<EOF
# /etc/restic/backup-system.conf — read by $SELF (shell syntax)
BACKUP_DRIVE=$BACKUP_DRIVE
BACKUP_ROOT=\$BACKUP_DRIVE/backups
HOME_USER=$HOME_USER
EXTRA_PATHS="$EXTRA_PATHS"            # other disks to include, space separated
RESTIC_PASSWORD_FILE=/etc/restic/password
KEEP="$KEEP"
EOF
    fi
    if [ ! -f /etc/restic/excludes ]; then
      cat > /etc/restic/excludes <<EOF
# /etc/restic/excludes — never backed up (rebuildable, huge, or volatile)
/tmp/*
/var/tmp/*
/var/cache/*
/var/log/journal/*
/var/lib/systemd/coredump/*
/swapfile
/home/*/.cache
/home/*/.local/share/Trash
/home/*/.npm
/home/*/.cargo/registry
/home/*/.rustup/toolchains
/home/*/srv
/root/.cache
**/node_modules
**/.venv
**/__pycache__
**/.ipynb_checkpoints
**/lost+found
# /var/lib/docker        # uncomment if you run Docker and do not need its images back
EOF
    fi
    if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
      if [ -f "/home/$HOME_USER/.config/restic/password" ]; then
        install -m 600 "/home/$HOME_USER/.config/restic/password" "$RESTIC_PASSWORD_FILE"
        log "copied the restic password from /home/$HOME_USER/.config/restic/password"
      else
        echo "Put the restic password in $RESTIC_PASSWORD_FILE (chmod 600), then run install again"; exit 1
      fi
    fi
    chmod 600 "$RESTIC_PASSWORD_FILE"
    cat > /etc/systemd/system/backup-system.service <<EOF
[Unit]
Description=restic: whole home laptop + StorageHDD to the backup drive
RequiresMountsFor=$BACKUP_DRIVE
[Service]
Type=oneshot
ExecStart=$SELF run
Nice=10
IOSchedulingClass=idle
EOF
    cat > /etc/systemd/system/backup-system.timer <<EOF
[Unit]
Description=Daily whole-system backup
[Timer]
OnCalendar=*-*-* 03:30
Persistent=true
[Install]
WantedBy=timers.target
EOF
    cat > /etc/systemd/system/backup-prune.service <<EOF
[Unit]
Description=restic: thin and check every repository on the backup drive
RequiresMountsFor=$BACKUP_DRIVE
[Service]
Type=oneshot
ExecStart=$SELF prune
Nice=15
IOSchedulingClass=idle
EOF
    cat > /etc/systemd/system/backup-prune.timer <<EOF
[Unit]
Description=Weekly restic prune
[Timer]
OnCalendar=Sun 05:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
    cat > /etc/systemd/system/backup-check.service <<EOF
[Unit]
Description=restic: read back part of every repository
RequiresMountsFor=$BACKUP_DRIVE
[Service]
Type=oneshot
ExecStart=$SELF check-all
Nice=15
IOSchedulingClass=idle
EOF
    cat > /etc/systemd/system/backup-check.timer <<EOF
[Unit]
Description=Monthly restic data check
[Timer]
OnCalendar=*-*-01 06:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now backup-system.timer backup-prune.timer backup-check.timer
    # the per-user backup timer (backup.sh) is not needed on this laptop any more
    uid=$(id -u "$HOME_USER")
    runuser -u "$HOME_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user disable --now backup.timer backup-prune.timer 2>/dev/null || true
    if command -v smartctl >/dev/null; then systemctl enable --now smartd 2>/dev/null || true
    else log "tip: pacman -S smartmontools, then install again (disk health warnings)"; fi
    systemctl list-timers --no-pager | grep -E 'NEXT|backup'
    log "installed. First snapshot now: sudo $SELF run" ;;

  manifest) need_root "$@"; write_manifest ;;

  run)
    need_root "$@"; drive_ok
    write_manifest
    if [ ! -f "$REPO/config" ]; then mkdir -p "$BACKUP_ROOT/restic"; restic -r "$REPO" init; fi
    T=$(targets | sort -u | tr '\n' ' ')
    log "backing up: $T"
    # shellcheck disable=SC2086
    restic -r "$REPO" backup $T --one-file-system --exclude-file /etc/restic/excludes \
      --exclude-caches --host "$HOST" --tag system
    recovery_kit
    log "done; recovery kit refreshed in $KIT" ;;

  snapshots) need_root "$@"; restic -r "$REPO" snapshots ;;

  prune)
    need_root "$@"; drive_ok
    for r in "$BACKUP_ROOT"/restic/*/; do
      [ -f "$r/config" ] || continue
      owner=$(stat -c %U "$r")
      log "pruning $r"
      restic -r "$r" unlock 2>/dev/null || true        # removes only stale locks (a crashed run), never live ones
      # shellcheck disable=SC2086
      restic -r "$r" forget $KEEP --prune
      restic -r "$r" check
      [ "$owner" = root ] || chown -R "$owner": "$r" 2>/dev/null || true   # the work laptop writes to its repo as $owner
    done ;;

  check-all)
    need_root "$@"; drive_ok
    for r in "$BACKUP_ROOT"/restic/*/; do
      [ -f "$r/config" ] || continue
      log "reading back 10% of $r"
      restic -r "$r" unlock 2>/dev/null || true
      owner=$(stat -c %U "$r")
      restic -r "$r" check --read-data-subset=10%
      [ "$owner" = root ] || chown -R "$owner": "$r" 2>/dev/null || true
    done ;;

  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
