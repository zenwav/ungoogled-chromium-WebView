#!/usr/bin/env bash
set -euo pipefail

echo "::group::Disk before cleanup"
df -h / /mnt
echo "::endgroup::"

sudo rm -rf /usr/local/lib/android \
            /usr/local/.ghcup \
            /usr/lib/jvm \
            /usr/lib/google-cloud-sdk \
            /usr/lib/dotnet \
            /usr/share/swift \
            /opt/hostedtoolcache 2>/dev/null || true

export DEBIAN_FRONTEND=noninteractive
sudo apt-get -qq update
sudo apt-get -qq install -y ccache zstd

sudo fallocate -l 24G /mnt/swapfile
sudo chmod 600 /mnt/swapfile
sudo mkswap -f /mnt/swapfile >/dev/null
sudo swapon /mnt/swapfile

sudo mkdir -p "${UGC_WORK:-/mnt/ugc}" /mnt/ccache
sudo chown -R "$(id -u):$(id -g)" /mnt

echo "::group::Disk after cleanup"
df -h / /mnt
echo "::endgroup::"
