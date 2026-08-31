# Slice 2 — walkthrough

Record, save, play back. No AI, no network. Written for Sulaiman reading it
having not watched it being built, same standard as Slice 1.

Read `docs/slice2-unverified.md` alongside this. That document lists what has
never been executed, and it is longer than you would like.

---

## What changed

| File | Status |
|---|---|
| `lib/services/audio_service.dart` | new |
| `lib/data/bank_question_repository.dart` | new |
| `lib/data/session_repository.dart` | `end()` added |
| `lib/screens/interview_screen.dart` | placeholder replaced |
| `lib/screens/people_screen.dart`, `lib/main.dart` | wiring |
| `ios/Runner/Info.plist`, `Runner.xcodeproj` | mic string, target 15.5 |
| `test/segment_lifecycle_test.dart` | new, 20 tests |

Slice 1 is untouched apart from constructor parameters being threaded through.
All 18 of its tests still pass.

---

## The one that matters: `lib/services/audio_service.dart`

### What it does

Starts and stops a recording, and hands back a `Recording` — a path, a
duration and a byte count.

### Why it is shaped this way

**This class is where CLAUDE.md D1 stops being a rule and becomes a fact
about the code.**

D1 says recording must never be able to fail, and that `audio_path` is written
before `transcribe_status` is ever set. The weak way to honour that is to
write the steps in the right order in the interview screen and remember not
to change them. The strong way is to make the wrong order impossible to
express, which is what this does:

```dart
Future<Recording?> stop() async {
  final returned = await _recorder.stop();   // encoder flushes and closes
  ...
  if (!await file.exists()) return null;
  final bytes = await file.length();
  if (bytes == 0) { await file.delete(); return null; }
  return Recording(path: path, duration: _clock.elapsed, bytes: bytes);
}
```

`Recording` has no other constructor that the app calls. So the only way to
obtain a path to put in `audio_path` is to have already awaited the encoder
closing the file and confirmed it has bytes in it. **The ordering is not a
convention the caller follows; it is the only order the types permit.**

Say it that way if you are asked. "We enforce it" is weaker than "there is no
way to express the other order."

### The three checks, and why each is there

- **`await _recorder.stop()`** — completes after the AAC encoder has flushed
  its buffer and closed the file. Without awaiting it you can get a path to a
  file that is still being written.
- **`file.exists()`** — the recorder can report a path for a file that was
  never created, if the microphone was never actually acquired.
- **`bytes == 0`** — the specific artefact left behind by a recorder that
  opened and captured nothing. The file is deleted and null returned.

That last one is a judgement call worth defending. A zero-byte segment would
appear in the archive as a story card that plays silence, which looks like a
recording that failed quietly. Losing it outright is more honest: nothing
appears, and the user records again.

### The recording format

AAC-LC, 16 kHz, mono. Not a default — each part is a decision:

- **16 kHz** because Whisper resamples everything to 16 kHz internally.
  Recording at 44.1 kHz means uploading roughly three times the bytes to get
  identical text.
- **Mono** because one person is speaking, and speaker separation is out of
  scope per spec §5.
- **AAC** because it is hardware-encoded on both platforms, so it costs
  almost no battery.

At this setting a 90-second answer is roughly 350 kB. That number matters for
the persona: a phone at 40% in a majlis with thick walls.

### Where the files go

`getApplicationDocumentsDirectory()`, not the cache directory. The OS is
allowed to empty the cache when storage runs low, and the recording is the
one thing in this app that cannot be regenerated.

Filenames carry both the sequence number and a timestamp —
`seg_3_1756700000000.m4a`. The timestamp means a re-recorded segment never
overwrites the file it replaces. We would rather leak a file we can clean up
later than destroy audio we cannot get back.

**Alternative considered.** Reading the duration back off the file with a
decoder instead of timing with a `Stopwatch`. More accurate by a few
milliseconds, and it means decoding a file while the grandmother sits waiting
for the next question. The stopwatch is wall-clock time from start to stop,
which is within a frame of the truth and free.

---

## `lib/screens/interview_screen.dart`

### What it does

Shows one question, records an answer, appends a segment, shows the next
question. Lists the session's segments with playback.

### The phase enum

```dart
enum _Phase { loading, blocked, ready, recording, saving }
```

One field rather than four booleans. With booleans, `_recording && _blocked`
is a state you can write and would have to defend against; with an enum it
cannot be constructed. Five screens' worth of impossible states removed by
one type.

### `_stopAndSave`, line by line

This is the method a judge will ask about.

1. Phase goes to `saving`, so the button is disabled and a second tap cannot
   start a duplicate save.
2. `await widget.audio.stop()` — returns only when the file is real.
3. If null, tell the user and return. **No row is written.**
4. `nextSeq(session.id)` — asked of the database, not counted in memory, so
   it is right after an app restart mid-session.
