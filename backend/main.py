import os
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List
import google.generativeai as genai
from dotenv import load_dotenv
from opik import track

load_dotenv()

# Initialize Opik for observability
os.environ.setdefault("OPIK_PROJECT_NAME", "flexifit-hackathon")

app = FastAPI(title="FlexiFit Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load API keys
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
if not GOOGLE_API_KEY:
    raise ValueError("GOOGLE_API_KEY not found in environment variables")

genai.configure(api_key=GOOGLE_API_KEY)

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

FEW-SHOT EXAMPLES:
- Goal: "Run 5km" | User: "I'm exhausted" 
  → "Totally get it. Rest matters. How about just walk 5 minutes to keep streak alive?"
- Goal: "Read 20 pages" | User: "No time today"
  → "Busy days happen! Can you read one page before bed? Keeps the habit pathway strong."
- Goal: "Workout 1 hour" | User: "Ready to go!"
  → "Love the energy! Go crush that workout! 💪"
"""

model = genai.GenerativeModel(model_name="gemini-1.5-flash")

class ChatMessage(BaseModel):
    role: str
    text: str

class ChatRequest(BaseModel):
    user_message: str
    current_goal: str
    chat_history: List[ChatMessage] = []

class ChatResponse(BaseModel):
    response: str

# AI wrapper function with Opik tracking
@track(name="gemini_negotiation")
def call_gemini_negotiator(user_msg: str, goal: str, history: List):
    # Combine system instruction with context
    full_prompt = f"{SYSTEM_INSTRUCTION}\n\nCONTEXT [User's Main Goal: {goal}]\nUSER SAYS: {user_msg}\n(Apply negotiation protocol based on user's energy/motivation level)"

    # Format history for Gemini
    history_formatted = [
        {"role": msg.role, "parts": [msg.text]} 
        for msg in history[-10:]  # Keep last 10 messages
    ]

    chat_session = model.start_chat(history=history_formatted)
    response = chat_session.send_message(full_prompt)
    
    return response.text

@app.get("/")
async def root():
    return {"message": "FlexiFit Backend is running!", "status": "healthy"}

@app.post("/chat", response_model=ChatResponse)
async def chat_endpoint(request: ChatRequest):
    try:
        # Call AI with Opik tracking
        ai_reply = call_gemini_negotiator(
            user_msg=request.user_message,
            goal=request.current_goal,
            history=request.chat_history
        )
        
        return ChatResponse(response=ai_reply)

    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=f"AI processing failed: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001)