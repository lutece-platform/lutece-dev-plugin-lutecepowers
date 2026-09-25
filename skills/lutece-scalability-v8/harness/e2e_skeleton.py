#!/usr/bin/env python3
"""
Skeleton for the RED/GREEN UI e2e (async Playwright, N concurrent clients over nginx).
Copy into the plugin's e2e/, adapt the CONFIG block and the arm/submit selectors.
Validated patterns baked in: FO login, X-Upstream capture, simultaneous submits via
asyncio.gather, DB as source of truth via docker exec, docker-log scan.

Exit code: 0 = GREEN, 1 = RED, 2 = harness/setup error.
"""
import argparse, asyncio, json, pathlib, subprocess, sys, time
from playwright.async_api import async_playwright

# ---- CONFIG (adapt per plugin) ----------------------------------------------
BASE = "http://localhost:8080/lutece"
FO_USER, FO_PASS = "test", "testtest"
LOGIN_URL = f"{BASE}/jsp/site/Portal.jsp?page=mylutece&action=login&auth_provider=mylutece-database"
FORM_URL = f"{BASE}/jsp/site/Portal.jsp?page=<xpage>&view=<view>&<params>"   # the contended form
FORM_SELECTOR = "#<formId>"                                                  # the form to submit
LOG_ERROR_PATTERN = "Duplicate entry"                                        # server-side RED evidence
INVARIANT_SQL = None   # e.g. "SELECT COUNT(*) FROM <table> WHERE <scope>": rows each accepted submit must add
ARTIFACTS = pathlib.Path(__file__).parent / "artifacts"
# ------------------------------------------------------------------------------


def db(query):
    """SQL against the cluster's shared MariaDB (not exposed to the host)."""
    out = subprocess.run(
        ["docker", "exec", "lutece-mariadb", "mariadb", "-ulutece", "-psome_password",
         "core", "-N", "-B", "-e", query], capture_output=True, text=True, check=True)
    return [l for l in out.stdout.splitlines() if l]


def docker_logs_since(since_iso):
    """Logs of the three app nodes since the given local timestamp, one block per node."""
    chunks = []
    for node in ("lutece-app1", "lutece-app2", "lutece-app3"):
        out = subprocess.run(["docker", "logs", "--since", since_iso, node],
                             capture_output=True, text=True)
        chunks.append(f"===== {node} =====\n{out.stdout}\n{out.stderr}")
    return "\n".join(chunks)


async def login(ctx):
    """FO login — ONLY works when the mylutece block is enabled in the site pom and
    the FO user is seeded (see harness README "FO authentication"). For a BO flow,
    or when FO auth is not installed, use login_bo() instead (works on any site)."""
    pg = await ctx.new_page()
    await pg.goto(LOGIN_URL, wait_until="domcontentloaded")
    await pg.evaluate("() => document.querySelectorAll('[id^=tarteaucitron]').forEach(e => e.remove())")
    await pg.fill('input[name="username"]', FO_USER)
    await pg.fill('input[name="password"]', FO_PASS)
    async with pg.expect_navigation(wait_until="domcontentloaded"):
        await pg.click('button[type="submit"], input[type="submit"]')
    return pg


async def login_bo(ctx):
    """BO login (admin/adminadmin — post-init.sql clears the password-expiry wall).
    Use instead of login() when the contended flow is a Back Office feature."""
    pg = await ctx.new_page()
    await pg.goto(f"{BASE}/jsp/admin/AdminLogin.jsp", wait_until="domcontentloaded")
    await pg.fill('input[name="access_code"]', "admin")
    await pg.fill('input[name="password"]', "adminadmin")
    async with pg.expect_navigation(wait_until="domcontentloaded"):
        await pg.click('button[type="submit"], input[type="submit"]')
    return pg


async def arm(pg, idx, rnd):
    """Open the contended form and fill it, ready to submit. Adapt the field JS."""
    resp = await pg.goto(FORM_URL, wait_until="domcontentloaded")
    await pg.evaluate(
        f"""() => {{
            document.querySelector('{FORM_SELECTOR} [name=<field>]').value = 'client {idx} round {rnd}';
        }}""")
    return resp.headers.get("x-upstream", "?")


async def submit(pg, idx):
    """Click submit; capture (status, upstream) of the POST. 200/302 = accepted."""
    post = {}

    def on_response(r):
        """Records the status and upstream of the first POST to Portal.jsp."""
        if r.request.method == "POST" and "Portal.jsp" in r.url and not post:
            post["status"] = r.status
            post["upstream"] = r.headers.get("x-upstream", "?")

    pg.on("response", on_response)
    try:
        async with pg.expect_navigation(wait_until="domcontentloaded", timeout=30000):
            await pg.click(f'{FORM_SELECTOR} button[type="submit"]')
    except Exception as e:
        post.setdefault("status", f"nav-error: {e}")
    finally:
        pg.remove_listener("response", on_response)
    return idx, post.get("status", "?"), post.get("upstream", "?")


def count_invariant():
    """Current value of INVARIANT_SQL, or None when it is not configured."""
    return int(db(INVARIANT_SQL)[0]) if INVARIANT_SQL else None


async def run(n_clients, n_rounds):
    """Runs the rounds and writes the report. RED when a submit fails, when INVARIANT_SQL did not grow by exactly
    one row per client, or when LOG_ERROR_PATTERN shows in the node logs; adapt the condition to the invariant
    (lost write, oversell, counter drift)."""
    ARTIFACTS.mkdir(exist_ok=True)
    start_iso = time.strftime("%Y-%m-%dT%H:%M:%S")
    report = {"clients": n_clients, "rounds": [], "verdict": None}
    red = False

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True, args=["--no-sandbox"])
        contexts = [await browser.new_context() for _ in range(n_clients)]
        pages = [await login(c) for c in contexts]
        print(f"{n_clients} clients logged in")

        for rnd in range(1, n_rounds + 1):
            before = count_invariant()
            upstreams = await asyncio.gather(*[arm(pg, i, rnd) for i, pg in enumerate(pages)])
            results = await asyncio.gather(*[submit(pg, i) for i, pg in enumerate(pages)])
            after = count_invariant()
            created = None if before is None else after - before
            failures = [r for r in results if r[1] not in (200, 302)]
            if failures or (created is not None and created != n_clients):
                red = True
            report["rounds"].append({"round": rnd, "created": created,
                                     "posts": [{"client": i, "status": s, "upstream": u} for i, s, u in results],
                                     "view_upstreams": upstreams})
            print(f"round {rnd}: {len(failures)} HTTP failures, nodes={sorted({u for _, _, u in results})}")
        await browser.close()

    logs = docker_logs_since(start_iso)
    errors = logs.count(LOG_ERROR_PATTERN)
    report["verdict"] = "RED" if (red or errors) else "GREEN"
    (ARTIFACTS / "repro_docker_logs.txt").write_text(logs)
    (ARTIFACTS / "repro_result.json").write_text(json.dumps(report, indent=2))
    print(f"docker logs: {errors} '{LOG_ERROR_PATTERN}' — VERDICT: {report['verdict']}")
    return 1 if report["verdict"] == "RED" else 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--clients", type=int, default=6)
    ap.add_argument("--rounds", type=int, default=5)
    args = ap.parse_args()
    try:
        sys.exit(asyncio.run(run(args.clients, args.rounds)))
    except Exception as e:
        print(f"SETUP ERROR: {e}", file=sys.stderr)
        sys.exit(2)
