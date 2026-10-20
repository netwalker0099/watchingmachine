#!/bin/sh
# Runs every Lua test harness against this checkout. They stub the WoW API
# and load the real addon files, so they need only a Lua 5.1 interpreter:
#   LUA=/path/to/lua5.1 tests/run.sh
LUA=${LUA:-lua5.1}
REPO=$(cd "$(dirname "$0")/.." && pwd)
status=0
for t in "$REPO"/tests/test_*.lua; do
    out=$("$LUA" "$t" "$REPO" 2>&1) || status=1
    printf '%s: %s\n' "$(basename "$t")" "$(printf '%s\n' "$out" | tail -n 1)"
done
exit $status
