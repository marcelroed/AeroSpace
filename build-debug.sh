#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

./generate.sh --ignore-xcodeproj
swift build "${swift_build_system_args[@]}" --build-tests "$@"

rm -rf .debug && mkdir .debug
cp -r .build/debug/aerospace .debug
cp -r .build/debug/AeroSpaceApp .debug
