#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_DIR="${ROOT_DIR}/stats/generated_configs"

TEST_REPEATS=3
WAIT_SECS_ITER=20

CONFIG_FILES=("${CONFIG_DIR}"/*.yml)
FILES_COUNT=${#CONFIG_FILES[@]}

# -----------------------------------------------------------------------------
# Build the Elixir release used by run_experiment.sh
# (_build/dev/rel/chat_app/bin/chat_app)
# -----------------------------------------------------------------------------

build_release() {

    echo "Building Elixir release..."

    (
        cd "${PROJECT_DIR}"
        export MIX_ENV=dev
        mix deps.get
        mix release --overwrite
    )
}

# -----------------------------------------------------------------------------
# Kill benchmark-related processes
# -----------------------------------------------------------------------------

kill_associated_processes() {

    echo "Cleaning benchmark processes..."

    pkill -f "main.py" 2>/dev/null || true
    # Only kill this benchmark's release, never every BEAM VM on the machine.
    pkill -f "rel/chat_app/" 2>/dev/null || true
}

echo "============================================================"
echo "Running benchmark (${FILES_COUNT} configurations)"
echo "============================================================"

build_release

for CONFIG_FILE in "${CONFIG_FILES[@]}"; do

    [[ -f "${CONFIG_FILE}" ]] || continue

    echo
    echo "------------------------------------------------------------"
    echo "Configuration: $(basename "${CONFIG_FILE}")"
    echo "------------------------------------------------------------"

    for ((i=1; i<=TEST_REPEATS; i++)); do

        echo "Run ${i}/${TEST_REPEATS}"

        "${SCRIPT_DIR}/run_experiment.sh" "${CONFIG_FILE}"

        kill_associated_processes

        echo "Waiting ${WAIT_SECS_ITER} seconds..."

        sleep "${WAIT_SECS_ITER}"

    done

done

kill_associated_processes

echo
echo "Benchmark completed."