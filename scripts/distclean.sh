#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Repository paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================================"
echo "Performing full workspace cleanup"
echo "Repository: ${REPO_ROOT}"
echo "============================================================"

clean_directory() {

    local dir="$1"

    [[ -d "${dir}" ]] || return

    echo "Cleaning ${dir}"

    find "${dir}" \
        -type f \
        ! -name ".gitkeep" \
        -delete
}

# -----------------------------------------------------------------------------
# Benchmark results
# -----------------------------------------------------------------------------

clean_directory "${REPO_ROOT}/stats/results"

# -----------------------------------------------------------------------------
# Per-implementation intermediate results
# -----------------------------------------------------------------------------

rm -rf "${REPO_ROOT}/elixir/scripts/results"
rm -rf "${REPO_ROOT}/scala-akka/scripts/results"
rm -rf "${REPO_ROOT}/go-protoactor/scripts/results"

# -----------------------------------------------------------------------------
# Generated benchmark configurations
# -----------------------------------------------------------------------------

clean_directory "${REPO_ROOT}/stats/generated_configs"

# -----------------------------------------------------------------------------
# Runtime logs
# -----------------------------------------------------------------------------

rm -rf "${REPO_ROOT}/elixir/logs"
rm -rf "${REPO_ROOT}/scala-akka/logs"
rm -rf "${REPO_ROOT}/go-protoactor/logs"

# -----------------------------------------------------------------------------
# Elixir build artefacts
# -----------------------------------------------------------------------------

rm -rf "${REPO_ROOT}/elixir/_build"
rm -rf "${REPO_ROOT}/elixir/deps"
rm -f  "${REPO_ROOT}/elixir/erl_crash.dump"

# -----------------------------------------------------------------------------
# Scala build artefacts
# -----------------------------------------------------------------------------

rm -rf "${REPO_ROOT}/scala-akka/target"
rm -rf "${REPO_ROOT}/scala-akka/project/target"

echo
echo "Workspace successfully cleaned."