#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONFIG_DIR="${ROOT_DIR}/stats/generated_configs"

TEST_REPEATS=3
WAIT_SECS_ITER=20

CONFIG_FILES=("${CONFIG_DIR}"/*.yml)
FILES_COUNT=${#CONFIG_FILES[@]}

# -----------------------------------------------------------------------------
# Kill benchmark-related processes
# -----------------------------------------------------------------------------

kill_associated_processes() {

    echo "Cleaning benchmark processes..."

    pkill -f "main.py" 2>/dev/null || true
    # Only target this benchmark's sbt/app invocation, never every JVM on the machine.
    pkill -f "runMain App" 2>/dev/null || true
}

echo "============================================================"
echo "Running benchmark (${FILES_COUNT} configurations)"
echo "============================================================"

for CONFIG_FILE in "${CONFIG_FILES[@]}"; do

    [[ -f "${CONFIG_FILE}" ]] || continue

    echo
    echo "------------------------------------------------------------"
    echo "Configuration: $(basename "${CONFIG_FILE}")"
    echo "------------------------------------------------------------"

    for ((i = 1; i <= TEST_REPEATS; i++)); do

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