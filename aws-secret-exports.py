#!/usr/bin/env python3
"""Read an AWS Secrets Manager SecretString payload on stdin, emit shell exports.

Companion to run-with-aws-secrets.sh. Kept as its own file rather than an inline
heredoc: a heredoc feeding `python3 -` takes over stdin, which starves the pipe
carrying the secret JSON.

Emits only the keys the MCP server consumes, single-quote escaped so values with
shell metacharacters survive `eval`. Values are never printed to stderr or logs.
Exits non-zero when the payload is unparseable or holds none of the wanted keys,
so the caller can fail closed.
"""
import json
import sys

WANTED = ("GEMINI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY")


def sq(value: str) -> str:
    """Escape for single-quoted shell context: ' -> '\\''"""
    return str(value).replace("'", "'\\''")


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception as exc:
        print(f"FATAL: could not parse secret payload: {exc}", file=sys.stderr)
        return 1

    if not isinstance(data, dict):
        print("FATAL: secret payload is not a JSON object", file=sys.stderr)
        return 1

    found = []
    for key in WANTED:
        val = data.get(key)
        if val:
            print(f"export {key}='{sq(val)}'")
            found.append(key)

    if not found:
        print("FATAL: secret contained none of: " + ", ".join(WANTED), file=sys.stderr)
        return 1

    print(f"loaded {len(found)} key(s): {', '.join(found)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
