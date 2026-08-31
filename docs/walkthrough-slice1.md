# Slice 1 — walkthrough

Written for Sulaiman, reading this the morning after, having not watched the
code being written. It goes file by file: what it does, why it is shaped that
way, and what the alternative was.

Nothing here is a summary of the comments in the code. If a file says
something in a comment, this document says why that thing was worth deciding.

---

## What Slice 1 actually is

A running app that stores people and shows them. No audio, no network, no AI.
The data layer underneath it is built for the whole app, not just for this
screen — the schema is complete, all five tables, because changing a schema
after there is real recorded audio in it is far more expensive than getting
it right while the database is empty.

Three things are true of it right now:

- `flutter analyze` is clean.
- `flutter test` passes, 18 tests.
- `flutter build apk --debug` succeeds.

It has never run on a phone. iOS signing is not set up yet, and no Android
device has been connected. **Everything below is verified by the analyzer,
the tests and the compiler, and by nothing else.** That distinction matters
and is not hedging: the first run on real hardware will find things.

---

## How to run it

```
cd app
flutter test          # 18 tests
flutter analyze       # clean
flutter run           # needs a device; not yet possible
```

---

## The shape of it

```
lib/
  main.dart              app, theme, routes, opens the database
  theme.dart             colours and type
  models/                five plain classes, one per table
  data/                  db.dart + three repositories — all the SQL
  screens/               five screens, two real, three placeholders
  widgets/               bilingual text, "not built yet" placeholder
test/
  person_repository_test.dart
  bank_seed_test.dart
```

The rule this layout enforces: **SQL lives in `data/`, and nowhere else.**
A widget that wanted to run a query would have to import sqflite to do it,
which is visible in a diff and easy to reject in review.

---

## The four questions you asked me to answer

### 1. Why `audio_path` is written before `transcribe_status` is ever set

This is decision D1 from CLAUDE.md, expressed in code rather than in prose.

The recording is the irreplaceable thing. A transcript can be regenerated
from the audio any number of times; the audio cannot be regenerated from
anything. So the order of operations when a segment finishes is fixed:

1. The recorder writes the audio file and closes it.
2. Only then is a `segment` row inserted, and `audio_path` is one of its
   required columns.
3. That row is born with `transcribe_status = 'pending'`.
4. Transcription happens later, as a separate job, against a row that
   already exists.

The consequence is the thing worth understanding: **there is no moment in
which the database believes a recording exists that is not on disk.** If the
app is killed between steps 1 and 2 you lose a database row and keep the
audio file, which is recoverable. If the order were reversed you would lose
the audio and keep a row pointing at nothing, which is not.

Three places in the code enforce this rather than just hoping for it:

- `Segment.audioPath` is `String`, not `String?`. You cannot construct a
  Segment without one.
- `segment.audio_path` is `TEXT NOT NULL` in the schema. Even raw SQL cannot
  write a row without it.
- `SegmentRepository` exposes `create` and nothing else that writes. There is
  no `createPending()` or `reserveSegment()` that would let you make the row
  first and fill in the audio later.

**The alternative** was to insert the segment row when recording *starts*,
which is what you would do if you wanted a progress indicator driven by the
database, or if you wanted to survive a crash mid-recording. We rejected it
because it makes "a row exists" mean "a recording was attempted" instead of
"a recording exists", and every read path downstream would then need to
handle a segment whose audio is absent. One nullable column would have cost
us a null check in the interview screen, the story card, the archive, the
player and the transcription queue.

### 2. Why sqflite and hand-written SQL instead of Drift

Drift is the better library. It generates type-safe queries, catches column
name typos at compile time, and handles migrations more gracefully than we
will. On engineering merit alone, Drift wins.

We are not optimising for engineering merit alone. The rubric puts 35% on
GitHub evidence and the Q&A, and CLAUDE.md's rule is that no line survives
that a team member cannot explain in thirty seconds. Drift works by code
generation: you write a table description, run `build_runner`, and it emits
several thousand lines of Dart into `*.g.dart` files that are committed to
the repository and are unmistakably not written by you.

Picture the question: *"who wrote this file?"* The honest answer is "a code
generator", which is fine, and then the follow-up is "so what does it do?",
and the honest answer to that is that we would have to go and read it.

With `db.dart` the answer is that the file is 170 lines, every statement in
it can be read out loud, and the schema in it can be diffed against
`docs/spec.md` section 8 by eye.

