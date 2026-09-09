#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
echo "Running host-safe acuKids regression suite (no root or system-path writes)."
for test_file in "$repo_root"/tests/test_*.sh; do
  bash "$test_file"
done
if command -v shellcheck >/dev/null 2>&1; then
  echo "ShellCheck: available (covered by test_host_safe.sh)."
else
  echo "ShellCheck: unavailable; syntax and behavioral tests still ran, but ShellCheck findings are deferred."
fi
echo "Host-safe suite: OK"
