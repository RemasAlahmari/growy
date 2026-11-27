"""PT-NFR2-01: time real photo verifications on the deployed backend.

Uploads every photo in a folder to POST /habits/{id}/complete/ai on Render and
times each request. Requirement: every request answers in under 30 seconds.

Photos go in one folder per habit (JPG or PNG, under 5 MB):
    perf_photos/reading/      perf_photos/walking/
    perf_photos/workout/      perf_photos/drink_water/

Each account can verify a habit once a day and has at most 3 rejected tries
per habit, so give 2 test accounts for 20 photos. The script moves to the
next account by itself when one can't take more photos for a habit.

Run from the backend folder (no extra packages needed):
    python scripts/perf_photo_upload.py --email test1@example.com --email test2@example.com

Passwords are asked when it starts and are never saved. Results go to
perf_results.csv (one row per photo) and a summary is printed at the end.
"""
import argparse
import csv
import getpass
import json
import math
import re
import statistics
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime
from pathlib import Path

DEFAULT_SERVER = "https://growy-api.onrender.com"
LIMIT_SECONDS = 30
TIMEOUT_SECONDS = 90
PAUSE_SECONDS = 3  # between photos, to stay inside the Gemini free quota
HABIT_FOLDERS = {"reading": "Reading", "walking": "Walking",
                 "workout": "Workout", "drink_water": "Drink Water"}
IMAGE_TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}


# ---------------------------------------------------------------- HTTP helpers
def http(method, url, token=None, body=None, content_type=None, timeout=30):
    """Returns (status code, parsed JSON or text). Never raises for HTTP errors."""
    req = urllib.request.Request(url, data=body, method=method)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as e:
        status, raw = e.code, e.read()
    text = raw.decode("utf-8", "replace")
    try:
        return status, json.loads(text)
    except ValueError:
        return status, text


