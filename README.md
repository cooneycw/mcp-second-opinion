# MCP Second Opinion

Multi-model code review MCP server for Claude Code. Ask a panel of external LLMs
(Gemini / OpenAI / Anthropic) for a second opinion when your primary agent gets
stuck.

> Extracted from [claude-power-pack](https://github.com/cooneycw/claude-power-pack)
> as a standalone, independently deployable service. Run it wherever you like and
> point any MCP client at it (see "Connect a client" below). Architecture
> decisions: [`docs/decisions/0001`](docs/decisions/0001-standalone-extraction-and-architecture.md).

## Two ways to run it

- **Quick / local (no AWS):** put your LLM keys in `.env`, then `./start-server.sh`.
  No sidecar, no Docker required. See "Quick start".
- **AWS Secrets Manager (Docker):** keys live in AWS, none on disk. The
  `aws-secrets-agent` sidecar fetches them at runtime and the server pulls from
  the agent over the container network with only an SSRF token. See "Run with
  Docker".

## Features

- **Code Review**: Get AI-powered second opinions on code issues
- **Multi-Model Support**: Consult multiple LLMs (Gemini, Claude, GPT/Codex)
- **Session-Based**: Interactive multi-turn conversations for deeper analysis
- **Visual Analysis**: Support for screenshot/image analysis (Playwright integration)
- **Streamable HTTP**: Stateless transport - no persistent connection, resilient to disconnects

## Quick Start

```bash
# Start the server (uv handles dependencies automatically)
./start-server.sh

# Or run directly
uv run python src/server.py
```

## Add to Claude Code

**stdio (recommended - auto-start, no manual server management):**
```bash
claude mcp add second-opinion --transport stdio -- uv run --directory /path/to/mcp-second-opinion python src/server.py --stdio
```

**Streamable HTTP (for systemd/docker deployments):**
```bash
claude mcp add second-opinion --transport streamable-http --url http://127.0.0.1:8080/mcp
```

## Run with Docker (AWS Secrets Manager)

For deployments where API keys live in AWS Secrets Manager instead of on disk.
The `aws-secrets-agent` sidecar is built from AWS's upstream
[aws-secretsmanager-agent](https://github.com/aws/aws-secretsmanager-agent),
pinned by commit SHA in `aws-secrets-agent/Dockerfile` (no vendored source) plus
two small patches so it is reachable across the container network.

```bash
# .env holds AWS credentials only (never commit it):
#   AWS_ACCESS_KEY_ID=...
#   AWS_SECRET_ACCESS_KEY=...
#   AWS_TOKEN=...          # unique SSRF token for the secrets agent
#   AWS_SECRET_NAME=...    # Secrets Manager secret holding GEMINI/OPENAI/ANTHROPIC keys
cp .env.example .env      # then edit for AWS creds

docker compose up --build -d
docker compose logs -f
```

The server listens on `http://127.0.0.1:8080` (`/` liveness, `/readyz`
readiness once provider keys load). The sidecar is internal-only and never
published to the host.

## Connect a client

Point any MCP client (Claude Code, or the claude-power-pack `/second-opinion:*`
commands) at the running server via `.mcp.json`:

```json
{
  "mcpServers": {
    "second-opinion": {
      "type": "streamable-http",
      "url": "http://127.0.0.1:8080/mcp"
    }
  }
}
```

Running it on another host? Serve it over your private network (for example a
Tailscale address) and point the `url` at that host instead of `127.0.0.1`.

## Environment Variables

Copy `.env.example` to `.env` and configure:

| Variable | Required | Description |
|----------|----------|-------------|
| `GEMINI_API_KEY` | Any one | Google Gemini API key |
| `OPENAI_API_KEY` | Any one | OpenAI API key (GPT, Codex, o-series) |
| `ANTHROPIC_API_KEY` | Any one | Anthropic API key (Claude models) |

Optional tunables:

| Variable | Default | Description |
|----------|---------|-------------|
| `MODEL_RESPONSE_TIMEOUT` | `600` | Per-model response timeout (seconds) for the multi-model fan-out. Bounds a single hung/slow provider so it cannot stall the batch; the timed-out model returns an error entry while the others still succeed. Generous by default so a legitimate detailed/in_depth response is never truncated. |

## MCP Tools

| Tool | Description |
|------|-------------|
| `get_code_second_opinion` | Single-model code review |
| `get_multi_model_second_opinion` | Multi-model parallel review |
| `list_available_models` | Show available LLM models |
| `create_session` | Start interactive session |
| `consult` | Continue session conversation |
| `get_session_history` | View session transcript |
| `close_session` | End session with summary |
| `list_sessions` | Show active sessions |
| `approve_fetch_domain` | Allow URL fetching for domain |
| `revoke_fetch_domain` | Remove domain approval |
| `list_fetch_domains` | Show approved domains |
| `health_check` | Server status |

## Troubleshooting

### Error: `-32602: Invalid request parameters`

This usually means Claude Code cannot reach the server or the SSE session expired.

**Fix 1: Upgrade to streamable-http transport (recommended)**

The streamable-http transport is stateless - each request is independent, so there are no
session timeouts or disconnection issues. Update your `.mcp.json`:

```json
{
  "mcpServers": {
    "second-opinion": {
      "type": "streamable-http",
      "url": "http://127.0.0.1:8080/mcp"
    }
  }
}
```

**Fix 2: Switch to stdio transport**

```bash
# Remove the old configuration
claude mcp remove second-opinion

# Add with stdio (auto-starts, no manual server management)
claude mcp add second-opinion --transport stdio -- uv run --directory /path/to/mcp-second-opinion python src/server.py --stdio
```

**If using HTTP transport:** Ensure the server is running before starting Claude Code:

```bash
# Check if server is running
curl -s http://127.0.0.1:8080/ | jq .

# Start if not running
cd /path/to/mcp-second-opinion
./start-server.sh
```

### Diagnosing Configuration Issues

```bash
# Run pre-flight diagnostics
./start-server.sh --diagnose

# Or directly
uv run python src/server.py --diagnose
```

This checks API keys, .env file, port availability, and available models.

### No API keys configured

The server starts but all LLM calls will fail. Add at least one key:

```bash
cp .env.example .env
# Edit .env - add at least one API key (GEMINI, OPENAI, or ANTHROPIC)
```

## License

MIT
