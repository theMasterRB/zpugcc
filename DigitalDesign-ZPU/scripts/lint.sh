#!/usr/bin/env bash
# Lints every block in LINT_BLOCKS with Verilator inside the repo's Docker image.
# Together with scripts/ci.sh this reproduces CI locally. Results land in build/lint/; see them with `make lint-summary`.
set -euo pipefail

# Verilator comes from the repo Dockerfile so the runner only needs Docker, not sudo or per-tool installs
os_name=$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || uname -s)
echo "Host: $(hostname) as $(whoami), $os_name"
if ! command -v docker >/dev/null 2>&1; then
    echo "::error::Docker is not installed"
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "::error::$(whoami) cannot reach the Docker daemon (not in the docker group, or the daemon is not running)"
    docker info 2>&1 | tail -n 5
    exit 1
fi
docker version --format 'Docker client {{.Client.Version}}, server {{.Server.Version}}'

# Docker keeps its layer cache, so only the first build (or a Dockerfile change) is slow
docker build -t zpu-ci .

# Files written to the workspace must end up owned by the calling account so the next checkout can clean them.
# Rootful Docker needs --user for that; rootless/userns-remap Docker already maps container root to the calling
# account, and --user would map to an unprivileged subuid that can't write the workspace.
security=$(docker info --format '{{join .SecurityOptions " "}}')
echo "Docker security options: $security"
if echo "$security" | grep -qE 'rootless|userns'; then
    user_args=()
else
    user_args=(--user "$(id -u):$(id -g)")
fi

# ${arr[@]+...} keeps an empty array from tripping `set -u` on bash 3.2 (macOS)
docker run --rm ${user_args[@]+"${user_args[@]}"} -v "$PWD":/workspace -w /workspace zpu-ci verilator --version
docker run --rm ${user_args[@]+"${user_args[@]}"} -v "$PWD":/workspace -w /workspace zpu-ci make lint
