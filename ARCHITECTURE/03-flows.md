# 03 — Flows

Every important user journey, drawn. Use these as the source-of-truth when
implementing or reviewing a screen — if the code disagrees with the diagram,
one of them is wrong.

---

## Onboarding (cold start → main app)

The user opens Sema for the first time. They go through three intro pages,
pick a language with live preview, hit a confirmation screen, and land in
the shell. Already implemented as `IntroCarouselScreen` →
`LanguagePickerScreen` → `WelcomeScreen` → `ShellScreen`.

```mermaid
flowchart LR
    START([Cold launch]) --> SETUP{First<br/>launch?}
    SETUP -- yes --> INTRO1[Intro · Privacy]
    INTRO1 --> INTRO2[Intro · Voice]
    INTRO2 --> INTRO3[Intro · Care offline]
    INTRO3 --> PICK[Language picker<br/>live greeting preview]
    PICK --> WELCOME["Welcome · Sema is ready<br/>+ what's inside list"]
    WELCOME --> SHELL[Shell · Home tab]
    SETUP -- no --> BIO{Biometric<br/>lock on?}
    BIO -- yes --> AUTH[Biometric prompt]
    AUTH -- ok --> SHELL
    AUTH -- fail --> AUTH
    BIO -- no --> SHELL
```

**Side effects on completion of onboarding:**
- `Profile` row created (the user, marked `is_active = 1`).
- `app_setting.current_profile_id` set.
- Default language saved to that profile.
- First-run model download kicked off in the background (see [05](05-offline-privacy.md)).

---

## Voice triage conversation (the core loop)

The user taps the mic on the home hero card or in the conversation screen,
speaks, and gets a calm reply in their language. Every step is local.

The orchestrator first asks the **LanguageRouter** which path this
language takes (direct vs pivot via English), then runs the
corresponding pipeline. The safety guard always sits on **Gemma's
output, before any translation-out** — rejected content never reaches
MT-out.

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant UI as Conversation UI
    participant ORC as TriageOrchestrator
    participant RT as LanguageRouter
    participant ASR as ASR (in-house ONNX)
    participant TR as Translator (in-house ONNX)
    participant NLU as NLU + NER (in-house ONNX)
    participant AGENT as Gemma agent (genai)
    participant TOOLS as Tools<br/>lookup · find_care · escalate
    participant GUARD as SafetyGuard
    participant TTS as TTS (in-house ONNX)
    participant DB as ConversationRepo

    U->>UI: Hold mic
    UI->>ORC: startCapture()
    ORC->>ORC: VAD records until<br/>silence ≥ 800 ms
    UI-->>U: Live waveform animates
    ORC->>DB: insert Message(user, voice, draft)
    ORC->>DB: insert AudioClip (encrypted)

    ORC->>RT: pathFor(profile.lang)
    RT-->>ORC: LanguagePath{pivot, ...}

    ORC->>ASR: transcribe(audio, lang)
    ASR-->>ORC: native_text + confidence
    ORC->>DB: upsert Transcript(raw)

    alt path.pivot == true · sw, aka, gaa, yo
        ORC->>TR: translate(native → en)
        TR-->>ORC: english_text + mt_confidence
        ORC->>DB: upsert Transcript(translated)
        Note over ORC: if mt_confidence < 0.5,<br/>ask user to repeat
    else path.pivot == false · en, fr
        Note over ORC: native_text is already English<br/>or a Gemma-native language
    end

    ORC->>NLU: extractSymptoms(text)
    NLU-->>ORC: symptoms[], intent
    ORC->>DB: upsert ConversationSymptom rows

    ORC->>AGENT: respond(history, symptoms, gemmaInputLang)
    loop tool-using turns
        AGENT->>TOOLS: e.g. lookup_first_aid("burn")
        TOOLS-->>AGENT: guide ref + steps
    end
    AGENT-->>ORC: draft reply (in path.gemmaOutputLang)

    ORC->>GUARD: check(draft, path)
    Note over GUARD: SafetyGuard always runs on<br/>Gemma's output, before any MT-out.<br/>Rejected → swap in template from path.templateBank
    alt unsafe / out-of-scope
        GUARD-->>ORC: replace with template (pre-translated for pivot)
    else safe
        GUARD-->>ORC: pass-through
    end

    alt path.pivot == true
        ORC->>TR: translate(en → native)
        TR-->>ORC: native_text
    end
    ORC->>TTS: synthesize(reply, lang)
    TTS-->>ORC: PCM buffer
    ORC->>DB: insert Message(sema, voice, complete)<br/>+ AudioClip
    ORC-->>UI: stream tokens then audio
    UI-->>U: Sema bubble appears + plays
