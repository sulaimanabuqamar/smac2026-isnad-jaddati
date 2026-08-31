# AI Usage Log

Required by SMAC 2026 competition rules (orientation deck, slide 10):

> "Participants may use AI as a supporting tool; however, they must clearly
> document all AI usage in their report, including the prompts used and how
> the generated content contributed to the development process."

This file is written the day each thing happens. It is not reconstructed
before the deadline. Every entry names the member, the tool, the actual
prompt, and what was done with the output.

**Format**

```
## YYYY-MM-DD — Member — Tool
**Prompt:** the actual text sent
**Output:** what came back, summarised
**What we did with it:** what the member wrote, changed, or rejected
```

---

## 2026-08-31 — Sulaiman — Claude (chat)

**Prompt:** Provided the SMAC orientation deck, the GitHub guide and the
scoring rubric. Asked for five candidate app concepts for the theme "AI for
Stronger Family Bonds", each with the target user, the concrete AI mechanism,
core screens, cold-start answer, nearest existing apps, and a predicted score
against each rubric row.

**Output:** Five concepts with per-rubric predictions, a ranking, and flagged
contradictions between the orientation deck (submission 8 Sep) and the SMAC
web page (1 Sep) — resolved by the Outreach Office email confirming 8 Sep.

**What we did with it:** Discussed all five as a team. Shortlisted two
(a document-scanning family calendar, and this oral-history concept) and
chose Jaddati, on the reasoning that theme relevance carries exclusion risk
and a document scanner argues its way onto the theme rather than showing it.
No code was produced in this exchange.

## 2026-08-31 — Sulaiman — Claude (chat)

**Prompt:** Asked for a product spec: one-page spec, high-level and low-level
user flow in the format taught in the orientation deck, wireframes for every
screen, data model, an explicit AI boundary covering what runs on-device
versus cloud, cost, offline behaviour and failure modes, and a stack decision
argued on install reliability and defensibility.

**Output:** A written spec covering all of the above. Key architectural
recommendations: decouple audio capture from transcription so recording never
depends on the network; structure a session as a chain of short segments so a
follow-up question can be generated mid-conversation; Flutter targeting an
Android APK; sqflite with hand-written SQL rather than a code-generating ORM.

**What we did with it:** Adopted the architecture. The reasoning behind each
decision is recorded in CLAUDE.md and docs/spec.md so all three of us can
defend it. Schema and screens still to be written by us.

## 2026-08-31 — Sulaiman — Claude (chat)

**Prompt:** Asked it to create the project folder and repository scaffolding.

**Output:** Directory structure, .gitignore, README.md, this file, CLAUDE.md,
and the seed question bank. No application code.

**What we did with it:** Kept as the starting repo. All Dart code from here is
written by the team.
