import os
import json
import re
import inspect
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi import Request
from pydantic import BaseModel
from typing import List, Optional, Any
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


_ID_STOPWORDS = {
    # A lightweight heuristic list to detect Indonesian output.
    "yang",
    "untuk",
    "dan",
    "dari",
    "dengan",
    "kamu",
    "anda",
    "ayo",
    "hari",
    "ini",
    "jangan",
    "bisa",
    "saja",
    "lebih",
    "mulai",
    "waktu",
    "ambil",
    "buku",
    "bukumu",
    "baca",
    "satu",
    "halaman",
    "tetap",
    "semangat",
    "karena",
    "kalau",
    "banget",
}


_LANGUAGE_NAME = {
    "en": "English",
    "id": "Indonesian",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
    "pt": "Portuguese",
    "it": "Italian",
    "nl": "Dutch",
    "tr": "Turkish",
    "ar": "Arabic",
    "hi": "Hindi",
    "ja": "Japanese",
    "ko": "Korean",
    "zh": "Chinese",
}


def _normalize_language(lang: Optional[str]) -> str:
    """Normalize BCP-47/locale strings to a primary language code.

    Examples: 'en-US' -> 'en', 'id_ID' -> 'id'.
    """

    if not lang:
        return "en"

    raw = str(lang).strip().lower().replace("_", "-")
    if not raw:
        return "en"

    primary = raw.split("-")[0]
    if not re.match(r"^[a-z]{2,3}$", primary):
        return "en"
    return primary


def _language_label(lang: Optional[str]) -> str:
    code = _normalize_language(lang)
    return _LANGUAGE_NAME.get(code, code)


def _coerce_insights_bullets(value: Any) -> str:
    """Coerce model output into a newline-separated bullet string.

    Prevents UI issues where a Python/JSON list ends up being stringified like
    "['a', 'b']".
    """

    if value is None:
        return ""

    if isinstance(value, (list, tuple)):
        items = [str(v).strip() for v in value if str(v).strip()]
        return "\n".join([f"- {i.lstrip('-').strip()}" for i in items])

    text = str(value).strip()
    if not text:
        return ""

    # If the model returned something list-like as a string, try to recover.
    if text.startswith("[") and text.endswith("]"):
        try:
            decoded = json.loads(text)
            if isinstance(decoded, list):
                items = [str(v).strip() for v in decoded if str(v).strip()]
                return "\n".join([f"- {i.lstrip('-').strip()}" for i in items])
        except Exception:
            pass

    # Ensure bullets.
    lines = [l.strip() for l in text.split("\n") if l.strip()]
    if not lines:
        return ""

    normalized: List[str] = []
    for line in lines:
        if line.startswith("- "):
            normalized.append(line)
        elif line.startswith("• "):
            normalized.append("- " + line[2:].strip())
        else:
            normalized.append("- " + line.lstrip("-").strip())

    return "\n".join(normalized)


def _looks_indonesian(text: str) -> bool:
    if not text:
        return False
    # Keep only letters/spaces for tokenization.
    cleaned = re.sub(r"[^A-Za-z\s]", " ", text).lower()
    tokens = [t for t in cleaned.split() if t]
    if not tokens:
        return False
    hits = sum(1 for t in tokens if t in _ID_STOPWORDS)
    # Require multiple hits to reduce false positives.
    return hits >= 2 or (hits >= 1 and (hits / max(1, len(tokens))) >= 0.20)

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


@app.middleware("http")
async def _opik_flush_middleware(request: Request, call_next):
    response = await call_next(request)
    if OPIK_ENABLED and OPIK_AVAILABLE:
        try:
            import opik as _opik

            flush_fn = getattr(_opik, "flush", None)
            if callable(flush_fn):
                flush_fn()
        except Exception:
            # Never fail requests due to observability.
            pass
    return response

# CORS Configuration: Tighten in production

raw_cors_origins = os.getenv("CORS_ORIGINS", "*")
CORS_ORIGINS = [o.strip() for o in raw_cors_origins.split(",") if o.strip()]
_cors_has_wildcard = "*" in CORS_ORIGINS

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if _cors_has_wildcard else CORS_ORIGINS,
    allow_credentials=False if _cors_has_wildcard else True,
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
PROMPT_VERSION = (os.getenv("PROMPT_VERSION") or "v1").strip() or "v1"
model = genai.GenerativeModel(model_name=GEMINI_MODEL, system_instruction=SYSTEM_INSTRUCTION)

