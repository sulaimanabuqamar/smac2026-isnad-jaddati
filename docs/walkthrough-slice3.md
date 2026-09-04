# Slice 3 walkthrough — transcription and the queue

4 September 2026. Owner: Sulaiman.

What this slice adds: her words appear under her voice. What it deliberately
does not add: any way for that to matter to whether the interview works.

---

## The shape of it

```
_stopAndSave()                        TranscriptionQueue.run()
  ├─ audio.stop()   ── file on disk     ├─ getPending()          ← the database
  ├─ segments.create()  ── row written  ├─ service.transcribe()  ← the network
  ├─ queue.run()    ── NOT awaited      ├─ saveTranscript() / markFailed()
  └─ next question shown                └─ notifyListeners()  → screen re-reads
```

The left column finishes in milliseconds and never touches the network. The
right column can take a minute, fail, or never run at all. They are joined by
one un-awaited call and one listener, and that is the entire coupling.

Three files:

| File | Does |
|---|---|
| `services/transcription_service.dart` | One file in, Arabic text or a typed failure out. No database, no state. |
| `services/transcription_queue.dart` | Decides what to retry, what to give up on, and when. Owns no audio. |
| `services/api_keys.dart` | Where the key comes from, and why it is not a file. |

Splitting the service from the queue is what makes the hallucination guard
testable: `isImplausible` is a pure static function over a string and a
duration, so the two clips that broke the spike are literally in the test file
as assertions.

---

## Five decisions and why

### 1. `whisper-large-v3-turbo`, not `whisper-large-v3`

Not because it is newer. Plain v3 returned `اشتركوا في القناة` — "subscribe to
the channel" — on two unrelated clips in the spike, and turbo returned real
text for both. The full working is in `docs/asr-failure-modes.md`. The model
name is a constant with that document cited above it, so nobody later
"upgrades" it back without reading why.

### 2. The queue does one segment at a time

Not for correctness — for the free tier and for the connection. Three parallel
uploads on a phone in a majlis with one bar is three slow uploads instead of
one fast one, and Groq's free tier rate-limits us into a 429 anyway. Serial is
also what makes "stop at the first network failure" a coherent rule.

### 3. Transient and permanent are different, and only that difference matters

Every failure the service can return carries a `transient` flag:

- **transient** — no key, offline, rate-limited, server down. The row stays
  `pending` and the queue stops. Trying again later is the whole plan.
- **permanent** — a 4xx refusal, a missing file, a transcript we do not
  believe. The row is marked `failed` and the queue moves to the next one.

The queue reads nothing else. Everything a failure knows about how it should
be described to a person lives in the enum's `message`, and everything about
what to *do* is that one boolean. A judge asking "what happens when the
network dies mid-session" can be answered by pointing at one field.

The reason this distinction is load-bearing: without it, a phone in aeroplane
mode would march through every pending segment, mark them all failed, and lose
the entire queue to one moment of no signal.

### 4. The implausibility guard runs on our side, not the model's

Both spike hallucinations returned 17 characters for 10–15 seconds of audio.
Conversational Arabic runs about 10–12 characters a second. The rule is: under
2 characters per second, over 5 seconds of audio, we do not believe it.

It is a ratio, not a blocklist. Blocking the literal string
`اشتركوا في القناة` would catch the one artefact we happen to have seen and
nothing else; the ratio catches the shape of the failure, which is a confident
model returning almost nothing.

The threshold is deliberately far from both edges — a fifth of normal speech,
and still comfortably above the 1.2 and 1.6 the failures produced. It is
picked from two data points and is not calibrated, and the guard is documented
as such rather than presented as a measurement.

**Why err towards rejecting.** A false positive costs one bank question
instead of one AI question, which is the fallback the app already has for
having no signal. A false negative puts words in her mouth and then asks her a
follow-up question about them. Those costs are not close.

Below 5 seconds the guard does not apply at all, because "نعم طبعا" is a real
answer and would trip any ratio rule.

### 5. The queue outlives the screen

It is built once in `main.dart` and passed down, like every other dependency
in this app. A segment recorded in the kitchen finishes uploading twenty
minutes later in the car, and the interview screen it was recorded on is long
gone. Building the queue per-screen would have thrown that work away — and
would have let two screens upload the same row twice.

