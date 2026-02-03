# FlexiFit - AI Wellness Negotiator

An AI application that helps maintain healthy habit streaks through smart negotiation, not force.

##  Quick Start

### 1. Backend Setup
```bash
cd backend
pip install -r requirements.txt

# copy and fill your keys
copy .env.example .env

# run (Windows/macOS/Linux)
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Backend will run at `http://localhost:8000`.

More details: see [backend/README.md](backend/README.md).

### 2. Frontend Setup
```bash
cd frontend/flexifit_app
flutter pub get
```

#### Run on Browser (Chrome / Edge)
```bash
flutter devices
flutter run -d chrome
# or
flutter run -d edge
```

#### Run on Physical Device / Emulator
```bash
flutter devices
flutter run -d <device-id>
```

If you want to use an Android emulator:
```bash
flutter emulators
flutter emulators --launch <emulator-id>
flutter run -d <device-id>
```

#### API Base URL (no hardcoded URL)
Set the backend URL at runtime using `--dart-define`:
```bash
# Local backend
flutter run -d <device-id> --dart-define=API_BASE_URL=http://localhost:8000

# Deployed backend
flutter run -d <device-id> --dart-define=API_BASE_URL=<your-backend-url>
```

If you prefer a boolean flag for local dev (if supported in your build):
```bash
flutter run -d <device-id> --dart-define=USE_LOCAL_API=true
```

##  Testing Scenarios

### Test 1: Goal Setting
1. Open app → Dialog appears
2. Input: "Run 5km every day"
3. Expected: Goal saved, chat starts

### Test 2: Negotiation Logic
1. Chat: "I'm really tired today"
2. Expected: AI validates feelings + offers micro-habit
3. Example response: "I understand you're tired. How about just a 10-minute walk?"

### Test 3: Motivation Mode
1. Chat: "Ready for action!"
2. Expected: AI provides encouragement + actionable steps

##  Troubleshooting

### Backend Issues
- Check API key in `.env`
- Test endpoint: `http://localhost:8000/docs`

### Frontend Issues
- Ensure `baseUrl` matches environment
- Check Flutter console for HTTP errors

##  Deployment Ready

### Backend → Railway
1. Push to GitHub
2. Connect Railway → Deploy from GitHub
3. Set Railway Variables (`GOOGLE_API_KEY`, `OPIK_API_KEY`)
4. Deploy using the monorepo Dockerfile setup (details in [backend/README.md](backend/README.md))
5. Update Flutter `baseUrl` with the Railway public URL

### Frontend → APK
```bash
flutter build apk --release
```

### Frontend (Flutter Web) → Vercel (GitHub Actions CI/CD)

This option builds Flutter Web in **GitHub Actions** and deploys the generated static site to **Vercel**.
You do **not** need Flutter installed on Vercel.

#### 1) Create a Vercel Project (one-time)
- Create a new project in Vercel (Dashboard).
- The deployment will be done by GitHub Actions using the Vercel CLI.

#### 2) Add GitHub Actions secrets (one-time)
In GitHub: **Settings → Secrets and variables → Actions → Secrets**, add:
- `VERCEL_TOKEN` (used by GitHub Actions to authenticate to Vercel)
- `VERCEL_ORG_ID` (tells GitHub Actions which Vercel team/org to deploy into)
- `VERCEL_PROJECT_ID` (tells GitHub Actions which Vercel project to deploy)

Important: these are **NOT** the same as app/runtime environment variables.

- `VERCEL_TOKEN` / `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID` are only for **GitHub Actions → Vercel deployment authentication + selecting the target Vercel project**.
- Things like **Gemini API key** belong to the backend (Railway) and are set in Railway variables.
- Things like **API base URL** for the Flutter app are set as **GitHub Actions Variables** and baked into the web build via `--dart-define`.

So: you do **not** put `VERCEL_TOKEN` etc into Vercel “Environment Variables” for the app. They live in **GitHub Secrets** so CI can deploy.

How to get `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` (recommended):
```bash
cd frontend/flexifit_app
npm i -g vercel
vercel login
vercel link

# after linking, read IDs from:
# .vercel/project.json
```

What is inside `.vercel/project.json` (example):
```json
{
	"orgId": "team_xxxxxxxxxxxxxxxxx",
	"projectId": "prj_xxxxxxxxxxxxxxxxx"
}
```

How to get `VERCEL_TOKEN`:
- Vercel Dashboard → your **Avatar/Profile** → **Settings** → **Tokens** → create a token.

Alternative (Dashboard):
- Vercel Dashboard → your Project → **Settings → General** → copy **Project ID**
- For `VERCEL_ORG_ID`: open **Team/Account settings** (or use the `.vercel/project.json` method above)

Tip: do **not** commit the `.vercel/` folder to git.

#### 3) (Optional) Set GitHub Actions variables for build-time config
In GitHub: **Settings → Secrets and variables → Actions → Variables**, add:
- `API_BASE_URL` (example: `https://flexifit-production.up.railway.app`)
- `SHOW_DEBUG_EVALS` (`false` recommended for prod)

These are injected into `flutter build web` using `--dart-define`.

Note: `--dart-define` is **build-time** for Flutter Web. Changing Vercel environment variables after deploy will **not** change the already-built web bundle.

#### 4) Deploy
- Push to `main`.
- Workflow: `.github/workflows/deploy_flutter_web_vercel.yml` builds and deploys.

Notes:
- Flutter Web is a single-page app; we include a `vercel.json` route rule to rewrite unknown routes to `index.html`.
- If your backend restricts CORS origins, add your Vercel domain to backend `CORS_ORIGINS`.

#### Will the app still work as a static site?
Yes. Flutter Web builds into a client-side single-page app (static HTML/CSS/JS). Features remain active because:
- **Chat / persona / insights**: still call your backend over HTTPS (`API_BASE_URL`).
- **Journey history / streak / local state**: stored in the browser (SharedPreferences → browser storage). It will persist on the same browser/device, but it won’t sync across devices unless you add a real database/auth later.

Common gotchas on web:
- Make sure backend **CORS** allows your Vercel domain.
- Microphone / speech-to-text depends on browser support + HTTPS permissions.

## Key Features

✅ **Core MVP**: AI Negotiator with BJ Fogg methodology
✅ **Stateless Architecture**: Fast deploy, no database complexity  
✅ **Context Injection**: AI "remembers" goal without server storage
✅ **Advanced Prompting**: Few-shot examples + structured negotiation protocol
✅ **Opik Integration**: End-to-end observability (traces + metrics)
✅ **Smart Demo UI**: Quick reply buttons for consistent demo experience

## Key Innovation

**Context Injection Technique**: Every user message is wrapped with goal context, making AI appear "smart" without needing complex database server.

```python
context_prompt = f"USER'S GOAL: {goal}\nUSER SAYS: {message}"
```

## Evaluation + Observability (Opik)

We implemented a **closed-loop, self-improving AI system** using Opik tracing + online LLM-based evaluations:

1. **Real-time evaluation:** Every AI response is scored on **Empathy (1-5)** with a human-readable rationale.
2. **Automated self-correction:** If the score falls below a threshold, the backend automatically rewrites the response once **before** returning it to the user.
3. **Scientific Experiments:** A golden-dataset experiment runner ([backend/evals/run_experiment.py](backend/evals/run_experiment.py)) runs fixed scenarios across prompt/model versions and logs results to Opik for comparison.
4. **Client-Side Debugging:** A Flutter debug overlay (enabled via `--dart-define=SHOW_DEBUG_EVALS=true`) shows empathy score + rationale in real time without affecting production UX.
