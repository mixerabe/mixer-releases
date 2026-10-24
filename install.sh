#!/bin/sh
# Installs Mixer's base on this Linux machine as a systemd service:
#   curl -fsSL https://downloads.mixer.ai/install.sh | sh
# (what follows `sh -s --` goes to `mixer-base install`: `| sh -s -- --listen 0.0.0.0`). It downloads the base built for
# this machine's distribution and processor, checks it against the SHA-256 below, and runs its `mixer-base install`, which
# copies it into ~/.local/share/mixer-base, writes its unit, starts it, and prints a link that pairs a device with it.
# Written for each release (dev/scripts/site.ts) from dev/scripts/install.sh, which names no downloads.
set -eu

# This release's download for a machine (core/base/updates.ts platformOf names them): its address and SHA-256.
download() {
  case "$1" in
    linux-x64-ubuntu-24.04) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-393/mixer-base-0.8.0-393-linux-x64-ubuntu-24.04.tar.gz' sha256='3405aa2dec1fd0219f7b5f24b7d0e00e28ae06cc9984446c9a89c2e783a56663' ;;
    linux-arm64-ubuntu-24.04) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-393/mixer-base-0.8.0-393-linux-arm64-ubuntu-24.04.tar.gz' sha256='6996a738ad84eba26fee52cdf02dd7d60778dff73aaab0bde846cc75fb574288' ;;
    linux-x64-debian-13) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-393/mixer-base-0.8.0-393-linux-x64-debian-13.tar.gz' sha256='9371549c2d9fe29810e27aca979c60401419ba167871b3855af64ee5006ddeea' ;;
    linux-arm64-debian-13) url='https://github.com/mixerabe/mixer-releases/releases/download/v0.8.0-393/mixer-base-0.8.0-393-linux-arm64-debian-13.tar.gz' sha256='7d49467361ee83e59de93b2362f2f820eba553a865fda2dc92f5792e02b2ed4e' ;;
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
