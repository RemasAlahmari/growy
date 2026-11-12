# Growy backend (FastAPI)

## First-time setup (Windows, from the repo root)

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # if blocked: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
pip install -r requirements-dev.txt
copy .env.example .env          # macOS/Linux: cp .env.example .env
```

Then edit `backend/.env`. **Only `GEMINI_API_KEY` is needed to try the app**; everything
else works without accounts:

| Variable | What to put |
|---|---|
| `GEMINI_API_KEY` | Free key from https://aistudio.google.com/apikey: choose **Create API key in new project**, not the Firebase project. Without it, everything works except photo verification (503) |
| `GEMINI_MODEL` | Leave as `gemini-3.5-flash-lite`; if it errors, try `gemini-3.1-flash-lite` |
| `DATABASE_URL` | Leave **empty** to use a local test database (`backend/growy_local.db`, created automatically). For the team's shared data, paste the Supabase connection string (ask Layan); at home, use the **Session pooler** string if the direct one fails |
| `FIREBASE_PROJECT_ID` | `growy-4036d` (the app's project). Logins are checked with this ID and Google's public certificates, so no key file is needed; the server needs internet for that |
| `FIREBASE_SERVICE_ACCOUNT` / `FIREBASE_CREDENTIALS` | Optional service-account key (the whole JSON, or a file path). Used instead of the project ID if present; `backend/firebase-service-account.json` is also picked up automatically |
| `CORS_ORIGINS` | Only for a deployed Flutter Web app. Local web (localhost, any port) already works |

`backend/.env`, `growy_local.db` and the service-account JSON are git-ignored. Never commit them.
To start the local database from scratch, stop the server and delete `backend/growy_local.db`.

## Run

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Run it from inside `backend/`. `--host 0.0.0.0` lets the Android emulator and phones on
the same Wi-Fi reach it.

On startup the server creates missing tables and columns, and adds the four default
habits (Reading, Walking, Workout, Drink Water) and the seven default groups if they
are missing. To also refresh the habits' points and photo instructions, run
`python seed_habits.py`. There is no "create group" screen yet, so new groups are
added to `ROOMS` in `seed_groups.py`.

Check http://localhost:8000/health. You should see (`database_type` is `postgresql` with Supabase):

```json
{"status": "ok", "database": "ok", "database_type": "sqlite", "login_check": "project_id:growy-4036d", "ai_configured": true, "ai_model": "gemini-3.5-flash-lite"}
```

Interactive docs (try every endpoint): http://localhost:8000/docs

## Tests (no Supabase, Firebase or Gemini needed)

```bash
pytest -v
```

## Endpoints used by the app

All except `/health` need `Authorization: Bearer <Firebase ID token>`.

| Method | Path | Used by |
|---|---|---|
| GET | `/health` | Developers: server, database and AI status |
| POST | `/users/sync?username=&gender=` | Sign Up and every Login: creates the user row if it is missing (see "Usernames") |
| GET | `/users/me` | Home header, Me page (points, level, streaks, gender...) |
| PUT | `/users/me` | Edit Profile (`username`, `display_name`, `gender`); 409 = username taken |
| GET / PUT | `/users/me/avatar` | Avatar colours |
| GET | `/habits` | All habits (id, name, points, ai_label) |
| GET | `/habits/today` | Home habit cards (done today? streak) |
| GET | `/habit-logs?month=YYYY-MM` | Habits page history |
| POST | `/habits/{id}/complete/ai` | Verify screen (photo upload) |
| GET | `/progress` | Last 7 days stats (no screen uses it yet) |
| POST / DELETE | `/users/me/photo` | Me page profile photo (multipart field `file`) |
| GET | `/photos/{token}.jpg` | Shows a saved photo (no login needed: the random token is the key) |
| GET | `/groups/mine`, `/groups/discover` | Groups screen and the Home "Groups to join" strip |
| POST | `/groups/{id}/join`, `/groups/join` (`{"room_code": "STUDY24"}`) | Join from a card / with a code (404 = unknown code) |
| POST / DELETE | `/groups/{id}/dismiss` | "Not interested" / Undo |
| DELETE | `/groups/{id}/membership` | Leave a group |
| GET | `/groups/{id}/leaderboard` | Group page leaderboard and member list (members only, else 403) |

A `503` on any endpoint with "can't check logins" means the server has no internet
connection to download Google's login certificates.

A `404 User not found` means the Firebase account has no row in this database yet.
The app fixes that by calling `/users/sync` automatically.

## Usernames

Sign Up accepts any text, but usernames must be 3–20 letters, numbers or underscores
and unique (ignoring upper/lower case), the same rule as Edit Profile. So
`/users/sync` makes the typed name valid and unique: `Sara Ahmed` → `SaraAhmed`,
an Arabic name → a name made from the email, a taken `sara` → `sara2`. When the
username differs from what was typed, the typed text becomes the display name.

## Levels

`leveling.py`: Level 0 = 0–99 XP, 1 = 100+, 2 = 500+, 3 = 1500+, 4 = 3000+ (max).
The app's progress bars use the same numbers.

## AI photo verification

`POST /habits/{habit_id}/complete/ai` (multipart field `file`).
Gemini classifies the photo's activity; it passes only if
`detected_activity == habit` **and** `evidence == activity_in_progress` **and** `confidence != low`.
The prompt and rules live in `ai_verification.py`.

| Status | Meaning |
|---|---|
| 200 | Checked: `verification_status` is `verified` (points added) or `rejected` (uses 1 of 3 daily attempts) |
| 400 | Habit has no AI mapping (add it to `HABIT_ACTIVITY`) |
| 404 | Habit not found, or user never synced |
| 409 | Already verified today |
| 413 | Image over 5 MB |
| 415 | Not a JPG/PNG/WEBP or unreadable |
| 429 | 3 rejected photos today for this habit: try again tomorrow |
| 503 | Gemini unavailable / rate-limited / key missing: nothing saved, the attempt doesn't count |

## Groups

- A member's points in a group = XP from verified habits **after** joining it.
- Leaderboard: most points first; ties go to whoever joined first.
- Group goal: XP all current members earned together this calendar month (Saudi time).
- The invite code is only sent to members.

## Photos

Verified habit photos and profile photos are stored in the database as small JPEGs
(max 640 px, quality 75), so no paid storage service is needed. Each photo is
served at `/photos/<random token>.jpg`: the address can't be guessed, but anyone who
has it can open the photo. Rejected photos are not stored.
