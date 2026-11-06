#!/bin/zsh
# Recognition-chain diagnosis (2026-11-06): drives the PRODUCTION
# LocalAnalyzer.swift with Baby 1.0 (heuristic v2.2) parameters over
# deterministic synthetic thumps — a "clean" group (what the 600-case
# ml-equivalence harness feeds) versus a "simulated phone recording"
# group (knock excitation, heavy damping, mic high-pass, pink/rumble
# room noise, realistic levels, repeat taps) — and reports, per scenario,
# the detection pass rate, verdict distribution and which gate rejected.
# Runs on macOS, no device, no network; fixtures are generated from a
# fixed seed, so every run prints identical numbers.
#   ./run.sh                 full report (default N=300 per scenario)
#   ./run.sh 100             faster, N=100 per scenario
#   ./run.sh --wav a.wav ... analyze real recordings with Baby 1.0
#   ./run.sh --dump DIR      also write one WAV per scenario to DIR
set -e
here=${0:A:h}
ios=$here/../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcrun swiftc -O -swift-version 5 -o $out/diag \
  $here/stub.swift $ios/MelonThump/ModelFile.swift $ios/MelonThump/LocalAnalyzer.swift $here/main.swift
$out/diag "$@"
