# Slice 3 — what has never been executed

Written 4 September 2026, the day Slice 3 was built. Same discipline as
`docs/slice2-unverified.md`: the distinction is between **verified** and
**written**, and "it compiles" is not allowed to stand in for "it works".

Slice 3 is the first slice where a meaningful part of the risk *was* retired
before the commit.

**Updated the same day, after the device run.** Slice 2 has now been executed
on an iPhone, which unblocks part of this list — the offline banner in
particular — and which found the reinstall bug described in
`docs/slice2-unverified.md`. That bug broke this slice too: a segment whose
audio could not be found was marked permanently failed. Both halves are fixed
by the same change.

---

## Genuinely verified

| Claim | How |
|---|---|
| Groq accepts our exact request and returns Arabic | curl to the live endpoint with the same fields, model, and an m4a AAC file. HTTP 200, correct transcript |
| Our m4a container is acceptable to the endpoint | same call — the probe file was AAC in m4a, as `AudioService` produces |
| `--dart-define-from-file=.env` reaches `ApiKeys` | `flutter test --dart-define-from-file=.env` passes an assertion on the key; the same test fails without the flag |
| The guard rejects both real spike hallucinations | `flutter test`, with the actual strings and durations |
| Every HTTP branch does the right thing to a row | `flutter test` through `MockClient` — 200, 400, 429, 503, dead socket |
| The transcript SQL, including the correction guard | `flutter test` against real SQLite |
| The queue's retry decisions | `flutter test` — drains, stops on transient, marks permanent, carries on |
| The offline banner and queueing, on the phone | device run, 4 September — recorded with no signal, answers saved, banner correct |
| `audio_path` is never stored absolute, and old rows migrate | `flutter test` — the invariant, the SQL, and a real version 1 → 2 reopen |
| 80 tests, analyze clean, debug APK builds | `flutter test`, `flutter analyze`, `flutter build apk --debug` |

The endpoint verification is the important one. It means the single most
likely way Slice 3 fails on a phone — a wrong model name, a rejected
container, a field the API does not accept — has already been eliminated on
this machine.

---

## Never executed

### 1. Transcription on a device

Slice 2 now runs on hardware, so this is no longer blocked. What has been
seen on the phone is the queue's *offline* behaviour — the banner appears
with no signal and the answers save anyway. What has not been seen is a
transcript arriving.

- [ ] A real recording made by `AudioService` — 16 kHz mono AAC, not
      macOS `say` output — is accepted by Groq. The container is confirmed;
      our specific encoder settings are not.
- [ ] A 30–90 second segment. The probe was 5.9 seconds. Upload time, the
      60-second timeout and the free-tier size limit are all untested at
      real length.
- [ ] Real Arabic from a real grandmother, in a real room. Every transcript
      we have seen came from a spike dataset or a synthetic voice.
- [ ] A transcript appearing under an answer on the phone. The path from a
      200 response to text on screen has only ever run in tests.

### 2. The queue over time

- [ ] The backoff timer firing. `Timer(wait, run)` is written and has never
      fired in a test or on a device — the tests drive `run()` directly.
- [ ] Recovery when signal comes back on its own, without the user opening
      the interview screen.
- [ ] The app being backgrounded mid-upload. iOS suspends the process; what
      happens to an in-flight `http` request is not known here. The row stays
      `pending` either way, which is the point, but the failure it produces
      has not been seen.
- [ ] A segment recorded while the previous one is still uploading. The
      `while` loop re-reads `getPending()` each pass specifically to catch
      this, and it has only been tested with rows written up front.

### 3. Rate limiting, for real

- [ ] An actual 429 from Groq. The handling is tested against a fake; the
      free tier's real limits and headers have not been hit deliberately.
- [ ] Whether a whole session — ten to fifteen segments in twenty minutes —
      stays inside the free tier at all. **This is a demo-day risk, not a
      code risk.** If it does not, the app degrades to a queue that catches
      up afterwards, which is survivable but is not what we would want a
      judge to watch.

### 4. The guard against real speech

- [ ] A genuinely short real answer over long audio: a grandmother who
      thinks for twenty seconds and says four words. Under the current rule
      that is marked failed. We believe the trade is right, and we have never
      seen it happen.
- [ ] The threshold against a corpus. Two data points is not a calibration,
      and the walkthrough says so.

### 5. Screen behaviour

- [ ] Long Arabic transcripts in a card. Nothing truncates them, deliberately,
      so a two-minute answer makes a tall row. Whether that scrolls acceptably
      on a phone is unmeasured.
- [x] **The offline banner, with no signal, on the device — verified.** The
      answers saved and the banner said how many were waiting.
- [ ] The banner *disappearing* as signal comes back, and the transcripts
      filling in behind it. Only the offline half was seen.
- [ ] "Try again" on a failed segment, tapped by a finger rather than called
      by a test.
- [ ] Whether `_onQueueChanged` re-reading the whole session on every
      notification is fast enough at thirty segments. It is one indexed query
      per notification and should be, and "should be" is what this list is for.

---

## Known gaps that are not bugs

- **No follow-up question yet.** The question still comes from the bank.
  Slice 4 reads the transcripts this slice writes. Until then, transcription
  is visible but not yet load-bearing — which is a good order to build in.
- **No transcript editing.** `edited_by_user` is respected by the SQL and is
  still never set by any screen. The guard is in place before the feature
  that needs it, on purpose: adding the editor later cannot introduce the
  overwrite bug.
- **No English yet.** `transcript_en` stays null until Bilal's ML Kit slice.
- **Retry count is not persisted.** A segment that fails permanently, is
  retried by the user and fails again looks identical to one failing for the
  first time. Schema version 1 has no `attempts` column and a migration for
  this was not worth it.
- **The key is in the binary.** Extractable, as `docs/spec.md` section 11
  already says. A proxy server is the real answer and is out of scope for
  eight days.

---

## The honest summary

The network half of Slice 3 is better verified than any code we have written
so far, because the API contract was checked against the live service instead
of being asserted. The database half is covered by 66 tests.

The gap has narrowed but not closed. Slice 2 now runs on a phone, and the
queue's offline behaviour was seen there — which is the half of this slice
that matters most for the reliability rule. What has still never happened on
a device is a transcript coming *back*: no recording made by our own encoder
has been sent to Groq, and no Arabic has appeared under an answer on screen.

The device run also cost this slice a defect. A segment whose audio could not
be located was marked permanently failed, so the reinstall bug in
`docs/slice2-unverified.md` was quietly destroying transcription state as
well as playback. That is worth saying plainly: the two failures looked
unrelated on screen and were one line of code.
