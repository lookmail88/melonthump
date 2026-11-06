#!/bin/zsh
# Promo-gate acceptance (2026-11-06, corrected rule): drives the
# PRODUCTION CreditWallet.swift. Promo freebies are PER APP VERSION: the
# first N (= initialFreeThumps, default 2) real analyses of each version
# skip the promo ad gate; a version change restarts the count at 0.
# Each "launch" is a separate process (a real relaunch: in-memory
# session unlock lost, UserDefaults kept). macOS, no device, no network.
#
#   L <expect> [ENV=..] launch thumps...
# <expect> is one letter per thump, checked against the wallet's decision:
#   F = no gate, promo freebie   N = no gate (other)   P = promo ad gate
#   S = post-promotion session gate   (a gate letter applies whether the
#   thump was then unlocked by :watch/:credit or declined)
# Optional 2nd arg form  L <expect> @<versionCount> ...  also checks the
# versionCount at the start of the launch. Exit status != 0 on mismatch.
set -e
here=${0:A:h}
ios=$here/../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcrun swiftc -swift-version 5 -o $out/promo-gate-harness \
  $here/stub.swift $ios/MelonThump/CreditWallet.swift $here/main.swift
h=$out/promo-gate-harness
fails=0; checks=0
L() {
  local expect=$1; shift
  local startCount=""
  if [[ $1 == @* ]]; then startCount=${1#@}; shift; fi
  local o; o=$(env "$@" | sed 's/^/    /')
  print -r -- "$o"
  local got=""
  while IFS= read -r line; do
    case $line in
      *"PROMO AD GATE"*) got+=P ;;
      *"SESSION GATE"*) got+=S ;;
      *"promo freebie"*) got+=F ;;
      *"no gate"*) got+=N ;;
    esac
  done <<< "$(print -r -- "$o" | grep 'thump#' || true)"
  checks=$((checks+1))
  if [[ $got != $expect ]]; then
    print "    ✗ FAIL: expected gates '$expect', got '$got'"; fails=$((fails+1))
  else
    print "    ✓ gates '$got'"
  fi
  if [[ -n $startCount ]]; then
    checks=$((checks+1))
    if print -r -- "$o" | grep -q "versionCount=$startCount balance"; then
      print "    ✓ start versionCount=$startCount"
    else
      print "    ✗ FAIL: expected start versionCount=$startCount"; fails=$((fails+1))
    fi
  fi
}
K() {  # K <key> <expected value>: checks a persisted key after a launch
  checks=$((checks+1))
  local v; v=$($h dump | grep "  $1 = " | sed 's/.* = //')
  if [[ $v == $2 ]]; then print "    ✓ $1 = $v"; else print "    ✗ FAIL: $1 = $v, expected $2"; fails=$((fails+1)); fi
}

echo "== A. fresh install v1.2.0, promo, default N=2: 1..2 free, 3rd gated, watch unlocks"
$h reset
L FFPNN @0 APP_VERSION=1.2.0 POLICY=promo $h launch t t t:watch t t
echo "-- relaunch same version: gate re-arms (no freebies left this version)"
L PNN @5 APP_VERSION=1.2.0 POLICY=promo $h launch t:watch t t
echo "-- relaunch, ad declined: still gated, nothing recorded"
L PP @8 APP_VERSION=1.2.0 POLICY=promo $h launch t t

echo "== B. UNKNOWN verdicts do not count"
$h reset
L FFFFP @0 POLICY=promo $h launch u u t t t

echo "== C. freebies split across launches (same version)"
$h reset
L F @0 POLICY=promo $h launch t
L F @1 POLICY=promo $h launch t
L PN @2 POLICY=promo $h launch t:watch t

echo "== D. upgrade 1.2.0 -> 1.2.1: count resets to 0, N free again, then gate returns"
$h reset
L FFP @0 APP_VERSION=1.2.0 POLICY=promo $h launch t t t:watch
L P @3 APP_VERSION=1.2.0 POLICY=promo $h launch t
L FFPN @0 APP_VERSION=1.2.1 POLICY=promo $h launch t t t:watch t
K analysis.countVersion 1.2.1
echo "-- relaunch on 1.2.1: no second reset"
L PN @4 APP_VERSION=1.2.1 POLICY=promo $h launch t:watch t
echo "-- next upgrade 1.3.0, freebies split across launches"
L F @0 APP_VERSION=1.3.0 POLICY=promo $h launch t
L FP @1 APP_VERSION=1.3.0 POLICY=promo $h launch t t

