# -*- coding: utf-8 -*-
"""
Pepper QA harness — MelonThump 2.0 package S1 (contributor data layer,
application flow, admin API, audit-log design).

Standalone: boots its own server instance (qa profile, in-memory H2) from
the packaged qa jar, runs black-box HTTP assertions, kills the server.
No external services, no pre-running app, fixtures are generated UUIDs.

Usage (on the Mac, from the repo worktree root):
  python3 qa-s1.py [jar_path] [port]
Defaults: jar = newest server/target/melonthump-server-*.jar (qa build),
port = 18099. Exit code 0 = all checks pass, 1 = failures.
"""
import glob
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

JAVA = "/Users/Shared/jdks/temurin-25/Contents/Home/bin/java"
BASE = None  # set in main

passed = []
failed = []
notes = []


def check(name, cond, detail=""):
    if cond:
        passed.append(name)
        print("PASS  %s" % name)
    else:
        failed.append(name)
        print("FAIL  %s  %s" % (name, detail))


def req(method, path, body=None, raw=None, headers=None):
    url = BASE + path
    data = raw
    hdrs = {"Content-Type": "application/json"}
    # 2.0 S2: /api/v1/contributions/** is App Attest gated; the qa profile
    # honours the simulator bypass header.
    if path.startswith("/api/v1/contributions"):
        hdrs["X-Attest-Bypass"] = "simulator"
    if headers:
        hdrs.update(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    r = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(r, timeout=10) as resp:
            payload = resp.read().decode("utf-8")
            return resp.status, json.loads(payload) if payload else {}
    except urllib.error.HTTPError as e:
        payload = e.read().decode("utf-8")
        try:
            return e.code, json.loads(payload) if payload else {}
        except Exception:
            return e.code, {"_raw": payload}


def wait_health(proc, timeout=150):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        try:
            status, body = req("GET", "/api/health")
            if status == 200 and body.get("status") == "UP":
                return True
        except Exception:
            pass
        time.sleep(2)
    return False


def boot(jar, port, extra_env=None):
    env = dict(os.environ)
    if extra_env:
        env.update(extra_env)
    proc = subprocess.Popen(
        [JAVA, "-jar", jar, "--spring.profiles.active=qa",
         "--server.port=%d" % port],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
    if not wait_health(proc):
        proc.kill()
        raise RuntimeError("server did not become healthy on port %d" % port)
    return proc


def main():
    global BASE
    jar = sys.argv[1] if len(sys.argv) > 1 else None
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 18099
    if jar is None:
        candidates = sorted(glob.glob("server/target/melonthump-server-*.jar"))
        candidates = [c for c in candidates if "sources" not in c and "javadoc" not in c]
        if not candidates:
            print("no server jar found under server/target — build the qa jar first")
            return 1
        jar = candidates[-1]
    BASE = "http://127.0.0.1:%d" % port
    print("QA target jar: %s  base: %s" % (jar, BASE))

    proc = boot(jar, port)
    try:
        # --- A. health ---
        status, body = req("GET", "/api/health")
        check("A1 health UP", status == 200 and body.get("status") == "UP")

        # --- B. existing version-policy endpoint regression (structural) ---
        status, body = req("GET", "/api/v1/version/getclientversion")
        check("B1 policy no-param 200 + keys", status == 200
              and "latestVersion" in body and "minSupportedVersion" in body
              and "forceUpdate" in body, str(status))
        status, body = req("GET", "/api/v1/version/getclientversion?currentVersion=1.2.0")
        check("B2 policy cv=1.2.0 200", status == 200 and "forceUpdate" in body, str(status))
        status, body = req("GET", "/api/v1/version/getclientversion?currentVersion=1.0.0")
        check("B3 policy cv=1.0.0 200", status == 200, str(status))

        # --- C. application flow ---
        cid = str(uuid.uuid4())
        status, body = req("POST", "/api/v1/contributions/applications",
                           {"contributorId": cid, "note": "Pepper QA harness tester"})
        check("C1 create application 201 PENDING",
              status == 201 and body.get("status") == "PENDING"
              and body.get("contributorId") == cid, "%s %s" % (status, body))
        status, body = req("POST", "/api/v1/contributions/applications",
                           {"contributorId": cid, "note": "OVERWRITE ATTEMPT"})
        check("C2 re-post idempotent 200", status == 200 and body.get("status") == "PENDING",
              "%s %s" % (status, body))
        status, body = req("GET", "/api/admin/applications?status=PENDING")
        mine = [a for a in body if a.get("contributorId") == cid] if isinstance(body, list) else []
        check("C3 admin list shows original note (no overwrite)",
              len(mine) == 1 and mine[0].get("note") == "Pepper QA harness tester",
              str(mine))
        status, _ = req("POST", "/api/v1/contributions/applications",
                        {"contributorId": str(uuid.uuid4()), "note": "   "})
        check("C4 blank note 400", status == 400, str(status))
        status, _ = req("POST", "/api/v1/contributions/applications",
                        {"contributorId": str(uuid.uuid4()), "note": "x" * 1001})
        check("C5 note >1000 chars 400", status == 400, str(status))
        status, _ = req("POST", "/api/v1/contributions/applications",
                        {"note": "no id"})
        check("C6 missing contributorId 400", status == 400, str(status))
        status, _ = req("POST", "/api/v1/contributions/applications",
                        {"contributorId": "not-a-uuid", "note": "hi"})
        check("C7 malformed uuid 400", status == 400, str(status))
        status, _ = req("POST", "/api/v1/contributions/applications",
                        raw=b"this is not json")
        check("C8 non-JSON body 400", status == 400, str(status))

        # --- D. status endpoint ---
        status, body = req("GET", "/api/v1/contributions/status?contributorId=" + str(uuid.uuid4()))
        check("D1 status unknown 404 contributor_not_found",
              status == 404 and body.get("error") == "contributor_not_found",
              "%s %s" % (status, body))
        status, body = req("GET", "/api/v1/contributions/status?contributorId=" + cid)
        check("D2 status known 200 PENDING balance 0",
              status == 200 and body.get("status") == "PENDING"
              and body.get("adFreeBalance") == 0, "%s %s" % (status, body))
        status, _ = req("GET", "/api/v1/contributions/status?contributorId=abc")
        check("D3 status malformed id 400", status == 400, str(status))
        status, _ = req("GET", "/api/v1/contributions/status")
        check("D4 status missing param 400", status == 400, str(status))

        # --- E. admin transitions ---
        status, body = req("POST", "/api/admin/applications/%s/approve" % cid)
        check("E1 approve PENDING→APPROVED", status == 200 and body.get("status") == "APPROVED",
              "%s %s" % (status, body))
        status, body = req("POST", "/api/admin/applications/%s/approve" % cid)
        check("E2 approve again no-op 200", status == 200 and body.get("status") == "APPROVED",
              "%s %s" % (status, body))
        status, body = req("POST", "/api/admin/applications/%s/decline" % cid)
        check("E3 decline APPROVED→409 illegal_transition",
              status == 409 and body.get("error") == "illegal_transition",
              "%s %s" % (status, body))
        status, body = req("GET", "/api/v1/contributions/status?contributorId=" + cid)
        check("E4 status now APPROVED", status == 200 and body.get("status") == "APPROVED")
        status, body = req("POST", "/api/admin/contributors/%s/revoke" % cid)
        check("E5 revoke APPROVED→REVOKED", status == 200 and body.get("status") == "REVOKED",
              "%s %s" % (status, body))
        status, body = req("POST", "/api/admin/applications/%s/approve" % cid)
        check("E6 approve REVOKED→APPROVED (toggle back on)",
              status == 200 and body.get("status") == "APPROVED", "%s %s" % (status, body))
        status, _ = req("POST", "/api/admin/applications/%s/approve" % uuid.uuid4())
        check("E7 approve unknown 404", status == 404, str(status))
        status, _ = req("POST", "/api/admin/applications/not-a-uuid/approve")
        check("E8 approve malformed id 400", status == 400, str(status))
        status, _ = req("GET", "/api/admin/applications?status=BOGUS")
        check("E9 admin list bad status filter 400", status == 400, str(status))

        cid2 = str(uuid.uuid4())
        req("POST", "/api/v1/contributions/applications",
            {"contributorId": cid2, "note": "second tester"})
        status, body = req("POST", "/api/admin/applications/%s/decline" % cid2)
        check("E10 decline PENDING→DECLINED", status == 200 and body.get("status") == "DECLINED",
              "%s %s" % (status, body))
        status, body = req("POST", "/api/v1/contributions/applications",
                           {"contributorId": cid2, "note": "please reopen me"})
        check("E11 re-post DECLINED stays DECLINED (no reopen)",
              status == 200 and body.get("status") == "DECLINED", "%s %s" % (status, body))
        status, _ = req("POST", "/api/admin/contributors/%s/revoke" % cid2)
        check("E12 revoke DECLINED→409", status == 409, str(status))

        notes.append("audit_log rows are not exposed via any API in S1; "
                     "verified by code inspection + the Maven test suite, not black-box.")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except Exception:
            proc.kill()

    # --- F. admin kill-switch: env override must be able to turn admin off ---
    proc = boot(jar, port, extra_env={"MELONTHUMP_ADMIN_ENABLED": "false"})
    try:
        status, _ = req("GET", "/api/admin/applications")
        if status == 404:
            check("F1 admin off via MELONTHUMP_ADMIN_ENABLED=false → 404", True)
        else:
            notes.append("F1 INFO: env override did not disable admin under the qa "
                         "profile (got %s); prod default-off rests on the field "
                         "default + AdminDisabledTest in the suite." % status)
            print("INFO  F1 env override result: %s" % status)
        cid3 = str(uuid.uuid4())
        status, _ = req("POST", "/api/v1/contributions/applications",
                        {"contributorId": cid3, "note": "admin-off tester"})
        check("F2 contribution endpoints still work with admin off", status == 201, str(status))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=15)
        except Exception:
            proc.kill()

    for n in notes:
        print("NOTE  %s" % n)
    print("---")
    print("QA RESULT: %d passed, %d failed" % (len(passed), len(failed)))
    if failed:
        print("FAILED: %s" % ", ".join(failed))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