**The cost we are accepting** is real and you should be able to name it:
column names are strings, so `map['nmae']` compiles and returns null at
runtime. That is exactly the class of bug Drift removes. Our mitigation is
that all the strings are confined to the `toMap`/`fromMap` pairs and the
repositories, and the tests read every field back after writing it — the
first test in `person_repository_test.dart` exists precisely to catch a typo
in a column name.

### 3. Why setState and repositories instead of a state management package

Count what state this app actually has. On `PeopleScreen`: one list, which
changes when you come back from having added someone. That is it.

Riverpod, Bloc and Provider all solve a problem we do not have — state shared
between screens that are not in a parent-child relationship, or state whose
updates need to be fine-grained for performance. Five screens, one list, and
a database that is the real source of truth in any case.

What we use instead:

- **`setState`** for the state a single screen owns.
- **Repositories** for anything that outlives a screen, which means the
  database.
- **Constructor parameters** to get repositories where they are needed.
  `main.dart` builds `PersonRepository` once and hands it to `PeopleScreen`,
  which hands it to `AddPersonScreen`.

That last point is doing more work than it looks. A screen's constructor is a
complete, honest list of everything that screen can touch. `AddPersonScreen`
takes a `PersonRepository` and therefore cannot read a session, cannot open
a file, cannot make a network call. With a service locator or a global
provider, every screen can reach everything, and the only way to know what a
screen touches is to read all of it.

**When to revisit this:** if two screens ever need to observe the *same*
changing state simultaneously — for example a transcription queue badge that
updates on the archive screen while the interview screen is also running —
`setState` stops being enough, and the right answer is probably a
`ValueNotifier` on the repository before it is a package. Say that in the
Q&A if pressed; "we would add X when Y happens" is a stronger answer than
"we do not need it".

### 4. How `bank.json` gets from an asset into the database

Four steps, and the split between them is the interesting part.

**Step one — the file is declared.** `app/assets/questions/bank.json` exists
on disk, and `pubspec.yaml` lists it:

```yaml
flutter:
  assets:
    - assets/questions/bank.json
```

Without that entry the file sits in the repository and is not in the built
app. This is the single most common way this breaks, and it fails at runtime
rather than at compile time, which is why there is a test asserting the file
exists at the path `AppDatabase.bankAssetPath` names.

**Step two — the database is created.** The first time the app runs,
`openDatabase` finds no file, so it runs `onCreate`. That is the *only* time
seeding happens. On every subsequent launch the database exists and
`onCreate` does not fire.

**Step three — the asset is read.** Inside `onCreate`:

```dart
await createSchema(db);
await seedBankQuestions(db, await rootBundle.loadString(bankAssetPath));
```

`rootBundle.loadString` reads the file out of the app bundle as a string.

**Step four — the string is parsed and written.** `seedBankQuestions` decodes
the JSON, maps each entry of the `questions` array through
`BankQuestion.fromJson`, and inserts them in one batch.

The design decision here is the signature: **`seedBankQuestions` takes a
`String`, not an asset path.** It does not know what an asset is. That is why
`bank_seed_test.dart` can hand it the real file read with `dart:io` and test
the actual parsing and the actual SQL, with no Flutter asset bundle and no
device. Had the function called `rootBundle` itself, testing it would have
required a widget test with a mocked bundle, and it would almost certainly
not have been tested at all.

Two smaller choices inside it:

- `BankQuestion.id` is the string from the file (`child_01`), not an
  autoincrement integer. The file's own id is stable across re-seeds.
- The inserts use `ConflictAlgorithm.replace`, so seeding twice updates
  wording instead of failing on the primary key. There is a test for this,
  because the day we move seeding into an `onUpgrade` for schema version 2,
  it will run against a database that already has rows.

---

## File by file

### `lib/models/person.dart`

**Does.** Holds one person, converts to and from a database row. Also defines
`PersonSummary`, a person plus their two counts.

**Why this way.** `toMap` omits `id` when it is null, which is what lets the
same method serve both insert (no id yet, SQLite assigns one) and update (id
present). Dates are stored as `millisecondsSinceEpoch` integers because
integers sort correctly in SQL; an ISO string would sort correctly too but
compares more slowly and invites timezone mistakes.

`PersonSummary` is a separate class rather than nullable count fields on
`Person`, because it is a *read model* — something the list screen needs and
nothing writes back. Putting `sessionCount` on `Person` would mean every
`Person` in the app carries two fields that are usually meaningless.

