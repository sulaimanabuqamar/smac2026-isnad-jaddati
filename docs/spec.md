# Jaddati — Product Spec

## 1. Problem

Every family has one person who holds the stories, and no one asks them,
because sitting down with a phone recording and saying "tell me about your
life" is an awkward and unanswerable prompt. The stories are lost to the
awkwardness, not to disinterest.

## 2. What the app does

Jaddati opens with a question. She answers. The app transcribes what she said,
reads it, and asks a specific follow-up drawn from her own words, so the
conversation keeps moving without the grandchild having to carry it. Each
session becomes a story card: her audio, her words in Arabic, an English
translation, and the people, places and decade extracted so the archive is
browsable rather than a pile of voice notes.

## 3. Persona

**Maryam, 20, KU undergraduate.** Speaks Arabic fluently, reads it slowly.
Sees her grandmother most Fridays. Has meant to record her for two years.
Phone at 40%, patchy signal in the majlis, one hand holding tea.

## 4. Use cases — when, where, how

- Friday after lunch, in the majlis, thirty minutes before people leave.
- On the drive home, listening back to what she just recorded.
- A week later, sending one story to the family group so cousins abroad can
  read it in English.

## 5. Out of scope

Multi-device sync · accounts and login · video · speaker separation ·
relationship inference · cloud backup · audio editing. Each is a deliberate
choice of depth over breadth, and each is an answer we give rather than a gap
we hide.

## 6. User flow

### High level
```
Choose person  →  Interview  →  Story card  →  Archive
```

### Low level

**Choose person** — pick an existing person / OR add a person (name, relation,
photo) / OR resume an unfinished session.

**Interview** — app shows a question (AI follow-up, or offline bank, or typed
by you) → hold to record → segment saved locally → transcribe now or queue →
follow-up appears → loop → end session.

**Story card** — play any segment / read Arabic, toggle English / edit the
transcript (always editable) / view extracted title, people, place, decade /
share as text.

**Archive** — browse by person / filter by decade or place / search transcripts
/ see the pending transcription queue.

## 7. Mobile constraints (orientation deck slides 29–33)

| Constraint | How we answer it |
|---|---|
| Finite battery | No background service, no polling |
| Sketchy internet | Recording and translation never touch the network |
| Small screen, handedness | Record button in the bottom third, thumb-reachable |
| Divided attention | One question on screen at a time |

## 8. Data model

SQLite via `sqflite`, hand-written SQL.

```
person   (id, name, name_ar, relation, photo_path, created_at)

session  (id, person_id → person, started_at, ended_at,
          title, place, decade, summary)

segment  (id, session_id → session, seq,
          question_text, question_source,      -- ai | bank | manual
          audio_path, duration_ms,
          transcript_ar, transcript_en,
          edited_by_user,                      -- 0 | 1
          transcribe_status,                   -- pending | done | failed
          created_at)

mention  (id, session_id → session, kind, value)   -- kind: person|place|year

bank_question (id, topic, text_ar, text_en)        -- seeded from assets
```

`segment` is the spine. Everything else hangs off it. `audio_path` is written
and flushed before `transcribe_status` is ever set — that ordering is the
reliability guarantee.

## 9. AI boundary

| Operation | Where | Why |
|---|---|---|
| Transcription (audio → Arabic text) | cloud | No on-device model handles Gulf Arabic at usable accuracy inside a sideloadable APK. Groq serves Whisper Large v3 on a free tier |
| Follow-up question generation | cloud | The question must be about what she just said — generation, not lookup. Gemini free tier; better Arabic than the alternatives |
| Story extraction (title, people, place, decade) | cloud | Piggybacked on the same call to save a round trip |
| Translation Arabic ↔ English | **on device** | ML Kit, ~32 MB model. Free, private, offline |
| Audio capture and storage | **on device** | No AI at all. The one thing that must never fail has no dependency that can |

**Cost.** Zero. Groq and Gemini both have free tiers that comfortably cover
our volume, and neither needs a card. If we ever exceeded them, Groq bills
Whisper at $0.111 per hour of audio.

### Failure modes

| Failure | What the user sees | Result |
|---|---|---|
| No connection | Question comes from the offline bank; recording normal; banner shows the queue | Session completes |
| Transcription fails | "Couldn't transcribe · retry"; audio plays; transcript typeable by hand | Audio safe |
| Transcript wrong | Every transcript editable, always, no special mode | User in control |
| Model returns bad JSON | Falls through to the bank question, logged | Session completes |
| Translation model missing | Button reads "Download Arabic pack · 32 MB" | Explained, not silent |

**The rule:** a session started with no signal, in a house with thick walls, on
a phone at 12%, must reach a saved story card.

