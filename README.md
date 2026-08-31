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
signal: questions fall back to a 48-question offline bank, recordings queue,
and translation runs on-device. Nothing about a bad connection can cost you
her voice.

## Running it

Requires Flutter (stable) and the Android SDK.

```bash
cd app
cp .env.example .env        # add your API key
flutter pub get
flutter run                 # debug on a connected device
flutter build apk --release # installable APK
```

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
The application was written by the team; AI was used for planning, review and
specific explanations, all logged.
