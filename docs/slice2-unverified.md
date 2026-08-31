# Slice 2 — what has never been executed

Written the night Slice 2 was built, before any of it ran on hardware. This
is the list to hammer first thing in the morning.

The distinction this document draws is between **verified** and **written**.
Everything in Slice 2 is written and compiles. A specific and much smaller
set of it has actually been observed to work.

---

## What is genuinely verified

| Claim | How |
|---|---|
| The project compiles | `flutter analyze` — no issues |
| The database half of the loop works | `flutter test` — 38 tests |
| It builds an installable Android artifact | `flutter build apk --debug` |

The 38 tests run real SQLite through `sqflite_common_ffi`, so the schema, the
constraints and every query are genuinely exercised. **Nothing else below is
covered by them.**

---

## Never executed — hammer these in order

### 1. Microphone permission (highest risk)

`AudioService.hasPermission()` calls `record`'s implementation. It has never
been called on a device, in either outcome.

- [ ] First launch shows the iOS permission dialog with our
      `NSMicrophoneUsageDescription` string. **If the key is missing or
      malformed, iOS terminates the app instantly with no dialog** — this is
      a hard crash, not a denial, and it is the single most likely way the
      first run fails.
- [ ] Denying permission shows `_MicrophoneBlocked`, not a crash.
- [ ] "Try again" after enabling it in Settings actually recovers. On iOS a
      permission change may restart the app, in which case the button is
      never reached — acceptable, but find out.
- [ ] Android runtime permission flow, which is a different code path.

### 2. Recording to a file

- [ ] `AudioRecorder.start()` succeeds with our config: AAC-LC, 16 kHz, mono.
      The encoder is platform code; 16 kHz mono AAC is a legal combination on
      both, but it has not been run.
- [ ] The file appears at
      `<app documents>/recordings/session_<id>/seg_<seq>_<stamp>.m4a`.
- [ ] `getApplicationDocumentsDirectory()` returns a writable path inside the
      iOS sandbox. Directory creation with `recursive: true` has never run
      there.
- [ ] The file has non-zero length after `stop()` — the check exists but the
      branch has never been taken.
- [ ] A recording of 30–90 seconds, which is the real segment length. Nothing
      longer than zero seconds has been recorded.

### 3. The audio_path ordering guarantee

This is the thing a judge is most likely to ask about, and it is currently
argued rather than demonstrated.

- [ ] `stop()` really does return only after the encoder has flushed. If
      `record` returns before the file is closed, the length check could see
      a partial file. **The argument is sound and the observation has not
      been made.**
- [ ] Killing the app mid-recording leaves an orphan file and no row —
      recoverable, as designed.
- [ ] Force-quitting between `stop()` and the insert loses the row and keeps
      the file. Same direction of failure, which is the point.

### 4. Playback

- [ ] `just_audio` plays back our own AAC files. Never run.
- [ ] The play/stop icon state tracks reality, including a segment finishing
      on its own — the `playerStateStream` listener has never fired.
- [ ] Playing a second segment while a first is playing.
- [ ] The missing-file path: the row exists, the file was deleted. The catch
      is written; it has never been entered.

### 5. Session lifecycle on a real device

Covered by tests at the database level. Not covered end-to-end:

- [ ] Backgrounding the app mid-session and returning.
- [ ] Resume: leaving the interview screen and re-entering finds the same
      unfinished session rather than starting a new one.
- [ ] A phone call arriving mid-recording. The recorder loses the microphone;
      what `stop()` returns then is unknown.

### 6. iOS build at all

- [ ] `pod install` has never run. **There is no Podfile in the repository** —
      it is generated on the first iOS build.
- [ ] Deployment target: the Xcode project is now 15.5, raised from 15.0
      because `google_mlkit_translation`'s podspec requires it. When the
      Podfile is generated, check its `platform :ios` line agrees. If pods
      fail to resolve, this is the first thing to look at.
- [ ] Signing is not configured, so no iOS build has been attempted.

### 7. Layout on a real screen

Every screen has only ever been laid out by the compiler, never rendered.

- [ ] The record button lands in the bottom third on a real phone. It is
      placed by a `Column` with the segment list in an `Expanded` above it,
      which puts it at the bottom — but "bottom third" is an assertion about
      a device I have not measured.
- [ ] Arabic renders in a font that has it. A missing glyph shows as boxes.
- [ ] The question does not overflow on a small screen. Long bank questions
      at 26pt in a fixed-height area is the likely first overflow.
- [ ] The segment list scrolls under a long session.

---

## Known gaps that are not bugs

- **No transcription.** Slice 3. Every segment reads "not transcribed yet",
  which is honest — the status column is real and nothing sets it yet.
- **`editedByUser` is never set.** The transcript editor does not exist.
- **Deviation from spec §6.** The spec says "hold to record". This is
  tap-to-start, tap-to-stop, because a 30–90 second press is not viable
  one-handed while holding tea. Flagged rather than silently changed —
  see `docs/walkthrough-slice2.md`.
- **Question repeats after the bank is exhausted.** `questionAt` wraps at 30
  questions. From Slice 3 the question comes from the model and the bank is
  the fallback, so this should not be reachable in practice.

---

## The honest summary

The database half of Slice 2 is tested. The audio half is written, reviewed,
and entirely unobserved. If exactly one thing on this page is broken tomorrow,
my money is on the iOS microphone permission — because its failure mode is a
silent termination rather than an error, and because it is the only item here
that cannot be diagnosed from a stack trace.
