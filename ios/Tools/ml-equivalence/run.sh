#!/bin/zsh
# Proves the .ml loader rules (docs/ml-format.md) and that Standard
# loaded from the bundled standard.ml is bit-for-bit heuristic v2.4.
# v24-reference.swift is a frozen copy of LocalAnalyzer.swift plus the
# Standard parameter set from ModelFile.swift as of commit df9dd0d (the
# shipped v2.4), with only the type names renamed (see its header).
# Any later production change fails section 4 until deliberately
# re-frozen. Runs on macOS, no device.
#   ./run.sh [trials]     (default 600)
set -e
here=${0:A:h}
ios=$here/../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcrun swiftc -O -swift-version 5 -o $out/harness \
  $here/stub.swift $here/v24-reference.swift \
  $ios/MelonThump/ModelFile.swift $ios/MelonThump/LocalAnalyzer.swift $here/main.swift
$out/harness $ios/MelonThump/Models/standard.ml ${1:-600}
