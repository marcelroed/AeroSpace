#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

# Package.swift already treats warnings as errors. Passing `-Xswiftc -warnings-as-errors` as well would only change
# the command line, and the next `swift test` (or build) without it would rebuild every module
args=()
while test $# -gt 0; do
    if test "$1" = -Xswiftc && test "${2:-}" = -warnings-as-errors; then shift 2; else args+=("$1"); shift; fi
done

./generate.sh --ignore-xcodeproj
swift build "${swift_build_system_args[@]}" --build-tests "${args[@]}"

rm -rf .debug && mkdir .debug
cp -r .build/debug/aerospace .debug
cp -r .build/debug/AeroSpaceApp .debug
