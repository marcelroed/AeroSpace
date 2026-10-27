#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

periphery_args=()
while test $# -gt 0; do
    case $1 in
        # Analyze the index store of the last ./build-debug.sh instead of building (test.sh has just built)
        --skip-build) periphery_args+=(--skip-build); shift ;;
        *) echo "Unknown option $1"; exit 1 ;;
    esac
done

./format.sh

if grep -E '( Task\.init| Task\s*\{| Task\()' -r ./Sources; then
    echo "ERROR: don't use Task.init directly. Use Task.startUnstructured instead."
    exit 1
fi

./script/install-dep.sh --swiftlint
./.deps/swiftlint/swiftlint lint --quiet

./script/install-dep.sh --periphery
# Disable superfluous comments detection because it's buggy. todo: report to periphery maintainer
# Args after -- go to periphery's `swift build --build-tests`
./periphery/.build/out/Products/Debug/periphery scan --quiet \
    --strict \
    --disable-redundant-public-analysis \
    --retain-codable-properties \
    --no-superfluous-ignore-comments \
    "${periphery_args[@]}" \
    -- "${swift_build_system_args[@]}"
