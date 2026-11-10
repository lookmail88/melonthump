#!/bin/zsh
# Proves the .ml loader rules (docs/ml-format.md) and that Standard
# loaded from the bundled standard.ml is bit-for-bit heuristic v2.2.
# v22-reference.swift is LocalAnalyzer.swift as of commit 504dcff (the
# shipped v2.2), with only the enum renamed. Runs on macOS, no device.
#   ./run.sh [trials]     (default 600)
set -e
here=${0:A:h}
ios=$here/../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcrun swiftc -O -swift-version 5 -o $out/harness \
  $here/stub.swift $here/v22-reference.swift \
  $ios/MelonThump/ModelFile.swift $ios/MelonThump/LocalAnalyzer.swift $here/main.swift
$out/harness $ios/MelonThump/Models/standard.ml ${1:-600}