```

**Performance budget per turn (target on a mid-tier Android):**

| Stage | Budget |
|---|---|
| ASR (5-second clip) | ≤ 1.5 s |
| Translate (if needed) | ≤ 0.4 s |
| NLU + symptom extract | ≤ 0.2 s |
| LLM first token | ≤ 1.0 s |
| LLM full reply (≤ 60 tokens) | ≤ 3.0 s |
| TTS (≤ 60 tokens of speech) | ≤ 1.5 s |
| **End-to-end (perceived)** | **≤ 4 s to first speech** |

We stream LLM tokens to the UI so the user sees a typing reply long before
TTS starts.

---

## Triage decision tree

What `TriageEngine` does with extracted symptoms before the LLM speaks. This
is **rule-based first, LLM second** — a deterministic safety net.

```mermaid
flowchart TD
    IN[Conversation symptoms + history] --> RED{Any<br/>red-flag?}
    RED -- yes --> EMG[severity = emergency<br/>recommendation = call/visit clinic NOW<br/>UI shows red banner]
    RED -- no --> COMBO{Combo<br/>matches a<br/>known guide?}
    COMBO -- yes --> GUIDE[severity = derived<br/>retrieve First Aid Guide<br/>LLM frames it]
    COMBO -- no --> CLAR{Need more<br/>info?}
    CLAR -- yes --> ASK[LLM asks 1 clarifying question]
    CLAR -- no --> GENERIC[severity = low<br/>generic safe-care advice<br/>+ suggest nearest provider]
```

**Red-flag rules** (non-exhaustive, all bundled JSON):
- `bleeding-heavy`, `chest-pain-acute`, `breathing-difficulty-severe`,
  `loss-of-consciousness`, `seizure-active`, `snake-bite`,
  `burn-large-area`, `pregnancy + bleeding`, `child + lethargy + fever-high`.

When any of these fires, the LLM's role downgrades from *advisor* to
*calmer-and-router*: short reassurance, push to action.

---

## First aid guided session

User taps a tile on the First aid grid → enters a step-by-step audio guide.

```mermaid
flowchart LR
    GRID[First aid grid] --> TILE{Tap tile}
    TILE --> LOAD[Load FirstAidGuide<br/>+ all steps]
    LOAD --> STEP1[Step 1<br/>play audio · show text]
    STEP1 -->|complete or tap next| STEP2[Step 2]
    STEP2 -->|...| STEPN[Step N · arrival/done]
    STEPN --> SUM[Summary screen<br/>· Talk to Sema<br/>· Find nearest care<br/>· Mark resolved]
    STEP1 -- emergency tap --> EMG[Show red banner + closest provider]
```

Steps autoplay their audio; a step with `hold_seconds > 0` waits that long
before advancing (e.g. "press for 10 seconds"). The guide can be paused, and
resumed from the same step within 24 hours.

---

## Care discovery & directions (already implemented)

Three states inside the Care tab. Already working — this diagram documents
the state machine.

```mermaid
stateDiagram-v2
    [*] --> Browse
    Browse --> Preview : Get directions
    Preview --> Browse : X (cancel)
    Preview --> Active : Start
    Active --> Browse : End
    Browse --> Browse : Tap chip<br/>(switch provider)
    Preview --> Preview : Tap chip<br/>(reset to walk mode)
    Active --> Preview : Tap chip<br/>(reset destination)

    note right of Browse
        Hero card · provider details ·
        chip strip
    end note
    note right of Preview
        Collapsed nav card · mode segments ·
        steps · Start CTA
    end note
    note right of Active
        Map ~62%h · slim now-strip ·
        current step · ETA · End
    end note
```

---

## Family profile switch

Triggered from the Family hero card's "Switch" chip or the Family tab's
"Other profiles" list.

```mermaid
sequenceDiagram
    actor U as User
    participant UI as Family screen
    participant SET as AppSetting repo
    participant CONV as ConversationRepo
    participant CACHE as Riverpod cache

    U->>UI: Tap "Switch" / row
    alt biometric lock on
        UI->>UI: prompt biometric
    end
    UI->>SET: setCurrentProfile(id)
    SET-->>UI: ok
    UI->>CACHE: invalidate(currentProfileProvider)
    CACHE-->>UI: rebuild dependent providers
    UI->>CONV: streamForProfile(id)
    CONV-->>UI: new conversation list
    UI-->>U: hero re-skins to that profile's accent
```

The active-profile change is **invalidation-only** — no data is moved or
copied. Every reactive query is parameterized on
`currentProfileProvider`, so they all naturally re-fetch.

---

## Conversation lifecycle

What happens to a conversation from start to closed.

```mermaid
stateDiagram-v2
    [*] --> Draft : first user turn
    Draft --> Draft : another turn within 5 min
    Draft --> Complete : 30 min idle
    Draft --> Escalated : red-flag triage
    Complete --> [*]
    Escalated --> [*]
    Escalated --> Complete : user marks resolved

    note right of Complete
        Title + summary generated by LLM
        offline at idle
    end note
```

- A `draft` conversation is appended to until idle.
- On transition to `complete` or `escalated`, a small LLM call generates the
  title (≤ 6 words) and the one-line summary stored on the row.
- Summaries enable fast scrolling through history without re-running ASR.
