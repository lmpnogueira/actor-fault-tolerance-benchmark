#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${PROJECT_DIR}/../.." && pwd)"

STATS_DIR="${ROOT_DIR}/stats"

# -----------------------------------------------------------------------------
# Stop all processes started by this script
# -----------------------------------------------------------------------------

stop_processes() {
    echo "Stopping processes..."

    if [[ -n "${STATS_PID:-}" ]] && ps -p "${STATS_PID}" >/dev/null 2>&1; then
        echo "Killing stats process (PID: ${STATS_PID})"
        kill "${STATS_PID}"
    fi

    if [[ -n "${CLIENT_PID:-}" ]] && ps -p "${CLIENT_PID}" >/dev/null 2>&1; then
        echo "Killing clients process (PID: ${CLIENT_PID})"
        kill "${CLIENT_PID}"
    fi

    if [[ -n "${CHAT_PID:-}" ]] && ps -p "${CHAT_PID}" >/dev/null 2>&1; then
        echo "Killing chats process (PID: ${CHAT_PID})"
        kill "${CHAT_PID}"
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

BENCHMARK_CONFIG="${BENCHMARK_CONFIG}" \
go run ./cmd/chatApp/main.go "${TEST_ID}" clients &
CLIENT_PID=$!

echo "Clients started (PID: ${CLIENT_PID})"

sleep 5

BENCHMARK_CONFIG="${BENCHMARK_CONFIG}" \
go run ./cmd/chatApp/main.go "${TEST_ID}" chats &
CHAT_PID=$!

echo "Chats started (PID: ${CHAT_PID})"

sleep 5

BENCHMARK_CONFIG="${BENCHMARK_CONFIG}" \
go run ./cmd/chatApp/main.go "${TEST_ID}" main &
MAIN_PID=$!

echo "Main started (PID: ${MAIN_PID})"

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