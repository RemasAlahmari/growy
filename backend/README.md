# Growy backend (FastAPI)

## First-time setup (Windows, from the repo root)

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # if blocked: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
pip install -r requirements-dev.txt
copy .env.example .env          # macOS/Linux: cp .env.example .env
```

Then edit `backend/.env`:

| Variable | What to put |
|---|---|
| `DATABASE_URL` | The Supabase connection string (ask Layan) |
| `GEMINI_API_KEY` | Free key from https://aistudio.google.com/apikey: choose **Create API key in new project**, not the Firebase project |
| `GEMINI_MODEL` | Leave as `gemini-3.5-flash-lite`; if it errors, try `gemini-3.1-flash-lite` |
| `FIREBASE_CREDENTIALS` | Leave as is, and put the private `firebase-service-account.json` in `backend/` |

`backend/.env` and the service-account JSON are git-ignored. Never commit them.

Load the habit list (safe to re-run; it updates existing rows):

```bash
python seed_habits.py
```

## Run

```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Run it from inside `backend/`. Check http://localhost:8000/health: you should see
`"ai_configured": true`. Interactive docs are at http://localhost:8000/docs.

## Tests (no Supabase, Firebase or Gemini needed)

```bash
pytest -v
```

## AI photo verification

`POST /habits/{habit_id}/complete/ai` (multipart field `file`, Firebase `Bearer` token).
Gemini classifies the photo's activity; it passes only if
`detected_activity == habit` **and** `evidence == activity_in_progress` **and** `confidence != low`.
The prompt and rules live in `ai_verification.py`.

| Status | Meaning |
|---|---|
| 200 | Checked: `verification_status` is `verified` (points added) or `rejected` |
| 400 | Habit has no AI mapping (add it to `HABIT_ACTIVITY`) |
| 404 | Habit not found, or user never synced |
| 409 | Already verified today |
| 413 | Image over 5 MB |
| 415 | Not a JPG/PNG or unreadable |
| 503 | Gemini unavailable / rate-limited / key missing: nothing saved, try again |