## 10. Stack

**Flutter, iOS with free provisioning.** Android is generated and kept — the
project builds for both and it costs us nothing — but iOS is the build we test
and demo.

*Installs on a real phone on Demo Day.* The deciding factor is which device we
actually have. We own an iPhone and no Android handset, and a build we install
on hardware in our hands beats one we can only reason about. Free provisioning
signs the app with a personal Apple ID and installs it over a cable from Xcode:
no paid Developer Program, no TestFlight, and no dependency on Apple's review
queue. Expo Go is not an installed app and does not satisfy slide 10's
"downloadable in your phone as an application"; a signed build on the device
does. `flutter build apk --release` remains one command away if an Android
phone appears.

*Known risk — the profile expires after 7 days.* An app signed with a free
personal Apple ID stops launching a week after install. This is Apple's limit
on free provisioning, not a defect we introduced.

| | |
|---|---|
| Risk | Free provisioning profile expires 7 days after install |
| Impact | App refuses to launch — on Demo Day, in front of judges |
| Mitigation | Rebuild and reinstall from Xcode on **15 September**, the night before Demo Day |
| Fallback | Laptop and cable travel with us; a reinstall takes about two minutes |

*Both targets, deliberately.* iOS is the development and demo target because
it is the device we own: we install, test and re-test on real hardware every
day, and over eight days that is worth more than any platform argument.
Android is generated and built so that slide 10's "downloadable in your phone
as an application" has a literal answer — `flutter build apk --release`
produces one file anyone can install unaided, no cable and no Xcode. Neither
target is a hedge against the other. One is the phone we develop against; the
other is the artefact we can hand over.

*What that costs us to say honestly.* Free provisioning installs by cable from
Xcode rather than by download, so the iOS build alone would be a weak answer
to slide 10; the APK is what makes the answer literal. Two caveats attach to
that, and we state both rather than implying more.

First, the APK **compiles but has never been run on real Android hardware.**
Sulaiman will borrow an Android phone once before **8 September** and test it. Until then it is a compile-verified deliverable, not a
demonstrated one.

Second, it got there by losing a dependency. `permission_handler` 14.0.0
declares `compileSdk = 37`, which AGP resolves to the SDK target `android-37`;
Google publishes `android-37.0`, `37.1` and `37.2` and no plain `android-37`,
so the Android build could not resolve it. Rather than pin an old version or
override `compileSdk`, we removed the package: `record` already requests the
microphone permission through `hasPermission()`, which was the only job
`permission_handler` had here. Eight dependencies instead of nine, and one
less thing to defend.

*Defensible in Q&A.* One language, one codebase, an explicit widget tree. Eight
dependencies, each explainable in a sentence by a named owner. Flutter is also
named on slide 36 as a cross-platform option the organizers teach.

| Package | Does | Owner |
|---|---|---|
| `record` | Captures microphone audio to m4a, and requests the microphone permission via `hasPermission()` | Adel |
| `just_audio` | Plays a segment back | Adel |
| `sqflite` | Local database | Sulaiman |
| `path_provider` | Finds the writable audio directory | Sulaiman |
| `http` | Two API calls | Sulaiman |
| `flutter_dotenv` | Loads the key from an untracked file | Sulaiman |
| `google_mlkit_translation` | On-device Arabic ↔ English | Bilal |
| `intl` | Dates and durations in both languages | Bilal |

No state-management library. `setState` plus a repository class is enough for
five screens, and it is enough to explain.

## 11. Secrets

- `app/.env` holds `GROQ_API_KEY` and `GEMINI_API_KEY`. It is gitignored from the first commit, before a key existed.
- `app/.env.example` is committed with blank values.
- Release builds pass the key with `--dart-define`.
- Honest caveat: a key shipped inside any client app is extractable. The
  production answer is a thin proxy server holding the key. We scoped it out
  for eight days and we say so rather than pretending otherwise.

## 12. Schedule

| Day | Slice | Installable? |
|---|---|---|
| Sun 31 Aug | Transcription spike · repo · first commit from all three | — |
| Mon 1 Sep | Navigation skeleton + database + people | Yes |
| Tue 2 Sep | Core loop: record, save, play back. No AI | Yes |
| Wed 3 Sep | Transcription + queue | Yes |
| Thu 4 Sep | Follow-up generation | Yes |
| Fri 5 Sep | Translation + story card + extraction | Yes |
| Sat 6 Sep | Offline states, error states, polish, seeded demo data | Yes |
| Sun 7 Sep | Video · 2-page document · AI usage report | Yes |
| Mon 8 Sep | Submit with a day of margin | Yes |

Every slice ends installable. There is no day on which the app is half-wired.
