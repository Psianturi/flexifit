import argparse
import datetime as _dt
import inspect
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

# Optional Opik integration
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


def _try_configure_opik() -> Tuple[bool, Optional[str]]:
    if not OPIK_AVAILABLE:
        return False, "opik SDK not installed"

    try:
        opik_api_key = os.getenv("OPIK_API_KEY") or os.getenv("COMET_API_KEY")
        opik_workspace = os.getenv("OPIK_WORKSPACE") or os.getenv("COMET_WORKSPACE")
        opik_project = os.getenv("OPIK_PROJECT_NAME", "flexifit-hackathon")
        opik_url = os.getenv("OPIK_URL")

        if not opik_api_key:
            return False, "OPIK_API_KEY not set"

        os.environ.setdefault("COMET_API_KEY", opik_api_key)
        if opik_workspace:
            os.environ.setdefault("COMET_WORKSPACE", opik_workspace)

        os.environ.setdefault("OPIK_PROJECT_NAME", opik_project)
        os.environ.setdefault("COMET_PROJECT_NAME", opik_project)

        sig = inspect.signature(configure)
        kwargs: Dict[str, Any] = {}
        if "api_key" in sig.parameters:
            kwargs["api_key"] = opik_api_key
        if "workspace" in sig.parameters:
            workspace_param = sig.parameters["workspace"]
            workspace_required = workspace_param.default is inspect._empty
            if workspace_required and not opik_workspace:
                return (
                    False,
                    "OPIK_WORKSPACE not set (required by installed opik SDK)",
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
        return True, None
    except Exception as e:
        return False, str(e)


def _http_post_json(url: str, payload: Dict[str, Any], timeout_s: int) -> Dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw)
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="ignore") if e.fp else ""
        raise RuntimeError(f"HTTP {e.code} from {url}: {raw[:400]}")


DEFAULT_DATASET: List[Dict[str, str]] = [
    {
        "id": "tired",
        "goal": "Run 5km every day",
        "message": "I'm exhausted and I hate running.",
    },
    {
        "id": "busy",
        "goal": "Workout 1 hour",
        "message": "I only have 2 minutes today.",
    },
    {
        "id": "lazy",
        "goal": "Read 20 pages",
        "message": "I feel lazy. Convince me without making me feel guilty.",
    },
    {
        "id": "anxious",
        "goal": "Meditate 10 minutes",
        "message": "I'm anxious and can't focus.",
    },
    {
        "id": "motivated",
        "goal": "Drink 2L water",
        "message": "Ready for action. Give me a concrete plan.",
    },
]


@track(
    name="flexifit_experiment_run",
    tags=["experiment"],
)
def run_experiment(
    base_url: str,
    run_id: str,
    label: str,
    timeout_s: int,
) -> Dict[str, Any]:
    outputs: List[Dict[str, Any]] = []
    scores: List[float] = []

    for case in DEFAULT_DATASET:
        out = run_case(
            base_url=base_url,
            run_id=run_id,
            label=label,
            case=case,
            timeout_s=timeout_s,
        )
        outputs.append(out)

        s = out.get("empathy_score")
        if isinstance(s, (int, float)):
            scores.append(float(s))

    avg = sum(scores) / len(scores) if scores else 0.0
    return {
        "run_id": run_id,
        "label": label,
        "base_url": base_url,
        "cases": len(outputs),
        "avg_empathy": round(avg, 3),
        "scores": scores,
        "outputs": outputs,
        "env": {
            "PROMPT_VERSION": os.getenv("PROMPT_VERSION"),
            "GEMINI_MODEL": os.getenv("GEMINI_MODEL"),
            "RETRY_ON_LOW_EMPATHY": os.getenv("RETRY_ON_LOW_EMPATHY"),
            "RETRY_EMPATHY_THRESHOLD": os.getenv("RETRY_EMPATHY_THRESHOLD"),
            "OPIK_PROJECT_NAME": os.getenv("OPIK_PROJECT_NAME"),
        },
    }


@track(
    name="flexifit_experiment_case",
    tags=["experiment", "eval", "llm-as-judge"],
)
def run_case(
    base_url: str,
    run_id: str,
    label: str,
    case: Dict[str, str],
    timeout_s: int,
) -> Dict[str, Any]:
    payload = {
        "user_message": case["message"],
        "current_goal": case["goal"],
        "chat_history": [],
    }

    started = time.time()
    result = _http_post_json(f"{base_url.rstrip('/')}/chat", payload, timeout_s=timeout_s)
    duration_ms = int((time.time() - started) * 1000)

    # Return a compact dict so Opik trace output is readable.
    return {
        "run_id": run_id,
        "label": label,
        "case_id": case.get("id"),
        "goal": case.get("goal"),
        "user_message": case.get("message"),
        "ai_response": result.get("response"),
        "empathy_score": result.get("empathy_score"),
        "empathy_rationale": result.get("empathy_rationale"),
        "prompt_version": result.get("prompt_version"),
        "retry_used": result.get("retry_used"),
        "initial_empathy_score": result.get("initial_empathy_score"),
        "duration_ms": duration_ms,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run a small golden-dataset experiment against the FlexiFit backend and log traces to Opik."
    )
    parser.add_argument(
        "--base-url",
        default=os.getenv("API_BASE_URL", "http://localhost:8000"),
        help="Backend base URL (default: API_BASE_URL env or http://localhost:8000)",
    )
    parser.add_argument(
        "--label",
        default=os.getenv("EXPERIMENT_LABEL", "local"),
        help="Experiment label (e.g., v1, v2, gemini-flash, retry-on)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=int(os.getenv("EXPERIMENT_TIMEOUT_S", "20")),
        help="Per-case timeout in seconds (default: 20)",
    )
    args = parser.parse_args()

    opik_ok, opik_err = _try_configure_opik()
    if opik_ok:
        print("✓ Opik configured")
    else:
        print(f"⚠ Opik not configured: {opik_err}. Continuing without Opik logging.")

    run_id = _dt.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    base_url = args.base_url
    label = args.label

    print(f"Running experiment run_id={run_id} label={label} base_url={base_url}")

    try:
        summary = run_experiment(
            base_url=base_url,
            run_id=run_id,
            label=label,
            timeout_s=args.timeout,
        )
    except Exception as e:
        print(f"ERROR running experiment: {e}")
        return 2

    # Keep console output short and demo-friendly.
    for out in summary.get("outputs", []):
        case_id = out.get("case_id")
        print(
            f"- {case_id}: empathy={out.get('empathy_score')} retry={out.get('retry_used')} duration_ms={out.get('duration_ms')}"
        )

    out_path = os.path.join(os.path.dirname(__file__), f"experiment_{run_id}_{label}.json")
    try:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(summary, f, ensure_ascii=False, indent=2)
        print(f"Saved: {out_path}")
    except Exception as e:
        print(f"⚠ Could not write output JSON: {e}")

    print(f"Average empathy (1-5): {summary['avg_empathy']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
