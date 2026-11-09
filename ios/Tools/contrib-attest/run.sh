#!/bin/zsh
# Contribution App Attest payload acceptance (2.0 S5).
#  1. The PRODUCTION ios/MelonThump/ContributionAttest.swift and the
#     server's ContributionAttestGate (compiled classes in
#     server/target/classes) must produce byte-identical canonical
#     payloads for the same vectors (multipart submit / append, GET,
#     DELETE, no-query GET).
#  2. Optional live check (QA_BASE and QA_CONTRIBUTOR set, an APPROVED
#     contributor on a `qa`-profile server): a sample encoded by the
#     production multipart encoder is accepted (201), and the server's
#     stored per-part SHA-256s equal our canonical digests in wire order.
# Needs: Xcode toolchain, JDK 25 ($JAVA_HOME), server compiled
# (mvn -f server/pom.xml compile). Exit status != 0 on any failure.
set -e
here=${0:A:h}
repo=$here/../../..
out=$(mktemp -d)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
JAVA_HOME=${JAVA_HOME:-/Users/Shared/jdks/temurin-25/Contents/Home}
classes=$repo/server/target/classes
[[ -f $classes/dev/melonthump/api/ContributionAttestGate.class ]] || { print "server classes missing: build the server first"; exit 1; }
xcrun swiftc -swift-version 5 -o $out/harness $repo/ios/MelonThump/ContributionAttest.swift $here/main.swift
$out/harness vectors > $out/swift.txt
cp=$classes:$(find ~/.m2/repository/org/apache/tomcat/embed/tomcat-embed-core -name 'tomcat-embed-core-*.jar' | sort | tail -1)
$JAVA_HOME/bin/java -cp $cp $here/Check.java > $out/java.txt
fails=0
while read -r name b64; do
  jb64=$(awk -v n=$name '$1==n{print $2}' $out/java.txt)
  if [[ $b64 == $jb64 && -n $jb64 ]]; then print "  ✓ $name identical ($(print -n $b64 | base64 -d | wc -c | tr -d ' ') bytes)"
  else print "  ✗ $name differs"; fails=$((fails+1)); fi
done < $out/swift.txt
[[ $(wc -l < $out/swift.txt) -eq $(wc -l < $out/java.txt) ]] || { print "  ✗ vector count differs"; fails=$((fails+1)); }
if [[ -n $QA_BASE && -n $QA_CONTRIBUTOR ]]; then
  $out/harness live $QA_BASE $QA_CONTRIBUTOR || fails=$((fails+1))
else
  print "  (live check skipped: set QA_BASE and QA_CONTRIBUTOR)"
fi
print; [[ $fails -eq 0 ]] && print "RESULT: contribution attest payloads match the server" || { print "RESULT: $fails failure(s)"; exit 1; }
