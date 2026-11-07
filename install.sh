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
    linux-x64-ubuntu-24.04) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-470/mixer-base-0.8.0-470-linux-x64-ubuntu-24.04.tar.gz' sha256='6184f71683837263f957322d4f8a7d06b8e86bc0dc8bf238f14b0e472686d4e9' ;;
    linux-arm64-ubuntu-24.04) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-470/mixer-base-0.8.0-470-linux-arm64-ubuntu-24.04.tar.gz' sha256='3f70820ca7a42f94c28dd903d9f2168ae278265303a29f7265da08c34a985aed' ;;
    linux-x64-debian-13) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-470/mixer-base-0.8.0-470-linux-x64-debian-13.tar.gz' sha256='ed84e2cd421154e74ab1a3f072d4604092a21561d867d9f37b013387b82d4137' ;;
    linux-arm64-debian-13) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-470/mixer-base-0.8.0-470-linux-arm64-debian-13.tar.gz' sha256='4697042214dad1c37b694093776d841ff2e5fbaf88d7f21eb013c2e692c96a2c' ;;
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
