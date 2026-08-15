#!/usr/bin/env bash

set -euo pipefail

PORT="${1:-8000}"
LISTENER_PID=""
LISTENER_COMMAND=""

if command -v lsof >/dev/null 2>&1; then
  LISTENER_PID="$(lsof -nP -tiTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
  if [[ -n "${LISTENER_PID}" ]]; then
    LISTENER_COMMAND="$(ps -p "${LISTENER_PID}" -o command= 2>/dev/null || true)"
  fi
fi

icp network stop 2>/dev/null || true

for _ in {1..5}; do
  if [[ -z "${LISTENER_PID}" ]] || ! kill -0 "${LISTENER_PID}" 2>/dev/null; then
    exit 0
  fi
  sleep 1
done

if [[ "${LISTENER_COMMAND}" != *"/icp-cli/"*"/pocket-ic"* ]]; then
  echo "Port ${PORT} is held by a process not recognized as ICP CLI PocketIC." >&2
  exit 1
fi

CURRENT_LISTENER="$(lsof -nP -tiTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
if [[ "${CURRENT_LISTENER}" != "${LISTENER_PID}" ]]; then
  echo "Port ${PORT} changed owner; refusing to terminate it." >&2
  exit 1
fi

echo "ICP CLI left PocketIC ${LISTENER_PID} running; sending TERM." >&2
kill -TERM "${LISTENER_PID}"

for _ in {1..10}; do
  if ! kill -0 "${LISTENER_PID}" 2>/dev/null; then
    exit 0
  fi
  sleep 1
done

echo "PocketIC ${LISTENER_PID} did not stop after TERM." >&2
exit 1
