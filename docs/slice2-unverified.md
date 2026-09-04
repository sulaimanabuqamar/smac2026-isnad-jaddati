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
| `AudioRecorder.start` with AAC-LC, 16 kHz, mono | **works** — the encoder accepts our config on real hardware |
| A file appears under the app documents directory | **works** |
| `stop()` returns a file with bytes in it | **works** |
| A segment row is written after the file, never before | **works** — the D1 ordering holds in practice, not just in argument |
| Recordings and rows survive closing and reopening the app | **works** |
| The question chain advances through the bank, one question per answer | **works** |
| The offline queue banner appears with no signal, and the answers still save | **works** — this is the demo described in `docs/qa-slice3.md` |

That is the great majority of what the old file listed as unknown. The
riskiest item on it — iOS terminating the app instantly over a missing usage
string — did not happen.

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

### 1. The fix, on a second install

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

Nine of the ten things the old file called unknown turned out to work. The
tenth was broken in a way that would have appeared for the first time in front
of a judge — on the second install of the week, with a phone full of
recordings that all looked lost.

That is the argument for the whole practice: the list existed, we ran it, and
it found the one defect that no amount of testing on a laptop could have.
