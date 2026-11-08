#!/bin/sh
# Runs every Lua test harness against this checkout. They stub the WoW API
# and load the real addon files, so they need only a Lua 5.1 interpreter:
#   LUA=/path/to/lua5.1 tests/run.sh
# On GitHub Actions, each failing check (and any error) is also written as an
# annotation, so it shows on the run's page without opening the log.
LUA=${LUA:-lua5.1}
REPO=$(cd "$(dirname "$0")/.." && pwd)
status=0
for t in "$REPO"/tests/test_*.lua; do
    name=$(basename "$t")
    if out=$("$LUA" "$t" "$REPO" 2>&1); then ok=1; else ok=0; status=1; fi
    printf '%s: %s\n' "$name" "$(printf '%s\n' "$out" | tail -n 1)"
    if [ "$ok" = 0 ]; then
        printf '%s\n' "$out" | grep -E '^FAIL|error|lua' | head -n 20 | while IFS= read -r line; do
            printf '  %s\n' "$line"
            if [ -n "$GITHUB_ACTIONS" ]; then printf '::error title=%s::%s\n' "$name" "$line"; fi
        done
    fi
done
exit $status
