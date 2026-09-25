#!/bin/sh
# backup-clusters — copy your data from HPC clusters to the home laptop's drive.
#
#   sh backup-clusters.sh            # every cluster in ~/.config/home-server/clusters
#   sh backup-clusters.sh bcb        # only the entries whose name is "bcb"
#
# ~/.config/home-server/clusters, one line per folder to keep:
#   <name>   <ssh-host from ~/.ssh/config>   <remote path>
#   bcb      bcb_cluster                     /home/hlima/projects
#   bcb      bcb_cluster                     /scratch/hlima/results
#
# Where the copy goes depends on the machine you run it on, so it works whichever machine can
# reach the cluster (many clusters only accept logins from the institute's network):
#   * home laptop: straight to  $BACKUP_ROOT/clusters/<name>/<path>   (files deleted on the
#     cluster are not deleted here: they move to $BACKUP_ROOT/clusters/<name>/.deleted/<date>/)
#   * any other machine: to  ~/cluster-mirror/<name>/<path>, which that machine's restic backup
#     (backup.sh) then carries to the drive — encrypted, deduplicated, with history.
# Clusters are never written to. Big regenerable things are skipped (see EXCL below).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/config.sh"
LIST=$HOME/.config/home-server/clusters
[ -f "$LIST" ] || { echo "no $LIST yet — see the header of this script"; exit 1; }
command -v rsync >/dev/null || { echo "rsync is not installed"; exit 1; }

if mountpoint -q "$BACKUP_DRIVE" 2>/dev/null; then DEST=$BACKUP_ROOT/clusters; LOCAL_DRIVE=1
else DEST=$HOME/cluster-mirror; LOCAL_DRIVE=0; fi
TODAY=$(date +%F)
EXCL="--exclude=.cache/ --exclude=__pycache__/ --exclude=.venv/ --exclude=*.sif --exclude=core.*"
FAILED=""

while read -r name host path; do
  case $name in ''|\#*) continue ;; esac
  [ -n "${1:-}" ] && [ "$1" != "$name" ] && continue
  sub=$(echo "$path" | sed 's|^/||')
  target=$DEST/$name/$sub
  mkdir -p "$target"
  echo "== $name: $host:$path -> $target =="
  if [ $LOCAL_DRIVE = 1 ]; then
    extra="--delete --backup --backup-dir=$DEST/$name/.deleted/$TODAY/$sub"
  else
    extra="--delete"
  fi
  # shellcheck disable=SC2086
  rsync -aH --partial --info=stats1 -e "ssh -o BatchMode=yes -o ConnectTimeout=20" \
        $EXCL $extra "$host:$path/" "$target/" </dev/null \
    || { echo "  !! $host not reachable from $(hostname -s) (or rsync failed) — try from a machine that can log in to it"; FAILED="$FAILED $name:$path"; }
done < "$LIST"

[ -z "$FAILED" ] || { echo; echo "Not copied:$FAILED"; exit 1; }
