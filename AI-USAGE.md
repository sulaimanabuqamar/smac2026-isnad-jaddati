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

## 2026-08-31 — Sulaiman — Claude Code (CLI)

**Prompt:** Toolchain setup. Asked it to check free disk space before
installing anything, then install the Flutter SDK, the Android SDK and
platform-tools, accept the Android licences and show `flutter doctor` — with
an explicit instruction to stop at each step so the result could be checked,
and to write no application code.

**Output:** Flutter 3.47.2 and Android Studio installed via Homebrew. Two
things it pushed back on rather than doing as asked. First, it checked the JDK
version instead of assuming: the prompt said to point Flutter at Android
Studio's bundled JDK 21, but the bundled JBR is 25, so the step had nothing to
point at and was dropped. Second, `brew install --cask temurin@21` failed
because the cask needs a sudo password it cannot supply; it reported the
failure rather than routing around it. Android SDK was then installed headless
with `sdkmanager` — platform-tools 37.0.1, `platforms;android-36`,
`build-tools;36.1.0`, API 36 read from Flutter's own `gradle_utils.dart`
rather than guessed.

**What we did with it:** Accepted the JDK correction and stayed on 25.
`flutter doctor` green on the Android toolchain; Xcode left red deliberately
at that point.

**Prompt:** Platform change to iOS, because the only phone on the team is an
iPhone and free provisioning on a device we own beats sourcing an Android we
do not have. Asked it to add the iOS runner with
`flutter create --platforms ios .`, keep Android, update `docs/spec.md` §10
and CLAUDE.md D3, and record the 7-day profile expiry as a known risk.

**Output:** It stopped on the premise: there was no existing scaffold to add a
runner to, because the earlier `flutter create` had never been run. On an
empty directory `--platforms ios` would have produced an iOS-only project with
no `android/`, and would have defaulted the organisation to `com.example`. It
ran the combined command instead —
`flutter create --org com.isnad --project-name jaddati --platforms ios,android .`
— then added the nine dependencies with `flutter pub add`, registered
`assets/questions/bank.json` in `pubspec.yaml`, and rewrote spec §10 and D3.
It also flagged that free provisioning installs by cable rather than download,
which is a weaker answer to slide 10's "downloadable in your phone as an
application" than an APK is, and wrote that caveat into the spec rather than
leaving it out.

**What we did with it:** Kept the scaffold. `lib/main.dart` is exactly what
`flutter create` generates and has not been edited — every screen, model and
service in this app is written by us, starting tomorrow. No iOS build has been
attempted yet; Xcode was still downloading.

## 2026-08-31 — Sulaiman — Claude Code (CLI)

**Prompt:** Asked it to run `flutter build apk --debug` to prove the scaffold
compiles while Xcode downloaded, record the dual-target position in
`docs/spec.md` §10 as a deliberate choice, and push to the remote.

**Output:** The build failed after 3m22s, and the failure is worth recording
because it is not the one we expected. Gradle ran on JDK 25 without objecting,
so the JDK-21 question is settled empirically rather than by assumption. It
died instead on `permission_handler_android` 14.0.0, which declares
`compileSdk = 37`; the Android Gradle Plugin resolves that to the SDK target
`android-37`, and Google's SDK repository now publishes `android-37.0`, `37.1`
and `37.2` with no plain `android-37`. AGP 9.1.0 and Gradle 9.3.1 are both
current, so this is an upstream naming mismatch and not our configuration.

It also found that the repository had no git remote configured despite the
GitHub repo existing, and that the local branch was `master` while GitHub's
default is `main`.

**What we did with it:** Did not accept a workaround. Two were offered and
declined for now — a `subprojects` block overriding `compileSdk`, which fails
our rule that any line must be explainable in thirty seconds, and pinning
`permission_handler_android` back to 13.0.1. The spec was corrected the same
hour to say the APK does not currently build, rather than leaving the earlier
sentence claiming it compiled. iOS is unaffected: `permission_handler_apple`
is a separate package and does not use `compileSdk`.

**Follow-up, same session.** Three fixes were offered for the failed APK
build: pin `permission_handler_android` to 13.0.1, override `compileSdk` in a
`subprojects` block, or drop the package entirely because `record` already
exposes `hasPermission()`. We chose to drop it, on the reasoning that the only
job the spec gives `permission_handler` is the microphone permission and
`record` does that on both platforms. Verified before deciding: nothing else
in the tree imports it, and `record` 7.1.1 declares
`Future<bool> hasPermission({bool request = true})`.

