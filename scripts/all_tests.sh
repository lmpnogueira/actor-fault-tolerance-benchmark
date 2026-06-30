#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Repository paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMPLEMENTATIONS=(
    "elixir"
    "scala-akka"
    "go-protoactor"
)

echo "============================================================"
echo "Running benchmark campaigns"
echo "Repository: ${REPO_ROOT}"
echo "============================================================"

run_benchmark() {

    local implementation="$1"

    local implementation_dir="${REPO_ROOT}/${implementation}"
    local benchmark_script="${implementation_dir}/scripts/run_benchmark.sh"

    echo
    echo "------------------------------------------------------------"
    echo "Implementation: ${implementation}"
    echo "------------------------------------------------------------"

    if [[ ! -d "${implementation_dir}" ]]; then
        echo "Directory not found: ${implementation_dir}"
        return 1
    fi

    if [[ ! -x "${benchmark_script}" ]]; then
        echo "Benchmark script not found or not executable:"
        echo "  ${benchmark_script}"
        return 1
    fi

    (
        cd "${implementation_dir}/scripts"
        ./run_benchmark.sh
    )
}

for implementation in "${IMPLEMENTATIONS[@]}"; do
    run_benchmark "${implementation}"
done

echo
echo "============================================================"
echo "All benchmark campaigns completed successfully."
echo "============================================================"