def multipart(field, filename, data, mime):
    boundary = uuid.uuid4().hex
    head = (f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n").encode()
    tail = f"\r\n--{boundary}--\r\n".encode()
    return head + data + tail, f"multipart/form-data; boundary={boundary}"


# ---------------------------------------------------------------- setup
def firebase_api_key(path):
    """The Firebase web API key from lib/firebase_options.dart (it is not a secret)."""
    text = Path(path).read_text(encoding="utf-8")
    match = re.search(r"apiKey:\s*'([^']+)'", text)
    if not match:
        sys.exit(f"No apiKey found in {path}. Pass it with --api-key.")
    return match.group(1)


def sign_in(api_key, email, password):
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={api_key}"
    body = json.dumps({"email": email, "password": password, "returnSecureToken": True}).encode()
    status, data = http("POST", url, body=body, content_type="application/json")
    if status != 200:
        message = data.get("error", {}).get("message") if isinstance(data, dict) else data
        sys.exit(f"Could not log in as {email}: {message}")
    return data["idToken"]


def wake_server(server):
    print(f"Waking {server} (the free server can take about a minute)...")
    for _ in range(12):
        try:
            status, data = http("GET", f"{server}/health", timeout=90)
            if status == 200:
                print(f"  Server is up: {data}")
                return
        except Exception as e:  # noqa: BLE001  (server still starting)
            print(f"  not yet ({e})")
        time.sleep(5)
    sys.exit("The server did not wake up. Open /health in a browser and try again.")


class Account:
    def __init__(self, email, token, habits):
        self.email = email
        self.token = token
        self.habit_ids = {h["name"]: h["id"] for h in habits}
        # Habits this account can't send more photos for today
        self.done = {h["name"] for h in habits if h.get("completed_today")}


def load_account(server, api_key, email):
    password = getpass.getpass(f"Password for {email}: ")
    token = sign_in(api_key, email, password)
    http("POST", f"{server}/users/sync", token=token)  # makes sure the user row exists
    status, habits = http("GET", f"{server}/habits/today", token=token)
    if status != 200:
        sys.exit(f"GET /habits/today failed for {email}: {status} {habits}")
    account = Account(email, token, habits)
    print(f"  {email}: logged in; already done today: {sorted(account.done) or 'none'}")
    return account


def find_photos(folder):
    photos = []
    for sub, habit in HABIT_FOLDERS.items():
        for path in sorted((Path(folder) / sub).glob("*")):
            if path.suffix.lower() in IMAGE_TYPES:
                photos.append((habit, path))
    return photos


# ---------------------------------------------------------------- the test
def upload(server, account, habit, path):
    data = path.read_bytes()
    body, ctype = multipart("file", path.name, data, IMAGE_TYPES[path.suffix.lower()])
    url = f"{server}/habits/{account.habit_ids[habit]}/complete/ai"
    start = time.perf_counter()
    try:
        status, resp = http("POST", url, token=account.token, body=body,
                            content_type=ctype, timeout=TIMEOUT_SECONDS)
    except Exception as e:  # noqa: BLE001  (timeout or network error)
        status, resp = "error", str(e)
    seconds = time.perf_counter() - start
    return status, resp, seconds, len(data)


def percentile(values, pct):
    """Nearest-rank percentile (p95 of 20 values = the 19th smallest)."""
    ordered = sorted(values)
    rank = max(1, math.ceil(pct / 100 * len(ordered)))
    return ordered[rank - 1]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--email", action="append", required=True,
                        help="test account email (repeat for each account)")
    parser.add_argument("--photos", default="perf_photos", help="folder with the habit folders")
    parser.add_argument("--server", default=DEFAULT_SERVER)
    parser.add_argument("--firebase-options", default="../lib/firebase_options.dart")
    parser.add_argument("--api-key", help="Firebase web API key (read from firebase_options.dart if not given)")
    parser.add_argument("--out", default="perf_results.csv")
    args = parser.parse_args()

    photos = find_photos(args.photos)
    if not photos:
        sys.exit(f"No photos found. Put JPG/PNG files in {args.photos}/reading, walking, workout, drink_water.")
    too_big = [p.name for _, p in photos if p.stat().st_size > 5 * 1024 * 1024]
    if too_big:
        sys.exit(f"These photos are over 5 MB (the server refuses them): {too_big}")
    print(f"{len(photos)} photos found.")

    api_key = args.api_key or firebase_api_key(args.firebase_options)
    server = args.server.rstrip("/")
    wake_server(server)
    accounts = [load_account(server, api_key, email) for email in args.email]

    rows = []
    for number, (habit, path) in enumerate(photos, 1):
        for account in accounts:
            if habit in account.done:
                continue
            status, resp, seconds, size = upload(server, account, habit, path)
            verdict = resp.get("verification_status", "") if isinstance(resp, dict) else ""
            reason = resp.get("reason", "") if isinstance(resp, dict) else str(resp)[:120]
            if status in (409, 429):
                # Not a Gemini check (blocked before it): try the next account.
                account.done.add(habit)
                print(f"  [{number:2}] {path.name}: {account.email} can't take more {habit} today ({status}); next account")
                continue
            if verdict == "verified" or (isinstance(resp, dict) and resp.get("attempts_remaining") == 0):
                account.done.add(habit)
            counted = status == 200
            rows.append({
                "photo": path.name, "habit": habit, "account": account.email,
                "size_kb": round(size / 1024), "status": status, "result": verdict,
                "seconds": round(seconds, 2), "under_30s": seconds < LIMIT_SECONDS if counted else "",
                "counted": counted, "reason": reason,
                "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            })
            print(f"  [{number:2}] {path.name} ({habit}): {status} {verdict or ''} in {seconds:.2f} s")
            break
        else:
            rows.append({"photo": path.name, "habit": habit, "account": "", "size_kb": "",
                         "status": "not sent", "result": "", "seconds": "", "under_30s": "",
                         "counted": False, "reason": "every account is done with this habit today",
                         "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S")})
            print(f"  [{number:2}] {path.name}: NOT SENT, no account left for {habit} today")
        time.sleep(PAUSE_SECONDS)

    with open(args.out, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    times = [r["seconds"] for r in rows if r["counted"]]
    print("\n================ PT-NFR2-01 summary ================")
    print(f"Photos: {len(photos)}   timed (HTTP 200): {len(times)}   "
          f"not counted: {len(rows) - len(times)}")
    if times:
        slow = [r["photo"] for r in rows if r["counted"] and not r["under_30s"]]
        print(f"Mean {statistics.mean(times):.2f} s | median {statistics.median(times):.2f} s | "
              f"p95 {percentile(times, 95):.2f} s | min {min(times):.2f} s | max {max(times):.2f} s")
        print(f"Verified: {sum(r['result'] == 'verified' for r in rows)}   "
              f"rejected: {sum(r['result'] == 'rejected' for r in rows)}")
        print(f"Under {LIMIT_SECONDS} s: {len(times) - len(slow)}/{len(times)}")
        print("RESULT: PASS" if not slow and len(times) == len(photos)
              else f"RESULT: CHECK -> slow: {slow or 'none'}; not timed: {len(photos) - len(times)}")
    print(f"Details saved to {args.out}")


if __name__ == "__main__":
    main()