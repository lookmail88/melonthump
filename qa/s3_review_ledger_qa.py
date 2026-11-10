# -*- coding: utf-8 -*-
"""MelonThump 2.0 S3 black-box QA — admin sample review, incentive ledger,
contributor exemption, client spend, install adExempt policy, audit read.

Also closes the S2 black-box gap: RETURNED-resubmit and the sample-state
409 paths are driven end-to-end through the admin review endpoints.

Independent of the Maven suite: boots the packaged qa jar itself and
drives the real HTTP API.

Run from the repo root on the build machine:
    python3 qa/s3_review_ledger_qa.py [--jar server/target/melonthump-server-1.13.0.jar] [--port 18102]

Exit code 0 = every check passed.
"""
import argparse
import json
import os
import subprocess
import sys
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


def req_raw(method, port, path, headers=None):
    url = "http://127.0.0.1:%d%s" % (port, path)
    r = urllib.request.Request(url, headers=dict(headers or {}), method=method)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            return resp.status, resp.read(), resp.headers.get("Content-Type")
    except urllib.error.HTTPError as e:
        e.read()
        return e.code, b"", None


def multipart(parts):
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
FEEDBACK = {"score": 88, "tasteTags": ["CRISP"], "bandTruth": "RIPE"}


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
    ap.add_argument("--port", type=int, default=18102)
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

    proc = subprocess.Popen(
        [JAVA, "-jar", jar, "--spring.profiles.active=qa",
         "--server.port=%d" % port],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if not wait_health(port, proc):
            print("server did not become healthy")
            return 1
        check("A1 health UP", True)

        cidA, cidB, cidC = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
        for cid in (cidA, cidB, cidC):
            status, _ = req("POST", port, "/api/v1/contributions/applications",
                            body={"contributorId": cid, "note": "qa"},
                            headers=BYPASS)
            assert status in (201, 200), status
        for cid in (cidA, cidC):
            status, _ = req("POST", port,
                            "/api/admin/applications/%s/approve" % cid)
            assert status == 200, status

        def submit(cid, parts, feedback=None):
            meta = {"contributorId": cid, "variety": "KIRIN"}
            if feedback:
                meta["feedback"] = feedback
            body, ctype = multipart([meta_part(meta)] + parts)
            status, resp = req("POST", port, "/api/v1/contributions/samples",
                               raw=body, ctype=ctype, headers=BYPASS)
            assert status == 201, (status, resp)
            return resp["id"]

        appearance = [file_part("appearance", "a.jpg", "image/jpeg", JPEG)]
        full = appearance + [
            file_part("recording", "r.m4a", "audio/mp4", M4A),
            file_part("cutOpen", "c.png", "image/png", PNG)]
        s_complete = submit(cidA, list(full), FEEDBACK)
        s_incomp = submit(cidA, list(appearance))
        s_return = submit(cidA, list(appearance))
        s_void = submit(cidA, list(full), FEEDBACK)
        check("setup samples submitted", True)

        def balance(cid):
            status, body = req("GET", port,
                               "/api/v1/contributions/status?contributorId="
                               + cid, headers=BYPASS)
            assert status == 200, status
            return body

        # --- Admin review: list / detail / download ------------------------
        status, body = req("GET", port, "/api/admin/samples?status=SUBMITTED")
        ids = [s["id"] for s in body] if body else []
        check("R1 admin list SUBMITTED contains the 4 samples",
              status == 200 and all(s in ids for s in
                                     (s_complete, s_incomp, s_return, s_void)),
              "got %s" % ids)
        status, body = req("GET", port,
                           "/api/admin/samples?contributorId=" + cidC)
        check("R2 admin list filtered to other contributor -> []",
              status == 200 and body == [], "got %s %s" % (status, body))
        status, body = req("GET", port, "/api/admin/samples/%d" % s_complete)
        admin_files = body.get("files") if body else []
        check("R3 admin detail files carry ids",
              status == 200 and len(admin_files) == 3
              and all("id" in f for f in admin_files),
              "got %s %s" % (status, admin_files))
        status, body = req("GET", port,
                           "/api/v1/contributions/samples/%d?contributorId=%s"
                           % (s_complete, cidA), headers=BYPASS)
        contrib_files = body.get("files") if body else []
        check("R4 contributor detail files unchanged (no ids leaked)",
              status == 200 and len(contrib_files) == 3
              and all("id" not in f for f in contrib_files),
              "got %s" % (contrib_files,))
        cut = [f for f in admin_files if f["part"] == "CUT_OPEN"][0]
        status, data, ctype = req_raw(
            "GET", port, "/api/admin/samples/%d/files/%d"
            % (s_complete, cut["id"]))
        check("R5 admin download cut-open photo bytes + content type",
              status == 200 and data == PNG and ctype == "image/png",
              "got %s %s %d bytes" % (status, ctype, len(data)))
        other = [f for f in admin_files if f["part"] == "RECORDING"][0]
        status, _d, _c = req_raw(
            "GET", port, "/api/admin/samples/%d/files/%d"
            % (s_incomp, other["id"]))
        check("R6 download file of another sample -> 404", status == 404,
              "got %s" % status)

        # --- Return flow (closes the S2 resubmit gap) ----------------------
        status, _ = req("POST", port, "/api/admin/samples/%d/return" % s_return,
                        body={})
        check("T1 return without reason -> 400", status == 400,
              "got %s" % status)
        status, _ = req("POST", port, "/api/admin/samples/%d/return" % s_return,
                        body={"reason": "   "})
        check("T2 return with blank reason -> 400", status == 400,
              "got %s" % status)
        status, body = req("POST", port,
                           "/api/admin/samples/%d/return" % s_return,
                           body={"reason": "cut-open photo too blurry"})
        check("T3 return with reason -> RETURNED",
              status == 200 and body and body.get("status") == "RETURNED",
              "got %s %s" % (status, body))
        status, body = req("GET", port,
                           "/api/v1/contributions/samples?contributorId="
                           + cidA, headers=BYPASS)
        mine = {s["id"]: s for s in body} if body else {}
        check("T4 contributor sees the return reason",
              mine.get(s_return, {}).get("returnReason")
              == "cut-open photo too blurry",
              "got %s" % (mine.get(s_return),))
        status, _ = req("POST", port, "/api/admin/samples/%d/approve" % s_return)
        check("T5 approve while RETURNED -> 409", status == 409,
              "got %s" % status)
        body_bytes, ctype = multipart([
            meta_part({"feedback": FEEDBACK}),
            file_part("recording", "r.m4a", "audio/mp4", M4A),
            file_part("cutOpen", "c.png", "image/png", PNG)])
        status, body = req("POST", port,
                           "/api/v1/contributions/samples/%d/parts?contributorId=%s"
                           % (s_return, cidA),
                           raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("T6 resubmit after return -> SUBMITTED, reason cleared",
              status == 200 and body and body.get("status") == "SUBMITTED"
              and body.get("returnReason") is None
              and body.get("complete") is True,
              "got %s %s" % (status, body))

        # --- Approve + grant-once -------------------------------------------
        status, body = req("POST", port,
                           "/api/admin/samples/%d/approve" % s_return)
        check("V1 approve resubmitted complete sample -> APPROVED",
              status == 200 and body and body.get("status") == "APPROVED",
              "got %s" % status)
        st = balance(cidA)
        check("V2 balance is 5 after first complete approval (+ field present)",
              st.get("adFreeBalance") == 5
              and st.get("adExemptPermanent") is False,
              "got %s" % st)
        status, _ = req("POST", port, "/api/admin/samples/%d/approve" % s_return)
        st = balance(cidA)
        check("V3 approve again no-op: still APPROVED, balance still 5",
              status == 200 and st.get("adFreeBalance") == 5,
              "got %s %s" % (status, st))
        status, _ = req("POST", port, "/api/admin/samples/%d/return" % s_return,
                        body={"reason": "too late"})
        check("V4 return an APPROVED sample -> 409", status == 409,
              "got %s" % status)
        status, _ = req("POST", port, "/api/admin/samples/%d/approve" % s_incomp)
        st = balance(cidA)
        check("V5 approve incomplete sample: APPROVED but no grant",
              status == 200 and st.get("adFreeBalance") == 5,
              "got %s %s" % (status, st))
        body_bytes, ctype = multipart([
            file_part("recording", "r.m4a", "audio/mp4", M4A)])
        status, _ = req("POST", port,
                        "/api/v1/contributions/samples/%d/parts?contributorId=%s"
                        % (s_incomp, cidA),
                        raw=body_bytes, ctype=ctype, headers=BYPASS)
        check("V6 append to APPROVED sample -> 409", status == 409,
              "got %s" % status)
        status, _ = req("DELETE", port,
                        "/api/v1/contributions/samples/%d?contributorId=%s"
                        % (s_incomp, cidA), headers=BYPASS)
        check("V7 withdraw APPROVED sample -> 409", status == 409,
              "got %s" % status)

        # --- Void + clawback --------------------------------------------------
        status, _ = req("POST", port, "/api/admin/samples/%d/void" % s_incomp)
        st = balance(cidA)
        check("W1 void an APPROVED sample that earned nothing: balance intact",
              status == 200 and st.get("adFreeBalance") == 5,
              "got %s %s" % (status, st))
        status, _ = req("POST", port, "/api/admin/samples/%d/approve" % s_void)
        st = balance(cidA)
        check("W2 approve second complete sample: balance 10",
              status == 200 and st.get("adFreeBalance") == 10,
              "got %s %s" % (status, st))

        def spend(cid, headers=BYPASS):
            return req("POST", port, "/api/v1/contributions/adfree/spend",
                       body={"contributorId": cid}, headers=headers)

        status, body = spend(cidA)
        ok1 = status == 200 and body and body.get("spent") is True \
            and body.get("balance") == 9
        status, body = spend(cidA)
        ok2 = status == 200 and body and body.get("balance") == 8
        check("W3 spend twice: balance 10 -> 8", ok1 and ok2,
              "got %s" % (body,))
        status, _ = req("POST", port, "/api/admin/samples/%d/void" % s_void)
        st = balance(cidA)
        check("W4 void after partial spend: clawback min(8, 5) -> balance 3",
              status == 200 and st.get("adFreeBalance") == 3,
              "got %s %s" % (status, st))
        status, _ = req("POST", port, "/api/admin/samples/%d/void" % s_void)
        st = balance(cidA)
        check("W5 void again no-op: balance still 3",
              status == 200 and st.get("adFreeBalance") == 3,
              "got %s %s" % (status, st))
        status, body = req("GET", port,
                           "/api/admin/audit?objectType=SAMPLE&objectId=%d"
                           % s_void)
        actions = [e.get("action") for e in body] if body else []
        check("W6 audit read for the sample: newest first, approve+void present",
              status == 200 and actions and actions[0] == "SAMPLE_VOIDED"
              and "SAMPLE_APPROVED" in actions,
              "got %s" % (actions,))

        # --- Manual grants -----------------------------------------------------
        status, body = req("POST", port,
                           "/api/admin/contributors/%s/adfree/grants" % cidA,
                           body={"delta": -10, "reason": "qa claw"})
        check("G1 negative grant applies only to zero floor (-3 of -10)",
              status == 200 and body and body.get("appliedDelta") == -3
              and body.get("balance") == 0,
              "got %s %s" % (status, body))
        status, body = req("POST", port,
                           "/api/admin/contributors/%s/adfree/grants" % cidA,
                           body={"delta": 7, "reason": "goodwill top-up"})
        check("G2 manual grant +7 -> balance 7",
              status == 200 and body and body.get("appliedDelta") == 7
              and body.get("balance") == 7,
              "got %s %s" % (status, body))
        status, body = req("GET", port,
                           "/api/admin/contributors/%s/adfree" % cidA)
        entries = body.get("entries") if body else []
        check("G3 ledger read: newest first, manual rows coded ADMIN_GRANT",
              status == 200 and entries
              and entries[0].get("delta") == 7
              and entries[0].get("reason") == "ADMIN_GRANT",
              "got %s" % (entries[:2],))
        status, body = req("GET", port,
                           "/api/admin/audit?objectType=CONTRIBUTOR&objectId="
                           + cidA)
        texts = " ".join((e.get("afterJson") or "") for e in body or [])
        check("G4 grant free-text reason preserved in audit row",
              status == 200 and "goodwill top-up" in texts, "got %s" % status)
        status, _ = req("POST", port,
                        "/api/admin/contributors/%s/adfree/grants" % cidA,
                        body={"delta": 0, "reason": "zero"})
        check("G5 zero-delta grant -> 400", status == 400, "got %s" % status)
        status, _ = req("POST", port,
                        "/api/admin/contributors/%s/adfree/grants"
                        % uuid.uuid4(),
                        body={"delta": 1, "reason": "ghost"})
        check("G6 grant to unknown contributor -> 404", status == 404,
              "got %s" % status)

        # --- Spend guards + permanent exemption --------------------------------
        status, body = spend(cidA)
        check("P1 spend: balance 7 -> 6, spent true",
              status == 200 and body and body.get("spent") is True
              and body.get("balance") == 6, "got %s %s" % (status, body))
        status, _ = spend(cidB)
        check("P2 spend by PENDING contributor -> 403", status == 403,
              "got %s" % status)
        status, _ = spend(str(uuid.uuid4()))
        check("P3 spend by unknown contributor -> 404", status == 404,
              "got %s" % status)
        status, _ = req("POST", port, "/api/v1/contributions/adfree/spend",
                        body={"contributorId": cidA})
        check("P4 spend without attest bypass -> 401", status == 401,
              "got %s" % status)
        status, _ = req("POST", port,
                        "/api/admin/contributors/%s/exemption" % cidA,
                        body={"permanent": True})
        st = balance(cidA)
        check("P5 set permanent exemption: status field flips true",
              status == 200 and st.get("adExemptPermanent") is True,
              "got %s %s" % (status, st))
        status, body = spend(cidA)
        check("P6 spend while exempt: spent false, exempt true, balance kept",
              status == 200 and body and body.get("spent") is False
              and body.get("exempt") is True and body.get("balance") == 6,
              "got %s %s" % (status, body))
        status, _ = req("POST", port,
                        "/api/admin/contributors/%s/exemption" % cidA,
                        body={"permanent": False})
        st = balance(cidA)
        check("P7 exemption cleared again", status == 200
              and st.get("adExemptPermanent") is False, "got %s" % status)

        # --- Install allowlist + policy gating ----------------------------------
        status, _ = req("POST", port, "/api/admin/exemptions",
                        body={"installId": "QA-INSTALL-1", "note": "qa"})
        check("E1 create install exemption -> 201", status == 201,
              "got %s" % status)
        status, body = req("GET", port, "/api/admin/exemptions")
        check("E2 exemption list contains it",
              status == 200 and body
              and any(e.get("installId") == "QA-INSTALL-1" for e in body),
              "got %s" % (body,))

        def policy(cv, install=None):
            hdrs = {}
            if install:
                hdrs["X-Install-Id"] = install
            path = "/api/v1/version/getclientversion"
            if cv:
                path += "?currentVersion=" + cv
            return req("GET", port, path, headers=hdrs)

        status, body = policy("2.0.0", "QA-INSTALL-1")
        check("E3 policy 2.0.0 + allowlisted install -> adExempt true",
              status == 200 and body and body.get("adExempt") is True,
              "got %s %s" % (status, body))
        status, body = policy("2.0.0")
        check("E4 policy 2.0.0 without header -> adExempt false",
              status == 200 and body and body.get("adExempt") is False,
              "got %s" % (body,))
        status, body = policy("2.0.0", "SOMEONE-ELSE")
        check("E5 policy 2.0.0 + other install -> adExempt false",
              status == 200 and body and body.get("adExempt") is False,
              "got %s" % (body,))
        status, body = policy("1.2.0", "QA-INSTALL-1")
        check("E6 policy 1.2.0: no adExempt field (legacy shape intact)",
              status == 200 and body and "adExempt" not in body,
              "got %s" % (body,))
        status, body = policy("1.0.0", "QA-INSTALL-1")
        check("E7 policy 1.0.0: no adExempt field",
              status == 200 and body and "adExempt" not in body,
              "got %s" % (body,))
        status, _ = req("DELETE", port, "/api/admin/exemptions/QA-INSTALL-1")
        check("E8 delete exemption -> 204", status == 204, "got %s" % status)
        status, body = policy("2.0.0", "QA-INSTALL-1")
        check("E9 policy after removal -> adExempt false",
              status == 200 and body and body.get("adExempt") is False,
              "got %s" % (body,))
        status, _ = req("DELETE", port, "/api/admin/exemptions/QA-INSTALL-1")
        check("E10 delete absent exemption -> 404", status == 404,
              "got %s" % status)

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
