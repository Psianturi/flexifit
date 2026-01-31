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
flutter run
```

By default, the app targets the Railway backend:
- https://flexifit-production.up.railway.app

For local dev, run Flutter with:
- `flutter run --dart-define=USE_LOCAL_API=true`

Or explicitly set any backend URL:
- `flutter run --dart-define=API_BASE_URL=https://flexifit-production.up.railway.app`

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

## Key Features

✅ **Core MVP**: AI Negotiator with BJ Fogg methodology
✅ **Stateless Architecture**: Fast deploy, no database complexity  
✅ **Context Injection**: AI "remembers" goal without server storage
✅ **Advanced Prompting**: Few-shot examples + structured negotiation protocol
✅ **Opik Integration**: Full observability for demo to judges
✅ **Smart Demo UI**: Quick reply buttons for consistent demo experience

## Key Innovation

**Context Injection Technique**: Every user message is wrapped with goal context, making AI appear "smart" without needing complex database server.

```python
context_prompt = f"USER'S GOAL: {goal}\nUSER SAYS: {message}"
```