**Alternative.** A single class with nullable counts, or a record type. The
named class costs eight lines and makes the query's purpose obvious.

### `lib/models/session.dart`

**Does.** One sitting with one person.

**Why this way.** `endedAt` is nullable and its nullness is load-bearing: it
is the definition of "unfinished". A session interrupted by a phone call is
a row with `ended_at IS NULL`, which is what `getUnfinishedForPerson` finds
and what the counts query excludes from the story count.

`title`, `place`, `decade` and `summary` are all nullable because they are
filled in later by the extraction call, and a session is completely valid
without them. That is decision D1 again: the AI-derived fields are always
optional, so a session survives the AI failing.

**Alternative.** A `status` enum column (`open` / `finished`). Rejected
because it duplicates information already in `ended_at` and creates the
possibility of the two disagreeing.

### `lib/models/segment.dart`

**Does.** One question, one answer, one audio file. The spine.

**Why this way.** Covered at length in question 1 above. The other decision
here is the two enums, `QuestionSource` and `TranscribeStatus`. Each carries
its database string on the enum value itself:

```dart
enum TranscribeStatus {
  pending('pending'), done('done'), failed('failed');
  const TranscribeStatus(this.db);
  final String db;
}
```

So the mapping lives in one place and `TranscribeStatus.pending.db` is the
only way to produce that string. Writing `'pendign'` somewhere is impossible
rather than merely unlikely.

`seq` is an explicit column rather than being inferred from `id` order,
because the two would diverge the moment we allow re-recording an answer.

**Alternative.** Bare strings, which is what most Flutter tutorials do. It
saves fifteen lines and costs you a class of silent bug that only shows up
as an empty list.

### `lib/models/mention.dart`

**Does.** A person, place or year found in a session's transcripts.

**Why this way.** `value` is flat text, deliberately not a foreign key to
`person`. Deciding that "Fatima" in a transcript is the same Fatima as a row
in the database is relationship inference, which `docs/spec.md` section 5
puts explicitly out of scope. This is a case where the code enforces a scope
decision — you could not accidentally build relationship inference on this
schema without changing the schema first.

### `lib/models/bank_question.dart`

**Does.** One offline fallback question.

**Why this way.** Two constructors, `fromMap` and `fromJson`, because the
database column names (`text_ar`, `text_en`) and the JSON keys (`ar`, `en`)
are different. Rather than renaming one to match the other, the class knows
both. The spec wrote the schema and the question bank independently and both
are reasonable in their own context; forcing them to agree would mean
editing the question bank to suit the database.

### `lib/data/db.dart`

**Does.** Opens the database, creates schema version 1, seeds the bank.

**Why this way.** Three things worth knowing.

`configure` runs `PRAGMA foreign_keys = ON`. SQLite disables foreign keys by
default and does it **per connection**, so this cannot go in `onCreate` — it
has to run every time the database is opened. Get this wrong and nothing
fails loudly: the `ON DELETE CASCADE` clauses are simply ignored, and
deleting a person leaves their sessions behind forever. The cascade test in
`person_repository_test.dart` is there to catch exactly that.

`createSchema` is a static method separate from `_open`, so the tests can
build the identical schema in an in-memory database. There is one definition
of the schema and both the app and the tests use it.

The `CHECK` constraints on `question_source`, `transcribe_status`,
`edited_by_user` and `kind` are belt and braces over the Dart enums. The
enums stop us writing a bad value; the CHECK stops anything else doing it,
including a future migration script or a debugging session with a SQL client.

**Alternative.** Skipping the CHECKs and trusting the enums. They cost four
lines and mean the database is self-describing — someone opening the file in
a SQLite browser can see what the legal values are without reading the Dart.

### `lib/data/person_repository.dart`

**Does.** All SQL for `person`. Full CRUD plus the counts query.

**Why this way.** `update` throws `ArgumentError` if the person has no id,
rather than silently doing nothing. Updating an unsaved object is a
programming mistake, not a runtime condition, and it should be loud. But
updating an id that does not exist *is* a runtime condition — the row may
have been deleted — so that returns `0` and lets the caller decide.

`getAllWithCounts` uses two correlated subqueries in one statement:

```sql
SELECT p.*,
  (SELECT COUNT(*) FROM session s WHERE s.person_id = p.id) AS session_count,
  (SELECT COUNT(*) FROM session s WHERE s.person_id = p.id
     AND s.ended_at IS NOT NULL)                            AS story_count
FROM person p
ORDER BY p.name COLLATE NOCASE
```

