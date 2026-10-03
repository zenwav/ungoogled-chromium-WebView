#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="ungoogled-software/ungoogled-chromium-android"
FORK_REPO="${GITHUB_REPOSITORY:-zenwav/ungoogled-chromium-WebView}"

AUTH_HEADER=()
if [ -n "${GH_TOKEN:-}" ]; then
    AUTH_HEADER=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

echo "Checking latest release in ${UPSTREAM_REPO}..."
UPSTREAM_JSON=$(curl -fsSL "${AUTH_HEADER[@]}" "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest")
LATEST_TAG=$(echo "$UPSTREAM_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')

if [ -z "$LATEST_TAG" ]; then
    echo "FATAL: Could not fetch latest upstream tag"
    exit 1
fi

echo "Latest upstream release tag: ${LATEST_TAG}"

# Check if a build is already in progress or queued on the fork
ACTIVE_RUNS=$(curl -fsSL "${AUTH_HEADER[@]}" \
    "https://api.github.com/repos/${FORK_REPO}/actions/runs?status=in_progress&status=queued" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    runs = [r for r in data.get("workflow_runs", []) if r.get("path", "").endswith("build-webview.yml") and r.get("status") in ("in_progress", "queued")]
    print(len(runs))
except Exception:
    print(0)
')

if [ "${ACTIVE_RUNS:-0}" -gt 0 ]; then
    echo "A build is currently in progress or queued on ${FORK_REPO}. Skipping to avoid duplicate runs."
    echo "new_release=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
fi

# Check if release exists on fork
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "${AUTH_HEADER[@]}" \
    "https://api.github.com/repos/${FORK_REPO}/releases/tags/${LATEST_TAG}")

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "Release ${LATEST_TAG} already exists on ${FORK_REPO}. Nothing to build."
    echo "new_release=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
elif [ "$HTTP_STATUS" -eq 404 ]; then
    echo "New upstream release detected: ${LATEST_TAG}"
    echo "new_release=true" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "upstream_tag=${LATEST_TAG}" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
else
    echo "FATAL: GitHub API returned unexpected HTTP status ${HTTP_STATUS} when querying ${FORK_REPO}"
    echo "new_release=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 1
fi
