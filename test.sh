#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

./build-debug.sh -Xswiftc -warnings-as-errors
# --skip-build: test and lint exactly what was just built with -warnings-as-errors.
# Building again with different args would rebuild all modules
./swift-test.sh --skip-build

./.debug/aerospace -h > /dev/null
./.debug/aerospace --help > /dev/null
./.debug/aerospace -v | grep -q "0.0.0-SNAPSHOT SNAPSHOT"
./.debug/aerospace --version | grep -q "0.0.0-SNAPSHOT SNAPSHOT"

./lint.sh --skip-build
./generate.sh
./script/check-uncommitted-files.sh

echo
echo "✅ All tests have passed successfully"
