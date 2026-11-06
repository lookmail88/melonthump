#!/bin/zsh
# Promo-gate acceptance (2026-11-06): drives the PRODUCTION
# CreditWallet.swift through fresh install → promo freebies → promo
# session gate → relaunch, plus upgrade / free-day / post-promo cases.
# Each "launch" is a separate process (a real relaunch: in-memory
# session unlock lost, UserDefaults kept). macOS, no device, no network.
set -e
here=${0:A:h}
ios=$here/../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcrun swiftc -swift-version 5 -o $out/promo-gate-harness \
  $here/stub.swift $ios/MelonThump/CreditWallet.swift $here/main.swift
h=$out/promo-gate-harness
echo "== A. fresh install, promo active"
$h reset
POLICY=promo $h launch t t t:watch t t
echo "-- relaunch (count >= 2): gate re-arms"
POLICY=promo $h launch t t:watch t
echo "== B. fresh install, UNKNOWN verdicts do not use a freebie"
$h reset
POLICY=promo $h launch u u t t t
echo "== C. freebies split across launches"
$h reset
POLICY=promo $h launch t
POLICY=promo $h launch t
POLICY=promo $h launch t:watch
echo "== D. free day (-1) overrides everything; its real analyses still count"
echo "   (the 2nd launch is the same local day, so it is still a free day)"
$h reset
POLICY=freeday $h launch t t t t
POLICY=promo $h launch t
echo "== E. 1.2.0 tester upgrade (firstFreeUsed set, no counter): seeded 1"
$h reset
$h seed allowance.firstFreeUsed=true
POLICY=promo $h launch t t:watch
echo "== F. App Store 1.1.0 upgrade (no 1.2.0 flags): counter starts at 0"
$h reset
$h seed credit.welcomed=true
POLICY=promo $h launch t t t:watch
echo "== G. promo used both freebies → promo ends: no double grant"
$h reset
POLICY=promo $h launch t t
POLICY=post $h launch t t:watch
echo "== H. promo used one freebie → promo ends: 1 credit covers the 2nd"
$h reset
POLICY=promo $h launch t
POLICY=post $h launch t:credit t t:watch
echo "== I. never thumped in promo → post-promo allowance unchanged"
$h reset
POLICY=promo $h launch
POLICY=post $h launch t t:credit t
POLICY=post $h launch t t:watch t
echo "== J. policy fetch fails during promo window (fail-open defaults)"
$h reset
POLICY=fail $h launch t t t
$h reset
