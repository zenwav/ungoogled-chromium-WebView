#!/usr/bin/env bash
set -euo pipefail

_out="${GITHUB_WORKSPACE}/build-tree.tar.zst"
rm -f "$_out"

echo "::group::Packing build tree"
( cd "${UGC_WORK:-/mnt/ugc}" && tar --format=posix -cf - \
      --exclude='src/.git' \
      --exclude='build-step.log' \
      --exclude='domsubcache*.tar.gz' \
      . ) \
  | zstd -T0 -3 -o "$_out"
ls -lh "$_out" | sed 's/^/  /'
echo "::endgroup::"

df -h / /mnt
