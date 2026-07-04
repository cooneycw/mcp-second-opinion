# ADR 0001: Standalone extraction and architecture

- Status: Accepted
- Date: 2026-07-03
- Deciders: cooneycw (owner)
- Provenance: extracted from [claude-power-pack](https://github.com/cooneycw/claude-power-pack).
  The extraction rationale (why this became its own repo) lives in CPP's ADR:
  `docs/decisions/0001-plugin-marketplace-packaging.md`.

## Context

This server began inside the claude-power-pack monorepo as its cross-vendor
code-review MCP server. It is now distributed independently: you run it on its
own and point any MCP client at it, without cloning CPP. This ADR records the
decisions that let it stand alone, so a reader of *this* repo understands the
architecture without reference to CPP.

## Decisions

### 1. Independent distribution

Its own repo, its own release story. A consumer (Claude Code, or CPP's
`/second-opinion:*` commands) connects to it as an external service via a
`.mcp.json` pointer. It is not a submodule of any client and clients do not build
it. Consequence: this repo must be self-contained and self-documenting.

### 2. The AWS Secrets Manager sidecar carries no vendored code

`aws-secrets-agent/` does not vendor AWS's source. Its Dockerfile fetches the
upstream [aws-secretsmanager-agent](https://github.com/aws/aws-secretsmanager-agent)
at a pinned commit SHA and applies two tracked patches (bind `0.0.0.0`; drop the
TTL hop limit) so the sidecar is reachable across the container network. The pin
is verified at build time and build-time assertions prove each patch took
effect, so an upstream reformat fails the build rather than silently shipping a
misconfigured agent. See `aws-secrets-agent/patches/README.md` and `NOTICE`.

### 3. Fully decoupled consumption

Clients connect over streamable-http at `:8080` via `.mcp.json`. There is no
package coupling to any client. Run the server where you like (localhost, or a
private/Tailscale address) and point clients at it, so the server stays
independently deployable and independently versioned.

### 4. Two run modes, secrets fail closed

- **Direct-key:** put LLM keys in `.env`, run `./start-server.sh`. No AWS, no
  Docker. Lowest barrier.
- **AWS Secrets Manager:** `docker compose up` brings up the server plus the
  sidecar; keys live in AWS, none on disk; the server fetches from the sidecar
  with only an SSRF token. If a configured secret cannot be fetched the server
  fails closed (it does not start keyless).

### 5. Transport: streamable-http

Streamable-http (stateless) is the default over SSE: each request is
independent, so there are no session-expiry / disconnection failure modes. A
stdio mode is also available for auto-start clients.

## Consequences

- The repo stands alone: `README` + this ADR + `NOTICE` fully describe how to
  run it, connect to it, and reason about it without reference to CPP.
- The sidecar tracks upstream AWS security fixes by bumping one pinned SHA, with
  build-time assertions guarding the two patches.
- The two run modes cover both the "just try it" solo user and the "no keys on
  disk" deployment.
