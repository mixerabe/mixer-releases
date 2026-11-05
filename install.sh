#!/bin/sh
# Installs Mixer's base on this Linux machine as a systemd service:
#   curl -fsSL https://downloads.mixer.ai/install.sh | sh
# (what follows `sh -s --` goes to `mixer-base install`: `| sh -s -- --listen 0.0.0.0`). It downloads the base built for
# this machine's distribution and processor, checks it against the SHA-256 below, and runs its `mixer-base install`, which
# copies it into ~/.local/share/mixer-base, writes its unit, starts it, and prints a link that pairs a device with it.
# Written for each release (scripts/site.ts) from scripts/install.sh, which names no downloads.
set -eu

# This release's download for a machine (core/base/updates.ts platformOf names them): its address and SHA-256.
download() {
  case "$1" in
    linux-x64-ubuntu-24.04) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-446/mixer-base-0.8.0-446-linux-x64-ubuntu-24.04.tar.gz' sha256='5c0649d50f8e11b585550f4a272a4d599b772a36de8c6de3272098f3045d9756' ;;
    linux-arm64-ubuntu-24.04) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-446/mixer-base-0.8.0-446-linux-arm64-ubuntu-24.04.tar.gz' sha256='5a4591ece535a7c37c86635beab95beb5ae14558a8fa354200f11bae28dbfb47' ;;
    linux-x64-debian-13) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-446/mixer-base-0.8.0-446-linux-x64-debian-13.tar.gz' sha256='93b11ae44080b6270b43615a871389af50c39fbbd8fa79a3b298262d984d4d5b' ;;
    linux-arm64-debian-13) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-446/mixer-base-0.8.0-446-linux-arm64-debian-13.tar.gz' sha256='af8ca5c176f5189fd16cbdeef0c9053fea1342e60c042ca8dff97be527efca79' ;;
    *) return 1 ;;
  esac
}

# The name of a machine's download (core/base/updates.ts linuxPlatform), from its processor (`uname -m`) and its
# os-release file.
platform_of() {
  case "$1" in
    x86_64 | amd64) arch=x64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) echo "Mixer's base isn't built for this processor ($1)." >&2; return 1 ;;
  esac
  echo "linux-$arch-$(. "$2" && echo "${ID:-}-${VERSION_ID:-}")"
}

# As root: itself, else through sudo (mixer-base install's own rule, core/base/systemd.ts asRoot).
as_root() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

main() {
  if [ "$(uname -s)" != Linux ]; then
    echo "This installs Mixer's base on Linux; on a Mac, Mixer installs it (This Mac)." >&2
    exit 1
  fi
  if [ ! -r /etc/os-release ]; then
    echo "This machine's /etc/os-release doesn't say which Linux it is." >&2
    exit 1
  fi
  platform=$(platform_of "$(uname -m)" /etc/os-release)
  if ! download "$platform"; then
    echo "Mixer's base isn't built for $platform, only for: linux-x64-ubuntu-24.04 linux-arm64-ubuntu-24.04 linux-x64-debian-13 linux-arm64-debian-13." >&2
    exit 1
  fi

  # What the base needs of its machine that it doesn't carry (the libraries its WebKit links, `mixer-base install` adds).
  needed=""
  command -v git >/dev/null 2>&1 || needed="$needed git"
  [ -x /usr/bin/unzip ] || needed="$needed unzip"
  if [ -n "$needed" ]; then
    echo "Installing$needed…"
    as_root apt-get update -qq
    as_root apt-get install -y -qq $needed
  fi

  cache="${XDG_CACHE_HOME:-$HOME/.cache}"
  mkdir -p "$cache"
  dir=$(mktemp -d "$cache/mixer-base-install.XXXXXX")
  trap 'rm -rf "$dir"' EXIT
  echo "Downloading Mixer's base for $platform…"
  curl -fL --retry 3 --progress-bar -o "$dir/base.tar.gz" "$url"
  if ! echo "$sha256  $dir/base.tar.gz" | sha256sum -c --status -; then
    echo "The download isn't what this release published (its SHA-256 differs)." >&2
    exit 1
  fi
  mkdir "$dir/base"
  tar -xzf "$dir/base.tar.gz" -C "$dir/base"
  rm "$dir/base.tar.gz"
  # What it asks (sudo's password) is asked on the terminal: this script's input may be the script itself, still read.
  if (: </dev/tty) 2>/dev/null; then
    "$dir/base/bin/mixer-base" install "$@" </dev/tty
  else
    "$dir/base/bin/mixer-base" install "$@" </dev/null
  fi
}

main "$@"
