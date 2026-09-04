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

---

## 2026-09-04 — Sulaiman — Claude Code (CLI) — Slice 3

**Prompt:** continued the existing session in the repo with no new
instruction, i.e. "pick up where we left off". It read `CLAUDE.md`,
`docs/spec.md`, the Slice 2 code and `docs/slice2-unverified.md`, established
from the schedule in spec §12 that Slice 3 is transcription + queue, and
built it.

**Output — files AI wrote:** `lib/services/transcription_service.dart`,
`lib/services/transcription_queue.dart`, `lib/services/api_keys.dart`, the
four new methods on `SegmentRepository`, the queue wiring in `main.dart`,
`people_screen.dart` and `interview_screen.dart`, the rewritten `_SegmentRow`
plus the new `_TranscriptPending` and `_QueueBanner` widgets, and
`test/transcription_test.dart` (28 tests). Plus `docs/walkthrough-slice3.md`,
`docs/qa-slice3.md`, `docs/slice3-unverified.md`, and the edits to
`README.md` and `docs/spec.md` §10–11.

**What we did with it:**

**A dependency went, and for a real reason.** The first plan was the obvious
one: keep `flutter_dotenv` and declare `.env` in `pubspec.yaml` as an asset.
Checking what Flutter does with a *missing* declared asset killed it — the
build fails outright, so anyone cloning this repo without a `.env` could not
have built the app at all. `flutter run --dart-define-from-file=.env` does the
same job with the SDK we already have, and a missing key becomes an empty
string, which is a state we already have to support. Seven dependencies now,
down from nine on Sunday.

**The API contract was verified against the live service, not the docs.** A
5.9-second AAC m4a of spoken Arabic, posted to `api.groq.com` with exactly the
fields our service sends: HTTP 200 and the correct Arabic back. That
eliminated the most likely way this slice fails on a phone — a wrong model
name or a rejected container. It also surfaced two details we would otherwise
have found on stage: the response body has a leading space, and carries an
extra `x_groq` key.

**The key path was verified too.** `flutter test --dart-define-from-file=.env`
against a throwaway assertion on `ApiKeys.groq`: passes with the flag, fails
without it. The test was deleted rather than committed, because it would have
failed for anyone without a key.

**Two bugs the tests caught.** First, the fake answers in the queue tests were
short Arabic phrases against 40-second segments — which tripped our own
implausibility guard and failed every queue test. The guard is real code and
the fixtures have to respect it; the fixture is now a realistic 120-character
answer, with a comment saying why. Second, `run()` originally returned
immediately when a run was already in flight, so a caller could not await
completion and a test closed the database mid-upload. It now returns the
in-flight run instead of starting a second one — which is also what stops the
interview screen uploading the same segment twice, since it calls `run()` on
open, on save and on retry.

**One thing rejected.** The first draft of `saveTranscript` guarded the
human-corrected case with `WHERE ... AND edited_by_user = 0`, which would have
left an edited row stuck at `pending` forever and the queue spinning on a row
it is forbidden to write. Rewritten as a single statement with the guard in a
`CASE` on the text column only, so the status always advances. There is a test
named after exactly that failure.

**Verification:** `flutter analyze` clean, `flutter test` 66 passing (38 from
Slices 1–2, 28 new), `flutter build apk --debug` succeeds, and the live Groq
call above. **Still nothing has run on a phone** — `docs/slice3-unverified.md`
lists what that leaves open, and every item in `docs/slice2-unverified.md` is
still open too.

---

## 2026-09-04 — Sulaiman — Claude Code (CLI) — the reinstall bug

**Prompt:** "Bug found on device: recordings are unplayable after any
reinstall. audio_service.dart stores an absolute path in audio_path. On iOS
the app container UUID changes on every install, so all prior audio_path
values are dead after a rebuild. [...] Fix: store the path RELATIVE to the
documents directory [...] Add one helper both AudioService and the queue use;
no caller should ever touch a raw absolute path again. Bump the schema version
and migrate existing rows by stripping everything up to and including
'/Documents/'. Keep it, don't wipe [...] Add a test that pins the invariant: a
stored audio_path must never begin with '/'."

