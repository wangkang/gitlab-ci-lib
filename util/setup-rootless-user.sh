#!/bin/bash
set -eo pipefail

root_or_sudoer_or_exit() {
  if [[ $EUID -ne 0 ]]; then
    if ! sudo -n true 2>/dev/null; then
      echo "This script must be run as root or sudoer."
      exit 88
    fi
  fi
}

install_dependencies() {
  local dependencies=(
    "iptables"
    "uidmap"
    "slirp4netns"
    "dbus-user-session"
    "fuse-overlayfs"
  )
  if dpkg -s "${dependencies[@]}" >/dev/null 2>&1; then
    echo "Dependencies are already installed."
    return
  fi
  apt update
  apt list --upgradable
  apt upgrade -y
  apt full-upgrade -y
  apt install -y "${dependencies[@]}"
  apt autoremove -y --purge
}

init_rootless_user_ssh() {
  local user="${1}"
  local group="${2:-${user}}"
  local dir_ssh="/home/${user}/.ssh"
  mkdir -p "${dir_ssh}"
  cp -p /root/.ssh/authorized_keys "${dir_ssh}/"
  chown "${user}:${group}" "${dir_ssh}" "${dir_ssh}/authorized_keys"
  chmod 700 "${dir_ssh}"
}

init_rootless_user() {
  local user="${1}"
  id "${user:?}" || (
    adduser --gecos "" --disabled-password "${user}"
    init_rootless_user_ssh "${user}"
    loginctl enable-linger "${user}"
  )
}

root_or_sudoer_or_exit

echo "Installing dependencies..."
install_dependencies

echo "Initializing rootless user..."
init_rootless_user "${1:?}"

echo "Done."
## The end
