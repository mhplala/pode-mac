#!/usr/bin/env bash
# Catches duplicate keys in the L10n string tables BEFORE we build
# and ship — Swift's `[K: V]` dictionary literal SIGTRAPs on
# duplicate keys at first access, which on 0.5.28 took out the
# whole app for zh-Hans users with no warning.
#
# Greps every `private static let <lang>_<...>: [String: String] = [`
# block in L10n.swift, extracts `"key":` tokens, and fails if any
# key appears more than once within the same block.
#
# Wired into `scripts/build-dmg.sh` so a publishing build can't
# silently regress.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/Pode/Services/L10n.swift"

if [[ ! -f "$FILE" ]]; then
    echo "❌ check-l10n: cannot find $FILE"
    exit 1
fi

# awk state machine: when we enter a `[String: String] = [`
# block, we collect each `"key":` line. On `]` we check for
# duplicates inside that block and reset.
fail=0
awk '
    /private static let [a-zA-Z_]+: \[String: String\] = \[/ {
        in_block = 1
        block_name = $0
        delete seen
        delete dups
        next
    }
    in_block && /^[[:space:]]*\]/ {
        for (k in dups) {
            printf "❌ Duplicate L10n key in %s: \"%s\"\n", block_name, k
            bad++
        }
        in_block = 0
        next
    }
    in_block {
        # BSD awk (macOS) only supports 2-arg match(); we extract the
        # captured key manually with substr() instead of using m[1].
        line = $0
        while (match(line, /"[^"]+"[[:space:]]*:/)) {
            token = substr(line, RSTART, RLENGTH)
            # Strip leading `"`, trailing `":` (and any spaces before `:`).
            sub(/^"/, "", token)
            sub(/"[[:space:]]*:$/, "", token)
            if (token in seen) dups[token] = 1
            seen[token] = 1
            line = substr(line, RSTART + RLENGTH)
        }
    }
    END { exit (bad ? 1 : 0) }
' "$FILE" || fail=1

if [[ $fail -ne 0 ]]; then
    echo ""
    echo "❌ check-l10n: duplicate keys detected. Build aborted."
    echo "   Swift '[K: V]' literals SIGTRAP on duplicate keys at"
    echo "   runtime — shipping this would crash users on launch."
    exit 1
fi

echo "✅ L10n keys unique within every language block."
