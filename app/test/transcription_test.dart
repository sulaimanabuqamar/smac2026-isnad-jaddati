import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jaddati/data/db.dart';
import 'package:jaddati/data/person_repository.dart';
import 'package:jaddati/data/segment_repository.dart';
import 'package:jaddati/data/session_repository.dart';
import 'package:jaddati/models/person.dart';
import 'package:jaddati/models/segment.dart';
import 'package:jaddati/models/session.dart';
import 'package:jaddati/services/audio_files.dart';
import 'package:jaddati/services/transcription_queue.dart';
import 'package:jaddati/services/transcription_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Slice 3: transcription and the queue.
///
/// What is genuinely covered here: the hallucination guard, every branch of
/// the HTTP outcome, the SQL that writes a transcript, and the queue's
/// decision about what to retry and what to give up on. The HTTP client is a
/// `MockClient` from the `http` package, so no request leaves the machine and
/// no API key is needed to run these.
///
/// What is not covered, and is listed in docs/slice3-unverified.md instead:
/// a real upload to Groq from a phone, real Arabic coming back, and the
/// backoff timer actually firing.
/// About 120 characters — what forty seconds of speech actually looks like.
///
/// Not decoration: the queue tests record 40-second segments, and a two-word
/// fake answer would trip the implausibility guard and fail every one of them.
/// The guard is real code and the fixtures have to respect it.
const _answer = 'كنا ساكنين في بيت العريش قريب من السوق القديم وكان جدي '
    'يشتغل في الغوص وكل يوم نروح نلعب عند الشاطئ مع اولاد الحارة';

