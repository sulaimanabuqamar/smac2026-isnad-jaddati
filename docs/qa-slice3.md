# Slice 3 — questions a judge could ask, and how to answer them

Ten questions. Four are marked **hard**: three where the honest answer is a
concession, and one where the confident answer is the wrong one.

Same rule as Slices 1 and 2 — the first sentence of each answer stands alone.
Say it, stop, let them ask for more.

---

## 1. Walk me through what happens after she stops speaking.

The recording is stopped, the file is closed, a `segment` row is written with
that file's path, and the transcription queue is kicked — without being waited
on.

That last part is the design. `unawaited(queue.run())` in `_stopAndSave` means
the next question goes on screen whether or not anything reaches the network.
The queue picks the row up, uploads the file to Groq, writes the transcript
back, and tells the screen to re-read. If any of that fails, the screen never
knew about it.

## 2. Why not just send the audio to the API while she is talking? It would be faster.

Because it would couple the thing we cannot recreate to the thing that fails.
Her voice is irreplaceable; a transcript can be regenerated from the file any
number of times.

Streaming would also mean that losing signal mid-answer loses the answer. As
it is, losing signal mid-answer loses nothing at all — the file is already on
disk and the row already exists.

## 3. What happens if the phone has no signal for the entire session?

Every segment stays at `transcribe_status = 'pending'` and the interview
continues exactly as it did in Slice 2. A line above the record button says
"No connection — this will finish later" and how many answers are waiting.

The queue retries on a rising schedule — 15 seconds, 45, 2 minutes, 5 — and
also whenever the interview screen is opened. When signal comes back the
transcripts fill in on their own.

## 4. **hard** — Your app uses AI. What happens when the AI is wrong?

We have a real example, and it is worse than being wrong. In the spike,
Whisper returned "اشتركوا في القناة" — *subscribe to the channel* — for two
unrelated clips. One of them was a man saying good morning to his friends.

That is a hallucination from YouTube subtitle data, not a mishearing, and it
fails *confidently*: our question generator then produced a perfectly fluent
follow-up asking which grandchild taught her to subscribe to a YouTube
channel. That is the moment a real session ends.

We did three things. We changed the model to `whisper-large-v3-turbo`, which
does not produce it on those clips. We added a guard: under 2 characters of
transcript per second of audio, we do not believe it, and the segment is
marked failed rather than shown as her words. And every transcript will be
editable, because none of them should be presented as certain.

The audio was never at risk in any of this. That is what decoupling buys.

## 5. How did you pick 2 characters per second? That sounds arbitrary.

**It is not calibrated, and I would not claim it is.** It comes from two data
points and one estimate.

Both hallucinations returned 17 characters for 10–15 seconds of audio: 1.2 and
1.6 characters per second. Conversational Arabic runs about 10–12. Two is a
fifth of normal speech and still clearly above both failures, so it is
deliberately far from either edge.

What makes a loose threshold acceptable is the asymmetry of being wrong. A
false positive costs one bank question instead of one AI question — the same
fallback the app already has for no signal. A false negative puts words in her
mouth and asks her about them. Those costs are not close, so the rule leans
towards rejecting.

It is a ratio rather than a blocklist on purpose. Blocking that one string
would catch the artefact we happened to see. The ratio catches the shape of
the failure — a confident model returning almost nothing.

## 6. Show me the code that stops one bad segment from blocking the queue.

Every failure carries one boolean, `transient`, and the queue reads nothing
else.

Transient — offline, rate-limited, server down, no key — leaves the row
`pending` and stops the run, because the next row would fail identically.
Permanent — a refusal, a missing file, a transcript we do not believe — marks
that row `failed` and the loop carries on to the next one.

Without that distinction, a phone in aeroplane mode would march through the
whole queue marking everything failed, and one moment of no signal would cost
the entire session's transcripts.

## 7. **hard** — Have you actually run this against the real API, or only against mocks?

Both, and the real one matters more. A 5.9-second AAC m4a of spoken Arabic
posted to `api.groq.com` with exactly the fields our service sends came back
HTTP 200 with the correct Arabic text.

That confirms the endpoint, the model name, `language=ar`, `temperature=0`,
the multipart field names, our m4a container, and the JSON response shape —
against the live service rather than the documentation. It also told us the
response has a leading space and an extra `x_groq` key, which we now trim and
ignore because we looked.

What has *not* been verified is a real recording from the phone's own
microphone at 30–90 seconds, and that is written down in
`docs/slice3-unverified.md` rather than glossed over.

## 8. **hard** — So none of this has run on a phone.

Correct, and neither has Slice 2. The microphone, the file write and playback
have never executed on hardware, and until they do, this is a transcription
pipeline for files that nothing on a phone has yet produced.

`docs/slice2-unverified.md` and `docs/slice3-unverified.md` list every
unexecuted path in order of risk, and they were written the day the code was,
not reconstructed afterwards.

What is genuinely verified is written down as precisely: 66 tests against real
SQLite and a mocked HTTP client, a clean analyze, a debug APK, and the live
API check above.

## 9. You removed a dependency this slice. Why?

`flutter_dotenv` read the API key out of a file bundled as a Flutter asset.
`flutter run --dart-define-from-file=.env` does the same job with the SDK we
already have.

The reason was not tidiness. A bundled `.env` must be declared in
`pubspec.yaml`, and a declared asset that is missing stops the build outright
— so anyone cloning this repo without a `.env`, including a judge, could not
have built the app at all. With `--dart-define-from-file`, a missing key is an
empty string, and a build with no keys is a configuration we support and test.

Seven dependencies now, down from nine on Sunday.

## 10. **hard** — The API key is inside the app. Isn't that a security problem?

Yes. A key shipped in any client app is extractable by anyone who wants it,
and moving it from a bundled file into the binary does not change that — it
only changes how much effort it takes.

The correct answer is a thin proxy server holding the key, with the app
talking to that. We scoped it out for an eight-day build and wrote the
trade-off into `docs/spec.md` section 11 rather than leaving it unsaid.

For the demo the key is ours, on the free tier, and rotatable in a minute.

---

## The one to be ready for

**"Show me the app working with the wifi off."**

That is the demo we should *offer*, not wait to be asked for. Aeroplane mode,
record an answer, watch the banner appear and the answer save anyway, then
turn wifi back on and watch the transcript arrive without touching anything.

It is the whole architecture in fifteen seconds, and it is the part of this
app that most entries will not have.