**Alternative, and why not.** The obvious alternative is a query per person
in a loop, which is trivially readable and is the N+1 problem. With five
people you would never notice. The reason to avoid it is not this screen's
performance; it is that the loop version puts a database call inside a widget
build path, which is the habit that hurts later.

A `LEFT JOIN ... GROUP BY` would also work and is the more conventional SQL,
but counting two different things needs `COUNT(*)` and
`SUM(CASE WHEN ended_at IS NOT NULL THEN 1 ELSE 0 END)`, which reads worse
than the subqueries do.

**One known limitation.** `COLLATE NOCASE` is ASCII-only in SQLite. It sorts
`Ahmed` before `khalid` correctly, but has no effect on Arabic names, which
sort by code point. That is acceptable because the list is sorted by the
Latin `name` column, and it is worth knowing before someone asks.

### `lib/data/session_repository.dart` and `segment_repository.dart`

**Does.** Create and read only, as scoped.

**Why this way.** They are deliberately incomplete and the comments say so.
Writing `update` now would mean writing it against a guess about what the
interview screen needs; writing it in the slice that needs it means writing
it against a real caller.

`SegmentRepository.nextSeq` asks the database for `MAX(seq) + 1` rather than
counting in Dart, because the app may have been closed and reopened in the
middle of a session and any in-memory counter would be gone. `COALESCE`
handles the first segment, where `MAX` over zero rows is null.

### `lib/theme.dart`

**Does.** Colours and text styles.

**Why this way.** Two decisions with reasons behind them rather than taste.

Body text is 17pt against Material's default of 14. The person holding the
phone may be twenty or eighty, and it is often on a table between two people
rather than in someone's hand. Larger type costs nothing.

Arabic is 21pt where English is 17pt, with more line height. This is not
decoration: Arabic script renders visually smaller than Latin at the same
point size and needs the extra leading for its diacritics. Set them equal and
the Arabic reads as a footnote to the English, which is precisely the wrong
relationship between a grandmother's words and their translation.

The palette is warm and low-saturation — paper, ink brown, one clay accent,
one olive. The brief was a room, not a tool.

### `lib/widgets/bilingual.dart`

**Does.** `ArabicText` renders Arabic right-to-left. `BilingualText` stacks
Arabic above English.

**Why this way.** This is the file to understand if you are asked about
internationalisation.

Flutter lays out text according to the ambient `Directionality`. Our app's is
left-to-right, because the interface chrome is English. Arabic placed inside
that inherits the wrong direction, and the symptoms are subtle rather than
obvious: the string still appears, but punctuation lands on the wrong end of
the line and a string mixing Arabic with digits comes out in the wrong order.

The fix has to be applied **per piece of Arabic text**, not once at the app
level, because both languages are on screen simultaneously. There is no
app-level switch that is correct for a bilingual screen. Hence a widget:
wrapping is required at every site, so it needs to be one word.

`BilingualText` puts Arabic above English and that order is fixed, not a
parameter. Making it configurable would invite a future screen to put the
translation first, which quietly makes the English the real text.

`english` is nullable, because a segment may be transcribed but not yet
translated. It shows the Arabic alone rather than reserving blank space.

### `lib/widgets/not_built_yet.dart`

**Does.** The placeholder screen, parameterised with what the screen will do,
when it is scheduled, and who owns it.

**Why this way.** A judge will navigate into these. A blank screen or a
"TODO" reads as broken. A screen that says *"Shows one question at a time,
records the answer to a file on this phone… Tue 2 Sep — Adel"* reads as a
team with a plan. The dates come from `docs/spec.md` section 12 and the
owners from CLAUDE.md, so the app itself is evidence that the schedule exists.

### `lib/screens/people_screen.dart`

**Does.** Home. The list, the empty state, the FAB.

**Why this way.** `_people` is `List<PersonSummary>?` and the nullness is
meaningful: null means the first load has not finished, empty means it
finished and there is nobody. Collapsing those into one empty list would
flash the empty state for a frame on every launch, which looks like data loss
to someone who has fifteen people saved.

The empty state is written as prose, not as an icon and the word "Empty". It
is the first screen on a fresh install, so it is the screen most likely to be
seen by a judge who has never used the app, and it has to answer "what is
this for" without a tutorial.

`_addPerson` awaits a `bool?` from the push and reloads only if it is true.
The `?` matters — a back-swipe pops with null, and null must not trigger a
reload.

