# ASR failure modes

What we learned by looking at the two worst clips in the transcription spike,
and what it changes about the app.

Dated 1 September 2026. Reproducible from `spike/asr-retest.json` and
`spike/score_retest.py`.

---

## The two failures

Out of 31 clips in the first spike run, the median CER was 16.5% and two
clips scored 86% and 90%. That gap is too large to be the same phenomenon as
the rest of the distribution, so it was worth finding out what it was.

Both produced **the identical output**:

```
اشتركوا في القناة        "subscribe to the channel"
```

| clip | truth (opening) | whisper-large-v3 |
|---|---|---|
| `cars_chunk-03` | وصبحكم الله بالخير يا رفاقه الخير… | اشتركوا في القناة |
| `police_chunk-43` | قمنا باجراء سريع طلعنا السياره برا الشارع… | اشتركوا في القناة |

Two unrelated clips, from different topics, both collapsing to the same short
stock phrase. That is not mishearing. **It is Whisper emitting a
high-frequency artefact from its training data** — YouTube subtitles are full
of "subscribe to the channel", so it is the phrase the model falls back to
when its acoustic evidence is weak or the content resembles channel
boilerplate.

## What it is not

We checked the obvious explanations first, and they were all wrong.

**Not short clips.** `police_chunk-43` is 14.52 s — the longest length in the
dataset. `police_chunk-03`, the same 14.52 s, scored 20%. `cars_chunk-03` is
10.65 s against a dataset median of 13.11 s.

**Not file corruption.** Both are 16 kHz mono PCM, the same as everything
else, and both play.

**Not the language hint.** Removing `language=ar` changed the output by
nothing at all on `whisper-large-v3` — byte-identical hallucination with and
without it.

The acoustic measurements do show something, though it is a secondary effect:

| clip | dBFS | crest factor | verdict |
|---|---|---|---|
| `police_chunk-43` | −14.2 | **5.1** | loudest and most compressed in the set |
| `cars_chunk-03` | −25.1 | 12.1 | normal for speech |
| `police_chunk-03` (good) | −20.5 | 10.6 | normal for speech |

A crest factor of 5 is dense, compressed audio — background music, engine
noise or heavy broadcast processing rather than clean speech. So
`police_chunk-43` is a genuinely hard clip. `cars_chunk-03` is not: it is
acoustically ordinary, and its *content* is a YouTube-style intro that
literally says "everyone subscribed and activated". The model heard channel
boilerplate and produced the canonical form of it.

**Two different triggers, one output.** Weak acoustic evidence, or content
that resembles the artefact. Either is enough.

---

## The fix: whisper-large-v3-turbo

We re-ran both clips, plus a control clip that had scored well, across four
configurations.

| clip | v3 + `ar` | v3 + auto | **turbo + `ar`** | turbo + auto |
|---|---|---|---|---|
| `cars_chunk-03` | 86% | 86% | **1%** | 1% |
| `police_chunk-43` | 90% | 90% | **50%** | 60% |
| `police_chunk-03` (control) | 20% | 20% | **17%** | 17% |

Three conclusions, in order of confidence:

1. **`whisper-large-v3-turbo` does not produce the hallucination.** On
   `cars_chunk-03` it returns the actual sentence at 1% CER — from 86%. On
   `police_chunk-43` it returns real, if garbled, speech at 50% instead of a
   confident fabrication.
2. **Turbo does not cost us anything on clips that already worked.** The
   control went 20% → 17%.
3. **Keep `language=ar`.** It makes no difference on v3, and on turbo it is
   worth 10 points on the hard clip (50% vs 60%).

**Decision: switch transcription to `whisper-large-v3-turbo` with
`language=ar` in Slice 3.** The spike's mean CER of 22.8% was measured on v3;
expect it to improve, and re-measure rather than assume.

### The caveat

Three clips is not a benchmark. What we have is one clip where turbo
decisively fixes a catastrophic failure, one where it converts a fabrication
into a poor-but-honest transcript, and one where it is marginally better. That
is enough to switch a default. It is not enough to claim turbo is better in
general, and we should re-run the full spike on turbo before quoting any
accuracy number.

---

## Why this matters beyond accuracy

**A hallucination is worse than a bad transcript, because everything
downstream believes it.**

`cars_chunk-03` in the pipeline run is the whole problem in one screenshot.
Whisper returned "subscribe to the channel", and Gemini — behaving perfectly,
given its input — generated three fluent, well-grounded follow-up questions
about a television channel:

> - شو اسم هاي القناة اللي تطريها يا يدّي؟
>   *What is the name of this channel you are talking about, grandfather?*
> - منو من العيال اللي علمك تشترك في القناة؟
>   *Which of the grandkids taught you how to subscribe to the channel?*

The grandmother said good morning to her friends. The app would ask her which
grandchild taught her to subscribe to a YouTube channel. She would assume the
app is broken, or that she is being misunderstood, and that is the moment the
session ends.

A 50% CER transcript degrades gracefully — the follow-up question is vague but
not insane. A hallucination fails **confidently**, and confidence is what
makes it unrecoverable in front of a real person.

---

## What this changes in the app

### 1. Transcription config (Slice 3)

`whisper-large-v3-turbo`, `language=ar`. Recorded here so the choice has a
reason attached rather than being a string someone typed.

### 2. A guard on implausibly short transcripts

Both failures returned **17 characters** for 10–15 seconds of speech. That
ratio is the cheapest possible detector, and it needs no second model call.

The rule: if a transcript is very short relative to the audio duration, treat
it as failed rather than as content. Do not send it to the question generator,
do not show it as her words. Fall back to the offline bank question, and mark
the segment for retry.

The audio is safe either way — that is D1 — so the cost of a false positive is
one bank question instead of one AI question, which is the fallback the app
already has for having no signal.

### 3. Interview screen design input

- **Recording environment matters more than we assumed.** The worst clip was
  the one with music or noise over the speech. A quiet room is not a nicety.
- **Never present a transcript as certain.** Every transcript is editable —
  already the design, and this is the evidence for why.
- **A failed transcription must not stall the interview.** The next question
  comes from the bank and the session continues, which is exactly the
  no-signal path.

### 4. Q&A answer

If asked "what happens when the AI gets it wrong", this is the honest answer
with a real example: we found a case where it did not just get it wrong, it
got it wrong confidently and the error propagated into a question that would
have embarrassed the user. We changed the model, added a length guard, and
kept every transcript editable. The audio was never at risk, because
transcription is decoupled from recording.

---

## Reproducing

```
cd ~/Documents/SMAC/spike
python score_retest.py          # scores asr-retest.json
```

`spike/` is outside the repository and is not tracked — it holds the dataset,
API keys in old error logs, and 467 audio files.

**Note:** `spike/results.md` from 31 August contains the Gemini API key in
plaintext, inside 429 error URLs. It must not be copied into this repository,
and the key should be rotated.