/// Arabic has to go over the wire as bytes.
///
/// `http.Response(String, ...)` encodes with Latin-1 when the content type
/// carries no charset, and throws on any Arabic character. That is the same
/// asymmetry the service guards against when it decodes, and it caught these
/// tests first.
http.Response _ok(String text) => http.Response.bytes(
      utf8.encode(jsonEncode({'text': text})),
      200,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // ---------------------------------------------------------------- guard

  group('the implausible-transcript guard', () {
    // The two real failures from the spike, in the numbers they actually
    // produced. If a future change lets either of these through, the app is
    // back to asking a grandmother which grandchild taught her to subscribe
    // to a YouTube channel.
    test('rejects the cars_chunk-03 hallucination', () {
      expect(
        TranscriptionService.isImplausible(
          'اشتركوا في القناة',
          const Duration(milliseconds: 10650),
        ),
        isTrue,
      );
    });

    test('rejects the police_chunk-43 hallucination', () {
      expect(
        TranscriptionService.isImplausible(
          'اشتركوا في القناة',
          const Duration(milliseconds: 14520),
        ),
        isTrue,
      );
    });

    test('accepts a normal-length transcript for the same audio', () {
      // 14.5 seconds of ordinary speech is well over a hundred characters.
      final real = 'قمنا باجراء سريع طلعنا السياره برا الشارع وبعدين '
          'وقفنا على الجنب لحد ما وصلت الشرطه وسجلوا الحادث';
      expect(
        TranscriptionService.isImplausible(
          real,
          const Duration(milliseconds: 14520),
        ),
        isFalse,
      );
    });

    test('empty text is never believed, at any length', () {
      expect(TranscriptionService.isImplausible('   ', null), isTrue);
      expect(
        TranscriptionService.isImplausible(
          '',
          const Duration(seconds: 2),
        ),
        isTrue,
      );
    });

    test('a short real answer under short audio survives the guard', () {
      // "Yes, of course" over three seconds. Four characters a second is
      // under the threshold, which is exactly why the guard does not apply
      // below five seconds.
      expect(
        TranscriptionService.isImplausible(
          'نعم طبعا',
          const Duration(seconds: 3),
        ),
        isFalse,
      );
    });

    test('unknown duration disables the ratio, not the empty check', () {
      expect(TranscriptionService.isImplausible('اشتركوا في القناة', null),
          isFalse);
    });
  });

  // -------------------------------------------------------------- service

  group('TranscriptionService', () {
    late Directory tmp;
    late File audio;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('jaddati_asr');
      audio = File('${tmp.path}/seg_1.m4a')..writeAsBytesSync([1, 2, 3, 4]);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    TranscriptionService serviceReturning(
      http.Response Function(http.BaseRequest) respond, {
      String key = 'test-key',
    }) =>
        TranscriptionService(
          apiKey: key,
          client: MockClient((request) async => respond(request)),
        );

    test('sends the model and language we decided on', () async {
      late http.Request seen;
      final service = TranscriptionService(
        apiKey: 'test-key',
        client: MockClient((request) async {
          seen = request;
          return _ok(_answer);
        }),
      );

      expect(await service.transcribe(audio), isA<Transcribed>());

      // MockClient flattens the multipart request before we see it, so the
      // fields are read out of the encoded body. Latin-1 because we are
      // looking for ASCII field names inside binary, not reading text.
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('whisper-large-v3-turbo'));
      expect(body, contains('name="language"'));
      expect(body, contains('\r\nar\r\n'));
      expect(body, contains('name="temperature"'));
      expect(seen.headers['Authorization'], 'Bearer test-key');
      expect(seen.headers['content-type'], startsWith('multipart/form-data'));
    });

    test('decodes Arabic as UTF-8, not Latin-1', () async {
      // The bug this guards against is invisible in English and total in
      // Arabic: http's `response.body` guesses Latin-1 when the server sends
      // no charset, and every Arabic character comes back as mojibake.
      const arabic = 'جدتي كانت تسكن في العين';
      final service = serviceReturning((_) => _ok(arabic));

      final result = await service.transcribe(audio);
      expect((result as Transcribed).textAr, arabic);
    });

    test('no key is a transient failure — the row stays pending', () async {
      final service = serviceReturning((_) => http.Response('{}', 200),
          key: '');
      final result = await service.transcribe(audio);
      expect((result as TranscriptionRejected).reason,
          TranscriptionFailure.noKey);
      expect(TranscriptionFailure.noKey.transient, isTrue);
    });

    test('a missing file is permanent — no amount of signal fixes it',
        () async {
      final service = serviceReturning((_) => http.Response('{}', 200));
      final result =
          await service.transcribe(File('${tmp.path}/never_existed.m4a'));
      expect((result as TranscriptionRejected).reason,
          TranscriptionFailure.audioMissing);
      expect(TranscriptionFailure.audioMissing.transient, isFalse);
    });

    test('429 is transient and 400 is not', () async {
      final limited = serviceReturning((_) => http.Response('slow down', 429));
      expect(
        ((await limited.transcribe(audio)) as TranscriptionRejected).reason,
        TranscriptionFailure.rateLimited,
      );

      final refused = serviceReturning((_) => http.Response('bad file', 400));
      final result =
          (await refused.transcribe(audio)) as TranscriptionRejected;
      expect(result.reason, TranscriptionFailure.rejected);
      expect(result.reason.transient, isFalse);
    });

    test('500 is transient — their outage is not our failed segment',
        () async {
      final service = serviceReturning((_) => http.Response('oops', 503));
      final result =
          (await service.transcribe(audio)) as TranscriptionRejected;
      expect(result.reason, TranscriptionFailure.serverError);
      expect(result.reason.transient, isTrue);
    });

    test('a dead socket reads as offline, not as a broken recording',
        () async {
      final service = TranscriptionService(
        apiKey: 'test-key',
        client: MockClient(
          (_) async => throw const SocketException('Network unreachable'),
        ),
      );
      final result =
          (await service.transcribe(audio)) as TranscriptionRejected;
      expect(result.reason, TranscriptionFailure.offline);
      expect(result.reason.transient, isTrue);
    });

    test('the guard runs on the response, not just on the request',
        () async {
      final service =
          serviceReturning((_) => _ok('اشتركوا في القناة'));
      final result = await service.transcribe(
        audio,
        audioDuration: const Duration(seconds: 30),
      );
      expect((result as TranscriptionRejected).reason,
          TranscriptionFailure.implausible);
    });
  });

  // ----------------------------------------------------------- repository

  group('writing a transcript', () {
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

    Future<int> addSegment({int seq = 1}) => segments.create(
          Segment(
            sessionId: sessionId,
            seq: seq,
            questionText: 'وين كنتي ساكنة وانتي صغيرة؟',
            questionSource: QuestionSource.bank,
            // Relative, like every row the app writes. See
            // test/audio_path_test.dart for why that is an invariant.
            audioPath: 'recordings/session_1/seg_${seq}_1757.m4a',
            durationMs: 42000,
            createdAt: DateTime.now(),
          ),
        );

    test('saveTranscript writes the text and clears it from the queue',
        () async {
      final id = await addSegment();
      expect(await segments.countByStatus(TranscribeStatus.pending), 1);

      await segments.saveTranscript(id, 'كنا ساكنين في الهيلي');

      final row = (await segments.getForSession(sessionId)).single;
      expect(row.transcriptAr, 'كنا ساكنين في الهيلي');
      expect(row.transcribeStatus, TranscribeStatus.done);
      expect(await segments.countByStatus(TranscribeStatus.pending), 0);
    });

    test('a hand-corrected transcript is never overwritten', () async {
      final id = await addSegment();
      await segments.saveTranscript(id, 'the machine version');
      await db.update('segment', {
        'transcript_ar': 'what she actually said',
        'edited_by_user': 1,
      }, where: 'id = ?', whereArgs: [id]);

      await segments.saveTranscript(id, 'the machine version, again');

      final row = (await segments.getForSession(sessionId)).single;
      expect(row.transcriptAr, 'what she actually said');
    });

    test('but the status still advances, so the queue cannot loop', () async {
      final id = await addSegment();
      await db.update('segment', {'edited_by_user': 1},
          where: 'id = ?', whereArgs: [id]);

      await segments.saveTranscript(id, 'ignored');

      expect(await segments.countByStatus(TranscribeStatus.pending), 0);
      expect(await segments.countByStatus(TranscribeStatus.done), 1);
    });

    test('markFailed takes a row out of the queue and leaves its audio',
        () async {
      final id = await addSegment();
      await segments.markFailed(id);

      final row = (await segments.getForSession(sessionId)).single;
      expect(row.transcribeStatus, TranscribeStatus.failed);
      expect(row.audioPath, 'recordings/session_1/seg_1_1757.m4a');
      expect(await segments.getPending(), isEmpty);
    });

    test('markPending puts it back for a retry', () async {
      final id = await addSegment();
      await segments.markFailed(id);
      await segments.markPending(id);
      expect(await segments.getPending(), hasLength(1));
    });

    test('getPending is oldest first, across sessions', () async {
      await addSegment(seq: 1);
      await addSegment(seq: 2);
      await addSegment(seq: 3);
      final pending = await segments.getPending();
      expect(pending.map((s) => s.seq), [1, 2, 3]);
    });
  });

  // ---------------------------------------------------------------- queue

  group('TranscriptionQueue', () {
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
      tmp = await Directory.systemTemp.createTemp('jaddati_queue');
      final personId = await PersonRepository(db)
          .create(Person(name: 'Fatima', createdAt: DateTime.now()));
      sessionId = await SessionRepository(db)
          .create(Session(personId: personId, startedAt: DateTime.now()));
    });

    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    /// Writes a real file and a row pointing at it *relatively*, the way the
    /// app does. `tmp` stands in for the app documents directory, which is
    /// what the injected resolver joins against.
    Future<void> addSegment(int seq) async {
      final relative =
          AudioFiles.segmentPath(sessionId: sessionId, seq: seq, stamp: 1757);
      final file = File('${tmp.path}/$relative');
      await file.parent.create(recursive: true);
      file.writeAsBytesSync(List.filled(64, 7));

      await segments.create(
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

    TranscriptionQueue queueThat(
      http.Response Function(int call) respond, {
      String key = 'test-key',
    }) {
      var calls = 0;
      return TranscriptionQueue(
        segments: segments,
        service: TranscriptionService(
          apiKey: key,
          client: MockClient((_) async => respond(++calls)),
        ),
        // Stands in for getApplicationDocumentsDirectory, which needs a
        // device. The queue only ever sees relative paths either way.
        resolveAudio: (relative) async => File('${tmp.path}/$relative'),
      );
    }

    test('drains every pending segment in one run', () async {
      await addSegment(1);
      await addSegment(2);
      await addSegment(3);

      final queue = queueThat(
        (n) => _ok('$_answer $n'),
      );
      await queue.run();

      expect(await segments.getPending(), isEmpty);
      expect(await segments.countByStatus(TranscribeStatus.done), 3);
      queue.dispose();
    });

    test('stops at the first transient failure and leaves the rest pending',
        () async {
      await addSegment(1);
      await addSegment(2);
      await addSegment(3);

      // First one succeeds, then the connection dies. Segments 2 and 3 must
      // still be pending — not failed — so a later run picks them up.
      final queue = queueThat(
          (n) => n == 1 ? _ok(_answer) : http.Response('gone', 503));
      await queue.run();

      expect(await segments.countByStatus(TranscribeStatus.done), 1);
      expect(await segments.countByStatus(TranscribeStatus.pending), 2);
      expect(await segments.countByStatus(TranscribeStatus.failed), 0);
      expect(queue.pausedBy, TranscriptionFailure.serverError);
      queue.dispose();
    });

    test('a permanent failure is marked and the queue carries on', () async {
      await addSegment(1);
      await addSegment(2);

      // The first file is refused outright; the second transcribes. One bad
      // segment must not block the ones behind it.
      final queue = queueThat(
          (n) => n == 1 ? http.Response('unsupported', 400) : _ok(_answer));
      await queue.run();

      expect(await segments.countByStatus(TranscribeStatus.failed), 1);
      expect(await segments.countByStatus(TranscribeStatus.done), 1);
      expect(queue.pausedBy, isNull);
      queue.dispose();
    });

    test('a hallucination fails the segment rather than becoming her words',
        () async {
      await addSegment(1);
      final queue = queueThat((_) => _ok('اشتركوا في القناة'));
      await queue.run();

      final row = (await segments.getForSession(sessionId)).single;
      expect(row.transcribeStatus, TranscribeStatus.failed);
      expect(row.transcriptAr, isNull);
      queue.dispose();
    });

    test('no key leaves everything pending and schedules no retry', () async {
      await addSegment(1);
      final queue = queueThat((_) => http.Response('{}', 200), key: '');
      await queue.run();

      expect(await segments.countByStatus(TranscribeStatus.pending), 1);
      expect(queue.pausedBy, TranscriptionFailure.noKey);
      queue.dispose();
    });

    test('retry puts a failed segment through on the second attempt',
        () async {
      await addSegment(1);
      final queue = queueThat(
          (n) => n == 1 ? http.Response('unsupported', 400) : _ok(_answer));

      await queue.run();
      expect(await segments.countByStatus(TranscribeStatus.failed), 1);

      await queue.retry(
        (await segments.getForSession(sessionId)).single.id!,
      );
      // retry() starts a run without awaiting it. run() joins the run that
      // is already going rather than starting another, which is what makes
      // this awaitable at all — and is the same property that stops the
      // interview screen uploading a segment twice.
      await queue.run();

      expect(await segments.countByStatus(TranscribeStatus.done), 1);
      queue.dispose();
    });

    test('a row whose file has been deleted fails without taking the run down',
        () async {
      await addSegment(1);
      final stored = (await segments.getForSession(sessionId)).single.audioPath;
      File('${tmp.path}/$stored').deleteSync();

      final queue = queueThat((_) => http.Response('{}', 200));
      await queue.run();

      expect(await segments.countByStatus(TranscribeStatus.failed), 1);
      queue.dispose();
    });

    test('the screen is told about every state change', () async {
      await addSegment(1);
      var notifications = 0;
      final queue = queueThat((_) => _ok(_answer))
        ..addListener(() => notifications++);

      await queue.run();

      // Start, in-flight, saved, finished. The exact count matters less than
      // it being more than zero — without these the interview screen would
      // show "waiting to transcribe" under a transcript it already has.
      expect(notifications, greaterThan(2));
      queue.dispose();
    });
  });
}
