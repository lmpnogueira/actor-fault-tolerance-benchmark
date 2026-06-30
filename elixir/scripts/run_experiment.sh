#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${PROJECT_DIR}/../.." && pwd)"

STATS_DIR="${ROOT_DIR}/stats"
CHAT_APP="${PROJECT_DIR}/_build/dev/rel/chat_app/bin/chat_app"

# -----------------------------------------------------------------------------
# Stop all processes started by this script
# -----------------------------------------------------------------------------

stop_processes() {
    echo "Stopping processes..."

    if [[ -n "${STATS_PID:-}" ]] && ps -p "${STATS_PID}" >/dev/null 2>&1; then
        echo "Killing stats process (PID: ${STATS_PID})"
        kill "${STATS_PID}"
    fi

    if [[ -n "${SERVERS_PID:-}" ]] && ps -p "${SERVERS_PID}" >/dev/null 2>&1; then
        echo "Killing servers process (PID: ${SERVERS_PID})"
        kill "${SERVERS_PID}"
    fi

    if [[ -n "${CLIENTS_PID:-}" ]] && ps -p "${CLIENTS_PID}" >/dev/null 2>&1; then
        echo "Killing clients process (PID: ${CLIENTS_PID})"
        kill "${CLIENTS_PID}"
    fi

    if [[ -n "${MAIN_PID:-}" ]] && ps -p "${MAIN_PID}" >/dev/null 2>&1; then
        echo "Killing main process (PID: ${MAIN_PID})"
        kill "${MAIN_PID}"
    fi

    echo "All processes terminated"
}

trap stop_processes EXIT
trap "exit 130" INT

# -----------------------------------------------------------------------------
# Check arguments
# -----------------------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <config.yml>"
    exit 1
fi

BENCHMARK_CONFIG="$1"

if [[ ! -f "${BENCHMARK_CONFIG}" ]]; then
    echo "Configuration file not found: ${BENCHMARK_CONFIG}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Generate test identifier
# -----------------------------------------------------------------------------

TEST_ID=$(date +%s | tail -c 8)$(head -c 8 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 3)

echo "============================================================"
echo "Running benchmark experiment"
echo "Configuration : ${BENCHMARK_CONFIG}"
echo "Test ID       : ${TEST_ID}"
echo "============================================================"

cd "${PROJECT_DIR}"

start_node() {
    local role="$1"
    local node="$2"

    export RELEASE_DISTRIBUTION=name
    export RELEASE_NODE="${node}@127.0.0.1"
    export RELEASE_COOKIE=123

    TEST_ID="${TEST_ID}" \
    ROLE="${role}" \
    BENCHMARK_CONFIG="${BENCHMARK_CONFIG}" \
    "${CHAT_APP}" start &

    echo $!
}

SERVERS_PID=$(start_node servers servers)
echo "Servers started (PID: ${SERVERS_PID})"

sleep 5

CLIENTS_PID=$(start_node clients clients)
echo "Clients started (PID: ${CLIENTS_PID})"

sleep 5

MAIN_PID=$(start_node main main)
echo "Main node started (PID: ${MAIN_PID})"

sleep 90

cd "${SCRIPT_DIR}"

if [[ ! -d "${STATS_DIR}/venv" ]]; then
    echo "Python virtual environment not found:"
    echo "  ${STATS_DIR}/venv"
    exit 1
fi

# shellcheck disable=SC1091
source "${STATS_DIR}/venv/bin/activate"

python3 "${STATS_DIR}/main.py" \
    "${TEST_ID}" \
    "${BENCHMARK_CONFIG}" &

STATS_PID=$!

echo "Statistics started (PID: ${STATS_PID})"

wait "${STATS_PID}"

echo "Statistics completed."