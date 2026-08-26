# ADR 0002: Discover and retry the control gateway safely

## Status

Accepted — August 25, 2026

## Context

The eFlow gateway can be published through a rotating Cloudflare Quick Tunnel. The mobile app needs the current URL without bundling an internal server address, and it must never duplicate a sensitive mutation when a tunnel changes.

## Decision

The app reads `system_config.ai_endpoint` through authenticated Supabase access, validates an absolute HTTPS URL, and normalizes the audited `/controlpanelEflow/api` base path. HTTP is accepted only for explicitly enabled private-network development hosts in non-production builds.

Every request gets the current Supabase bearer token, an abort signal, a bounded timeout, and typed errors. After a network failure or gateway 502/503/504/530 response, the app refreshes endpoint discovery and retries once only for GET/HEAD requests or for mutations whose caller supplies an accepted backend idempotency key.

## Consequences

- The app never contacts the private AI service or Ollama directly.
- A Quick Tunnel rotation recovers one safe read automatically.
- Approval, role, finance, and other sensitive mutations cannot be repeated without server-side de-duplication support.

