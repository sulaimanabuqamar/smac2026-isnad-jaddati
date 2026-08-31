# Slice 1 — questions a judge could ask, and how to answer them

Ten questions. The three marked **hard** are the ones I think would catch you
out if you had not thought about them beforehand — two of them because the
honest answer is a concession, and one because the obvious answer is wrong.

Answer length matters. Every answer below has a first sentence that stands on
its own. Say that, stop, and let them ask for more.

---

## 1. Walk me through what happens when I press save on the add-person screen.

`AddPersonScreen._save` validates the form, builds a `Person` object, and
calls `PersonRepository.create`, which runs one SQL insert and returns the
new row's id. The screen then pops with `true`, and `PeopleScreen` sees that
`true`, re-runs its counts query, and rebuilds the list with `setState`.

The screen never sees SQL. It calls a method on a repository and gets a
model back — that boundary is why we can test the database logic without a
widget, and it is the same boundary in every screen.

## 2. Why SQLite rather than just writing a JSON file?

Because the archive has to be searched and filtered, and that is what a
database is for. The spec calls for browsing by person, filtering by decade
or place, and searching across transcripts. With JSON, every one of those is
a full read of the file into memory and a loop in Dart. With SQL they are one
statement each, and they stay one statement when there are two hundred
segments instead of five.

There is also a durability answer: SQLite writes transactionally. A JSON file
rewritten on every change can be truncated by a phone dying mid-write, and
you lose the whole archive rather than one row.

## 3. What does `PRAGMA foreign_keys = ON` do, and why is it in `onConfigure`?

It makes SQLite actually enforce foreign keys, which it does not do by
default. Without it, our `ON DELETE CASCADE` clauses are parsed and then
ignored — deleting a person would silently leave their sessions behind as
orphaned rows.

It is in `onConfigure` rather than `onCreate` because the setting applies per
connection, not per database file. `onCreate` runs once, ever. `onConfigure`
runs every time the database is opened, which is what this needs.

We have a test for it: "cascades to the sessions belonging to that person" in
`person_repository_test.dart` fails if that line is removed.

## 4. Your `segment` table has `UNIQUE (session_id, seq)`. Why?

Because two segments in the same session cannot both be the third question.
`seq` is what orders the conversation, and a duplicate would make the order
ambiguous — the story card would render two answers in an arbitrary order.

It also protects `nextSeq`, which computes `MAX(seq) + 1`. If two segments
were ever saved concurrently they could both compute the same next value; the
constraint means the second insert fails loudly instead of quietly creating
an ambiguous session.

## 5. What happens if the transcription API is down?

Nothing that costs you a recording. Audio is captured to a local file with no
network involved, the `segment` row is written after that file is closed, and
the row is born with `transcribe_status = 'pending'`. Transcription is a
separate job that runs against a row that already exists.

So the API being down means some segments sit at `pending` until it comes
back. The audio is on the phone, the session continues, and the next question
comes from the offline bank in `bank_question` instead of from the model.

This is decision D1 in CLAUDE.md and it is the reason the app is built in two
halves rather than one.

## 6. Show me where the offline question bank comes from.

`assets/questions/bank.json` in the repository, declared under `flutter:
assets:` in `pubspec.yaml`, which is what puts it inside the built app. The
first time the app runs there is no database file, so `onCreate` fires; it
creates the schema and then calls `seedBankQuestions` with the file's
contents, which parses the JSON and inserts every question in one batch.

It only happens once, on first run. After that the database exists and
`onCreate` does not fire again.

One detail worth volunteering: `seedBankQuestions` takes the JSON as a
string rather than reading the asset itself. That is what lets us test the
parsing and the SQL against the real file with no device and no Flutter
asset bundle — there are five tests over it.

---

## 7. **Hard.** Did you write this code, or did AI write it?