**The diagnosis was ours, not the AI's.** The bug was found by running Slice 2
on the phone, and the cause — the iOS container UUID — was identified before
any of this was typed. Worth recording accurately: this entry is AI
implementing a fix that a device run and a human diagnosis had already
specified.

**Output — files AI wrote:** `lib/services/audio_files.dart`, the changes to
`audio_service.dart`, `db.dart` (schema version 2 and the migration),
`transcription_queue.dart`, `interview_screen.dart` and `segment.dart`, plus
`test/audio_path_test.dart` (14 tests). Rewrote `docs/slice2-unverified.md`
around the device run and updated `docs/slice3-unverified.md` and
`docs/spec.md` §8.

**What we did with it:**

**One correction to the brief.** The instruction said to strip up to and
including `/Documents/`. That is the iOS marker; Android's documents
directory is `app_flutter` and would not have matched, leaving those rows
absolute and broken. The migration handles both markers. Android is not a
platform we demo, but the line cost nothing and a wrong guess later would cost
recordings.

**A testability problem the fix created, and the fix for it.** Resolving a
path calls `getApplicationDocumentsDirectory`, which needs a platform channel
— so the moment the queue resolved its own paths, every queue test failed for
want of a device. The resolver is now injected into `TranscriptionQueue` the
same way the HTTP client is injected into `TranscriptionService`. That is the
second time this week the answer was a seam rather than a mock, and it is
worth noticing as a pattern: the parts of this app that can fail are the parts
that talk to a platform, and every one of them is now passed in.

**Fixtures that contradicted the invariant were changed too.** Two older tests
wrote `'/tmp/seg_1.m4a'` as an `audio_path`. Harmless to those tests, but a
fixture that violates a documented invariant is a trap for whoever reads it
next, so they now use relative paths with a comment pointing at
`test/audio_path_test.dart`.

**Verification:** `flutter analyze` clean, `flutter test` 80 passing (66
before, 14 new), `flutter build apk --debug` succeeds. The new tests cover the
invariant, both platforms' markers, the migration's idempotence, that it keeps
rows rather than wiping them, and a real version 1 → version 2 database reopen
so the `onUpgrade` wiring is exercised and not just the SQL.

**Not yet verified:** the fix on a device. The bug needs two installs to
appear and so does its fix. `docs/slice2-unverified.md` says so in those
words rather than calling the item closed.

---

## 2026-09-04 — Sulaiman — Claude Code (CLI) — the 28-byte recording

**Prompt:** first, "Playback still fails on a freshly recorded segment, on
device. [...] Change the catch to log the exception, the relative path, and
the resolved absolute path, and also log whether the file exists and its
length at that moment. [...] Do not guess a fix from reading. Get the real
error first."

Then, after running it: "Found it. Every recorded file is exactly 28 bytes —
an empty m4a container. The mic is capturing nothing. Playback's 'Cannot
Open' and the transcription failures are one bug, not two. [...] Likely
cause, to verify before you fix: record and just_audio are both touching
AVAudioSession. [...] Verify first: log the AVAudioSession category and
whether the permission actually returned granted, at the moment start() is
called. Confirm the diagnosis before writing the fix. [...] Second thing,
separately: stop() guards against bytes == 0 and lets 28 through."

**What we did with it:**

**The instruction not to guess was the whole value of the round.** The
previous entry describes a fix written from a correct diagnosis. This one
started from a wrong assumption — that playback was a path problem — and the
logging killed it in one run. The path work was verified *correct* by the
same output that found the real bug: relative stored, resolved right, file
present in the right directory, 28 bytes long.

**Two bugs were being read as one, and one bug was being read as two.**
Playback failing and transcription failing were the same empty file. The
28-byte file and the guard that let it through were separate problems, and
only the second is fixed here.

**The session-category fix is deliberately not written.** The `playAndRecord`
explanation has a good story behind it and no evidence yet, and this session
cannot run the app on the phone. Writing the fix now would be the exact thing
the prompt ruled out. `AudioService._logSessionState` logs the category, mode,
options and the OS-level `AVAudioSessionRecordPermission` before *and* after
`_recorder.start()` — before and after because whether `record` sets the
category itself is precisely the question.

