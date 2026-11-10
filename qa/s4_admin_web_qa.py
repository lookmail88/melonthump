# -*- coding: utf-8 -*-
"""MelonThump 2.0 S4 black-box QA — admin web page, runtime settings,
Access identity in the audit log, preliminary review, overview counts.

Independent of the Maven suite: boots the packaged qa jar itself and
drives the real HTTP API and the served page assets.

Run from the repo root on the build machine:
    python3 qa/s4_admin_web_qa.py [--jar server/target/melonthump-server-1.13.0.jar] [--port 18103]

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
ACCESS = {"Cf-Access-Authenticated-User-Email": "owner-qa@example.com"}

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


def req_text(method, port, path, headers=None):
    url = "http://127.0.0.1:%d%s" % (port, path)
    r = urllib.request.Request(url, headers=dict(headers or {}), method=method)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            return resp.status, resp.read().decode("utf-8", "replace"), \
                resp.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), e.headers


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


def boot(jar, port, env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    return subprocess.Popen(
        [JAVA, "-jar", jar, "--spring.profiles.active=qa",
         "--server.port=%d" % port],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)


def stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jar", default=None)
    ap.add_argument("--port", type=int, default=18103)
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

    proc = boot(jar, port)
    try:
        if not wait_health(port, proc):
            print("server did not become healthy")
            return 1
        check("A1 health UP", True)

        # --- The page -------------------------------------------------------
        status, html, hdrs = req_text("GET", port, "/admin/")
        check("PG1 /admin/ served as HTML with CSP",
              status == 200 and "text/html" in (hdrs.get("Content-Type") or "")
              and "Content-Security-Policy" in hdrs
              and "MelonThump" in html,
              "got %s" % status)
        status, js, _h = req_text("GET", port, "/admin/admin.js")
        status2, css, _h2 = req_text("GET", port, "/admin/admin.css")
        check("PG2 page assets served, no external URLs anywhere",
              status == 200 and status2 == 200
              and "http://" not in js and "https://" not in js
              and "http://" not in css and "https://" not in css
              and 'src="http' not in html and 'href="http' not in html,
              "js=%s css=%s" % (status, status2))

        # --- Settings defaults ----------------------------------------------
        status, body = req("GET", port, "/api/admin/settings")
        settings = {s["key"]: s for s in body} if body else {}
        check("ST1 four settings with defaults, none overridden",
              status == 200 and len(settings) == 4
              and all(not s.get("overridden") for s in settings.values())
              and settings.get("adfree_per_approved_sample", {})
              .get("defaultValue") == "5",
              "got %s" % (settings,))
        defaults = {k: v.get("defaultValue") for k, v in settings.items()}

        # --- Seed a scenario, then overview -----------------------------------
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
            body_b, ctype = multipart(
                [("meta", None, "application/json",
                  json.dumps(meta).encode("utf-8"))] + parts)
            status, resp = req("POST", port, "/api/v1/contributions/samples",
                               raw=body_b, ctype=ctype, headers=BYPASS)
            assert status == 201, (status, resp)
            return resp["id"]

        appearance = [("appearance", "a.jpg", "image/jpeg", JPEG)]
        full = appearance + [("recording", "r.m4a", "audio/mp4", M4A),
                             ("cutOpen", "c.png", "image/png", PNG)]
        s1 = submit(cidA, list(full), FEEDBACK)
        s2 = submit(cidC, list(appearance))
        s3 = submit(cidA, list(appearance))
        req("POST", port, "/api/admin/samples/%d/approve" % s1)
        req("POST", port, "/api/admin/samples/%d/return" % s2,
            body={"reason": "needs the cut-open photo"})

        status, body = req("GET", port, "/api/admin/overview")
        check("OV1 overview counts match the seeded scenario",
              status == 200 and body
              and body.get("contributors") == {"PENDING": 1, "APPROVED": 2,
                                               "DECLINED": 0, "REVOKED": 0}
              and body.get("samples") == {"SUBMITTED": 1, "APPROVED": 1,
                                          "RETURNED": 1, "VOIDED": 0}
              and body.get("completeSamplesApproved") == 1
              and body.get("pendingReview") == 1
              and body.get("adFreeOutstanding") == 5,
              "got %s" % (body,))

        # --- Access identity in audit ------------------------------------------
        status, _ = req("POST", port,
                        "/api/admin/applications/%s/approve" % cidB,
                        headers=ACCESS)
        status, body = req("GET", port,
                           "/api/admin/audit?objectType=CONTRIBUTOR&objectId="
                           + cidB)
        actors = [e.get("actor") for e in body] if body else []
        check("AC1 Access email header becomes the audit actor",
              status == 200 and "owner-qa@example.com" in actors,
              "got %s" % (actors,))
        cidD = str(uuid.uuid4())
        req("POST", port, "/api/v1/contributions/applications",
            body={"contributorId": cidD, "note": "qa"}, headers=BYPASS)
        req("POST", port, "/api/admin/applications/%s/decline" % cidD)
        status, body = req("GET", port,
                           "/api/admin/audit?objectType=CONTRIBUTOR&objectId="
                           + cidD)
        actors = [e.get("actor") for e in body] if body else []
        check("AC2 without the header the admin actor falls back to owner "
              "(newest row), client-facing row keeps the contributor id",
              status == 200 and actors and actors[0] == "owner"
              and cidD in actors,
              "got %s" % (actors,))

        # --- Preliminary review ---------------------------------------------------
        status, body = req("POST", port,
                           "/api/admin/samples/%d/preliminary-review" % s3,
                           body={"recommendation": "SUGGEST_RETURN",
                                 "note": "cut-open missing; ask for it"})
        check("PR1 preliminary review written",
              status == 200, "got %s %s" % (status, body))
        status, body = req("GET", port, "/api/admin/samples/%d" % s3)
        check("PR2 admin detail shows the Pepper fields",
              status == 200 and body
              and body.get("pepperRecommendation") == "SUGGEST_RETURN"
              and body.get("pepperNote") == "cut-open missing; ask for it"
              and body.get("pepperReviewedAt"),
              "got %s" % (body,))
        status, body = req("GET", port,
                           "/api/v1/contributions/samples/%d?contributorId=%s"
                           % (s3, cidA), headers=BYPASS)
        check("PR3 contributor detail has no Pepper fields",
              status == 200 and body
              and "pepperRecommendation" not in body
              and "pepperNote" not in body,
              "got %s" % (list((body or {}).keys()),))
        status, body = req("GET", port,
                           "/api/admin/audit?objectType=SAMPLE&objectId=%d" % s3)
        pre = [e for e in body or [] if e.get("action") == "PRELIMINARY_REVIEW"]
        check("PR4 preliminary review audited with actor pepper",
              len(pre) == 1 and pre[0].get("actor") == "pepper",
              "got %s" % (pre,))
        status, _ = req("POST", port,
                        "/api/admin/samples/%d/preliminary-review" % s3,
                        body={"recommendation": "MAYBE"})
        check("PR5 bad recommendation -> 400", status == 400,
              "got %s" % status)

        # --- Settings wiring -------------------------------------------------------
        def policy(cv):
            path = "/api/v1/version/getclientversion"
            if cv:
                path += "?currentVersion=" + cv
            return req("GET", port, path)

        def policy_value(cv, field, want, tries=10):
            for _ in range(tries):
                _s, body = policy(cv)
                if body and body.get(field) == want:
                    return True
                time.sleep(1)
            return False

        _s, base = policy("1.2.0")
        base_thumps = base.get("initialFreeThumps")
        status, _ = req("PUT", port, "/api/admin/settings",
                        body={"key": "initial_free_thumps", "value": "7"})
        ok = policy_value("1.2.0", "initialFreeThumps", 7)
        check("SE1 override initial_free_thumps=7 reaches the policy",
              status == 200 and ok, "put=%s policy ok=%s" % (status, ok))
        _s, body = policy("1.0.0")
        check("SE2 legacy 1.0.0 policy still has no initialFreeThumps",
              body and "initialFreeThumps" not in body, "got %s" % (body,))
        status, _ = req("DELETE", port,
                        "/api/admin/settings/initial_free_thumps")
        ok = policy_value("1.2.0", "initialFreeThumps", base_thumps)
        check("SE3 reset restores the default in the policy",
              status == 200 and ok, "delete=%s ok=%s" % (status, ok))
        status, _ = req("PUT", port, "/api/admin/settings",
                        body={"key": "credit_per_ad", "value": "-1"})
        ok = policy_value("1.2.0", "creditPerAd", -1)
        check("SE4 free-day override credit_per_ad=-1 reaches the policy",
              status == 200 and ok, "put=%s ok=%s" % (status, ok))
        req("DELETE", port, "/api/admin/settings/credit_per_ad")
        ok = policy_value("1.2.0", "creditPerAd",
                          int(defaults.get("credit_per_ad") or 1))
        check("SE5 credit_per_ad reset restores default", ok, "ok=%s" % ok)
        status, _ = req("PUT", port, "/api/admin/settings",
                        body={"key": "promo_ends_at_epoch_millis",
                              "value": "1893456000000"})
        ok = policy_value("1.2.0", "promoEndsAtEpochMillis", 1893456000000)
        check("SE6 promo end override reaches the policy",
              status == 200 and ok, "put=%s ok=%s" % (status, ok))
        req("DELETE", port, "/api/admin/settings/promo_ends_at_epoch_millis")

        cidE = str(uuid.uuid4())
        req("POST", port, "/api/v1/contributions/applications",
            body={"contributorId": cidE, "note": "qa"}, headers=BYPASS)
        req("POST", port, "/api/admin/applications/%s/approve" % cidE)
        status, _ = req("PUT", port, "/api/admin/settings",
                        body={"key": "adfree_per_approved_sample",
                              "value": "9"})
        s9 = submit(cidE, list(full), FEEDBACK)
        req("POST", port, "/api/admin/samples/%d/approve" % s9)
        status, body = req("GET", port,
                           "/api/v1/contributions/status?contributorId="
                           + cidE, headers=BYPASS)
        check("SE7 overridden unit count (9) is what approval grants",
              status == 200 and body and body.get("adFreeBalance") == 9,
              "put + approve -> %s" % (body,))
        req("DELETE", port, "/api/admin/settings/adfree_per_approved_sample")

        status, _ = req("PUT", port, "/api/admin/settings",
                        body={"key": "latest_version", "value": "9.9.9"})
        check("SE8 release-class key rejected -> 400", status == 400,
              "got %s" % status)
        status, _ = req("PUT", port, "/api/admin/settings",
                        body={"key": "credit_per_ad", "value": "-2"})
        check("SE9 invalid value -> 400", status == 400, "got %s" % status)
        status, _ = req("PUT", port, "/api/admin/settings",
                        body={"key": "nope", "value": "1"})
        check("SE10 unknown key -> 400", status == 400, "got %s" % status)
        status, _ = req("DELETE", port, "/api/admin/settings/credit_per_ad")
        check("SE11 reset of a non-overridden key -> 404", status == 404,
              "got %s" % status)
        status, body = req("GET", port,
                           "/api/admin/audit?objectType=SETTING&objectId="
                           "initial_free_thumps")
        actions = [e.get("action") for e in body] if body else []
        check("SE12 settings changes are audited",
              status == 200 and "SETTING_CHANGED" in actions
              and "SETTING_RESET" in actions, "got %s" % (actions,))
    finally:
        stop(proc)

    # --- Boot 2: admin flag off ------------------------------------------------
    proc = boot(jar, port, {"MELONTHUMP_ADMIN_ENABLED": "false"})
    try:
        if not wait_health(port, proc):
            print("second boot did not become healthy")
            return 1
        status, _html, _h = req_text("GET", port, "/admin/")
        check("D1 page still served with the admin flag off",
              status == 200, "got %s" % status)
        status, _ = req("GET", port, "/api/admin/overview")
        check("D2 admin API 404 with the flag off", status == 404,
              "got %s" % status)
        status, _ = req("GET", port, "/api/admin/settings")
        check("D3 settings API 404 with the flag off", status == 404,
              "got %s" % status)
    finally:
        stop(proc)

    print("---")
    print("QA RESULT: %d passed, %d failed" % (len(passed), len(failed)))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
