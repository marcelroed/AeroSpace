#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

# Finds what keeps the type checker busy in a cold debug build
# Usage: script/typecheck-hotspots.sh [threshold-ms]
# Prints the type-check time per module, then every function body and expression that took at least threshold-ms
# (default 20). The full build log is .build/typecheck/build.log
# Compare body totals. Expression times nest (statements of a closure inside the closure's expression, a macro's
# expansion inside its use), so their sum counts some time more than once
#
# Swift Build prints the frontend's timing output only with -v. The separate scratch path keeps the extra flags from
# rebuilding every module on the next ./build-debug.sh

threshold_ms="${1:-20}"
scratch=.build/typecheck
rm -rf "$scratch/out" # Cold build, but keep the resolved dependencies
mkdir -p "$scratch"
if ! swift build --build-tests -v --scratch-path "$scratch" \
    -Xswiftc -Xfrontend -Xswiftc -debug-time-function-bodies \
    -Xswiftc -Xfrontend -Xswiftc -debug-time-expression-type-checking \
    > "$scratch/build.log" 2>&1
then
    tail -30 "$scratch/build.log"
    exit 1
fi

: > "$scratch/hotspots.txt"
# A line is "<time>ms<TAB><file>:<line>:<col>" for an expression, plus "<TAB><declaration>" for a function body
awk -F'\t' -v threshold="$threshold_ms" -v hotspots="$scratch/hotspots.txt" '
    !match($0, /[0-9]+\.[0-9]+ms\t/) { next }
    {
        $0 = substr($0, RSTART) # Swift Build sometimes glues the line to a task header or indents it
        ms = $1 + 0
        kind = NF >= 3 ? "body" : "expr"
        declaration = $3
        sub(/@.*/, "", declaration)
        location = $2
        sub(/:[0-9]+$/, "", location) # Drop the column
        # AppBundle/model/Rect.swift:35, or the file name of a generated file in .build: test_entry_point.swift:519
        if (!sub(/.*\/Sources\//, "", location)) sub(/.*\//, "", location)
        if (match(declaration, / [A-Za-z0-9_]+\.\(file\)/)) { # instance method AppBundle.(file).Rect.contains
            module = substr(declaration, RSTART + 1, RLENGTH - 8)
        } else if (match($2, /\/Sources\/[^\/]+\//)) {
            module = substr($2, RSTART + 9, RLENGTH - 10)
        } else if (match($2, /\/[^\/]+-[pt]\.build\//)) { # .../AppBundleTests-p.build/DerivedSources/...
            module = substr($2, RSTART + 1, RLENGTH - 10)
        } else if (match($2, /__swiftmacro_[0-9]+/)) { # Macro expansion: @__swiftmacro_6Common...
            module = substr($2, RSTART + RLENGTH, substr($2, RSTART + 13, RLENGTH - 13) + 0)
        } else {
            module = "?"
        }
        total[module " " kind] += ms
        if (ms >= threshold) printf "%6d ms %s %s %s\n", ms, kind, location, declaration > hotspots
    }
    END {
        for (key in total) if (total[key] >= 5) printf "%s: %.2f s\n", key, total[key] / 1000
    }
' "$scratch/build.log" | sort
echo
echo "Function bodies and expressions that took at least $threshold_ms ms:"
sort -rn "$scratch/hotspots.txt"
