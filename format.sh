#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

./script/install-dep.sh --swiftformat
# Explicit paths: `.` would descend into .claude/worktrees (agent worktrees, full repo copies)
./.deps/swiftformat/swiftformat Sources Package.swift
