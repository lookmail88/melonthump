# -*- coding: utf-8 -*-
"""MelonThump 2.0 S2 black-box QA — sample submission, material storage,
contributor self-service, App Attest gating.

Independent of the Maven test suite: boots the packaged qa jar itself,
drives the real HTTP API with hand-built multipart bodies, and checks the
material files on disk (the harness sets MELONTHUMP_CONTRIB_STORAGE_DIR).

Run from the repo root on the build machine:
    python3 qa/s2_sample_api_qa.py [--jar server/target/melonthump-server-1.13.0.jar] [--port 18101]

Exit code 0 = every check passed.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

JAVA = "/Users/Shared/jdks/temurin-25/Contents/Home/bin/java"
BYPASS = {"X-Attest-Bypass": "simulator"}

passed = []
failed = []


def check(name, cond, extra=""):
    if cond:
        passed.append(name)
        print("PASS  %s" % name)
    else:
        failed.append(name)
        print("FAIL  %s  %s" % (name, extra))


def req(method, port, path, body=None, headers=None, raw=None, ctype=None):
    url = "http://127.0.0.1:%d%s" % (port, path)
    data = raw
    hdrs = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    if ctype:
        hdrs["Content-Type"] = ctype
    r = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            payload = resp.read().decode("utf-8", "replace")
            return resp.status, json.loads(payload) if payload else None
    except urllib.error.HTTPError as e:
        payload = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(payload) if payload else None
        except ValueError:
            return e.code, None


def multipart(parts):
    """parts: list of (name, filename, content_type, bytes)."""
    boundary = "qa-boundary-" + uuid.uuid4().hex[:16]
    out = bytearray()
    for name, filename, ctype, data in parts:
        out += ("--%s\r\n" % boundary).encode()
        disp = 'Content-Disposition: form-data; name="%s"' % name
        if filename:
            disp += '; filename="%s"' % filename
        out += (disp + "\r\n").encode()
        out += ("Content-Type: %s\r\n\r\n" % ctype).encode()
        out += data
        out += b"\r\n"
    out += ("--%s--\r\n" % boundary).encode()
    return bytes(out), "multipart/form-data; boundary=%s" % boundary


def meta_part(meta):
    return ("meta", None, "application/json", json.dumps(meta).encode("utf-8"))


def file_part(name, filename, ctype, data):
    return (name, filename, ctype, data)


JPEG = b"\xff\xd8\xff\xe0" + b"j" * 2000
PNG = b"\x89PNG\r\n\x1a\n" + b"p" * 1500
M4A = b"\x00\x00\x00\x18ftypM4A " + b"a" * 3000
M4A2 = b"\x00\x00\x00\x18ftypM4A " + b"b" * 2500


def sha(b):
    return hashlib.sha256(b).hexdigest()


def wait_health(port, proc, timeout=150):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        try:
            status, body = req("GET", port, "/api/health")
            if status == 200 and body and body.get("status") == "UP":
                return True
        except Exception:
            pass
        time.sleep(1.5)
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jar", default=None)
    ap.add_argument("--port", type=int, default=18101)
    args = ap.parse_args()

    jar = args.jar
    if jar is None:
        import glob
        cands = sorted(glob.glob("server/target/melonthump-server-*.jar"))
        cands = [c for c in cands if "original" not in c]
        if not cands:
            print("no server jar found; build with: mvn -Pqa clean package -DskipTests")
            return 1
        jar = cands[-1]
    port = args.port
    print("QA target jar: %s  base: http://127.0.0.1:%d" % (jar, port))

    storage = tempfile.mkdtemp(prefix="qa-s2-materials-")
    env = dict(os.environ)
    env["MELONTHUMP_CONTRIB_STORAGE_DIR"] = storage
    proc = subprocess.Popen(
        [JAVA, "-jar", jar, "--spring.profiles.active=qa",
         "--server.port=%d" % port],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
    try:
        if not wait_health(port, proc):
            print("server did not become healthy")
            return 1
        check("A1 health UP", True)

        cidA, cidB, cidC = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())

        # --- App Attest gating -------------------------------------------
        status, _ = req("POST", port, "/api/v1/contributions/applications",
                        body={"contributorId": cidA, "note": "qa A"})
        check("G1 application without bypass header -> 401", status == 401,
              "got %s" % status)
        status, _ = req("POST", port, "/api/v1/contributions/applications",
                        body={"contributorId": cidA, "note": "qa A"},
                        headers={"X-Attest-Bypass": "wrong"})
        check("G2 application with wrong bypass value -> 401", status == 401,
              "got %s" % status)

        # --- Setup: A and C approved, B pending ---------------------------
        for cid, note in ((cidA, "qa A"), (cidB, "qa B"), (cidC, "qa C")):
            status, _ = req("POST", port, "/api/v1/contributions/applications",
                            body={"contributorId": cid, "note": note},
                            headers=BYPASS)
            assert status in (201, 200), status
        for cid in (cidA, cidC):
            status, _ = req("POST", port, "/api/admin/applications/%s/approve" % cid)
            assert status == 200, status
        check("setup contributors ready", True)

        def submit(cid, parts, meta_extra=None):
            meta = {"contributorId": cid, "variety": "KIRIN"}
            if meta_extra:
                meta.update(meta_extra)
            body, ctype = multipart([meta_part(meta)] + parts)
            return req("POST", port, "/api/v1/contributions/samples",
                       raw=body, ctype=ctype, headers=BYPASS)

        # --- Submit authorization & validation ----------------------------
        status, _ = submit(cidB, [])
        check("S1 pending contributor submit -> 403", status == 403, "got %s" % status)
        status, _ = submit(str(uuid.uuid4()), [])
        check("S2 unknown contributor submit -> 404", status == 404, "got %s" % status)

        status, body = submit(cidA, [])
        sid_empty = body.get("id") if body else None
        check("S3 meta-only submit 201, incomplete, no files",
              status == 201 and body and body.get("complete") is False
              and body.get("completeness") == {"appearance": False,
                                               "recording": False,
                                               "cutOpen": False,
                                               "feedback": False}
              and body.get("files") == [],
              "got %s %s" % (status, body))

        status, body = submit(cidA, [
            file_part("appearance", "a1.jpg", "image/jpeg", JPEG),
            file_part("appearance", "a2.jpg", "image/jpeg", JPEG),
            file_part("recording", "r.m4a", "audio/mp4", M4A),
            file_part("cutOpen", "c.png", "image/png", PNG),
        ], {"weightGrams": 4200, "weightProvenance": "SCALE_MEASURED",
            "feedback": {"score": 88, "tasteTags": ["CRISP", "JUICY"],
                         "bandTruth": "RIPE"}})
        sid_full = body.get("id") if body else None
        files = body.get("files") if body else []
        by_part = {}
        for f in files or []:
            by_part.setdefault(f["part"], []).append(f)
        check("S4 complete submit 201 complete=true, 4 files, sha matches",
              status == 201 and body and body.get("complete") is True
              and len(files) == 4
              and by_part.get("APPEARANCE", [{}])[0].get("sha256") == sha(JPEG)
              and by_part.get("RECORDING", [{}])[0].get("sha256") == sha(M4A),
              "got %s %s" % (status, body))
        sdir = os.path.join(storage, cidA, str(sid_full))
        on_disk = []
        for root, _dirs, names in os.walk(sdir):
            on_disk += names
        check("S5 material files on disk (4)", len(on_disk) == 4,
              "found %s in %s" % (on_disk, sdir))

        status, _ = submit(cidA, [], {"variety": "NOPE"})
        check("S6 bad variety -> 400", status == 400, "got %s" % status)
        body_bytes, ctype = multipart([meta_part(
            {"contributorId": cidA, "variety": "KIRIN",
             "feedback": {"score": 50, "tasteTags": ["SOGGY"],
                          "bandTruth": "RIPE"}})])
        status, _ = req("POST", port, "/api/v1/contributions/samples",
                        raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("S7 unknown taste tag -> 400", status == 400, "got %s" % status)
        body_bytes, ctype = multipart([meta_part(
            {"contributorId": cidA, "variety": "KIRIN",
             "feedback": {"score": 50, "tasteTags": []}})])
        status, _ = req("POST", port, "/api/v1/contributions/samples",
                        raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("S8 feedback missing bandTruth -> 400", status == 400,
              "got %s" % status)
        body_bytes, ctype = multipart([meta_part(
            {"contributorId": cidA, "variety": "KIRIN",
             "feedback": {"score": 101, "tasteTags": [],
                          "bandTruth": "RIPE"}})])
        status, _ = req("POST", port, "/api/v1/contributions/samples",
                        raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("S9 score 101 -> 400", status == 400, "got %s" % status)
        status, _ = submit(cidA, [file_part("bogus", "x.jpg", "image/jpeg", JPEG)])
        check("S10 unknown part name -> 400", status == 400, "got %s" % status)
        status, _ = submit(cidA, [file_part("appearance", "x.txt",
                                            "text/plain", b"hello")])
        check("S11 text/plain appearance -> 400", status == 400,
              "got %s" % status)
        big = b"\xff\xd8\xff\xe0" + b"B" * (10 * 1024 * 1024)
        status, _ = submit(cidA, [file_part("appearance", "big.jpg",
                                            "image/jpeg", big)])
        check("S12 photo >10MB -> 413", status == 413, "got %s" % status)

        # --- List / detail -------------------------------------------------
        status, body = req("GET", port,
                           "/api/v1/contributions/samples?contributorId=" + cidA,
                           headers=BYPASS)
        check("L1 list own samples newest first",
              status == 200 and body and len(body) == 2
              and body[0].get("id") == sid_full
              and body[1].get("id") == sid_empty,
              "got %s %s" % (status, body))
        status, body = req("GET", port,
                           "/api/v1/contributions/samples?contributorId=" + cidC,
                           headers=BYPASS)
        check("L2 list for approved contributor without samples -> 200 []",
              status == 200 and body == [], "got %s %s" % (status, body))
        status, _ = req("GET", port,
                        "/api/v1/contributions/samples?contributorId="
                        + str(uuid.uuid4()), headers=BYPASS)
        check("L3 list unknown contributor -> 404", status == 404,
              "got %s" % status)
        status, body = req("GET", port,
                           "/api/v1/contributions/samples/%s?contributorId=%s"
                           % (sid_full, cidA), headers=BYPASS)
        check("L4 detail own sample 200 with files",
              status == 200 and body and len(body.get("files", [])) == 4,
              "got %s" % status)
        status, _ = req("GET", port,
                        "/api/v1/contributions/samples/%s?contributorId=%s"
                        % (sid_full, cidC), headers=BYPASS)
        check("L5 detail other's sample -> 403", status == 403,
              "got %s" % status)
        status, _ = req("GET", port,
                        "/api/v1/contributions/samples/999999?contributorId="
                        + cidA, headers=BYPASS)
        check("L6 detail nonexistent sample -> 403 (no existence leak)",
              status == 403, "got %s" % status)

        # --- Append ---------------------------------------------------------
        body_bytes, ctype = multipart([
            meta_part({"feedback": {"score": 80, "tasteTags": ["SWEET"],
                                    "bandTruth": "RIPE"}}),
            file_part("recording", "r.m4a", "audio/mp4", M4A)])
        status, body = req("POST", port,
                           "/api/v1/contributions/samples/%s/parts?contributorId=%s"
                           % (sid_empty, cidA),
                           raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("P1 append recording+feedback completes those parts",
              status == 200 and body
              and body.get("completeness", {}).get("recording") is True
              and body.get("completeness", {}).get("feedback") is True
              and body.get("completeness", {}).get("appearance") is False,
              "got %s %s" % (status, body))
        body_bytes, ctype = multipart([meta_part({"contributorId": cidA})])
        status, _ = req("POST", port,
                        "/api/v1/contributions/samples/%s/parts?contributorId=%s"
                        % (sid_empty, cidA),
                        raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("P2 empty append -> 400", status == 400, "got %s" % status)
        body_bytes, ctype = multipart([
            file_part("recording", "r.m4a", "audio/mp4", M4A)])
        status, _ = req("POST", port,
                        "/api/v1/contributions/samples/%s/parts?contributorId=%s"
                        % (sid_empty, cidC),
                        raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("P3 append by non-owner -> 403", status == 403, "got %s" % status)
        body_bytes, ctype = multipart([
            file_part("recording", "r2.m4a", "audio/mp4", M4A2)])
        status, body = req("POST", port,
                           "/api/v1/contributions/samples/%s/parts?contributorId=%s"
                           % (sid_full, cidA),
                           raw=body_bytes, ctype=ctype, headers=BYPASS)
        recs = [f for f in (body or {}).get("files", [])
                if f["part"] == "RECORDING"]
        check("P4 append recording replaces (one RECORDING, new sha)",
              status == 200 and len(recs) == 1
              and recs[0].get("sha256") == sha(M4A2),
              "got %s %s" % (status, recs))
        parts = [file_part("appearance", "p%d.jpg" % i, "image/jpeg", JPEG)
                 for i in range(12)]
        body_bytes, ctype = multipart(parts)
        status, _ = req("POST", port,
                        "/api/v1/contributions/samples/%s/parts?contributorId=%s"
                        % (sid_empty, cidA),
                        raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("P5 append 12 appearance photos -> 200", status == 200,
              "got %s" % status)
        body_bytes, ctype = multipart([
            file_part("appearance", "one-more.jpg", "image/jpeg", JPEG)])
        status, _ = req("POST", port,
                        "/api/v1/contributions/samples/%s/parts?contributorId=%s"
                        % (sid_empty, cidA),
                        raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("P6 13th appearance photo -> 400 (cap 12)", status == 400,
              "got %s" % status)

        # --- Withdraw -------------------------------------------------------
        status, _ = req("DELETE", port,
                        "/api/v1/contributions/samples/%s?contributorId=%s"
                        % (sid_empty, cidC), headers=BYPASS)
        check("W1 delete other's sample -> 403", status == 403,
              "got %s" % status)
        empty_dir = os.path.join(storage, cidA, str(sid_empty))
        existed_before = os.path.isdir(empty_dir)
        status, _ = req("DELETE", port,
                        "/api/v1/contributions/samples/%s?contributorId=%s"
                        % (sid_empty, cidA), headers=BYPASS)
        check("W2 withdraw own sample -> 204 and files gone from disk",
              status == 204 and existed_before
              and not os.path.exists(empty_dir),
              "got %s, dir existed before=%s, exists after=%s"
              % (status, existed_before, os.path.exists(empty_dir)))
        status, _ = req("GET", port,
                        "/api/v1/contributions/samples/%s?contributorId=%s"
                        % (sid_empty, cidA), headers=BYPASS)
        check("W3 detail after withdraw -> 403", status == 403,
              "got %s" % status)
        status, _ = req("DELETE", port,
                        "/api/v1/contributions/samples/%s?contributorId=%s"
                        % (sid_empty, cidA), headers=BYPASS)
        check("W4 second withdraw -> 403", status == 403, "got %s" % status)

        print("NOTE  RETURNED-resubmit and APPROVED/VOIDED 409 paths are not "
              "reachable black-box until the S3 admin sample-review endpoints "
              "exist; they are covered by the Maven suite via direct DB state.")
        print("---")
        print("QA RESULT: %d passed, %d failed" % (len(passed), len(failed)))
        return 0 if not failed else 1
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())