echo "== E. N=1 (server initialFreeThumps=1)"
$h reset
L FPN @0 APP_VERSION=1.2.0 FREE=1 POLICY=promo $h launch t t:watch t
L P @3 APP_VERSION=1.2.0 FREE=1 POLICY=promo $h launch t:watch
echo "-- upgrade with N=1: exactly one free again"
L FP @0 APP_VERSION=1.2.1 FREE=1 POLICY=promo $h launch t t:watch

echo "== F. N=3 (server initialFreeThumps=3)"
$h reset
L FFFPN @0 APP_VERSION=1.2.0 FREE=3 POLICY=promo $h launch t t t t:watch t
echo "-- upgrade with N=3: three free again"
L FFFP @0 APP_VERSION=1.2.1 FREE=3 POLICY=promo $h launch t t t t:watch

echo "== G. N retuned mid-version: count 2 under N=2 is gated; N=3 grants the 3rd"
$h reset
L FFP @0 FREE=2 POLICY=promo $h launch t t t
L FP @2 FREE=3 POLICY=promo $h launch t t
echo "-- N=0: no freebies at all, gate on the very first thump"
$h reset
L P @0 FREE=0 POLICY=promo $h launch t

echo "== H. free day (-1) overrides everything; its real analyses still count this version"
$h reset
L NNNN @0 POLICY=freeday $h launch t t t t
echo "   (same local day → still a free day on relaunch)"
L NN @4 POLICY=freeday $h launch t t
echo "-- free day on a fresh version overrides the freebies too (count still advances)"
$h reset
L NN @0 APP_VERSION=1.2.1 POLICY=freeday $h launch t t

echo "== I. transition from the 413210d lifetime counter: discarded, version count starts at 0"
$h reset
$h seed analysis.lifetimeCount=7 allowance.promoFreebiesUsed=2
L FFP @0 APP_VERSION=1.2.0 POLICY=promo $h launch t t t
K analysis.lifetimeCount '<absent>'
K allowance.promoFreebiesUsed '<absent>'
echo "-- App Store 1.1.0 upgrader (no counter keys at all): starts at 0 too"
$h reset
$h seed credit.welcomed=true
L FFP @0 POLICY=promo $h launch t t t

echo "== J. promo used both freebies -> promo ends (same version): full post-promo allowance"
echo "   (promo freebies do not touch firstFreeUsed or the credit grant: first free + 1 credit)"
$h reset
L FF @0 POLICY=promo $h launch t t
K allowance.firstFreeUsed '<absent>'
L NSN @2 POLICY=post $h launch t t:credit t
K credit.balance 0
L SN @5 POLICY=post $h launch t:watch t
echo "-- post-promo after an upgrade: allowance is per install, NOT re-granted"
L S @0 APP_VERSION=1.2.1 POLICY=post $h launch t
K credit.balance 0

echo "== K. promo used one freebie -> promo ends: allowance still the full first free + 1 credit"
$h reset
L F @0 POLICY=promo $h launch t
L NSN @1 POLICY=post $h launch t t:credit t
K credit.balance 0

echo "== L. never thumped in promo -> post-promo allowance unchanged"
$h reset
L "" @0 POLICY=promo $h launch
L NSN @0 POLICY=post $h launch t t:credit t
L SN @3 POLICY=post $h launch t:watch t

echo "== M. post-promo analyses count toward this version's promo freebies (promo window re-opens)"
$h reset
L N @0 POLICY=post $h launch t
L FP @1 POLICY=promo $h launch t t

echo "== N. policy fetch fails during the promo window (fail-open: no promo known, built-in N=2)"
$h reset
L NSS @0 POLICY=fail $h launch t t t

$h reset
echo
if (( fails )); then print "RESULT: $fails of $checks checks FAILED"; exit 1; fi
print "RESULT: all $checks checks passed"
