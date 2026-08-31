# Jaddati — SMAC 2026 (Team Isnad)

An AI-assisted oral-history recorder. You record a grandparent answering a
question; the app transcribes what they said and asks a specific follow-up
drawn from their own words, so the conversation keeps moving.

Team: Sulaiman Abuqamar (lead) · Adel Almheiri · Bilal Alkhofash
Submission: 8 September 2026 · Demo Day: 16 September 2026

---

## READ THIS BEFORE WRITING ANY CODE

This is a Khalifa University contest entry. Competition rules constrain how
code may be produced. They are not style preferences.

### Hard rules, quoted from the official orientation deck (slide 10)
- "Not Allowed to use AI to generate the full application."
- "Participants may use AI as a supporting tool; however, they must clearly
  document all AI usage in their report, including the prompts used and how
  the generated content contributed to the development process."
- "Any assistance from outside the team is not permitted."
- "The students must use GitHub accounts to proof their development and show
  the trails of contributions and improvements."
- "Copying a project or a complete part of a project from any where including
  internet is not permitted."
- "It is mobile Application not a web Application, so it must be downloadable
  in your phone as an application."

### How to work in this repo
1. **Do not write whole features or whole screens.** Explain the approach and
   the design decisions, then walk the assigned member through writing it.
   They type it. You review and correct.
2. **No line of code a team member cannot explain out loud in 30 seconds.**
   If the choice is between clever and explainable, choose explainable.
3. **No new dependency** without stating in one sentence what it does and who
   on the team owns that answer in the Q&A. Current list is nine. Justify any
   tenth against that bar.
4. **Append to AI-USAGE.md every session** — date, the actual prompt, what came
   back, what the member did with it. Written the day it happens, never
   reconstructed before the deadline.
5. **Never write a secret into a tracked file.** Keys live in `app/.env`,
   which is gitignored. `app/.env.example` is committed with blank values.
6. **Every commit from its own author's account.** Small, frequent, honestly
   messaged. Judges read the history and the contributor graph.

### The scoring rubric IS the spec
| Criterion | Weight |
|---|---|
| Idea originality + relevance to theme | 20% |
| UI / user-friendliness + functionality | 25% |
| Mobile realization + performance & reliability | 20% |
| GitHub development evidence + Q&A session | **35%** |

35% has nothing to do with features. It is whether the repo shows real
incremental work, and whether three people can defend every line under
questioning. A beautiful app we cannot defend loses to an average app we can.

---

## Architecture — the four decisions

**D1 — Recording and transcription are decoupled.** Audio is captured to a
local file first, always, offline, with no AI in the path. Transcription is a
separate retryable job against that file. The irreplaceable thing is the
voice; a transcript can be regenerated. Recording must never be able to fail.

**D2 — A session is a chain of 30–90 second segments, not one long recording.**
One question, one answer, one file. The segment ends, transcribes, and the
follow-up appears while the grandparent is still sitting there.

**D3 — Flutter, Android APK.** `flutter build apk --release` gives one
sideloadable file: no dev server, no account, no network on Demo Day.

**D4 — sqflite with hand-written SQL,** not Drift. Generated code is a
liability when a judge asks who wrote it. No state-management library either;
`setState` plus a repository class is enough for five screens and can be
explained.

## The AI boundary
| Operation | Where | Notes |
|---|---|---|
| Transcription (audio → Arabic text) | cloud | Whisper API |
| Follow-up question generation | cloud | last 2 turns → 3 candidates, JSON |
| Story extraction (title/people/place/decade) | cloud | same call as above |
| Translation Arabic ↔ English | **on device** | ML Kit, ~32 MB model, offline |
| Audio capture and storage | **on device** | no AI, deliberately |

**The reliability rule:** a session started with no signal, in a house with
thick walls, on a phone at 12%, must still reach a saved story card. If a
slice breaks that, the slice is not done.

## Ownership
- **Sulaiman** — data layer + services. Schema, segment lifecycle, both API
  calls, the prompt, secrets.
- **Adel** — interview screen + audio. Capture, permissions, storage, playback.
- **Bilal** — story card, archive, translation. ML Kit, extraction, search.

## Definition of done for a slice
1. The app still installs and runs on a real phone.
2. Commits pushed from the account of whoever wrote it.
3. AI-USAGE.md updated the same day.
4. Five questions a judge could ask about this slice, answered out loud.
   If they can't be answered, the slice is not done.
