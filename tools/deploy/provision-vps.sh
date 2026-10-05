#!/usr/bin/env bash
# Administrator preparation only; does not deploy or start the game.
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
  echo 'Administrator access is required to install Podman and enable swap.' >&2
  exit 77
fi
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
apt-get update
apt-get install -y --no-install-recommends podman

# Preserve existing swap. Add the approved dedicated file when less than 4 GiB
# is available; never format or overwrite an unrelated existing file.
swap_kib=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
swap_file=/swapfile-swgxr
if (( swap_kib < 4194304 )); then
  if [[ -L "$swap_file" ]]; then
    echo 'Refusing to use a symlink as the dedicated swap file.' >&2
    exit 1
  fi
  if [[ ! -e "$swap_file" ]]; then
    (umask 077; fallocate -l 4G "$swap_file")
    chmod 600 "$swap_file"
    mkswap "$swap_file"
  elif [[ ! -f "$swap_file" ]] || [[ $(blkid -p -s TYPE -o value "$swap_file" || true) != swap ]]; then
    echo 'Existing /swapfile-swgxr is not a recognized swap file; preserving it.' >&2
    exit 1
  fi
  if ! swapon --show=NAME --noheadings | awk '$1 == "/swapfile-swgxr" {found=1} END {exit !found}'; then
    swapon "$swap_file"
  fi
  if ! awk '$1 == "/swapfile-swgxr" {found=1} END {exit !found}' /etc/fstab; then
    printf '\n/swapfile-swgxr none swap sw 0 0\n' >> /etc/fstab
  fi
fi
podman --version
free -m
