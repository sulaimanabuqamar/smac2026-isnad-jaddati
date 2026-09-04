import 'package:flutter_test/flutter_test.dart';
import 'package:jaddati/data/db.dart';
import 'package:jaddati/data/person_repository.dart';
import 'package:jaddati/data/segment_repository.dart';
import 'package:jaddati/data/session_repository.dart';
import 'package:jaddati/models/person.dart';
import 'package:jaddati/models/segment.dart';
import 'package:jaddati/models/session.dart';
import 'package:jaddati/services/audio_files.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The reinstall bug, and the invariant that stops it coming back.
///
/// Version 1 stored the absolute path the recorder was given. On iOS the app
/// container is a UUID that changes on every install, so after a rebuild
/// every row pointed at a directory that no longer existed — the audio was
/// still on the phone and we were looking in the previous install's folder.
/// It surfaced as "That audio file is missing from this phone" on playback,
/// and as a permanently failed segment in the transcription queue.
///
/// The rule now: **a stored `audio_path` never begins with `/`.** That single
/// assertion is what these tests exist to hold, because it is checkable
/// without a device and the bug was not.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// The absolute paths the two platforms actually produced under version 1.
  const iosV1 = '/var/mobile/Containers/Data/Application/'
      '9C1B2E4A-77F0-4E2D-9E31-6A0B1F2C3D4E/Documents'
      '/recordings/session_3/seg_1_1757000000.m4a';
  const androidV1 = '/data/user/0/com.isnad.jaddati/app_flutter'
      '/recordings/session_3/seg_1_1757000000.m4a';
  const expected = 'recordings/session_3/seg_1_1757000000.m4a';

  group('the invariant', () {
    test('a path we generate never begins with a slash', () {
      final path = AudioFiles.segmentPath(
        sessionId: 3,
        seq: 1,
        stamp: 1757000000,
      );
      expect(path.startsWith('/'), isFalse);
      expect(path, expected);
    });

    test('it holds for every session and sequence number', () {
      for (var session = 1; session <= 20; session++) {
        for (var seq = 1; seq <= 20; seq++) {
          final path = AudioFiles.segmentPath(
            sessionId: session,
            seq: seq,
            stamp: 1757000000 + seq,
          );
          expect(path.startsWith('/'), isFalse,
              reason: 'session $session seq $seq produced $path');
        }
      }
    });
  });

  group('toRelative', () {
    test('strips an iOS container path', () {
      expect(AudioFiles.toRelative(iosV1), expected);
    });

    test('strips an Android app_flutter path', () {
      expect(AudioFiles.toRelative(androidV1), expected);
    });

    test('leaves an already-relative path alone', () {
      expect(AudioFiles.toRelative(expected), expected);
    });

    test('leaves a path it does not recognise absolute rather than guessing',
        () {
      // Better a row we can spot than a row we have silently mangled.
      const strange = '/somewhere/else/entirely/seg_1.m4a';
      expect(AudioFiles.toRelative(strange), strange);
    });
  });

  group('the version 2 migration', () {
    late Database db;
    late SegmentRepository segments;
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
      segments = SegmentRepository(db);
      final personId = await PersonRepository(db)
          .create(Person(name: 'Fatima', createdAt: DateTime.now()));
      sessionId = await SessionRepository(db)
          .create(Session(personId: personId, startedAt: DateTime.now()));
    });

    tearDown(() => db.close());

    /// Writes a row the way version 1 did, bypassing the repository — which
    /// is the only way to create one now, and the point: the old shape has
    /// to be reachable in a test or the migration is untestable.
    Future<int> insertV1Row(String absolutePath, {int seq = 1}) => db.insert(
          'segment',
          Segment(
            sessionId: sessionId,
            seq: seq,
            questionText: 'وين كنتي ساكنة وانتي صغيرة؟',
            questionSource: QuestionSource.bank,
            audioPath: absolutePath,
            durationMs: 42000,
            createdAt: DateTime.now(),
          ).toMap(),
        );

    Future<List<String>> paths() async =>
        (await segments.getForSession(sessionId))
            .map((s) => s.audioPath)
            .toList();

    test('rewrites an iOS absolute path to a relative one', () async {
      await insertV1Row(iosV1);
      await AppDatabase.migrateToRelativeAudioPaths(db);
      expect(await paths(), [expected]);
    });

    test('rewrites an Android absolute path too', () async {
      await insertV1Row(androidV1);
      await AppDatabase.migrateToRelativeAudioPaths(db);
      expect(await paths(), [expected]);
    });

    test('no row is left beginning with a slash', () async {
      await insertV1Row(iosV1, seq: 1);
      await insertV1Row(androidV1, seq: 2);
      await insertV1Row(expected, seq: 3);

      await AppDatabase.migrateToRelativeAudioPaths(db);

      final absolute = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM segment WHERE audio_path LIKE '/%'",
      );
      expect(absolute.first['n'], 0);
    });

    test('it keeps the rows rather than wiping them', () async {
      // The whole argument for migrating instead of deleting: the recordings
      // are fine, only the prefix was wrong.
      await insertV1Row(iosV1, seq: 1);
      await insertV1Row(androidV1, seq: 2);
      await AppDatabase.migrateToRelativeAudioPaths(db);
      expect(await paths(), hasLength(2));
    });

    test('running it twice changes nothing', () async {
      await insertV1Row(iosV1);
      await AppDatabase.migrateToRelativeAudioPaths(db);
      await AppDatabase.migrateToRelativeAudioPaths(db);
      expect(await paths(), [expected]);
    });

    test('an already-relative row is untouched', () async {
      await insertV1Row(expected);
      await AppDatabase.migrateToRelativeAudioPaths(db);
      expect(await paths(), [expected]);
    });

    test('a transcript on the row survives the migration', () async {
      final id = await insertV1Row(iosV1);
      await segments.saveTranscript(id, 'كنا ساكنين في الهيلي');
      await AppDatabase.migrateToRelativeAudioPaths(db);

      final row = (await segments.getForSession(sessionId)).single;
      expect(row.audioPath, expected);
      expect(row.transcriptAr, 'كنا ساكنين في الهيلي');
      expect(row.transcribeStatus, TranscribeStatus.done);
    });
  });

  group('opening a version 1 database at version 2', () {
    // The migration SQL is tested above. This tests the wiring around it —
    // that onUpgrade is actually hooked up and fires on a real reopen, which
    // is the thing that will happen on a phone that already has recordings.
    test('upgrades on open and rewrites the paths', () async {
      final dir = await databaseFactory.getDatabasesPath();
      final path = '$dir/upgrade_test_${DateTime.now().microsecondsSinceEpoch}.db';

      var v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: AppDatabase.configure,
          onCreate: (db, _) => AppDatabase.createSchema(db),
        ),
      );
      final personId = await PersonRepository(v1)
          .create(Person(name: 'Fatima', createdAt: DateTime.now()));
      final sessionId = await SessionRepository(v1)
          .create(Session(personId: personId, startedAt: DateTime.now()));
      await v1.insert(
        'segment',
        Segment(
          sessionId: sessionId,
          seq: 1,
          questionText: 'سؤال',
          questionSource: QuestionSource.bank,
          audioPath: iosV1,
          durationMs: 42000,
          createdAt: DateTime.now(),
        ).toMap(),
      );
      await v1.close();

      final v2 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: AppDatabase.version,
          onConfigure: AppDatabase.configure,
          onCreate: (db, _) => AppDatabase.createSchema(db),
          onUpgrade: AppDatabase.migrate,
        ),
      );

      final row =
          (await SegmentRepository(v2).getForSession(sessionId)).single;
      expect(row.audioPath, expected);
      expect(await v2.getVersion(), 2);

      await v2.close();
      await databaseFactory.deleteDatabase(path);
    });
  });
}
