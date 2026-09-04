# Slice 2 on hardware — what the device run established

Rewritten 4 September 2026, after Slice 2 ran on an iPhone for the first
time. The original version of this file was written the night Slice 2 was
built and listed everything that had never been executed. Most of it has now
been executed, so the list has been replaced by what actually happened rather
than deleted.

**The headline is not that the list came back clean. It is that it did not.**
Playback was broken on the device, in a way no test we had could have caught,
and finding it is the reason the run was worth doing.

---

## Verified on the device

The install itself, and then the whole recording path:

| Claim | Outcome |
|---|---|
| The app installs on a real iPhone and launches | **works** |
| `NSMicrophoneUsageDescription` is present and correct | **works** — the permission dialog appears, and the app does not terminate silently, which was the failure mode we most feared |
| Granting the microphone reaches the interview screen | **works** |
| `AudioRecorder.start` with AAC-LC, 16 kHz, mono | **starts without error** — but see below: it captured nothing |
| A file appears under the app documents directory | **works** |
| `stop()` returns a file with bytes in it | **NO** — every file was 28 bytes, an empty container |
| A segment row is written after the file, never before | **works** — the D1 ordering holds in practice, not just in argument |
| Recordings and rows survive closing and reopening the app | **works** |
| The question chain advances through the bank, one question per answer | **works** |
| The offline queue banner appears with no signal, and the answers still save | **works** — this is the demo described in `docs/qa-slice3.md` |

The riskiest item on the old list — iOS terminating the app instantly over a
missing usage string — did not happen.

**Read the two rows marked in bold before drawing any comfort from the rest.**
The recording path starts, writes a file, and orders its database write
correctly. It has never once captured audio.

## Verified broken: the microphone captured nothing

**Every recording the device made was exactly 28 bytes** — an m4a container
with a header and no frames behind it. Nothing was ever captured.

This is one bug wearing two faces. Playback failed with "Cannot Open" because
there is nothing in the file to decode, and transcription failed for the same
reason. We spent a round chasing them as separate problems; they are the same
empty file.

### Hypothesis 1: the audio session — **dead, disproved on the device**

`record` and `just_audio` both touch `AVAudioSession`, and if the session is
not in `playAndRecord` when recording starts, iOS hands the encoder silence.
Plausible, and wrong.

The log settled it: `record` sets the category itself — `soloAmbient` before
the first start, `playAndRecord` after it and on every attempt since — with
the permission granted, and the files still 28 bytes. **The fix we were about
to write would have been a no-op on a bug that was not there.** `audio_session`
has been removed again; there was nothing for it to do.

Worth keeping in the record: this is the second hypothesis in a row that
sounded right and was not. The first was that playback was still a path
problem.

### Hypothesis 2: the encoder rejects 16 kHz — **being tested**

`RecordConfig` asks for `aacLc` at 16 kHz mono. iOS's AAC encoder is not
reliable at 16 kHz, and when it refuses a rate it writes the container and no
frames — header only, no exception, `stop()` returns normally. That matches 28
bytes exactly.

Not assumed. `AudioService.probeEncoderConfigs`, reachable from the settings
screen, records 1.5 seconds with each of six configs and prints the byte
count for each: platform defaults, then a 2×2 over sample rate and channel
count, then `wav` at 16 kHz. The last one is the discriminator — if `wav` at
16 kHz works and `aacLc` at 16 kHz does not, the problem is the AAC encoder
and not the input rate.

**If every row comes back at 28 bytes, the encoder is not the cause**, and
the next place to look is `record` 7.1.1 on this iOS version. That is a real
outcome, and it gets reported as one rather than answered with a third
guess.

We want to keep 16 kHz mono if iOS will allow it: it was chosen for upload
size on a majlis connection, and Whisper resamples to 16 kHz anyway. The
probe exists to find the smallest setting that actually works, not to
abandon the reasoning behind the original one.

### Hypothesis 3: the package — **being tested, and we stopped debugging**

Every hypothesis died on the same wall. Session category correct, permission
granted, path correct, `stop()` clean, and a 28-byte file. `record` 7.1.1 on
iOS 18.5 reports a success it did not achieve, and with three days left the
cheapest move is to stop diagnosing it and change it.

`record` is now pinned to **5.2.1**. The 5.x line has years of production use
behind it, and — the part that makes this more than a version number — it
ships a completely different iOS implementation: 7.x uses `record_ios`, 5.x
uses `record_darwin`.

**Nothing in the app changed.** Not one line of Dart. `AudioRecorder`,
`start(config, path:)`, `stop()`, `cancel()`, `hasPermission()`, `dispose()`
and `RecordConfig` are identical across the two versions — the rename the
downgrade was expected to need happened at 4.x → 5.x, not 5.x → 7.x. The
`AudioService` seam held exactly as it was supposed to: the package under it
was replaced and no caller noticed.

The recording config is deliberately **unchanged** at `aacLc` 16 kHz mono, so
this is one variable moving and not two.

If 5.2.1 still writes 28 bytes, it is not the package, and the next decision —
`flutter_sound`, or a direct `AVAudioRecorder` channel — is a call to make
deliberately rather than a fourth guess.

## Fixed regardless: a 28-byte file is no longer storable

Separate from the cause, `stop()` was wrong. It guarded `bytes == 0`, and 28
bytes walked straight past it, so four segments were written that will never
play and never transcribe.

A container with no frames is not a short recording, it is a failed one, and
storing it is worse than losing it: it looks to the user like something that
saved. The guard is now a real minimum — 1024 bytes, thirty-six times the
dead file and a fraction of any real one — and `stop()` returns a typed
result rather than a null, so the save path cannot be reached without
handling the failure. The user is told the microphone picked nothing up,
which is a different sentence from "did not save" and points somewhere
different.

