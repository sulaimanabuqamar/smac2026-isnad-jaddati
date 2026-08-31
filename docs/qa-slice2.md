# Slice 2 — questions a judge could ask, and how to answer them

Ten questions. Four are marked **hard**: three because the honest answer is a
concession, and one because the obvious answer sounds good and is wrong.

Same rule as Slice 1 — the first sentence of each answer stands alone. Say it,
stop, let them ask for more.

---

## 1. Show me what happens when I press the record button.

`_startRecording` asks the database for the next sequence number in this
session, then calls `AudioService.start`, which checks the microphone
permission and opens a file at
`<app documents>/recordings/session_<id>/seg_<seq>_<timestamp>.m4a`. The
screen moves to the recording phase and the button becomes a stop button.

Pressing it again calls `stop`, which waits for the encoder to close the file,
confirms the file exists and has bytes in it, and only then does the screen
write a `segment` row.

## 2. Why does the recording go to a file first instead of straight to the transcription API?

Because the network is the part that fails, and the audio is the part we
cannot recreate. If we streamed to the API we would have coupled the
irreplaceable thing to the unreliable thing.

Capturing to a file means a session works with no signal at all. The segments
sit at `transcribe_status = 'pending'` and go up whenever there is a
connection. That is decision D1 in CLAUDE.md and it is why the app is built
in two halves.

## 3. Why 16 kHz mono? That is worse quality than the phone can record.

It is exactly the quality Whisper uses. Whisper resamples all input to 16 kHz
internally, so recording at 44.1 kHz means uploading roughly three times the
bytes to get an identical transcript.

Mono because one person is speaking, and speaker separation is out of scope.
The practical effect is that a 90-second answer is about 350 kB, which matters
for our persona — a phone at 40% with patchy signal in a majlis.

## 4. What happens if she denies the microphone permission?

A screen that explains what the app needs and offers to try again — not a
crash, and not a snackbar that disappears. Declining the microphone is a
reasonable thing to do, and the app has to stay coherent afterwards.

The copy explains *why* rather than *what*: recording her voice is the point
of the app, and it cannot ask a question without hearing the answer.

## 5. How do you know a segment's audio actually exists?

Because `audio_path` is `NOT NULL` in the schema, `Segment.audioPath` is
non-nullable in Dart, and the only thing that produces a path is
`AudioService.stop()`, which does not return one until the file is closed on
disk with bytes in it.

There are three tests on this. One of them goes around the Dart model with
raw SQL to insert a segment with no audio path, and asserts the database
rejects it — so the schema is a second line of defence, not just the type.

---

## 6. **Hard.** You say the ordering guarantee cannot be violated. Have you actually seen it work?

No. It has never run on a device.

What I have is an argument and a type system, not an observation. The argument
is that `Recording` is only constructed inside `stop()`, after the file has
been confirmed — so there is no value to put in `audio_path` until the audio
is on disk. That is sound, and it is not the same as having watched it.

The specific thing I have not verified is whether `record`'s `stop()` really
returns after the encoder has flushed on both platforms. If it returned early,
the length check could see a partial file. It is the first item under section
3 of `docs/slice2-unverified.md`, which lists everything in this slice that
has never been executed.

**Do not** claim it is proven. The honest version is stronger: we designed it
so the failure is impossible to express, we wrote down exactly what remains
unobserved, and here is the document.

## 7. **Hard.** You have 38 tests and not one of them records audio. What are they worth?

They cover the half of this slice that can be covered, and I would not claim
more than that.

What they genuinely test: every SQL statement, against a real SQLite engine —
sequence numbering, the uniqueness constraint, `NOT NULL` on `audio_path`, the
`CHECK` constraints, ending a session, and the cascade when a person is
deleted. Those run on a real database, not a mock.

What they cannot test: the microphone, the file write, playback, permissions,
or anything rendered on a screen. All of that needs a device.

The concrete value is not theoretical — a test caught a real bug in this
slice. The question bank was being ordered by `id`, which sorts
alphabetically, so `chg_01` came before `child_01` and every session would
have opened on the "change" topic instead of childhood. That shipped nowhere
because a test asserted the first question is `child_01`.

## 8. **Hard.** Your own spec says "hold to record". Your app does tap-to-start and tap-to-stop. Which is wrong?

The spec, and I changed the code rather than the document first, which I
should not have done in that order.

The reasoning: our segments are 30 to 90 seconds. Hold-to-record is right for
a two-second voice note and wrong for a ninety-second answer held one-handed
while the other hand has tea in it. Nobody does that twice.

It is flagged in `docs/walkthrough-slice2.md` and in
`docs/slice2-unverified.md` as a deliberate deviation rather than left for
someone to discover. If the team decides the spec wins, it is a small change —
swap `onTap` for `onLongPressStart` and `onLongPressEnd`.

**The thing to avoid** is not knowing the spec and the code disagree. Knowing
and having a reason is defensible; being surprised is not.

## 9. **Hard.** What happens if the phone dies in the middle of a recording?

You lose that one answer and nothing else, and that is the direction we chose
to fail in.

The file is on disk but no `segment` row was written, because the row is only
written after `stop()` returns. So the database has no record of it and the
archive is consistent. There is an orphaned `.m4a` file on the phone that
nothing points to.

That is deliberate. The alternative ordering — write the row when recording
starts, fill in the path afterwards — would leave a row pointing at a file
that does not exist, which is a story card that fails to play. A missing
segment is better than a broken one.

**The honest gap**: the orphaned file is never cleaned up. There is no sweeper
yet. On a phone that crashes repeatedly during recording, those files
accumulate. It is a known gap, not an oversight, and it is cheap to add once
there is a reason to.

---

## 10. This is a recording app with no transcription and no AI. What is actually finished?

The loop that everything else hangs off: pick a person, get a question,
record an answer, save it, play it back, and finish the session so it becomes
a story on the home screen. That works end to end at the database level and
has 38 tests over it.

What is deliberately not here is transcription, which is tomorrow. It attaches
without a schema change and without touching the interview screen — Slice 3
reads rows where `transcribe_status = 'pending'`, sends the file at
`audio_path` to Groq, and writes the transcript back.

The interview screen already shows "not transcribed yet" on every segment,
before anything can set it otherwise. The queue is visible from the day the
rows exist, so by the time transcription can fail, the user has already seen
the state it fails into.

---

## The one to have ready that is not a question

If someone asks you to demonstrate it on a phone right now, the answer today
is that it has not run on one yet — the APK builds, iOS signing is not set up,
and `docs/slice2-unverified.md` lists exactly what that leaves unproven.

Have that document open. Being able to produce a written list of what you have
not verified is a stronger position than being asked for it and improvising.
