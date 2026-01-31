import os
import json
import re
import inspect
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import google.generativeai as genai
from google.api_core.exceptions import DeadlineExceeded, Unauthenticated
from dotenv import load_dotenv
import logging

try:
    from opik import configure, track
    OPIK_AVAILABLE = True
except Exception:
    OPIK_AVAILABLE = False

    def configure(*args, **kwargs):
        return None

    def track(*args, **kwargs):
        def _decorator(fn):
            return fn

        return _decorator

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

# Configure Opik for observability
OPIK_ENABLED = False
OPIK_CONFIG_ERROR: Optional[str] = None
if OPIK_AVAILABLE:
    try:
        opik_api_key = os.getenv("OPIK_API_KEY") or os.getenv("COMET_API_KEY")
        opik_workspace = os.getenv("OPIK_WORKSPACE") or os.getenv("COMET_WORKSPACE")
        opik_project = os.getenv("OPIK_PROJECT_NAME", "flexifit-hackathon")
        opik_url = os.getenv("OPIK_URL")

        if not opik_api_key:
            raise ValueError("OPIK_API_KEY not set")

        # Provide Comet-compatible env aliases used by some Opik SDK versions.
        os.environ.setdefault("COMET_API_KEY", opik_api_key)
        if opik_workspace:
            os.environ.setdefault("COMET_WORKSPACE", opik_workspace)

        # Hint project selection for SDKs that support env-based project routing.
        os.environ.setdefault("OPIK_PROJECT_NAME", opik_project)
        os.environ.setdefault("COMET_PROJECT_NAME", opik_project)

        # Support both older and newer Opik SDKs by only passing supported kwargs.
        sig = inspect.signature(configure)
        kwargs = {}
        if "api_key" in sig.parameters:
            kwargs["api_key"] = opik_api_key
        if "workspace" in sig.parameters:
            # If workspace is required by the SDK, surface a clear error.
            workspace_param = sig.parameters["workspace"]
            workspace_required = workspace_param.default is inspect._empty
            if workspace_required and not opik_workspace:
                raise ValueError(
                    "OPIK_WORKSPACE not set (required by installed opik SDK). "
                    "Add OPIK_WORKSPACE in Railway Variables."
                )
            if opik_workspace:
                kwargs["workspace"] = opik_workspace
        if "url" in sig.parameters and opik_url:
            kwargs["url"] = opik_url
        if "project_name" in sig.parameters:
            kwargs["project_name"] = opik_project
        elif "project" in sig.parameters:
            kwargs["project"] = opik_project

        configure(**kwargs)
        OPIK_ENABLED = True
        logger.info("✓ Opik configured successfully")
    except Exception as e:
        OPIK_CONFIG_ERROR = str(e)
        logger.warning(
            f"⚠ Opik not fully configured: {e}. Continuing without observability."
        )
else:
    logger.warning("⚠ Opik SDK not available. Continuing without observability.")

app = FastAPI(title="FlexiFit Backend", version="1.0.0")

# CORS Configuration: Tighten in production
CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load API keys with validation
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
if not GOOGLE_API_KEY:
    raise ValueError(
        "❌ GOOGLE_API_KEY not found! "
        "Please create a .env file with GOOGLE_API_KEY=your_key"
    )

genai.configure(api_key=GOOGLE_API_KEY)
logger.info("✓ Google Gemini API configured")

# Advanced negotiator persona with BJ Fogg methodology
SYSTEM_INSTRUCTION = """
ROLE:
You are FlexiFit, a behavior science-based wellness coach using BJ Fogg's Tiny Habits methodology. 
You NEVER judge. You ALWAYS look for the smallest possible step (Micro-Habit).

CONTEXT:
User has a Main Goal (provided in input).
User is currently struggling or chatting about their state.

PROTOCOL (THE "NEGOTIATION LOOP"):
1. **Acknowledge & Empathize**: Validate their feeling immediately
2. **Assess Barrier**: Is it physical fatigue, lack of time, or motivation?
3. **Propose Micro-Habit**:
   - If TIRED: Suggest 10% of goal ("Just put on your shoes")
   - If BUSY: Suggest 2-minute version ("5 squats while water boils")
   - If MOTIVATED: Cheer them on for full goal
4. **Tone Check**: Casual, warm, concise (Max 2-3 sentences)

STREAK PROTECTION:
If user repeatedly uses excuses, gently remind: "Consistency beats intensity. Even 1% effort keeps the neural pathway alive! 🧠"

FEW-SHOT EXAMPLES:
- Goal: "Run 5km" | User: "I'm exhausted" 
  → "Totally get it. Rest matters. How about just walk 5 minutes to keep streak alive?"
- Goal: "Read 20 pages" | User: "No time today"
  → "Busy days happen! Can you read one page before bed? Keeps the habit pathway strong."
- Goal: "Workout 1 hour" | User: "Ready to go!"
  → "Love the energy! Go crush that workout! 💪"
"""