The four dead rows are swept at startup, along with their files. The sweep
**only deletes rows whose file it can open and measure**. A row whose file is
merely missing is left alone, deliberately: missing is exactly what the
reinstall bug looked like, and a sweep that deleted on absence would have
destroyed the entire archive that morning instead of fixing it. There is a
test named after that.

## Verified broken, and now fixed

**Playback failed after every reinstall.** Every previously recorded segment
reported *"That audio file is missing from this phone"*, and the transcription
queue marked those same segments permanently failed.

The audio was never missing. `audio_path` stored the absolute path the
recorder was given, and on iOS the app container is a UUID that changes on
every install — so after a rebuild, every row pointed into the previous
install's directory. The files were on the phone the whole time and we were
looking in a folder that no longer existed.

**Why nothing caught it.** Every test we had wrote a path and read the same
path back in the same process, where an absolute path works perfectly. The
bug needs two installs to appear, and it needs a platform whose container
moves. No unit test on any machine would have found it; only the device did.

The fix, in `lib/services/audio_files.dart`:

- `audio_path` is stored **relative** to the app documents directory —
  `recordings/session_3/seg_1_1757000000.m4a`.
- Every read resolves it against `getApplicationDocumentsDirectory()` at the
  moment the file is needed, so the container UUID is looked up now instead of
  remembered from whenever the recording was made.
- One helper does this, and both `AudioService` and the transcription queue go
  through it. No caller touches a raw absolute path.
- Schema version 2 migrates existing rows by stripping everything up to and
  including the documents directory. It rewrites; it does not wipe. The rows
  were correct apart from a prefix we can identify exactly, and deleting
  recordings to avoid eleven lines of SQL would have broken the one promise
  this app makes.
- A test pins the invariant: a stored `audio_path` never begins with `/`.

**The fix itself has not yet been observed on the device.** It is verified by
80 passing tests including the migration and the version-1-to-version-2 reopen,
and it is the first thing to check on the next install. Until that happens,
this section says "fixed" about a defect and "tested" about a fix, and those
are different words on purpose.

---

## Still unverified on hardware

Shorter than it was, and these are what to hammer next.

### 0. The 28-byte recording — the live bug

- [x] **The `AVAudioSession` category.** Read off the device: `soloAmbient`
      before the first start, `playAndRecord` after, and `playAndRecord` on
      every attempt since. `record` manages it itself. Hypothesis dead.
- [x] **Permission.** Granted, confirmed.
- [ ] **The encoder probe.** Six configs, one run, byte count for each. The
      code is committed and has never been run.
- [ ] A recording with actual audio in it. Nothing on this phone has ever
      produced one.

### 1. The reinstall fix, on a second install

- [ ] Install, record, reinstall, play back. This is the exact sequence that
      exposed the bug and the only thing that can confirm the fix.
- [ ] A database from before the fix, upgraded in place on the phone: the
      migration has run against real SQLite in a test and never against a
      real user's rows.

### 2. Recording at real length

- [ ] A 30–90 second segment. The recordings made on the device were short.
      Upload time, the 60-second transcription timeout and the free tier's
      file-size limit are all still untested at real length.
- [ ] A recording from our own encoder, transcribed by Groq. The live API
      check used a synthesised clip, so the endpoint and our container are
      confirmed but our specific 16 kHz mono AAC settings are not.

### 3. Interruptions

- [ ] A phone call arriving mid-recording. The recorder loses the microphone
      and what `stop()` returns then is still unknown.
- [ ] Backgrounding the app mid-recording, and mid-upload.
- [ ] Force-quitting between `stop()` and the row insert. By design this
      leaves an orphan file and no row, which is the recoverable direction,
      and it has not been produced deliberately.

### 4. Permission refusal

- [ ] Denying the microphone shows `_MicrophoneBlocked` rather than crashing.
      Only the granting path was exercised.
- [ ] "Try again" after enabling it in Settings. iOS may restart the app on a
      permission change, in which case the button is never reached — which is
      acceptable, but we should know.

### 5. Android

- [ ] Nothing on Android has been run at all. It still builds
      (`flutter build apk --debug`), and per decision D3 iOS is the platform
      we test and demo. The migration handles Android's `app_flutter`
      directory anyway, because writing the second marker cost one line and
      guessing wrong later would cost recordings.

### 6. Layout, measured rather than assumed

- [ ] Whether long Arabic transcripts make the segment list unwieldy. Nothing
      truncates them, deliberately.
- [ ] Long bank questions at 26pt on a small screen.

---

## Known gaps that are not bugs

- **`editedByUser` is never set.** The transcript editor does not exist. The
  SQL that respects it does — deliberately in place before the feature that
  needs it, so adding the editor cannot introduce the overwrite bug.
- **Deviation from spec §6.** The spec says "hold to record"; this is
  tap-to-start, tap-to-stop, because a 30–90 second press is not viable
  one-handed. Flagged in `docs/walkthrough-slice2.md` rather than silently
  changed.
- **Questions repeat after the bank is exhausted.** `questionAt` wraps at 30.
  From Slice 4 the question comes from the model and the bank is the fallback.

---

## What this run was worth

Two real defects, neither of which any test on a laptop could have found.

The first was the reinstall bug: it needs two installs and a container that
moves. The second is worse and is still open — **the microphone has never
captured anything on this device**, and every green tick in the recording
path above was measuring that a file appeared, not that there was audio in
it. `stop()` checked `bytes == 0` and a 28-byte header satisfied it, so the
app reported success four times over silence.

That is the more uncomfortable lesson of the two. The tests were right, the
build was clean, the file was there, the row was written, and the ordering
guarantee we are proudest of held perfectly — around nothing at all. A
verification that only asks "did a file appear" will answer yes to an empty
container.
