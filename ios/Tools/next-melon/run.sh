#!/bin/zsh
# Next-melon acceptance (2026-11-06, 1.2): result → "Thump Another
# Melon" → next thump must behave EXACTLY like coming back by hand.
#  1. Source checks on the PRODUCTION TapView.swift / AudioRecorder.swift:
#     the button is wired to startNextMelon(), which resets every piece
#     of per-thump screen state and references no wallet / ads API.
#  2. Runtime checks on the PRODUCTION CreditWallet.swift: each scenario
#     runs twice in a fresh install — with the next-melon action (n) and
#     without it (manual return) — and the gate decisions must be
#     identical, the wallet snapshot unchanged across every n, and the
#     versionCount must move only on completed real analyses.
# macOS, no device, no network. Exit status != 0 on any failure.
set -e
here=${0:A:h}
ios=$here/../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
fails=0; checks=0
ok()   { checks=$((checks+1)); print "    ✓ $1"; }
bad()  { checks=$((checks+1)); fails=$((fails+1)); print "    ✗ FAIL: $1"; }

echo "== 1. source: TapView.startNextMelon()"
tap=$ios/MelonThump/TapView.swift
body=$(awk '/private func startNextMelon\(\)/{f=1} f{print} f&&/^    }$/{exit}' $tap)
[[ -n $body ]] && ok "startNextMelon() found" || bad "startNextMelon() not found"
grep -q 'ResultView(result: result, errorMessage: errorMessage, onAgain: startNextMelon)' $tap \
  && ok "ResultView's primary button (res.again) calls startNextMelon" || bad "ResultView not wired to startNextMelon"
for s in 'ratingPromptTask?.cancel()' 'ratingPromptTask = nil' 'if recorder.isRecording { recorder.stopRecording() }' \
         'recorder.clearLastRecording()' 'recordingStartedAt = nil' 'isAnalyzing = false' 'errorMessage = nil' \
         'showSessionGate = false' 'showPromoGate = false' 'menuOpen = false' 'menuDestination = nil' \
         'showInviteSheet = false' 'shareItem = nil' 'result = nil'; do
  print -r -- "$body" | grep -qF -- "$s" && ok "resets: $s" || bad "missing reset: $s"
done
code=$(print -r -- "$body" | sed 's://.*$::')   # comments may name them; code may not
for s in wallet CreditWallet AdsManager earnWithAd recordAnalysis refreshPolicy unlockSession toggleRecording showRewarded preload; do
  print -r -- "$code" | grep -q -- "$s" && bad "startNextMelon references $s" || ok "no $s call"
done
grep -qF 'guard !Task.isCancelled, result?.verdict == Ripeness.ripe.rawValue' $tap \
  && ok "rating prompt: cancelled task never fires" || bad "rating prompt guard lacks Task.isCancelled"
grep -qF 'ratingPromptTask = Task {' $tap && ok "rating prompt task is kept for cancellation" || bad "rating task not stored"
grep -qF 'lastRecordingURL = nil' $ios/MelonThump/AudioRecorder.swift && ok "AudioRecorder.clearLastRecording drops the take" || bad "clearLastRecording"

echo "== 2. runtime: production CreditWallet, with vs without the next-melon action"
xcrun swiftc -swift-version 5 -o $out/next-melon-harness \
  $ios/Tools/promo-gate/stub.swift $ios/MelonThump/CreditWallet.swift $here/main.swift
h=$out/next-melon-harness
gates() {  # decision letters, one per thump
  local g=""
  while IFS= read -r line; do
    case $line in
      *"PROMO AD GATE"*) g+=P ;; *"SESSION GATE"*) g+=S ;;
      *"promo freebie"*) g+=F ;; *"no gate"*) g+=N ;;
    esac
  done <<< "$(print -r -- "$1" | grep 'thump#' || true)"
  print -r -- $g
}
# S <expect> <env...> -- <tokens with n>
S() {
  local expect=$1; shift
  local envs=(); while [[ $1 != -- ]]; do envs+=$1; shift; done; shift
  local toks=("$@") manual=(${@:#n})
  $h reset >/dev/null
  local a; a=$(env $envs $h launch $toks)
  $h reset >/dev/null
  local b; b=$(env $envs $h launch $manual)
  print -r -- "$a" | sed 's/^/    /'
  local ga=$(gates "$a") gb=$(gates "$b")
  [[ $ga == $expect ]] && ok "gates '$ga' (expected '$expect')" || bad "gates '$ga', expected '$expect'"
  [[ $ga == $gb ]] && ok "identical to manual return ('$gb')" || bad "next-melon '$ga' != manual '$gb'"
  local ea=$(print -r -- "$a" | grep 'end:') eb=$(print -r -- "$b" | grep 'end:')
  [[ $ea == $eb ]] && ok "final wallet identical to manual return" || bad "final wallet differs: [$ea] vs [$eb]"
  local navs=$(print -r -- "$a" | grep -c 'nav  next-melon' || true)
  local unch=$(print -r -- "$a" | grep -c 'wallet UNCHANGED' || true)
  (( navs > 0 && navs == unch )) && ok "wallet unchanged across all $navs next-melon actions" || bad "wallet changed on navigation ($unch/$navs unchanged)"
}

echo "-- A. promo session UNLOCKED → next-melon → next thump not gated, count +1 only on analysis"
S FFPN POLICY=promo -- t n t n t:watch n t
print -r -- "$($h reset >/dev/null; env POLICY=promo $h launch t n t n t:watch n t)" \
  | grep -q 'nav  next-melon: wallet UNCHANGED (versionCount=3 sessionUnlocked=true canThump=true' \
  && ok "after unlock + next-melon: versionCount=3, sessionUnlocked=true, canThump=true" || bad "unlock state lost"
print -r -- "$($h reset >/dev/null; env POLICY=promo $h launch t n t n t:watch n t)" \
  | grep -q 'thump#4 (versionCount before=3) → no gate → RIPE recorded, versionCount=4' \
  && ok "next thump: versionCount 3 → 4 on the completed analysis" || bad "count did not move exactly +1"

echo "-- B. NOT unlocked, freebies exhausted → next-melon → next thump still PROMO-gated"
S FFPP POLICY=promo -- t n t n t n t
print -r -- "$($h reset >/dev/null; env POLICY=promo $h launch t n t n t)" \
  | grep -q 'nav  next-melon: wallet UNCHANGED (versionCount=2 sessionUnlocked=false canThump=false needsPromoAd=true' \
  && ok "after freebies + next-melon: versionCount=2, gate still armed" || bad "gate disarmed by navigation"

echo "-- C. UNKNOWN verdict result → next-melon: count unchanged, freebie still available"
S FFF POLICY=promo -- u n t n t

echo "-- D. N=1: one freebie, then gate; unlocked session survives next-melon"
S FPN FREE=1 POLICY=promo -- t n t:watch n t

echo "-- E. post-promotion: first free, then session gate; credit unlock survives next-melon"
S NSN POLICY=post -- t n t:credit n t
echo "-- F. post-promotion, gate declined: next-melon does not bypass the session gate"
S NSS POLICY=post -- t n t n t

$h reset >/dev/null
echo
if (( fails )); then print "RESULT: $fails of $checks checks FAILED"; exit 1; fi
print "RESULT: all $checks checks passed"