`run()` returns the run that is already going rather than starting a second
one. The interview screen calls it on open, on every save, and on every retry,
so overlapping calls are the normal case rather than the edge.

---

## The SQL that writes a transcript

```sql
UPDATE segment
   SET transcript_ar = CASE WHEN edited_by_user = 0
                            THEN ? ELSE transcript_ar END,
       transcribe_status = ?
 WHERE id = ?
```

Two rules in one statement.

The `CASE` is the human-correction guard: once someone has fixed a transcript
by hand, a later transcription must not silently undo their work.

The status is set *outside* the `CASE`, so it always advances. This is the
subtle half. If an edited row kept its `pending` status, `getPending()` would
hand it back on every single run, forever, and the queue would spin on a row
it is forbidden to write. There is a test named exactly that:
*"but the status still advances, so the queue cannot loop."*

One statement rather than two updates, so there is no instant at which the
text is new and the status is old.

---

## Losing a dependency

`flutter_dotenv` is gone. It read the key out of a file bundled as a Flutter
asset; `flutter run --dart-define-from-file=.env` reads the same file with the
SDK we already have.

The reason is not tidiness. A bundled `.env` has to be declared in
`pubspec.yaml`, and **a declared asset that is missing stops the build
outright**. Anybody cloning this repo without a `.env` — a teammate, a judge —
could not have built the app at all. With `--dart-define-from-file` a missing
key is an empty string, which is a state the app is required to survive
anyway.

Seven dependencies now, down from nine at the start of the week.

---

## What the screen shows

Under each answer, one of four things:

| State | Shown |
|---|---|
| transcribed | her words, in Arabic, full size, never truncated |
| uploading now | *Transcribing…* |
| waiting | *Waiting to transcribe* |
| failed | *Could not transcribe — audio saved* · **Try again** |

The question moved to a smaller, softer line above the answer. It was the
loud line in Slice 2 because it was the only line. The question is ours and
the answer is hers, and now that both are on screen the sizes should say so.

Three of those four states are written so that nothing reads as a loss —
because nothing was lost. The audio is on the phone in all four.

When the queue is stuck, a line above the record button says why and how many
answers are waiting. Without it, a session recorded in a basement looks like a
session where transcription is broken. With it, the app has told you what it
is waiting for.

---

## What was actually verified

Not "it compiles". These were run.

**The endpoint, for real.** A 5.9-second AAC m4a of spoken Arabic, posted to
`api.groq.com` with exactly the fields the service sends:

```
{"text":" السلام عليكم أنا جدي وكنت سكن في العين قبل خمسين سنة"}   HTTP 200
```

So the endpoint, the model name, `language=ar`, `temperature=0`, the
multipart field names, our m4a container and the JSON response shape are all
confirmed against the real service rather than against the documentation.
Note the leading space and the extra `x_groq` key in the body — the parser
trims and ignores respectively, which we now know because we looked.

That transcript is 52 characters over 5.9 seconds: 8.8 characters a second,
comfortably clear of the 2/second guard.

**The key path, for real.** `flutter test --dart-define-from-file=.env`
against a throwaway test asserting `ApiKeys.groq` is non-empty: passes with
the flag, fails without it. The `.env` comment lines and blank lines parse
correctly.

**66 tests pass**, up from 38. The 28 new ones cover the guard against both
real spike clips, every HTTP branch through a `MockClient`, the UTF-8 decode,
the transcript SQL including the correction guard, and the queue's retry
decisions.

**`flutter analyze` clean. `flutter build apk --debug` succeeds.**

What has still never run on a phone is in `docs/slice3-unverified.md`, along
with everything from Slice 2 that is still open.

---

## A note on the broad catch

`transcribe` wraps the HTTP call in `on Object catch` and calls everything
that comes out of it `offline`. That is broader than a list of socket
exceptions, and it is deliberate: the failure modes of a dying connection are
many and platform-specific, and every one of them means the same thing to us.

It has one real cost, and we found it while writing the tests: a bug on our
own side inside that block would also be reported as "offline". The exception
text is kept in the failure's `detail` field for exactly that reason.

The direction of the mistake is the right one, though. An unknown error
treated as retryable leaves the row pending and the audio untouched. An
unknown error treated as permanent would throw away a transcript we could
have had.