**Alternative.** A `StreamBuilder` over a database watch. sqflite has no
change stream, that is a Drift feature, and adding one would be building
infrastructure for one list.

### `lib/screens/add_person_screen.dart`

**Does.** Three fields, validation on the name, saves and pops.

**Why this way.** `_saving` guards against a double tap inserting the person
twice, which is a real thing that happens on a slow phone.

The Arabic field wraps its `TextFormField` in its own `Directionality` so the
caret starts on the right regardless of which keyboard the phone opens with.

`Navigator.pop(true)` rather than popping the created `Person`. The caller
does not want the object; it wants to know whether to re-run its query. Given
the counts have to come from SQL anyway, returning the object would tempt
someone into inserting it into the list locally and having a list that
disagrees with the database.

### `lib/screens/interview_screen.dart`, `archive_screen.dart`, `settings_screen.dart`

**Does.** Placeholders.

**Why this way.** Note the asymmetry, because someone will ask about it.
`ArchiveScreen` and `SettingsScreen` have `static const route` and are reached
by `Navigator.pushNamed`. `InterviewScreen` has no route and is pushed with
`MaterialPageRoute(builder: (_) => InterviewScreen(person: ...))`.

The reason is type safety. Named routes carry arguments as `Object?`, which
has to be cast at the far end; get it wrong and it compiles fine and crashes
at runtime. A constructor parameter makes the same mistake a compile error.
So: named routes for screens that need nothing, typed constructors for
screens that need something.

### `lib/main.dart`

**Does.** Opens the database, builds the repository, configures the app.

**Why this way.** The database is opened in `main` and awaited **before**
`runApp`. So the app is either running with a working database or has not
started. No screen ever has to render a "database not ready" state, and no
screen has to handle a null repository.

`locale` is pinned to `en`. The app does not follow the phone's language.
Arabic here is *content*, not *interface* — it is on screen because a
grandmother said it. If the whole app flipped to RTL on an Arabic phone, the
layout would mirror around content that is already bilingual, which helps
nobody. `ar` is still in `supportedLocales` so Flutter loads Arabic text
handling for line breaking and cursor behaviour in the Arabic input field.

**Alternative.** A full localisation setup with ARB files and translated
interface strings. That is a genuine feature and it is not this slice; the
interface is English and the content is bilingual, which is what the persona
in the spec actually needs — Maryam reads English fluently and Arabic slowly.

### `test/person_repository_test.dart`

**Does.** 13 tests over PersonRepository.

**Why this way.** `sqflite_common_ffi` swaps in a real SQLite compiled for
macOS, so these tests run the actual SQL against the actual schema. They are
not testing a mock. The CHECK constraints are live, the cascade is live.

`inMemoryDatabasePath` gives each test a fresh database that never touches
disk, so tests cannot leak state into each other and the suite runs in under
a second.

The tests worth pointing at in a Q&A:

- The cascade test is really a test that `PRAGMA foreign_keys = ON` is being
  applied on every connection.
- "counts every session, but only finished ones as stories" is the one that
  pins down what the word "story" means in this app.
- "counts stay with the right person" would catch a subquery that was not
  correlated — a mistake that produces plausible-looking wrong numbers rather
  than an error.

### `test/bank_seed_test.dart`

**Does.** 5 tests over the seeding path, against the real `bank.json`.

**Why this way.** The first test asserts the asset file exists where
`AppDatabase.bankAssetPath` says. That is the failure mode that would
otherwise appear as an empty question bank on a phone with no error message.

The idempotence test exists because the day seeding moves into an
`onUpgrade`, it will run against a database that already has rows.

---

## What is deliberately not here

- **No audio.** Adel's slice.
- **No network, no API keys read.** The `.env` file is not loaded yet.
- **No update or delete on sessions and segments.** Written when there is a
  caller.
- **No photo on a person.** The column exists in the schema; the picker does
  not.
- **No widget tests.** The stock one was deleted rather than kept, because it
  tested the counter template. Widget tests are worth adding when there is a
  screen with behaviour worth asserting; `PeopleScreen` currently has one
  branch and the repository beneath it is well covered.

## The honest caveat

This has been verified by the analyzer, 18 tests and a successful APK build.
It has not been run. When it first runs on a phone, expect the ordinary
first-run problems — a layout that overflows on a small screen, the Arabic
font falling back to something unintended, the database path behaving
differently under an iOS sandbox. None of those would be surprising and none
of them are evidence the design is wrong.
