# 037 — AI gateway (serverski AI ključevi)

**Status**: Implementirano (čeka pravi ključeve na serveru i PR). **Grana**: `037-ai-gateway`.

Dizajn: [docs/superpowers/specs/2026-11-13-ai-gateway-design.md](../../docs/superpowers/specs/2026-11-13-ai-gateway-design.md)
Plan: [docs/superpowers/plans/2026-11-13-ai-gateway.md](../../docs/superpowers/plans/2026-11-13-ai-gateway.md)

Ugrađeni Tavli AI ide preko Supabase edge funkcije `ai-complete`. Provajder
ključevi (Gemini, Groq, OpenRouter) su serverski secrets; u izdanju aplikacije
ih nema. Limit po nalogu: 20 u minuti i 300 dnevno. Sopstveni ključevi
korisnika rade direktno kao do sada.