5. `segments.create(...)` with `audioPath` already populated and
   `transcribeStatus` defaulting to `pending`.
6. Reload from the database rather than appending to the in-memory list. The
   list on screen is then what is actually stored, not what we hope is.

Step 6 is a deliberate extra query. Appending locally would be faster and
would let the screen and the database disagree — which is exactly the class
of bug that ends with a demo showing a segment that was never saved.

### Resuming

`_bootstrap` looks for an unfinished session before creating one. So leaving
the interview screen and coming back continues the same session rather than
starting a second one. That is what makes an interrupted Friday afternoon
recoverable, and it is the reason `getUnfinishedForPerson` existed in Slice 1
before anything called it.

### The denied-microphone screen

A full screen, not a snackbar and not a crash. Someone declining the
microphone is a reasonable thing to do, and the app has to remain coherent
enough to say what it needs and let them change their mind.

The copy says why rather than what: *"Recording her voice is the whole point
of the app, and it cannot ask a question without being able to hear the
answer."* A permission dialog that explains itself is granted more often than
one that demands.

### Deviation from spec §6 — flagged, not buried

The spec says **"hold to record"**. This is **tap to start, tap to stop**.

The reason: segments are 30–90 seconds. Holding a button for ninety seconds,
one-handed, while the other hand holds tea, is not a thing anyone will do
twice. Hold-to-record is right for a two-second voice note and wrong for this.

This is a genuine departure from a written spec and it is yours to overrule.
If you want hold-to-record back it is a small change — swap the
`GestureDetector.onTap` for `onLongPressStart`/`onLongPressEnd`. Say either
way in the Q&A; what you cannot do is not know that the spec and the code
disagree.

---

## `lib/data/bank_question_repository.dart`

### What it does

Returns the *n*th question from the offline bank.

### The bug this file already had

The first version ordered by `id`. The ids in `bank.json` are `child_01`,
`home_01`, `chg_01` and so on, and **alphabetically `chg_01` sorts first**.
So a session would have opened on the "change" topic — the heaviest questions
in the bank — instead of "where were you living when you were small?"

It now orders by `rowid`, which is insertion order, which is the order the
questions appear in the file, which is the order they were deliberately
written in: childhood, home, work, family, traditions, change.

A test caught this before it shipped, and the comment in the file records it
so nobody re-introduces it. Worth telling this story in the Q&A if asked what
the tests are for — it is a concrete answer rather than a principled one.

### Wrapping

`index % total`, so a very long session cannot run out of questions. This
should be unreachable in practice: from Slice 3 the question comes from the
model and the bank is the offline fallback.

---

## `SessionRepository.end`

```dart
where: 'id = ? AND ended_at IS NULL'
```

The `AND` is the interesting half. Ending an already-ended session changes
nothing and returns 0, so the original end time cannot be overwritten by a
stray second call — which is a real possibility given the Finish button and
a back gesture can both reach it.

Only `ended_at` is written. Nothing else about a session changes when it
ends, and touching more columns would risk clobbering a title that the
extraction call had already set.

---

## iOS configuration

**`NSMicrophoneUsageDescription`** in `Info.plist`. Without this key iOS does
not deny the microphone — it **terminates the app**, with no dialog and no
catchable error. It would have been the first crash on device and it would
have looked like a code bug.

**Deployment target 15.0 → 15.5**, in all three build configurations.
`google_mlkit_translation`'s podspec declares
`s.ios.deployment_target = '15.5'`. Found by reading the podspec rather than
by waiting for `pod install` to fail, which is the same information half an
hour earlier.

There is still **no Podfile** — Flutter generates it on the first iOS build.
When it appears, check its `platform :ios` line agrees.

---

## `test/segment_lifecycle_test.dart`

20 tests. The ones worth pointing at:

- **`the database refuses a segment with no audio path`** goes around the
  Dart model with raw SQL. The model already makes it unrepresentable; this
  proves the schema is a second line of defence rather than the type being
  the only one.
- **`ending an already-ended session changes nothing`** pins the `AND
  ended_at IS NULL` guard.
- **`finishing a session turns it into a story on the people screen`** ties
  Slice 2's write to Slice 1's read, which is where an integration bug would
  otherwise hide.
- **`walks the bank in file order`** is the one that caught a real bug.

What these do **not** cover: the microphone, the file write, playback, or
anything on a screen. That is `docs/slice2-unverified.md`, and it is not a
short list.

---

## What Slice 3 attaches to

Every segment row is written with `transcribe_status = 'pending'` and a valid
`audio_path`. Slice 3 needs no schema change and no change to this screen: it
reads pending rows, sends the file at `audio_path` to Groq, and writes
`transcript_ar` and a new status back.

That the interview screen already displays "not transcribed yet" is
deliberate. The queue is visible from the day the rows exist, so by the time
transcription can fail, the user has already seen the state it fails into.
