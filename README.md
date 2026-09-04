# Jaddati — جدتي

**A recorder that conducts the interview.** It listens to what your
grandmother just said, and asks her the next question.

Khalifa University · Smart Mobile Application Contest (SMAC) 2026
Undergraduate category · Theme: *AI for Stronger Family Bonds*

**Team Isnad** — إسناد, the chain of transmission by which a story reaches you intact.

| | |
|---|---|
| Sulaiman Abuqamar | data layer, services, API integration |
| Adel Almheiri | audio capture and playback, interview screen |
| Bilal Alkhofash | story card, archive, on-device translation |

---

## The problem

Every family has one person who holds the stories, and no one asks them —
because sitting down with a phone recording and saying "tell me about your
life" is an awkward and unanswerable prompt. The stories are lost to the
awkwardness, not to disinterest.

## What it does

Jaddati opens with a question. She answers. The app transcribes what she
said, reads it, and asks a specific follow-up drawn from her own words —
*"who else lived in that house with you?"* — so the conversation keeps
moving without the grandchild having to carry it.

Afterwards each session becomes a story card: her audio, her words in Arabic,
an English translation for the cousins who don't read it, and the people,
places and decade the app extracted so the archive is browsable rather than a
pile of voice notes.

## How it works

```
question  →  record segment  →  save locally  →  transcribe  →  follow-up  →  ↺
                    (offline, always)              (cloud)       (cloud)
```

Recording and transcription are deliberately decoupled. Audio is written to
local storage before anything touches the network, so a session works with no
signal: questions fall back to a 30-question offline bank, recordings queue,
and translation runs on-device. Nothing about a bad connection can cost you
her voice.

## Running it

Requires Flutter (stable) and the Android SDK.

```bash
cd app
cp .env.example .env        # then paste your keys into it
flutter pub get
flutter run   --dart-define-from-file=.env   # debug on a connected device
flutter build apk --release --dart-define-from-file=.env
```

`.env` is gitignored and holds the two cloud keys. The Flutter SDK reads it
directly with `--dart-define-from-file`, so there is no `.env` asset and no
dotenv package — see `app/lib/services/api_keys.dart`.

**Without the flag the app still runs.** Recording, playback, the offline
question bank and the archive all work with no keys at all; transcripts simply
stay queued. That is the point of the design, not a degraded mode.

The release APK is at `app/build/app/outputs/flutter-apk/app-release.apk`.

## Repository

```
docs/       spec, user flows, wireframes, meeting notes
app/        the Flutter application
AI-USAGE.md every AI prompt used, dated — required by contest rules
CLAUDE.md   working rules for this repo
```

## AI usage

Per contest rules, all AI assistance is documented in
[AI-USAGE.md](AI-USAGE.md) — the actual prompts, and what each contributed.

The competition rules were amended on 31 August 2026: Dr. Hadi Otrok confirmed
by email that AI may be used for all parts of the entry. From that date AI has
written application code here, and every session that it did is logged in
AI-USAGE.md with the prompt and what was done with the result. What has not
changed is that the member who owns a file has read every line of it and can
explain it — each slice has a walkthrough in `docs/` recording why the code is
shaped the way it is.