The APK then built — `app-debug.apk`, 194 MB, debug with all ABIs. The
dependency table in `docs/spec.md` and the count in CLAUDE.md were updated
from nine to eight. This is the first dependency we have removed, and the
reason is recorded in spec section 10 so it can be answered in the Q&A.

## 2026-08-31 — Sulaiman — Claude Code (CLI) — Slice 1

**Organizer approval.** Dr. Hadi Otrok confirmed on 31 August 2026 that AI
may be used to write application code for this entry. Rule 1 in CLAUDE.md —
"do not write whole features or whole screens" — was lifted on that basis
before any of the code below was written. The amendment in CLAUDE.md still
carries a TODO to paste the exact wording of the email, because what is
recorded there is a summary written from a verbal description of it, not a
quotation. That must be replaced before submission.

**Prompt:** Build Slice 1 in full: models for Person, Session, Segment and
Mention as plain Dart classes; `lib/data/db.dart` with sqflite and
hand-written SQL matching `docs/spec.md` section 8 exactly, seeding
`bank_question` from `assets/questions/bank.json` on first open;
`PersonRepository` with full CRUD and `SessionRepository` /
`SegmentRepository` with create and read only; a `PeopleScreen` home with
session and story counts and an empty state, an `AddPersonScreen`, and marked
placeholders for Interview, Archive and Settings; `main.dart` with routes,
theme and bilingual support set up from the start; unit tests for
`PersonRepository` against an in-memory database. Verify with `flutter
analyze`, `flutter test` and `flutter build apk --debug`. Then write
`docs/walkthrough-slice1.md` and `docs/qa-slice1.md`, and commit in logical
steps.

**Output — files it wrote.** All of the following are AI-written first
drafts:

- `lib/models/` — `person.dart`, `session.dart`, `segment.dart`,
  `mention.dart`, `bank_question.dart`
- `lib/data/` — `db.dart`, `person_repository.dart`,
  `session_repository.dart`, `segment_repository.dart`
- `lib/screens/` — `people_screen.dart`, `add_person_screen.dart`,
  `interview_screen.dart`, `archive_screen.dart`, `settings_screen.dart`
- `lib/widgets/` — `bilingual.dart`, `not_built_yet.dart`
- `lib/theme.dart`, `lib/main.dart`
- `test/person_repository_test.dart`, `test/bank_seed_test.dart`
- `docs/walkthrough-slice1.md`, `docs/qa-slice1.md`
- The CLAUDE.md amendment and this entry

It deleted the stock `test/widget_test.dart`, which still tested the counter
template from `flutter create`.

**Decisions it made and flagged rather than making silently:**

- Declined to invent a quotation from Dr. Otrok's email, since it had not
  been given the text. It recorded the approval as a summary and marked it
  with a TODO instead. A fabricated quotation attributed to a named person in
  a file judges read would have been worse than no quotation.
- Avoided adding `package:path` for a single path join, because that would
  have taken the third-party dependency count from eight to nine against
  CLAUDE.md rule 3. Used string interpolation and wrote down why.
- Added two packages and justified both: `flutter_localizations`, which ships
  with the Flutter SDK and is not third-party, and `sqflite_common_ffi` as a
  dev dependency only, which lets sqflite run on the desktop VM so the
  repository SQL can be tested without a phone. Neither changes the shipped
  count of eight.
- Defined "story" as a finished session — one with `ended_at` set — since the
  brief asked for a story count without saying what a story was. Wrote a test
  pinning that definition and recorded it in the walkthrough.

**Verification, run and reported honestly:** `flutter analyze` clean;
`flutter test` 18 tests passing; `flutter build apk --debug` succeeds. iOS
signing is not set up, so nothing has been run on a device. The walkthrough
states plainly that the slice has never run on real hardware.

**What we did with it:** Read every file. The reasoning behind each decision
is in `docs/walkthrough-slice1.md`, written for exactly this purpose — so
that the Q&A is a conversation about decisions rather than a defence of code
we cannot account for. `docs/qa-slice1.md` includes the question of who wrote
the code, and the answer we give is the true one.

## 2026-09-01 — Sulaiman — Claude Code (CLI) — overnight

### 1. Follow-up question validation — verdict: **48 of 63 grounded (76%)**

**Prompt:** Run the pipeline spike over 20 clips and judge the generated
follow-up questions honestly — does each refer to a person, place, object or
event the speaker actually mentioned, or is it a generic prompt dressed up in
dialect? Say so plainly if most are generic.

**What happened first.** The run failed immediately, the same way it failed on
31 August, and the exponential backoff added since then could not have helped.
The 429 body says why: the quota is
`GenerateRequestsPerDayPerProjectPerModel-FreeTier`, **limit 20 per day**, not
per minute. Backoff retries against a wall that does not move until midnight.

