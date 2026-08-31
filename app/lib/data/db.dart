import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import '../models/bank_question.dart';

/// Opens and owns the one SQLite database the app uses.
///
/// The SQL below is written by hand rather than generated. That is a
/// deliberate trade: we type more, and in exchange every statement that runs
/// against our data is visible in this file and can be read aloud.
class AppDatabase {
  AppDatabase._();

  /// One database, one connection, for the life of the app.
  static final AppDatabase instance = AppDatabase._();

  static const fileName = 'jaddati.db';
  static const version = 1;

  /// Where `bank.json` lives inside the bundle. Declared in `pubspec.yaml`
  /// under `flutter: assets:`, which is what puts it in the built app.
  static const bankAssetPath = 'assets/questions/bank.json';

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    // Joined with a plain '/' rather than package:path. Both platforms we
    // ship to are POSIX, and path is only a transitive dependency here —
    // importing it directly would make it a ninth declared dependency for
    // one string join.
    final dir = await getDatabasesPath();
    return openDatabase(
      '$dir/$fileName',
      version: version,
      onConfigure: configure,
      onCreate: (db, _) async {
        await createSchema(db);
        await seedBankQuestions(db, await rootBundle.loadString(bankAssetPath));
      },
    );
  }

  /// Closes the connection. Used by tests; the app itself never needs it.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// SQLite disables foreign keys by default and does so per connection, so
  /// this has to run on every open, not once at creation. Without it the
  /// `ON DELETE CASCADE` clauses below are silently ignored and deleting a
  /// person would leave their sessions behind as orphans.
  static Future<void> configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Creates schema version 1, exactly as specified in docs/spec.md section 8.
  ///
  /// Separate from [_open] so tests can build the same schema in an in-memory
  /// database. If this and the spec ever disagree, one of them is a bug.
  static Future<void> createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE person (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        name_ar     TEXT,
        relation    TEXT,
        photo_path  TEXT,
        created_at  INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE session (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        person_id   INTEGER NOT NULL REFERENCES person(id) ON DELETE CASCADE,
        started_at  INTEGER NOT NULL,
        ended_at    INTEGER,
        title       TEXT,
        place       TEXT,
        decade      TEXT,
        summary     TEXT
      )
    ''');

    // question_source and transcribe_status are constrained by CHECK rather
    // than left as free text. The database refuses a typo even if the Dart
    // enum is bypassed.
    await db.execute('''
      CREATE TABLE segment (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id        INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
        seq               INTEGER NOT NULL,
        question_text     TEXT    NOT NULL,
        question_source   TEXT    NOT NULL CHECK (question_source IN ('ai','bank','manual')),
        audio_path        TEXT    NOT NULL,
        duration_ms       INTEGER,
        transcript_ar     TEXT,
        transcript_en     TEXT,
        edited_by_user    INTEGER NOT NULL DEFAULT 0 CHECK (edited_by_user IN (0,1)),
        transcribe_status TEXT    NOT NULL DEFAULT 'pending'
                                  CHECK (transcribe_status IN ('pending','done','failed')),
        created_at        INTEGER NOT NULL,
        UNIQUE (session_id, seq)
      )
    ''');

    await db.execute('''
      CREATE TABLE mention (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id  INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
        kind        TEXT    NOT NULL CHECK (kind IN ('person','place','year')),
        value       TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE bank_question (
        id       TEXT PRIMARY KEY,
        topic    TEXT NOT NULL,
        text_ar  TEXT NOT NULL,
        text_en  TEXT NOT NULL
      )
    ''');

    // Indexes for the two lookups the app does constantly: every segment of
    // one session, in order, and every session of one person.
    await db.execute(
        'CREATE INDEX idx_segment_session ON segment(session_id, seq)');
    await db.execute('CREATE INDEX idx_session_person ON session(person_id)');

    // Finding the pending transcription queue is a filtered scan otherwise.
    await db.execute(
        'CREATE INDEX idx_segment_status ON segment(transcribe_status)');
  }

  /// Parses `bank.json` and writes every question into `bank_question`.
  ///
  /// Takes the file's contents as a string rather than reading the asset
  /// itself, so the parsing and the SQL can be tested without a Flutter
  /// asset bundle. The caller decides where the JSON came from.
  ///
  /// One batch, one transaction: 30 inserts commit together or not at all,
  /// which is both faster and leaves no half-seeded database behind.
  static Future<void> seedBankQuestions(Database db, String jsonSource) async {
    final decoded = jsonDecode(jsonSource) as Map<String, Object?>;
    final questions = (decoded['questions'] as List)
        .cast<Map<String, Object?>>()
        .map(BankQuestion.fromJson);

    final batch = db.batch();
    for (final q in questions) {
      // `replace` rather than `insert` so re-seeding an existing database
      // updates the wording instead of failing on the primary key.
      batch.insert(
        'bank_question',
        q.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
