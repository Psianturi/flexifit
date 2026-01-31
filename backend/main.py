import os
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import google.generativeai as genai
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
if OPIK_AVAILABLE:
    try:
        configure(project_name="flexifit-hackathon")
        OPIK_ENABLED = True
        logger.info("✓ Opik configured successfully")
    except Exception as e:
        logger.warning(f"⚠ Opik not fully configured: {e}. Continuing without observability.")
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

model = genai.GenerativeModel(model_name="gemini-2.0-flash-exp")

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
        "model": "gemini-2.0-flash-exp",
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
    try:
        # Combine system instruction with context
        full_prompt = (
            f"{SYSTEM_INSTRUCTION}\n\n"
            f"CONTEXT [User's Main Goal: {goal}]\n"
            f"USER SAYS: {user_msg}\n"
            f"(Apply negotiation protocol based on user's energy/motivation level)"
        )

        history_formatted = [
            {"role": msg.role, "parts": [msg.text]} 
            for msg in history[-9:]
        ]

        # Initialize chat session with timeout
        chat_session = model.start_chat(history=history_formatted)
        
        response = chat_session.send_message(
            full_prompt,
            request_options={"timeout": 10}
        )

        return response.text

    except TimeoutError:
        logger.error("⏱ Gemini API timeout")
        raise HTTPException(
            status_code=504,
            detail="AI response timeout. Please try again."
        )
    except google.generativeai.errors.InvalidAPIKeyError:
        logger.error("❌ Invalid Google API key")
        raise HTTPException(
            status_code=401,
            detail="AI authentication failed. Check API key."
        )
    except Exception as e:
        logger.error(f"🔥 Unexpected error in Gemini call: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"AI processing failed: {str(e)[:100]}"
        )

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
        "gemini": "ready"
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

        # Simple calculation: count messages, estimate completion
        total_chats = len(request.chat_history) + 1
        
        # Heuristic: if more messages = user is engaging
        completion_rate = min(100, (total_chats / 10) * 100)
        
        # Placeholder for AI-generated insights
        insights = "Keep up the negotiation! Your streak is important. 💪"

        progress_data = ProgressData(
            goal=request.current_goal,
            total_chats=total_chats,
            micro_habits_offered=max(1, total_chats // 3),
            completion_rate=completion_rate,
            last_interaction="Just now",
            insights=insights
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