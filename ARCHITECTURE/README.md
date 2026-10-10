# Sema — Architecture

A design-first record of how Sema is built: the layers, the data, the ML/AI
pipeline, and the policies that bound everything. All diagrams are Mermaid
so they render on GitHub, in VS Code, and in JetBrains without extra tools.

## Product in one paragraph

Sema is a private, **fully offline** health companion for households in rural
West and East Africa. A user speaks (or types) to Sema in their own language —
Twi, Ga, Yorùbá, Swahili, French, or English — and Sema replies with calm,
clear guidance, points them to nearby trusted care, walks them through first
aid, and remembers each family member separately. **Nothing leaves the
device** unless the user explicitly opts in.

## Hard constraints

These are the non-negotiables every design decision is checked against.

| # | Constraint | Why |
|---|---|---|
| C1 | **Fully offline** by default — no runtime network for core features | Rural users have intermittent connectivity at best |
| C2 | **Privacy-first** — conversations never leave the device | Health data is sensitive; no servers means no breach surface |
| C3 | **Multi-profile** on a single device | One phone, the whole household |
| C4 | **Voice-first** in the user's own language | Many target users are not literate in English/French |
| C5 | **Mid-tier Android** as the floor (4GB RAM, ARM64) | The phones our users actually own |
| C6 | **Battery-conscious** | The device may not be charged daily |
| C7 | **Safety-first** — Sema is a guide, not a doctor | Wrong medical advice can kill |

## Reading order

Read top to bottom for the full picture, or jump to any one document.

1. [01 — System architecture](01-system-architecture.md) — layers, components, and how they talk
2. [02 — Data model](02-data-model.md) — ERD, schemas, encryption
3. [03 — Flows](03-flows.md) — onboarding, voice triage conversation, first aid, care directions
4. [04 — ML + AI](04-ml-and-ai.md) — ASR, NLU, triage, LLM agent, TTS, RAG
5. [05 — Offline + privacy](05-offline-privacy.md) — bundling, encryption, biometric lock, optional sync
6. [06 — Implementation](06-implementation.md) — tech stack, state management, file layout, roadmap

## Design principles

- **Bundle, don't fetch.** Every asset, model, map tile, first-aid guide is
  resolved at build or first-launch download. Never on demand.
- **Defaults matter.** The defaults must be safe for someone who never opens
  Settings.
- **One pattern, repeated.** UI uses a single DNA (eyebrow → emphasis headline
  → bespoke selector → ink CTA). Code uses one state pattern (Riverpod).
- **Local first, sync later.** All writes go to the on-device store first;
  any sync is opt-in and encrypted end-to-end.
- **Escalate, don't diagnose.** When in doubt, the AI's answer is "go see a
  trained clinician — here is the closest one."
- **Smallest model that works.** Phone storage and battery are precious;
  prefer a 200 MB model that's good enough over a 2 GB model that's perfect.

## Out of scope (for now)

- Cloud telemetry / analytics
- Doctor video consultation
- Insurance / payments integration
- Lab result ingestion
- Cross-device shared profiles (one family, two phones)

These are likely future milestones but **none of them gate the v1**.

## How decisions get recorded

Architecture decisions live inline in the document where they're relevant.
A meaningful change should:

1. Update the affected diagram and prose.
2. Note the tradeoff considered in the "Decision" callout near the change.
3. Link from any other doc that depends on it.

No separate ADR folder; the docs themselves are the source of truth.
