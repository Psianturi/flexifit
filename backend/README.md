# FlexiFit Backend (FastAPI + Gemini + Opik)

This backend is the “brain” for FlexiFit.
- Provides `/chat` for the AI Negotiator
- Provides `/progress` as the foundation for the Progress tab
- Uses **Google Gemini** for responses
- Uses **Comet Opik** for observability/tracing (hackathon requirement)

## Endpoints

- `GET /health` → health status + whether Opik is enabled
- `POST /chat` → main chat endpoint (goal + message + history)
- `POST /progress` → basic progress metrics (MVP)
- `GET /docs` → Swagger UI

## Environment Variables

Create `backend/.env` locally (never commit it):

- `GOOGLE_API_KEY` (required) — Gemini API key
- `OPIK_API_KEY` (recommended) — Opik API key
- `PORT` (optional) — default `8000`
- `CORS_ORIGINS` (optional) — default `*` (comma-separated if multiple)

Example: see `backend/.env.example`.

## Local Development

You have 2 correct ways to run locally. Pick ONE.

### Option A (recommended): run from `backend/` folder

From the repo root:

```bash
cd backend
pip install -r requirements.txt

# copy and fill your keys
copy .env.example .env

# run
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Option B: run from repo root (module path)

If you prefer not to `cd backend`, run this from the repo root:

```bash
pip install -r backend/requirements.txt

python -m uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

Then open:
- `http://localhost:8000/docs`
- `http://localhost:8000/health`

## Opik Notes (Important)

Opik is **intentionally resilient** in this project:
- If Opik installs + config succeeds → `OPIK_ENABLED = True` and `@track(...)` will record traces.
- If Opik is missing or misconfigured → the backend still runs (so demos don’t die), but `/health` will show Opik as disabled.

To verify Opik is active:
1. Set `OPIK_API_KEY` in Railway Variables (or local `.env`)
2. Redeploy / restart
3. Check `GET /health` — it should show `"opik": "configured"`

## Experiments (Golden Dataset)

To demonstrate **data-driven improvement**, run a small golden-dataset experiment that logs traces + online evals:

```bash
cd backend

# (optional) enable the self-correction loop for this run
set RETRY_ON_LOW_EMPATHY=true
set RETRY_EMPATHY_THRESHOLD=3

python evals/run_experiment.py --base-url http://localhost:8000 --label v1
```

Tips for judging:
- Change `PROMPT_VERSION` (and/or `GEMINI_MODEL`) and rerun with a new `--label`.
- In Opik, filter traces by `name=flexifit_experiment_case` and compare score distributions.

## Railway Deployment (Monorepo)

This repo is a monorepo:
- `backend/` (Python API)
- `frontend/` (Flutter app)

Railway can get confused if it tries to auto-detect from the repo root. The working setup here forces **Dockerfile builds**:

### 1) Connect GitHub repo
- Railway → New Project → Deploy from GitHub → select `flexifit`

### 2) Set Variables
In Railway → Service → Variables:
- `GOOGLE_API_KEY=...`
- `OPIK_API_KEY=...`
- (optional) `CORS_ORIGINS=*`

### 3) Build configuration
This project includes config-as-code at repo root:
- `railway.toml` and `railway.json`

They force Railway to build using:
- `backend/Dockerfile`

If Railway still doesn’t pick it up, set in Railway Variables:
- `RAILWAY_DOCKERFILE_PATH=backend/Dockerfile`

### 4) Confirm deploy
After deployment:
- Visit `/health` and `/docs`
- Ensure the service is “Exposed” publicly (Railway networking settings)

## Troubleshooting

### ERROR: `Could not import module "main"`
This happens when you run `python -m uvicorn main:app ...` from the repo root.

Fix:
- Either `cd backend` first (Option A)
- Or run `python -m uvicorn backend.main:app ...` from repo root (Option B)

### Build fails on dependencies
- Check `backend/requirements.txt` versions
- Common issue: pinning a package version that does not exist on PyPI

### Opik shows disabled
- Confirm `OPIK_API_KEY` is set
- Check Railway logs for Opik configuration warnings

### Flutter can’t reach backend
- Use the Railway public URL in Flutter `baseUrl`
- Android emulator uses `10.0.2.2` only for local dev, not Railway
