import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jaddati/data/bank_question_repository.dart';
import 'package:jaddati/data/db.dart';
import 'package:jaddati/data/person_repository.dart';
import 'package:jaddati/data/segment_repository.dart';
import 'package:jaddati/data/session_repository.dart';
import 'package:jaddati/models/person.dart';
import 'package:jaddati/models/segment.dart';
import 'package:jaddati/models/session.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Slice 2: the segment lifecycle.
///
/// These test the database half of record-save-play. The recording half —
/// the microphone, the file write, playback — cannot be tested without a
/// device and is listed in docs/slice2-unverified.md instead of being
/// pretended at here.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late PersonRepository people;
  late SessionRepository sessions;
  late SegmentRepository segments;
  late BankQuestionRepository bank;
  late int personId;
  late int sessionId;

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        onConfigure: AppDatabase.configure,
        onCreate: (db, _) => AppDatabase.createSchema(db),
      ),
    );
    people = PersonRepository(db);
    sessions = SessionRepository(db);
    segments = SegmentRepository(db);
    bank = BankQuestionRepository(db);

    personId = await people.create(
      Person(name: 'Fatima', createdAt: DateTime(2026, 9, 1)),
    );
    sessionId = await sessions.create(
      Session(personId: personId, startedAt: DateTime(2026, 9, 1, 15)),
    );
  });

  tearDown(() async => db.close());

  Segment seg(int seq, {String? path, TranscribeStatus? status}) => Segment(
        sessionId: sessionId,
        seq: seq,
        questionText: 'وين كنتِ ساكنة لما كنتِ صغيرة؟',
        questionSource: QuestionSource.bank,
        audioPath: path ?? '/documents/recordings/session_1/seg_${seq}_1.m4a',
        durationMs: 42000,
        transcribeStatus: status ?? TranscribeStatus.pending,
        createdAt: DateTime(2026, 9, 1, 15, seq),
      );

  group('appending segments', () {
    test('nextSeq starts at 1 and increments with each segment', () async {
      expect(await segments.nextSeq(sessionId), 1);

      await segments.create(seg(1));
      expect(await segments.nextSeq(sessionId), 2);

      await segments.create(seg(2));
      expect(await segments.nextSeq(sessionId), 3);
    });

    test('nextSeq is per session, not global', () async {
      final other = await sessions.create(
        Session(personId: personId, startedAt: DateTime(2026, 9, 2)),
      );
      await segments.create(seg(1));
      await segments.create(seg(2));

      expect(await segments.nextSeq(sessionId), 3);
      expect(await segments.nextSeq(other), 1,
          reason: 'a new session starts its own numbering');
    });

    test('segments come back in seq order regardless of insertion order',
        () async {
      await segments.create(seg(3));
      await segments.create(seg(1));
      await segments.create(seg(2));

      final rows = await segments.getForSession(sessionId);
      expect(rows.map((s) => s.seq).toList(), [1, 2, 3]);
    });

    test('a segment round-trips every field it was given', () async {
      await segments.create(seg(1));
      final s = (await segments.getForSession(sessionId)).single;

      expect(s.sessionId, sessionId);
      expect(s.seq, 1);
      expect(s.questionSource, QuestionSource.bank);
      expect(s.audioPath, '/documents/recordings/session_1/seg_1_1.m4a');
      expect(s.durationMs, 42000);
      expect(s.editedByUser, isFalse);
      expect(s.transcriptAr, isNull);
    });

    test('two segments cannot take the same position in a session', () async {
      await segments.create(seg(1));
      // UNIQUE (session_id, seq). Without it a duplicate seq would make the
      // order of the conversation ambiguous.
      expect(() => segments.create(seg(1)), throwsA(isA<DatabaseException>()));
    });
  });

  group('the audio_path guarantee', () {
    test('a new segment is born pending', () async {
      await segments.create(seg(1));
      expect((await segments.getForSession(sessionId)).single.transcribeStatus,
          TranscribeStatus.pending);
    });

    test('the database refuses a segment with no audio path', () async {
      // The Dart model makes this unrepresentable — audioPath is non-nullable
      // — so this goes around it with raw SQL to prove the schema is the
      // second line of defence, not just the type.
      expect(
        () => db.insert('segment', {
          'session_id': sessionId,
          'seq': 1,
          'question_text': 'q',
          'question_source': 'bank',
          'transcribe_status': 'pending',
          'created_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
        reason: 'audio_path is NOT NULL: no row may promise audio we lack',
      );
    });

    test('the database refuses an unknown transcribe_status', () async {
      expect(
        () => db.insert('segment', {
          'session_id': sessionId,
          'seq': 1,
          'question_text': 'q',
          'question_source': 'bank',
          'audio_path': '/a.m4a',
          'transcribe_status': 'nearly',
          'created_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('the database refuses an unknown question_source', () async {
      expect(
        () => db.insert('segment', {
          'session_id': sessionId,
          'seq': 1,
          'question_text': 'q',
          'question_source': 'vibes',
          'audio_path': '/a.m4a',
          'transcribe_status': 'pending',
          'created_at': 1,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('getPending returns only the segments still waiting', () async {
      await segments.create(seg(1));
      await segments.create(seg(2, status: TranscribeStatus.done));
      await segments.create(seg(3, status: TranscribeStatus.failed));

      final pending = await segments.getPending();
      expect(pending.map((s) => s.seq).toList(), [1]);
    });
  });

  group('ending a session', () {
    test('sets ended_at and makes the session finished', () async {
      expect((await sessions.getById(sessionId))!.isFinished, isFalse);

      final changed =
          await sessions.end(sessionId, DateTime(2026, 9, 1, 16));
      expect(changed, 1);

      final s = (await sessions.getById(sessionId))!;
      expect(s.isFinished, isTrue);
      expect(s.endedAt, DateTime(2026, 9, 1, 16));
    });

    test('ending an already-ended session changes nothing', () async {
      await sessions.end(sessionId, DateTime(2026, 9, 1, 16));

      final again = await sessions.end(sessionId, DateTime(2026, 9, 1, 18));
      expect(again, 0, reason: 'the WHERE clause guards ended_at IS NULL');

      expect((await sessions.getById(sessionId))!.endedAt,
          DateTime(2026, 9, 1, 16),
          reason: 'the original end time must not be overwritten');
    });

    test('ending a session that does not exist reports 0', () async {
      expect(await sessions.end(9999, DateTime.now()), 0);
    });

    test('an unfinished session is found for resuming, a finished one is not',
        () async {
      expect((await sessions.getUnfinishedForPerson(personId))!.id, sessionId);

      await sessions.end(sessionId, DateTime(2026, 9, 1, 16));
      expect(await sessions.getUnfinishedForPerson(personId), isNull);
    });

    test('finishing a session turns it into a story on the people screen',
        () async {
      expect((await people.getAllWithCounts()).single.storyCount, 0);
      await sessions.end(sessionId, DateTime(2026, 9, 1, 16));
      final row = (await people.getAllWithCounts()).single;
      expect(row.sessionCount, 1);
      expect(row.storyCount, 1);
    });

    test('deleting a person removes their segments too', () async {
      await segments.create(seg(1));
      await people.delete(personId);

      expect(await segments.getForSession(sessionId), isEmpty);
      expect(await sessions.getById(sessionId), isNull);
    });
  });

  group('question bank', () {
    setUp(() async {
      await AppDatabase.seedBankQuestions(
          db, File(AppDatabase.bankAssetPath).readAsStringSync());
    });

    test('walks the bank in file order, so topics progress gently', () async {
      final first = await bank.questionAt(0);
      final second = await bank.questionAt(1);

      expect(first, isNotNull);
      expect(second, isNotNull);

      // The first question of a session must be the gentlest one in the
      // bank, not whichever id sorts first alphabetically. Ordering by `id`
      // would open on chg_01, from the "change" topic.
      expect(first!.id, 'child_01');
      expect(second!.id, 'child_02');
      expect(first.topic, 'childhood');
    });

    test('the first six questions stay within the opening topic', () async {
      final topics = <String>[];
      for (var i = 0; i < 5; i++) {
        topics.add((await bank.questionAt(i))!.topic);
      }
      expect(topics, everyElement('childhood'),
          reason: 'a session should not jump topics on every question');
    });

    test('wraps rather than dead-ending past the last question', () async {
      final total = await bank.count();
      final first = await bank.questionAt(0);
      final wrapped = await bank.questionAt(total);

      expect(wrapped, isNotNull);
      expect(wrapped!.id, first!.id);
    });

    test('returns null when the bank was never seeded', () async {
      await db.delete('bank_question');
      expect(await bank.questionAt(0), isNull);
    });
  });
}
