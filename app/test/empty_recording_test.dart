import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jaddati/data/db.dart';
import 'package:jaddati/data/person_repository.dart';
import 'package:jaddati/data/segment_repository.dart';
import 'package:jaddati/data/session_repository.dart';
import 'package:jaddati/models/person.dart';
import 'package:jaddati/models/segment.dart';
import 'package:jaddati/models/session.dart';
import 'package:jaddati/services/audio_files.dart';
import 'package:jaddati/services/audio_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The 28-byte recording.
///
/// Every file the device recorded was exactly 28 bytes: an m4a container
/// with a header and no frames, which is what iOS leaves behind when it
/// hands the encoder silence. The old guard tested `bytes == 0` and let all
/// of them through, so four segments were written that will never play and
/// never transcribe.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('the minimum', () {
    test('sits well above the empty container we actually observed', () {
      expect(AudioService.observedEmptyContainerBytes, 28);
      expect(
        AudioService.minimumBytes,
        greaterThan(AudioService.observedEmptyContainerBytes * 10),
      );
    });

    test('sits well below any real recording', () {
      // 16 kHz mono AAC runs about 2 kB per second of audio. Even a quarter
      // of a second clears this comfortably, so the threshold judges whether
      // there is audio at all, not how long someone spoke.
      const bytesPerSecondOfSpeech = 2000;
      expect(
        AudioService.minimumBytes,
        lessThan(bytesPerSecondOfSpeech),
      );
    });

    test('every RecordingLoss carries something to show a person', () {
      for (final loss in RecordingLoss.values) {
        expect(loss.message, isNotEmpty);
        expect(loss.message.length, greaterThan(20));
      }
    });

    test('a lost recording and a saved one are different types', () {
      // The point of the sealed pair: the save path is unreachable without
      // handling the failure, so a dead recording cannot fall through into
      // a database row the way 28 bytes did.
      const saved = RecordingSaved(
        Recording(
          relativePath: 'recordings/session_1/seg_1_1.m4a',
          duration: Duration(seconds: 30),
          bytes: 60000,
        ),
      );
      const lost = RecordingDiscarded(RecordingLoss.silent);
      expect(saved, isA<RecordingResult>());
      expect(lost, isA<RecordingResult>());
      expect(saved, isNot(isA<RecordingDiscarded>()));
    });
  });

  group('sweeping dead segments', () {
    late Database db;
    late SegmentRepository segments;
    late Directory tmp;
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
      tmp = await Directory.systemTemp.createTemp('jaddati_sweep');
      final personId = await PersonRepository(db)
          .create(Person(name: 'Fatima', createdAt: DateTime.now()));
      sessionId = await SessionRepository(db)
          .create(Session(personId: personId, startedAt: DateTime.now()));
    });

    tearDown(() async {
      await db.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<File> resolve(String relative) async =>
        File('${tmp.path}/$relative');

    /// Writes a row, and optionally a file of [bytes] behind it. Passing null
    /// writes the row with no file at all.
    Future<int> addSegment(int seq, {int? bytes}) async {
      final relative =
          AudioFiles.segmentPath(sessionId: sessionId, seq: seq, stamp: 1757);
      if (bytes != null) {
        final file = await resolve(relative);
        await file.parent.create(recursive: true);
        file.writeAsBytesSync(List.filled(bytes, 7));
      }
      return segments.create(
        Segment(
          sessionId: sessionId,
          seq: seq,
          questionText: 'سؤال',
          questionSource: QuestionSource.bank,
          audioPath: relative,
          durationMs: 40000,
          createdAt: DateTime.now(),
        ),
      );
    }

    Future<int> sweep() => segments.deleteEmptyRecordings(
          resolveAudio: resolve,
          minimumBytes: AudioService.minimumBytes,
        );

    test('removes a 28-byte segment', () async {
      await addSegment(1, bytes: 28);
      expect(await sweep(), 1);
      expect(await segments.getForSession(sessionId), isEmpty);
    });

    test('removes the file too, not just the row', () async {
      await addSegment(1, bytes: 28);
      final relative = (await segments.getForSession(sessionId)).single.audioPath;
      await sweep();
      expect((await resolve(relative)).existsSync(), isFalse);
    });

    test('keeps a real recording', () async {
      await addSegment(1, bytes: 64000);
      expect(await sweep(), 0);
      expect(await segments.getForSession(sessionId), hasLength(1));
    });

    test('NEVER deletes a row whose file is merely missing', () async {
      // The safety property, and the reason this sweep is narrow. Missing is
      // exactly what the reinstall bug looked like: every file on the phone
      // appeared absent because we resolved against the wrong container. A
      // sweep that deleted on absence would have destroyed the archive that
      // morning rather than fixing it.
      await addSegment(1);
      expect(await sweep(), 0);
      expect(await segments.getForSession(sessionId), hasLength(1));
    });

    test('sweeps only the dead ones out of a mixed session', () async {
      await addSegment(1, bytes: 28);
      await addSegment(2, bytes: 64000);
      await addSegment(3, bytes: 28);
      await addSegment(4);

      expect(await sweep(), 2);

      final left = await segments.getForSession(sessionId);
      expect(left.map((s) => s.seq), [2, 4]);
    });

    test('is idempotent — a second sweep finds nothing', () async {
      await addSegment(1, bytes: 28);
      await addSegment(2, bytes: 64000);
      expect(await sweep(), 1);
      expect(await sweep(), 0);
    });

    test('a file one byte under the minimum still goes', () async {
      await addSegment(1, bytes: AudioService.minimumBytes - 1);
      expect(await sweep(), 1);
    });

    test('a file exactly at the minimum stays', () async {
      await addSegment(1, bytes: AudioService.minimumBytes);
      expect(await sweep(), 0);
    });

    test('the four dead segments, as they were on the phone', () async {
      // The actual situation this was written for.
      for (var seq = 1; seq <= 4; seq++) {
        await addSegment(seq, bytes: 28);
      }
      expect(await sweep(), 4);
      expect(await segments.getForSession(sessionId), isEmpty);
    });
  });
}
