#!/bin/bash
# run-with-aws-secrets.sh - start the MCP Second Opinion server with LLM keys
# fetched from AWS Secrets Manager at startup and injected into the process
# environment. Keys are NEVER written to disk.
#
# This is the no-Docker alternative to the aws-secrets-agent sidecar (that
# sidecar is a container; this path suits a workstation with no Docker). It
# keeps the sidecar's actual security property: secrets live in AWS, and the
# local .env holds only non-secret server config.
#
# Fail-closed: if the secret cannot be fetched or parsed, the server does not
# start. A silently key-less server would accept every tool call and fail it.
#
# Requires AWS credentials resolvable by the CLI (profile, env, or instance
# role) with secretsmanager:GetSecretValue on the target secret.
#
# Env:
#   AWS_SECRET_NAME   secret to fetch (default: codex_llm_apikeys)
#   AWS_PROFILE       optional profile, honoured by the AWS CLI
#   AWS_BIN/PY_BIN/UV_BIN   override tool paths (default: first on PATH)
#   EXTRA_PATH        prepended to PATH; use when a service manager starts this
#                     with a minimal environment (launchd, systemd) and the
#                     tools live somewhere non-standard

set -euo pipefail

# Service managers start jobs with a minimal PATH, so seed the usual install
# locations before resolving tools. Homebrew (arm64 + intel) and the common
# user-local bin cover most workstations; EXTRA_PATH handles the rest. The
# system dirs are appended UNCONDITIONALLY, not merely as a fallback for an
# unset PATH: an inherited-but-narrow PATH would otherwise leave coreutils
# (dirname, date) unresolvable while aws still resolved from Homebrew, and the
# script would limp on half-broken instead of failing.
export PATH="${EXTRA_PATH:+$EXTRA_PATH:}${PATH:+$PATH:}/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Must run from the repo root - `uv run` and the parser are resolved relative to
# it. An unchecked `cd` is a real hazard here: if dirname were unavailable, the
# substitution yields "" and `cd ""` SUCCEEDS as a no-op, silently starting the
# server against whatever directory the caller happened to be in.
SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")" || {
    echo "FATAL: could not determine script directory (is dirname on PATH?)" >&2
    exit 1
}
[ -n "$SCRIPT_DIR" ] || { echo "FATAL: empty script directory" >&2; exit 1; }
cd -- "$SCRIPT_DIR" || { echo "FATAL: could not cd to '${SCRIPT_DIR}'" >&2; exit 1; }
[ -f src/server.py ] || {
    echo "FATAL: src/server.py not found in $(pwd) - wrong working directory" >&2
    exit 1
}

SECRET_ID="${AWS_SECRET_NAME:-codex_llm_apikeys}"

# Resolve tools once, with an override hook and a clear failure message.
AWS_BIN="${AWS_BIN:-$(command -v aws || true)}"
PY_BIN="${PY_BIN:-$(command -v python3 || true)}"
UV_BIN="${UV_BIN:-$(command -v uv || true)}"

for tool in AWS_BIN:aws PY_BIN:python3 UV_BIN:uv; do
    var="${tool%%:*}"; name="${tool##*:}"
    if [ -z "${!var}" ]; then
        echo "FATAL: '${name}' not found on PATH (${PATH})" >&2
        echo "  Install it, or set ${var}=/full/path/to/${name}" >&2
        exit 1
    fi
done

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

log "fetching secret '${SECRET_ID}' from AWS Secrets Manager..."

if ! SECRET_JSON="$("$AWS_BIN" secretsmanager get-secret-value \
      --secret-id "$SECRET_ID" \
      --query SecretString \
      --output text 2>&1)"; then
    echo "FATAL: could not fetch secret '${SECRET_ID}' from AWS Secrets Manager" >&2
    echo "  ${SECRET_JSON}" >&2
    exit 1
fi

# The secret JSON arrives on stdin via the pipe; the parser is its own file so a
# heredoc cannot take stdin away from it.
if ! EXPORTS="$(printf '%s' "$SECRET_JSON" | "$PY_BIN" aws-secret-exports.py)"; then
    echo "FATAL: refusing to start without LLM keys from '${SECRET_ID}'" >&2
    exit 1
fi

# Values are single-quote escaped by the parser, so eval is safe here.
eval "$EXPORTS"
unset EXPORTS SECRET_JSON

log "secrets loaded from AWS (none written to disk); starting server..."

exec "$UV_BIN" run python src/server.py "$@"