def _select_gemini_model() -> str:
    requested = (os.getenv("GEMINI_MODEL") or "").strip()
    if requested.startswith("models/"):
        requested = requested[len("models/") :]

    # 1) Try requested model if provided.
    if requested:
        try:
            if hasattr(genai, "get_model"):
                genai.get_model(f"models/{requested}")
            return requested
        except Exception as e:
            logger.warning(f"Requested GEMINI_MODEL '{requested}' not available: {e}")

    # 2) Otherwise, pick the first model that supports generateContent.
    try:
        available = []
        for m in genai.list_models():
            name = getattr(m, "name", "") or ""
            methods = getattr(m, "supported_generation_methods", []) or []
            if "generateContent" not in methods:
                continue
            short = name.replace("models/", "")
            if short:
                available.append(short)

        # Prefer flash models first for speed/cost.
        for preferred in ("flash", "pro"):
            for m in available:
                if preferred in m:
                    return m
        if available:
            return available[0]
    except Exception as e:
        logger.warning(f"Could not list Gemini models: {e}")

    # 3) Last resort fallback.
    return "gemini-pro"


GEMINI_MODEL = _select_gemini_model()
model = genai.GenerativeModel(model_name=GEMINI_MODEL, system_instruction=SYSTEM_INSTRUCTION)

class ChatMessage(BaseModel):
    role: str
    text: str

class ChatRequest(BaseModel):
    user_message: str
    current_goal: str
    chat_history: List[ChatMessage] = []

class ChatResponse(BaseModel):
    response: str

class ProgressData(BaseModel):
    goal: str
    total_chats: int
    micro_habits_offered: int
    completion_rate: float
    last_interaction: Optional[str] = None
    insights: Optional[str] = None

class ProgressResponse(BaseModel):
    status: str
    data: ProgressData

# AI wrapper function with enhanced Opik tracking
@track(
    name="flexifit_negotiation",
    tags=["wellness", "behavior-science", "bj-fogg"],
    metadata={
        "model": GEMINI_MODEL,
        "methodology": "tiny-habits",
        "feature": "negotiator-loop"
    }
)
def call_gemini_negotiator(user_msg: str, goal: str, history: List[ChatMessage]):
    """
    Core negotiation engine: 
    - Receives user message + goal context
    - Returns empathetic, adaptive micro-habit proposal
    - Opik automatically logs input/output + tracing
    """
    def _history_to_transcript(items: List[ChatMessage]) -> str:
        lines: List[str] = []
        for msg in items[-12:]:
            role = (msg.role or "").strip().lower()
            text = (msg.text or "").strip()
            if not text:
                continue

            if role in {"model", "assistant", "ai", "bot"}:
                speaker = "FLEXIFIT"
            elif role in {"user", "human"}:
                speaker = "USER"
            else:
                continue

            lines.append(f"{speaker}: {text}")
        return "\n".join(lines)

    try:
        transcript = _history_to_transcript(history)
        prompt = (
            "You are FlexiFit. Follow the NEGOTIATION LOOP strictly.\n"
            "Return 2-3 short sentences max.\n\n"
            f"GOAL: {goal}\n\n"
            f"CHAT_HISTORY:\n{transcript if transcript else '(empty)'}\n\n"
            f"NEW_MESSAGE (USER): {user_msg}\n"
        )

        response = model.generate_content(
            prompt,
            request_options={"timeout": 20},
        )

        text = (response.text or "").strip()
        if not text:
            raise ValueError("Empty AI response")

        return text

    except TimeoutError:
        logger.exception("Gemini API timeout")
        raise HTTPException(status_code=504, detail="AI response timeout. Please try again.")
    except DeadlineExceeded:
        logger.exception("Gemini API deadline exceeded")
        raise HTTPException(status_code=504, detail="AI response timeout. Please try again.")
    except Unauthenticated:
        logger.exception("Gemini authentication failed")
        raise HTTPException(status_code=401, detail="AI authentication failed. Check API key.")
    except Exception as e:
        logger.exception("Unexpected error in Gemini call")
        raise HTTPException(status_code=500, detail=f"AI processing failed: {str(e)[:160]}")


def _estimate_micro_habits_offered(history: List[ChatMessage]) -> int:
    patterns = [
        r"\bhow about\b",
        r"\blet'?s\b",
        r"\bcommit\b",
        r"\bjust\b",
        r"\b2\s*-?\s*minute\b",
        r"\b5\s*-?\s*minute\b",
        r"\bmicro\s*-?\s*habit\b",
        r"\btiny\b",
    ]

    count = 0
    for msg in history:
        if msg.role not in {"model", "assistant"}:
            continue
        text = (msg.text or "").lower()
        if any(re.search(p, text) for p in patterns):
            count += 1
    return count


