#!/bin/zsh
# Reveal timing acceptance (2.1 reveal animation, TASK-REVEAL): drives the
# PRODUCTION ios/MelonThump/RevealAnimation.swift RevealTiming.remaining
# function that TapView.analyze() uses to hold the analyzing page for the
# 1.2 s minimum on success. macOS, no device. Exit status != 0 on any
# failure.
#   ./run.sh
set -e
here=${0:A:h}
ios=$here/../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcrun swiftc -swift-version 5 -o $out/harness \
  $ios/MelonThump/RevealAnimation.swift $here/main.swift
$out/harness
