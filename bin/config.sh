# Settings shared by every script in ~/sys_org/home_hub/bin/ (sourced, not run).
# Edit here, or override any line in ~/.config/home-server.conf (same syntax) on one machine.

# The home laptop's machine name in Tailscale (`tailscale status` shows it). MagicDNS resolves it
# from every device in the tailnet, at home or away.
HOME_NODE=${HOME_NODE:-home}
# Your user name ON THE HOME LAPTOP (the external drive is mounted under /run/media/<this>/).
HOME_USER=${HOME_USER:-archx}

# The external drive on the home laptop, and where backups go on it.
BACKUP_DRIVE=${BACKUP_DRIVE:-/run/media/archx/Toshiba_4T}
BACKUP_ROOT=${BACKUP_ROOT:-$BACKUP_DRIVE/backups}
# restic repositories:  $BACKUP_ROOT/restic/<machine>      cluster mirrors: $BACKUP_ROOT/clusters/<host>
# The restic password (one for all repositories) lives in this file on each machine, mode 600.
# KEEP A COPY IN YOUR PASSWORD MANAGER: without it the backups cannot be read.
RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}

# SSH name the work laptop's backups use: the restricted key with no passphrase (Host home-backup in ~/.ssh/config)
BACKUP_SSH_HOST=${BACKUP_SSH_HOST:-home-backup}

# GitHub account that holds the private repositories.
GITHUB_USER=${GITHUB_USER:-h-lima}

# Local ports on the home laptop (only 127.0.0.1; Tailscale publishes them to your devices).
# Numbers come from the port registry, ../ports.txt (hub range 8760-8779). Check with: ports check
LECTURES_PORT=${LECTURES_PORT:-8765}   # https://<home>.<tailnet>.ts.net/        (lecture library)
STUDY_PORT=${STUDY_PORT:-8766}         # https://<home>.<tailnet>.ts.net:8443/   (study-system site)
TASKSYNC_PORT=${TASKSYNC_PORT:-8767}   # https://<home>.<tailnet>.ts.net:10000/  (Taskwarrior sync)

# Where the home laptop keeps its read-only serving clones (separate from the copies you edit).
SRV_DIR=${SRV_DIR:-$HOME/srv}

# shellcheck disable=SC1090,SC1091
[ -f "$HOME/.config/home-server.conf" ] && . "$HOME/.config/home-server.conf"

# The home laptop's full tailnet name (home.tail1234.ts.net), when tailscale is available.
tailnet_name() {
  command -v tailscale >/dev/null 2>&1 || return 1
  tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))'
}