@track(
    name="flexifit_progress",
    tags=["progress", "wellness", "behavior-science"],
    metadata={
        "model": GEMINI_MODEL,
        "feature": "progress-insights",
    },
)
def call_gemini_progress_insights(goal: str, history: List[ChatMessage]) -> dict:
    """Generate a short progress summary from recent chat history.

    Returns a dict with:
    - insights: short string (max ~3 bullets)
    - micro_habits_offered: int estimate
    """
    transcript = "\n".join(
        [f"{m.role.upper()}: {m.text}" for m in history[-20:]]
    )

    prompt = (
        "You analyze a user's habit-coaching chat history and summarize progress. "
        "Return STRICT JSON only (no markdown).\n"
        "Keys: insights (string), micro_habits_offered (integer).\n"
        "Rules: insights must be concise, max 3 bullet points, and include one next micro-habit suggestion.\n\n"
        f"GOAL: {goal}\n\n"
        f"CHAT_HISTORY:\n{transcript}\n"
    )

    response = model.generate_content(
        prompt,
        request_options={"timeout": 10},
    )

    raw = (response.text or "").strip()
    start = raw.find("{")
    end = raw.rfind("}")
    if start != -1 and end != -1 and end > start:
        raw = raw[start : end + 1]

    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("Progress insights must be a JSON object")
    return payload

@app.get("/")
async def root():
    return {
        "message": "FlexiFit Backend is running!", 
        "status": "healthy",
        "version": "1.0.0",
        "methodology": "BJ Fogg Tiny Habits",
        "observability": "Opik Enabled" if OPIK_ENABLED else "Opik Disabled"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "opik": "configured" if OPIK_ENABLED else "disabled",
        "opik_error": None if OPIK_ENABLED else OPIK_CONFIG_ERROR,
        "gemini": "ready",
        "gemini_model": GEMINI_MODEL,
        "opik_project": os.getenv("OPIK_PROJECT_NAME", "flexifit-hackathon"),
    }

@app.post("/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):

    try:
        if not request.user_message.strip():
            raise HTTPException(status_code=400, detail="Message cannot be empty")
        
        if not request.current_goal.strip():
            raise HTTPException(status_code=400, detail="Goal must be set")

        # Call AI with enhanced Opik tracking
        ai_reply = call_gemini_negotiator(
            user_msg=request.user_message,
            goal=request.current_goal,
            history=request.chat_history
        )
        
        logger.info(f"✓ Chat processed | Goal: {request.current_goal} | Reply length: {len(ai_reply)}")
        return ChatResponse(response=ai_reply)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"🔥 Unexpected error in /chat: {str(e)}")
        raise HTTPException(status_code=500, detail="Internal server error")


@app.post("/progress", response_model=ProgressResponse)
async def progress_endpoint(request: ChatRequest) -> ProgressResponse:
    """
    Endpoint to analyze chat history and extract progress metrics.
    - Analyzes conversations to extract completion rate
    - Opik logs this analysis for hackathon evaluation
    """
    try:
        if not request.current_goal.strip():
            raise HTTPException(status_code=400, detail="Goal must be set")

        history = request.chat_history
        total_chats = len(history)

        micro_habits_heuristic = _estimate_micro_habits_offered(history)

        insights = None
        micro_habits_from_ai: Optional[int] = None
        try:
            ai_payload = call_gemini_progress_insights(request.current_goal, history)
            insights = ai_payload.get("insights")
            mh = ai_payload.get("micro_habits_offered")
            if isinstance(mh, (int, float)):
                micro_habits_from_ai = int(mh)
        except Exception as e:
            logger.warning(f"⚠ Progress insights fallback (Gemini unavailable): {e}")

        micro_habits_offered = max(
            micro_habits_heuristic,
            micro_habits_from_ai or 0,
        )

       # Calculate completion rate (capped at 100%)
        completion_rate = float(min(100.0, (min(total_chats, 10) / 10.0) * 100.0))

        if not insights or not str(insights).strip():
            insights = "- Keep the habit tiny today.\n- Pick one micro-step and do it now.\n- Consistency beats intensity."

        progress_data = ProgressData(
            goal=request.current_goal,
            total_chats=total_chats,
            micro_habits_offered=micro_habits_offered,
            completion_rate=completion_rate,
            last_interaction="recent",
            insights=str(insights),
        )

        return ProgressResponse(status="success", data=progress_data)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"🔥 Error in /progress: {str(e)}")
        raise HTTPException(status_code=500, detail="Progress calculation failed")


if __name__ == "__main__":
    logger.info("🚀 Starting FlexiFit Backend...")
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8000)))