The quota is per model, so the spike was patched to rotate across
`gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite` and
`gemini-3.1-flash-lite`, retiring a model when its daily quota is gone. All 21
clips then completed with zero failures, entirely on `gemini-3.6-flash`.
(`spike/` is outside the repo, so that patch is not in this history.
`spike/pipeline.py.bak` is the original.)

**The verdict, counted rather than felt.** 63 questions, three per clip:

- **48 of 63 (76%) are genuinely grounded** — they name a person, place,
  object or event that appears in the transcript.
- **11 of 21 clips (52%) scored 3 out of 3.**
- **0 of 63 were the banned generic forms.** Not one "tell me more" or "how
  did that make you feel". The prohibition in the prompt is working.

The good ones are very good. From `sport_chunk-75`: *"شو قصدك بـ مدرب في
الدرج؟"* — it picked up an idiom and asked what he meant by it. From
`health_chunk-01`: *"ذكرت المشاهدين والفقرة، شو كان اسم البرنامج؟"* — it
noticed the speaker was addressing an audience and asked which programme.
Those are questions a curious grandchild would ask.

**So: it went well, and the honest answer is that the prompt does not need
revising for genericity.** The failure mode is something else.

**Where the 15 failures come from.** Almost none of them are generic. They
are grounded in a transcript that was itself wrong or empty:

- **Confidently wrong (3 questions, clip 10).** Whisper hallucinated
  "subscribe to the channel"; Gemini asked which grandchild taught her to
  subscribe. Fluent, specific, and about something that never happened.
- **Invention from an empty transcript (clips 8 and 18).** When the transcript
  carries almost no content, the model supplies plausible cultural detail —
  bamboo sticks in the Ayyala, a drummer who led it — that the speaker never
  mentioned.
- **Grounded in an ASR error (clips 2, 13, 14, 21).** "مش ملحقين" (we can't
  keep up) became a game called الملاحقين; "يا اخوي خليفه" became a person
  named أخو الخليفة.

**Proposed prompt revision** — aimed at the real fault, not at genericity:
instruct the model to return an empty `questions` array when the transcript is
too short or too incoherent to ground a question in, rather than inventing
one. The app already knows what to do with no AI question: it falls back to
the offline bank, which is the same path as having no signal. A refusal is
cheap; a confident question about a channel subscription is not.

One caveat on the whole exercise: this dataset is broadcast media — presenters,
doctors, match commentary — not grandparents. The model repeatedly assumes the
speaker participated in what they were describing. That is a dataset artefact
and we should not read it as a prompt flaw.

### 2. Transcription failure diagnosis

**Output:** Both 86% and 90% clips returned the identical string "اشتركوا في
القناة". Duration was ruled out (the 90% clip is the longest in the dataset;
an equal-length clip scored 20%), as was the language hint (byte-identical
output with and without it). Re-running on `whisper-large-v3-turbo` took
`cars_chunk-03` from 86% to **1%** and the control clip from 20% to 17%.
Written up in `docs/asr-failure-modes.md` with the decision to switch models
in Slice 3.

### 3. Slice 2 — the core loop

**Output — files AI wrote:** `lib/services/audio_service.dart`,
`lib/data/bank_question_repository.dart`, `SessionRepository.end`, a real
`lib/screens/interview_screen.dart`, wiring in `main.dart` and
`people_screen.dart`, the iOS microphone key and deployment target bump, and
`test/segment_lifecycle_test.dart`. Plus `docs/walkthrough-slice2.md`,
`docs/qa-slice2.md`, `docs/slice2-unverified.md` and `docs/asr-failure-modes.md`.

**A real bug the tests caught before it shipped.** `BankQuestionRepository`
ordered the bank by `id`. Ids sort alphabetically, so `chg_01` — the "change"
topic, the heaviest questions in the bank — came before `child_01`, and every
session would have opened there instead of on childhood. It now orders by
`rowid`, the order the questions appear in the file. The first version had a
doc comment confidently claiming the opposite of what the code did.

**Verification:** `flutter analyze` clean, `flutter test` 38 passing (18 from
Slice 1, 20 new), `flutter build apk --debug` succeeds. **Nothing has run on a
device.** `docs/slice2-unverified.md` lists every unexecuted path — the
microphone, permissions, the file write, playback, and the iOS build — rather
than letting "it builds" stand in for "it works".

**Also flagged:** `spike/results.md` contains the Gemini API key in plaintext
inside 429 error URLs. The spike directory is outside the repo so nothing has
leaked, but the key should be rotated.