class ChatMessage(BaseModel):
    role: str
    text: str

class ChatRequest(BaseModel):
    user_message: str
    current_goal: str
    chat_history: List[ChatMessage] = []
    language: Optional[str] = None

class ChatResponse(BaseModel):
    response: str
    deal_made: Optional[bool] = None
    deal_label: Optional[str] = None
    empathy_score: Optional[float] = None
    empathy_rationale: Optional[str] = None
    prompt_version: Optional[str] = None
    retry_used: Optional[bool] = None
    initial_empathy_score: Optional[float] = None


_DEAL_TAG_RE = re.compile(r"<DEAL>(.*?)</DEAL>", re.IGNORECASE | re.DOTALL)


def _extract_deal_meta(text: str) -> tuple[str, Optional[str]]:
    """Extract an optional deal label embedded by the model.

    The model may append a line like: <DEAL>put on your shoes</DEAL>
    We strip the tag from the user-visible response and return deal_label.
    """

    raw = (text or "").strip()
    if not raw:
        return "", None

    match = _DEAL_TAG_RE.search(raw)
    if not match:
        return raw, None

    label = (match.group(1) or "").strip()
    cleaned = _DEAL_TAG_RE.sub("", raw).strip()
    # Clean up any leftover blank lines introduced by stripping.
    cleaned = "\n".join([l.rstrip() for l in cleaned.splitlines() if l.strip()]).strip()

    return cleaned, (label or None)

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


class DayCompletion(BaseModel):
    date: str
    done: bool


class WeeklyMotivationRequest(BaseModel):
    goal: str
    completion_rate_7d: float
    last7_days: List[DayCompletion]
    language: Optional[str] = None


class WeeklyMotivationData(BaseModel):
    motivation: str


class WeeklyMotivationResponse(BaseModel):
    status: str
    data: WeeklyMotivationData


class PersonaRequest(BaseModel):
    current_goal: str
    completion_rate_7d: float = 0.0
    streak: int = 0
    last7_days: List[DayCompletion] = []
    chat_history: List[ChatMessage] = []
    language: Optional[str] = None


class PersonaData(BaseModel):
    archetype_title: str
    description: str
    avatar_id: str
    power_level: int


class PersonaResponse(BaseModel):
    status: str
    data: PersonaData

