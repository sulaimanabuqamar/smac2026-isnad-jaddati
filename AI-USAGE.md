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
