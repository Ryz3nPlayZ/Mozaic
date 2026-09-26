#!/usr/bin/env bash
# Reset Mozaic: kill running instances, build, package, relaunch, verify.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${ROOT_DIR}/.build/app/Mozaic.app"
APP_PROCESS_PATTERN="Mozaic.app/Contents/MacOS/Mozaic"
DEBUG_PROCESS_PATTERN="${ROOT_DIR}/.build/debug/Mozaic"
RELEASE_PROCESS_PATTERN="${ROOT_DIR}/.build/release/Mozaic"
LOCK_KEY="$(printf '%s' "${ROOT_DIR}" | shasum -a 256 | cut -c1-8)"
LOCK_DIR="${TMPDIR:-/tmp}/mozaic-compile-and-run-${LOCK_KEY}"
LOCK_PID_FILE="${LOCK_DIR}/pid"
WAIT_FOR_LOCK=0
RUN_TESTS=0
RUN_LINT=0
BUILD_CONFIG="release"

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

run_step() {
  local label="$1"; shift
  log "==> ${label}"
  if ! "$@"; then
    fail "${label} failed"
  fi
}

cleanup() {
  if [[ -d "${LOCK_DIR}" ]]; then
    rm -rf "${LOCK_DIR}"
  fi
}

acquire_lock() {
  while true; do
    if mkdir "${LOCK_DIR}" 2>/dev/null; then
      echo "$$" > "${LOCK_PID_FILE}"
      return 0
    fi

    local existing_pid=""
    if [[ -f "${LOCK_PID_FILE}" ]]; then
      existing_pid="$(cat "${LOCK_PID_FILE}" 2>/dev/null || true)"
    fi

    if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
      if [[ "${WAIT_FOR_LOCK}" == "1" ]]; then
        log "==> Another process is compiling (pid ${existing_pid}); waiting..."
        while kill -0 "${existing_pid}" 2>/dev/null; do
          sleep 1
        done
        continue
      fi
      log "==> Another process is compiling (pid ${existing_pid}); re-run with --wait."
      exit 0
    fi

    rm -rf "${LOCK_DIR}"
  done
}

trap cleanup EXIT INT TERM

kill_all_mozaic() {
  is_running() {
    pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1 \
      || pgrep -f "${DEBUG_PROCESS_PATTERN}" >/dev/null 2>&1 \
      || pgrep -f "${RELEASE_PROCESS_PATTERN}" >/dev/null 2>&1 \
      || pgrep -x "Mozaic" >/dev/null 2>&1
  }

  # Phase 1: request termination (give the app time to exit cleanly).
  for _ in {1..25}; do
    pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -f "${DEBUG_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -f "${RELEASE_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -x "Mozaic" 2>/dev/null || true
    if ! is_running; then
      return 0
    fi
    sleep 0.2
  done

  # Phase 2: force kill any stragglers.
  pkill -9 -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
  pkill -9 -f "${DEBUG_PROCESS_PATTERN}" 2>/dev/null || true
  pkill -9 -f "${RELEASE_PROCESS_PATTERN}" 2>/dev/null || true
  pkill -9 -x "Mozaic" 2>/dev/null || true

  for _ in {1..25}; do
    if ! is_running; then
      return 0
    fi
    sleep 0.2
  done

  fail "Failed to kill all Mozaic instances."
}

# 1) Parse arguments.
for arg in "$@"; do
  case "${arg}" in
    --wait|-w) WAIT_FOR_LOCK=1 ;;
    --test|-t) RUN_TESTS=1 ;;
    --lint|-l) RUN_LINT=1 ;;
    --debug|-d) BUILD_CONFIG="debug" ;;
    --release|-r) BUILD_CONFIG="release" ;;
    --help|-h)
      log "Usage: $(basename "$0") [--wait] [--test] [--lint] [--debug|--release]"
      log "  --wait, -w    Wait if another compile is in progress"
      log "  --test, -t    Run tests before packaging"
      log "  --lint, -l    Run swiftformat and swiftlint before building"
      log "  --debug, -d   Package a debug app bundle (shows DEBUG-only settings)"
      log "  --release, -r Package a release app bundle (default)"
      exit 0
      ;;
    *)
      ;;
  esac
done

acquire_lock

# 2) Kill all running Mozaic instances.
log "==> Killing existing Mozaic instances"
kill_all_mozaic

# 3) Lint (optional).
if [[ "${RUN_LINT}" == "1" ]]; then
  run_step "swiftformat" swiftformat .
  run_step "swiftlint" swiftlint --strict
fi

# 4) Test (optional).
if [[ "${RUN_TESTS}" == "1" ]]; then
  run_step "swift test" swift test -q
fi

# 5) Package.
run_step "package app (${BUILD_CONFIG})" "${ROOT_DIR}/Scripts/build-app.sh" "${BUILD_CONFIG}"

# 6) Launch the packaged app.
log "==> Launching app"
if ! open "${APP_BUNDLE}"; then
  log "WARN: launch app returned non-zero; falling back to direct binary launch."
  "${APP_BUNDLE}/Contents/MacOS/Mozaic" >/dev/null 2>&1 &
  disown
fi

# 7) Verify the app stays up for at least a moment.
for _ in {1..10}; do
  if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1; then
    log "✅ Mozaic is running."
    exit 0
  fi
  sleep 0.4
done
fail "App exited immediately. Check crash logs in Console.app (User Reports)."