AI wrote the first draft of this slice, and I reviewed and own every line of
it. Dr. Otrok approved AI-generated code for this entry by email on 31
August, and that approval is recorded in CLAUDE.md along with what it did and
did not change.

I would rather answer the question behind the question, which is whether I
can defend it. Ask me about any file. The reason `audio_path` is `NOT NULL`,
the reason `foreign_keys` is in `onConfigure` and not `onCreate`, the reason
the counts query uses correlated subqueries rather than a join — those are
decisions with reasons, and the reasons are written down in
`docs/walkthrough-slice1.md`, which exists precisely so that this is a
conversation and not a bluff.

**Do not**: get defensive, or claim you typed it. The GitHub history shows
commits co-authored with an AI assistant; denying it would be caught in
thirty seconds and would cost you the entire Q&A.

**If pressed on "so what did *you* do?"**: the architecture decisions came
first and are dated earlier in the repository than any code — the four
decisions in CLAUDE.md, the schema in `docs/spec.md` section 8, the AI
boundary table. The code implements a design that was already written down.

## 8. **Hard.** Your tests run SQLite on a Mac. The app runs SQLite on a phone. What do your tests actually prove?

They prove the SQL is correct and the repository logic is correct. They do
not prove the app works on a phone, and I would not claim they do.

Specifically: `sqflite_common_ffi` runs a real SQLite engine, not a mock, so
the schema, the CHECK constraints, the cascades and every query are genuinely
exercised. What differs is the platform layer around it — file paths, the iOS
sandbox, permissions, threading under load.

So the tests catch the class of bug I most expect to write, which is a wrong
query or a wrong column name, and they catch nothing about the platform. The
platform bugs get caught by running it on a device.

**The concession to make honestly**: as of this slice, that has not happened.
This code has never run on a phone. It analyses clean, 18 tests pass, and it
builds an APK — and those three facts are the entire basis for believing it
works.

## 9. **Hard.** Your spec says nine dependencies. Your pubspec has eight. Which is wrong?

Neither — the spec was updated when the dependency was removed, and the
commit history shows both the removal and the reason.

We dropped `permission_handler`. It was in the plan to request the microphone
permission, and then the Android build failed on it: version 14 declares
`compileSdk = 37`, and Google's SDK repository publishes `android-37.0` and
`android-37.1` but no plain `android-37`, so the target could not be
resolved.

The interesting part is what we did next. There were three options — pin the
old version, override `compileSdk` in a Gradle `subprojects` block, or find
out whether we needed the package at all. It turned out `record`, which we
already had for audio capture, exposes `hasPermission()` that both checks and
requests the microphone permission on both platforms. `permission_handler`
was doing a job something else already did.

So the answer is eight, and the reason there is a discrepancy to notice is
that the spec is kept current rather than written once.

---

## 10. You have no audio and no AI in this build. What have you actually got?

A complete data layer and a working app on top of it. The schema is all five
tables, not just the one this screen needs, because changing a schema after
there is real recorded audio in it is far more expensive than getting it
right while the database is empty.

Concretely: people can be added, stored and listed with their session and
story counts; the offline question bank is seeded into the database on first
run; the navigation for every screen exists; and the bilingual text layout —
which is the thing most likely to be wrong if retrofitted — is built and used.

The three unbuilt screens say what they will do, which day they are scheduled
for, and who owns them. That is deliberate: I would rather you navigate into
one and see a plan than see a blank page.

---

## Two you should be ready for that are not on this list

**"Can I install it on my phone right now?"** Not yet on iOS — signing is not
set up. There is a debug APK that builds, but it has never been run on an
Android device either. Say so plainly; the alternative is being caught out
by a judge who asks you to demonstrate it.

**"What is the riskiest thing about this project?"** The seven-day free
provisioning profile expiry, which is why there is a scheduled rebuild on
15 September in `docs/spec.md` section 10. Having a named risk with a dated
mitigation is a better answer than claiming there isn't one.
