#!/bin/zsh
# Recorder readiness acceptance (2.0.1 hotfix, TASK-201): drives the
# PRODUCTION ios/MelonThump/RecorderReadiness.swift predicate that
# AudioRecorder checks before ANY AVAudioFile / installTap call
# (installTap raises an uncatchable NSException on a 0 Hz / 0-channel
# input). macOS, no device. Exit status != 0 on any failure.
#   ./run.sh
set -e
here=${0:A:h}
ios=$here/../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcrun swiftc -swift-version 5 -o $out/harness \
  $here/stub.swift $ios/MelonThump/RecorderReadiness.swift $here/main.swift
$out/harness