# AI wrapper function with enhanced Opik tracking
@track(
    name="flexifit_negotiation",
    tags=["wellness", "behavior-science", "bj-fogg"],
    metadata={
        "model": GEMINI_MODEL,
        "prompt_version": PROMPT_VERSION,
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
            "If you propose a specific micro-habit for today, append ONE final line exactly in this format: <DEAL>your micro-habit</DEAL>. "
            "This deal line is metadata and does not count as a sentence.\n\n"
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


@track(
    name="flexifit_negotiation_retry",
    tags=["wellness", "behavior-science", "bj-fogg", "retry"],
    metadata={
        "model": GEMINI_MODEL,
        "prompt_version": PROMPT_VERSION,
        "feature": "negotiator-loop-retry",
    },
)
def call_gemini_negotiator_retry(
    user_msg: str,
    goal: str,
    history: List[ChatMessage],
    previous_reply: str,
    judge_score: int,
    judge_rationale: str,
) -> str:
    """Second-pass rewrite when the judge flags low empathy.

    Intentionally capped to 1 retry to control latency/cost.
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

    transcript = _history_to_transcript(history)
    prompt = (
        "You are FlexiFit. Your previous reply was judged as not empathetic enough. "
        "Rewrite it to be more validating and more micro-habit-focused, while staying concise.\n"
        "Constraints:\n"
        "- 2-3 short sentences max\n"
        "- Validate feelings first\n"
        "- Propose ONE tiny, doable micro-habit\n"
        "- No judgement, no lecturing\n\n"
        "If you propose a specific micro-habit for today, append ONE final line exactly in this format: <DEAL>your micro-habit</DEAL>. "
        "This deal line is metadata and does not count as a sentence.\n\n"
        f"GOAL: {goal}\n\n"
        f"CHAT_HISTORY:\n{transcript if transcript else '(empty)'}\n\n"
        f"NEW_MESSAGE (USER): {user_msg}\n\n"
        f"PREVIOUS_REPLY: {previous_reply}\n"
        f"JUDGE_SCORE: {judge_score}/5\n"
        f"JUDGE_RATIONALE: {judge_rationale}\n"
    )

    response = model.generate_content(
        prompt,
        request_options={"timeout": 20},
    )

    text = (response.text or "").strip()
    if not text:
        raise ValueError("Empty AI response (retry)")
    return text


@track(
    name="flexifit_eval_empathy",
    tags=["eval", "llm-as-judge", "empathy"],
    metadata={
        "model": GEMINI_MODEL,
        "prompt_version": PROMPT_VERSION,
        "metric": "empathy_score",
        "scale": "1_to_5",
    },
)
def call_gemini_empathy_judge(user_text: str, ai_text: str) -> dict:
    """Return a strict JSON dict: { empathy: 1..5, rationale: string }.

    This is an online LLM-as-a-judge evaluation for every AI reply.
    """
    prompt = (
        "You are an evaluator for a habit-coaching AI. "
        "Score the AI reply for EMPATHY + MICRO-HABIT behavior. "
        "Return STRICT JSON only (no markdown).\n"
        "Schema: {\"empathy\": 1|2|3|4|5, \"rationale\": \"...\"}.\n"
        "Scoring (1-5):\n"
        "- 5: Clearly validates feelings + proposes an ultra-small, doable micro-habit + supportive tone.\n"
        "- 4: Validates feelings + proposes a realistic micro-habit, minor wording issues.\n"
        "- 3: Some empathy OR some micro-habit, but not both strongly.\n"
        "- 2: Weak empathy and vague/too-big action step.\n"
        "- 1: No empathy, dismissive, or no actionable micro-habit.\n\n"
        f"USER: {user_text}\n"
        f"AI: {ai_text}\n"
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
        raise ValueError("Empathy evaluation must be a JSON object")

    empathy = payload.get("empathy")
    if isinstance(empathy, bool):
        empathy = 5 if empathy else 1
    if not isinstance(empathy, (int, float)):
        raise ValueError("Empathy must be 1..5")


    empathy = int(round(float(empathy)))
    empathy = max(1, min(5, empathy))
    rationale = payload.get("rationale")
    rationale_text = str(rationale).strip() if rationale is not None else ""

    return {"empathy": empathy, "rationale": rationale_text}


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
        "prompt_version": PROMPT_VERSION,
        "feature": "progress-insights",
    },
)
def call_gemini_progress_insights(
    goal: str,
    history: List[ChatMessage],
    language: Optional[str] = None,
) -> dict:
    """Generate a short progress summary from recent chat history.

    Returns a dict with:
    - insights: short string (max ~3 bullets)
    - micro_habits_offered: int estimate
    """
    transcript = "\n".join(
        [f"{m.role.upper()}: {m.text}" for m in history[-20:]]
    )

    lang_label = _language_label(language)

    prompt = (
        "You analyze a user's habit-coaching chat history and summarize progress. "
        f"Write in {lang_label}. Return STRICT JSON only (no markdown).\n"
        "Keys: insights (string), micro_habits_offered (integer).\n"
        "Rules:\n"
        "- insights must be a single STRING with 2–3 bullet lines, each starting with '- '.\n"
        "- Include exactly one next micro-habit suggestion as the final bullet.\n"
        "- Keep each bullet short and concrete.\n\n"
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

    # Coerce insights to a clean bullet string (handles list outputs).
    payload["insights"] = _coerce_insights_bullets(payload.get("insights"))
    insights_text = str(payload.get("insights") or "").strip()

    if _normalize_language(language) == "en" and insights_text and _looks_indonesian(insights_text):
        retry_prompt = (
            "You analyze a user's habit-coaching chat history and summarize progress. "
            "IMPORTANT: Write in English only. If the chat history contains Indonesian, translate it and still answer in English. "
            "Return STRICT JSON only (no markdown).\n"
            "Keys: insights (string), micro_habits_offered (integer).\n"
            "Rules:\n"
            "- insights must be a single STRING with 2–3 bullet lines, each starting with '- '.\n"
            "- Include exactly one next micro-habit suggestion as the final bullet.\n"
            "- Keep each bullet short and concrete.\n\n"
            f"GOAL: {goal}\n\n"
            f"CHAT_HISTORY:\n{transcript}\n"
        )
        try:
            retry = model.generate_content(
                retry_prompt,
                request_options={"timeout": 10},
            )
            retry_raw = (retry.text or "").strip()
            s = retry_raw.find("{")
            e = retry_raw.rfind("}")
            if s != -1 and e != -1 and e > s:
                retry_raw = retry_raw[s : e + 1]
            retry_payload = json.loads(retry_raw)
            if isinstance(retry_payload, dict):
                retry_payload["insights"] = _coerce_insights_bullets(retry_payload.get("insights"))
                retry_insights = str(retry_payload.get("insights") or "").strip()
                if retry_insights and not _looks_indonesian(retry_insights):
                    payload = retry_payload
        except Exception:
            pass

    final_insights = str(payload.get("insights") or "").strip()
    if not final_insights:
        payload["insights"] = "- Keep the habit tiny today.\n- Pick one micro-step and do it now.\n- Consistency beats intensity."
    elif _normalize_language(language) == "en" and _looks_indonesian(final_insights):
        payload["insights"] = "- Keep the habit tiny today.\n- Pick one micro-step and do it now.\n- Consistency beats intensity."

    return payload


@track(
    name="flexifit_weekly_motivation",
    tags=["progress", "motivation", "weekly"],
    metadata={
        "model": GEMINI_MODEL,
        "prompt_version": PROMPT_VERSION,
        "feature": "weekly-motivation",
    },
)
def call_gemini_weekly_motivation(
    goal: str,
    completion_rate_7d: float,
    last7_days: List[DayCompletion],
    language: Optional[str] = None,
) -> str:
    done_days = sum(1 for d in last7_days if bool(d.done))
    total_days = max(1, len(last7_days))

    days_compact = ", ".join(
        [f"{d.date}:{'done' if d.done else 'miss'}" for d in last7_days]
    )

    lang_label = _language_label(language)

    prompt = (
        "You are a tough-but-supportive fitness coach. "
        f"Return ONLY ONE sentence in {lang_label} (no markdown, no bullet points). "
        "Keep it short (max 20 words), direct, and motivating.\n\n"
        f"GOAL: {goal}\n"
        f"WEEKLY_COMPLETION_RATE: {completion_rate_7d:.0f}%\n"
        f"LAST_7_DAYS: {days_compact}\n"
        f"DONE_DAYS: {done_days}/{total_days}\n"
    )

    response = model.generate_content(
        prompt,
        request_options={"timeout": 10},
    )

    text = (response.text or "").strip()
    # Keep it a single line/sentence.
    text = re.sub(r"\s+", " ", text)
    text = text.strip().strip("\"").strip()

    if _normalize_language(language) == "en" and _looks_indonesian(text):
        rewrite_prompt = (
            "Rewrite the following text into English. "
            "Return ONLY ONE sentence, max 20 words, no markdown, no bullet points. "
            "Do NOT include any Indonesian words.\n\n"
            f"TEXT: {text}\n"
        )
        try:
            rewrite = model.generate_content(
                rewrite_prompt,
                request_options={"timeout": 10},
            )
            rewritten = re.sub(r"\s+", " ", (rewrite.text or "").strip())
            rewritten = rewritten.strip().strip("\"").strip()
            if rewritten and not _looks_indonesian(rewritten):
                text = rewritten
        except Exception:
            pass

    if not text:
        return "Tiny steps count—do the smallest version today and keep the streak alive."

    # Final hard-guard for English requests.
    if _normalize_language(language) == "en" and _looks_indonesian(text):
        return "Tiny steps count—do the smallest version today and keep the streak alive."

    return text


_ALLOWED_AVATAR_IDS = {
    "KUNG_FU_FOX",
    "LION",
    "NINJA_TURTLE",
    "PENGU",
    "SPORTY_CAT",
    "WORKOUT_WOLF",
}


@track(
    name="flexifit_persona",
    tags=["persona", "gamification", "hyper-personalized"],
    metadata={
        "model": GEMINI_MODEL,
        "prompt_version": PROMPT_VERSION,
        "feature": "flexi-archetype",
    },
)
def call_gemini_persona(payload: PersonaRequest) -> dict:
    """Generate a 'Flexi Archetype' persona as strict JSON."""

    done_days = sum(1 for d in payload.last7_days if bool(d.done))
    total_days = max(1, len(payload.last7_days))

    days_compact = ", ".join(
        [f"{d.date}:{'done' if d.done else 'miss'}" for d in payload.last7_days]
    )

    transcript = "\n".join(
        [f"{m.role.upper()}: {m.text}" for m in (payload.chat_history or [])[-20:]]
    )

    lang_label = _language_label(payload.language)

    prompt = (
        "You are a witty but supportive habit-coach game designer. "
        "Analyze the user data and generate a playful, slightly quirky RPG-style persona. "
        "Be motivating, not insulting. Keep it punchy.\n"
        "Return STRICT JSON only (no markdown, no extra text).\n"
        "Schema: {\"archetype_title\": string, \"description\": string, \"avatar_id\": string, \"power_level\": integer}.\n"
        "Rules:\n"
        f"- avatar_id MUST be exactly one of: {sorted(_ALLOWED_AVATAR_IDS)}\n"
        f"- archetype_title: 2-5 words, {lang_label} (funny, punchy).\n"
        f"- description: 1-2 short sentences in {lang_label}, funny but supportive.\n"
        "- power_level: 1..100 (higher = more consistent).\n\n"
        f"GOAL: {payload.current_goal}\n"
        f"COMPLETION_RATE_7D: {float(payload.completion_rate_7d):.0f}%\n"
        f"STREAK_DAYS: {int(payload.streak)}\n"
        f"DONE_DAYS: {done_days}/{total_days}\n"
        f"LAST_7_DAYS: {days_compact}\n\n"
        f"CHAT_HISTORY:\n{transcript if transcript else '(empty)'}\n"
    )

    response = model.generate_content(
        prompt,
        request_options={"timeout": 12},
    )

    raw = (response.text or "").strip()
    start = raw.find("{")
    end = raw.rfind("}")
    if start != -1 and end != -1 and end > start:
        raw = raw[start : end + 1]

    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("Persona output must be a JSON object")

    title = str(data.get("archetype_title") or "").strip()
    desc = str(data.get("description") or "").strip()
    avatar_id = str(data.get("avatar_id") or "").strip().upper()

    power_level = data.get("power_level")
    if isinstance(power_level, bool):
        power_level = 50
    if not isinstance(power_level, (int, float)):
        power_level = 50
    power_level = int(round(float(power_level)))
    power_level = max(1, min(100, power_level))

    if avatar_id not in _ALLOWED_AVATAR_IDS:
        # Safe fallback mapping.
        avatar_id = "PENGU"

    if not title:
        title = "The Strategic Pengu"
    if not desc:
        desc = "You're great at shrinking the goal while still moving forward. Slow and steady — consistency wins."

    return {
        "archetype_title": title,
        "description": desc,
        "avatar_id": avatar_id,
        "power_level": power_level,
    }

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
        "prompt_version": PROMPT_VERSION,
        "opik_project": os.getenv("OPIK_PROJECT_NAME", "flexifit-hackathon"),
        "evals": {
            "empathy_score": {
                "enabled": True,
                "type": "llm-as-judge",
                "scale": "1-5",
            },
        },
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

        cleaned_reply, deal_label = _extract_deal_meta(ai_reply)
        deal_made = True if deal_label else False
        ai_reply = cleaned_reply

        empathy_score: Optional[float] = None
        empathy_rationale: Optional[str] = None
        retry_used: bool = False
        initial_empathy_score: Optional[float] = None
        try:
            judged = call_gemini_empathy_judge(request.user_message, ai_reply)
            empathy_score = float(judged.get("empathy"))
            empathy_rationale = str(judged.get("rationale") or "").strip() or None

            initial_empathy_score = empathy_score

            retry_enabled = str(os.getenv("RETRY_ON_LOW_EMPATHY", "false")).strip().lower() in {
                "1",
                "true",
                "yes",
                "on",
            }
            retry_threshold = int(os.getenv("RETRY_EMPATHY_THRESHOLD", "3"))
            retry_threshold = max(1, min(5, retry_threshold))

            if retry_enabled and empathy_score is not None and empathy_score < retry_threshold:
                prev_score = int(round(empathy_score))
                prev_rationale = empathy_rationale or ""

                ai_reply_retry = call_gemini_negotiator_retry(
                    user_msg=request.user_message,
                    goal=request.current_goal,
                    history=request.chat_history,
                    previous_reply=ai_reply,
                    judge_score=prev_score,
                    judge_rationale=prev_rationale,
                )

                # Re-judge the improved response so Opik shows the effect.
                judged2 = call_gemini_empathy_judge(request.user_message, ai_reply_retry)
                empathy_score = float(judged2.get("empathy"))
                empathy_rationale = str(judged2.get("rationale") or "").strip() or None
                ai_reply = ai_reply_retry
                retry_used = True

                cleaned_retry, deal_label_retry = _extract_deal_meta(ai_reply)
                ai_reply = cleaned_retry
                if deal_label_retry:
                    deal_label = deal_label_retry
                    deal_made = True
        except Exception as e:
            logger.warning(f"⚠ Empathy eval skipped: {e}")
        
        logger.info(f"✓ Chat processed | Goal: {request.current_goal} | Reply length: {len(ai_reply)}")
        return ChatResponse(
            response=ai_reply,
            deal_made=deal_made,
            deal_label=deal_label,
            empathy_score=empathy_score,
            empathy_rationale=empathy_rationale,
            prompt_version=PROMPT_VERSION,
            retry_used=retry_used,
            initial_empathy_score=initial_empathy_score,
        )

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
            ai_payload = call_gemini_progress_insights(
                request.current_goal,
                history,
                language=request.language,
            )
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

        insights_text = _coerce_insights_bullets(insights)
        if not insights_text:
            insights_text = "- Keep the habit tiny today.\n- Pick one micro-step and do it now.\n- Consistency beats intensity."

        progress_data = ProgressData(
            goal=request.current_goal,
            total_chats=total_chats,
            micro_habits_offered=micro_habits_offered,
            completion_rate=completion_rate,
            last_interaction="recent",
            insights=insights_text,
        )

        return ProgressResponse(status="success", data=progress_data)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"🔥 Error in /progress: {str(e)}")
        raise HTTPException(status_code=500, detail="Progress calculation failed")


@app.post("/progress/motivation", response_model=WeeklyMotivationResponse)
async def weekly_motivation_endpoint(
    request: WeeklyMotivationRequest,
) -> WeeklyMotivationResponse:
    try:
        if not request.goal.strip():
            raise HTTPException(status_code=400, detail="Goal must be set")

        # Clamp to sane range to avoid prompt injection via absurd numbers.
        rate = float(max(0.0, min(100.0, request.completion_rate_7d)))

        try:
            motivation = call_gemini_weekly_motivation(
                goal=request.goal,
                completion_rate_7d=rate,
                last7_days=request.last7_days,
                language=request.language,
            )
        except Exception as e:
            logger.warning(f"⚠ Weekly motivation fallback (Gemini unavailable): {e}")
            motivation = "Keep it tiny today—one small action keeps the habit alive."

        # Fallback if model returns something unexpected.
        if not motivation or not str(motivation).strip():
            motivation = "Keep it tiny today—one small action keeps the habit alive."

        return WeeklyMotivationResponse(
            status="success",
            data=WeeklyMotivationData(motivation=str(motivation).strip()),
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"🔥 Error in /progress/motivation: {str(e)}")
        raise HTTPException(status_code=500, detail="Motivation generation failed")


@app.post("/persona", response_model=PersonaResponse)
async def persona_endpoint(request: PersonaRequest) -> PersonaResponse:
    try:
        if not request.current_goal.strip():
            raise HTTPException(status_code=400, detail="Goal must be set")

        # Clamp to sane ranges.
        rate = float(max(0.0, min(100.0, request.completion_rate_7d)))
        request.completion_rate_7d = rate
        request.streak = int(max(0, min(3650, request.streak)))

        persona = call_gemini_persona(request)

        data = PersonaData(
            archetype_title=str(persona.get("archetype_title") or "").strip(),
            description=str(persona.get("description") or "").strip(),
            avatar_id=str(persona.get("avatar_id") or "").strip(),
            power_level=int(persona.get("power_level") or 50),
        )

        return PersonaResponse(status="success", data=data)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"🔥 Error in /persona: {str(e)}")
        raise HTTPException(status_code=500, detail="Persona generation failed")


if __name__ == "__main__":
    logger.info("🚀 Starting FlexiFit Backend...")
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", 8000)))