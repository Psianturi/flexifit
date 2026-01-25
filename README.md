# FlexiFit - AI Wellness Negotiator

An AI application that helps maintain healthy habit streaks through smart negotiation, not force.

##  Quick Start

### 1. Backend Setup
```bash
cd backend
pip install -r requirements.txt

# Edit .env file and add API keys:
# GOOGLE_API_KEY=your_gemini_api_key_here
# OPIK_API_KEY=your_opik_api_key_here (register at comet.com/opik)

python main.py
```

Backend will run at `http://localhost:8000`

### 2. Frontend Setup
```bash
cd frontend/flexifit_app
flutter pub get
flutter run
```

**IMPORTANT**: Update `baseUrl` in `lib/api_service.dart`:
- Android Emulator: `http://10.0.2.2:8000`
- iOS Simulator: `http://localhost:8000`
- Physical Device: `http://[LAPTOP_IP]:8000`

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
2. Connect Railway → Auto deploy
3. Update Flutter `baseUrl` with Railway URL

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

## 💡 Key Innovation

**Context Injection Technique**: Every user message is wrapped with goal context, making AI appear "smart" without needing complex database server.

```python
context_prompt = f"USER'S GOAL: {goal}\nUSER SAYS: {message}"
```

This is the secret sauce that makes FlexiFit unique!