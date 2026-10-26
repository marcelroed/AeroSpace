#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

# By default, an XCTest assertion (XCTAssert*, XCTFail) inside a Swift Testing @Test is only a warning, and the test passes.
# Report it as a failure instead
export SWIFT_TESTING_XCTEST_INTEROP_MODE=complete

# Swift Testing prints only the file name of an issue:
#     ✘ Test testFoo() recorded an issue at FooTest.swift:12:5: Expectation failed: 1 == 2
# Rewrite it to the full path, so that vim can jump to it (all file names in Sources are unique):
#     /path/to/AeroSpace/Sources/AppBundleTests/FooTest.swift:12:5: error: testFoo(): Expectation failed: 1 == 2
swift-testing-issues-to-full-paths() {
    awk -v root="$PWD" '
        BEGIN {
            while (("find \"" root "/Sources\" -name \"*.swift\"" | getline path) > 0) {
                fileName = path
                sub(/.*\//, "", fileName)
                fullPath[fileName] = path
            }
        }
        /^[^ ]+ Test .* recorded (an issue|a warning)/ && match($0, / at [^ :]+\.swift:[0-9]+:[0-9]+: /) {
            location = substr($0, RSTART + 4, RLENGTH - 6) # FooTest.swift:12:5
            fileName = location
            sub(/:.*/, "", fileName)
            if (fileName in fullPath) {
                test = substr($0, 1, RSTART - 1)
                severity = (test ~ / recorded a warning/) ? "warning" : "error"
                sub(/^[^ ]+ Test /, "", test)
                sub(/ recorded (an issue|a warning)/, "", test)
                print fullPath[fileName] substr(location, length(fileName) + 1) ": " severity ": " test ": " substr($0, RSTART + RLENGTH)
                next
            }
        }
        { print }
    '
}

# 1. XCTest: drop the "started" and "passed" lines
# 2. Swift Testing: drop the "started" and "passed" lines (but keep the summary and passed tests with warnings), and the preamble
# 3. Replace colons with semicolons in dates to avoid treating these lines as files in vim
if swift test "${swift_build_system_args[@]}" "$@" \
    | sed -E '/^Test (Suite|Case).*(started|passed)/d' \
    | sed -E '/^[[:space:]]+Executed.*with 0 failures/d' \
    | sed -E -e '/^✔ Test run with /b' -e '/^✔ (Suite|Test) .* passed after [0-9.]+ seconds\.$/d' \
    | sed -E '/^◇ .* started\.$/d' \
    | sed -E '/^↳ (Testing Library Version|Target Platform): /d' \
    | sed -E '/ [[:digit:]]+(:[[:digit:]]+)+/s/:/;/g' \
    | swift-testing-issues-to-full-paths
then
    echo "✅ Swift tests have passed successfully"
else
    echo "❌ Swift tests have failed"
    exit 1
fi