**`audio_session` declared as a direct dependency.** It was already in the
tree under `just_audio`, so it costs nothing new to ship, but a package we
call into directly should be one we have named in the spec table and can
defend. Seven dependencies.

**The guard, fixed independently.** `stop()` tested `bytes == 0`; 28 bytes
went straight past it. It now requires 1024 bytes — thirty-six times the dead
file, a fraction of any real one — and returns a sealed `RecordingResult`
rather than a nullable `Recording`, so the save path is unreachable without
handling the failure. The user is told the microphone picked nothing up,
which points somewhere different from "did not save".

**One argument with the brief, and it changed the design.** The instruction
was to delete the four dead segments. A sweep that deletes rows whose audio
is missing would have wiped the entire archive during last week's reinstall
bug, when every file on the phone appeared absent. So the sweep only removes
rows whose file it can **open and measure** below the minimum; a missing file
is left alone. There is a test named after that, and it is the most important
test in the file.

**Verification:** `flutter analyze` clean, `flutter test` 93 passing (80
before, 13 new), `flutter build apk --debug` succeeds. The sweep is tested
including the exact four-dead-rows case, both boundary sizes, idempotence,
and the missing-file safety property. **The session diagnostics have not been
read off a device** — that is the next thing, and no fix should be written
before they are.

---

## 2026-09-05 — Sulaiman — Claude Code (CLI) — the encoder probe

**Prompt:** "The diagnosis was wrong and the log proves it. record sets the
category itself: soloAmbient before the first start, playAndRecord after, and
playAndRecord on every attempt thereafter. Permission granted. Still 28 bytes.
Do not write the audio_session fix — it would have been a no-op on a bug that
isn't there. New hypothesis, to test not assume: RecordConfig is aacLc at
sampleRate 16000. iOS's AAC encoder does not reliably accept 16 kHz [...] Test
it cheaply before committing to anything [...] If defaults still give 28
bytes, the encoder isn't the cause and we look at record 7.1.1 on iOS 18.5
next. Say so rather than trying a third guess."

Plus: "MissingPluginException on getRecordPermission every run. audio_session's
iOS side isn't fully registered [...] Your call which — tell me, don't
silently pick."

**What we did with it:**

**Two hypotheses in a row have now been wrong**, and both were killed by a
device log rather than by argument. The first was that playback was still a
path problem; the second was the audio session. Both sounded right. The
instrumentation is what made each round cheap, and that is worth saying in
the Q&A rather than presenting the eventual fix as though it were reasoned
out in one pass.

**One correction to the brief's step 1.** "Drop sampleRate and numChannels
entirely" does not test the platform's preference for our recording — the
`RecordConfig` defaults are 44100 Hz **stereo** at 128 kbps, so dropping both
changes two variables at once and a working result would not say which one
mattered. The probe therefore runs a 2×2 over sample rate and channel count
rather than one defaults-vs-ours comparison.

**One addition.** A `wav` row at 16 kHz mono. If `wav` at 16 kHz works and
`aacLc` at 16 kHz does not, the problem is specifically the AAC encoder
rather than the input rate — which is the difference between changing one
constant and changing the audio format. Steps 1 and 2 of the brief would have
found *a* working config; this finds out *why*.

**Built as one run, not six.** `AudioService.probeEncoderConfigs` records 1.5
seconds with each config and prints the byte count, triggered from a button
on the settings screen. This session cannot run anything on the phone, so
every round trip costs a rebuild and a message; collapsing six of those into
one is the largest thing that could be done from here.

**The dependency call: `audio_session` is removed.** It was added the day
before to read the session category. It answered its question — the answer
was "the session is fine" — and its iOS side is only half-registered here:
the category read worked, `getRecordPermission` threw `MissingPluginException`
every run. Fixing the registration would be work to keep a package we now
have no use for, since `record` manages the category itself. It stays in the
tree transitively under `just_audio`. Back to six dependencies.

**The shipping config is deliberately unchanged.** `aacLc` 16 kHz mono is
still what `_config` says, because changing it now would be committing to a
fix ahead of the evidence — the exact thing that wasted the last round. The
probe decides it.

**Verification:** `flutter analyze` clean, `flutter test` 93 passing,
`flutter build apk --debug` succeeds. **The probe has never been run.** No
byte counts are known to this session, and none are claimed.
