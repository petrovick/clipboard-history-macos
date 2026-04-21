#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

STATE_DIR = Path(".codex/hooks/.state")
STATE_FILE = STATE_DIR / "claude_review_state.json"
MAX_ATTEMPTS = 8

def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout.strip(), result.stderr.strip()

def load_state():
    if not STATE_FILE.exists():
        return {"attempt": 0, "last_review": ""}
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {"attempt": 0, "last_review": ""}

def save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2))

def clear_state():
    try:
        STATE_FILE.unlink()
    except FileNotFoundError:
        pass

def main():
    try:
        hook_input = json.load(sys.stdin)
    except Exception:
        hook_input = {}

    _, staged_diff, _ = run(["git", "diff", "--cached", "--no-ext-diff"])
    _, unstaged_diff, _ = run(["git", "diff", "--no-ext-diff"])

    diff_parts = [p for p in [staged_diff, unstaged_diff] if p.strip()]
    if not diff_parts:
        clear_state()
        print("{}")
        return

    diff_text = "\n\n".join(diff_parts)[:120000]

    state = load_state()
    attempt = int(state.get("attempt", 0)) + 1
    previous_review = (state.get("last_review") or "").strip()

    if attempt > MAX_ATTEMPTS:
        print(json.dumps({
            "continue": False,
            "stopReason": f"Claude review excedeu {MAX_ATTEMPTS} tentativas automáticas."
        }))
        return

    prompt = f"""
Você é um reviewer técnico muito criterioso.

Analise SOMENTE o patch atual e responda EXATAMENTE em um dos formatos:

APPROVED

ou

CHANGES_REQUIRED
- problema 1
- problema 2
- problema 3

Regras:
- Verifique se os problemas apontados na revisão anterior foram realmente corrigidos.
- Aponte apenas problemas reais de bug, regressão, edge case, segurança,
  arquitetura ruim, ou teste claramente necessário que continua faltando.
- Não elogie.
- Não reescreva código.
- Não explique demais.
- Se estiver aceitável, responda apenas APPROVED.

Tentativa atual: {attempt}

Revisão anterior:
{previous_review if previous_review else "(nenhuma)"}

Patch atual:
{diff_text}
""".strip()

    code, stdout, stderr = run([
        "claude",
        "-p",
        prompt,
        "--output-format", "text",
        "--max-turns", "2"
    ])

    if code != 0:
        print(json.dumps({
            "continue": True,
            "systemMessage": f"Claude review hook falhou: {(stderr or stdout)[:500]}"
        }))
        return

    review = stdout.strip()

    if review.startswith("APPROVED"):
        clear_state()
        print("{}")
        return

    if review.startswith("CHANGES_REQUIRED"):
        review = review[len("CHANGES_REQUIRED"):].strip()

    save_state({
        "attempt": attempt,
        "last_review": review
    })

    print(json.dumps({
        "decision": "block",
        "reason": (
            "O review automático do Claude encontrou problemas no patch atual. "
            "Corrija tudo e só encerre quando passar no review.\n\n"
            f"Pendências:\n{review[:5000]}"
        )
    }))

if __name__ == "__main__":
    main()
