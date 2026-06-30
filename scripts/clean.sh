#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Repository paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================================"
echo "Cleaning benchmark workspace"
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
#
# main.py writes per-run results into <impl>/scripts/results (its CWD during a
# run). These must be removed between campaigns, otherwise the aggregator would
# re-aggregate stale runs together with the new ones.
# -----------------------------------------------------------------------------

rm -rf "${REPO_ROOT}/elixir/scripts/results"
rm -rf "${REPO_ROOT}/scala-akka/scripts/results"
rm -rf "${REPO_ROOT}/go-protoactor/scripts/results"

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