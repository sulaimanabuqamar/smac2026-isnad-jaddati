/// Where the question on screen came from.
///
/// Stored in SQLite as text. The enum exists so a misspelling is caught by
/// the compiler instead of becoming a row that no query ever matches.
enum QuestionSource {
  ai('ai'),
  bank('bank'),
  manual('manual');

  const QuestionSource(this.db);
  final String db;

  static QuestionSource fromDb(String value) =>
      QuestionSource.values.firstWhere((s) => s.db == value);
}

/// How far the audio has got through transcription.
///
/// `pending` is the state a segment is born in. Nothing about the recording
/// depends on this ever leaving `pending`.
enum TranscribeStatus {
  pending('pending'),
  done('done'),
  failed('failed');

  const TranscribeStatus(this.db);
  final String db;

  static TranscribeStatus fromDb(String value) =>
      TranscribeStatus.values.firstWhere((s) => s.db == value);
}

/// One question, one answer, one audio file.
///
/// This is the spine of the app. `audioPath` is non-nullable on purpose: a
/// segment row is only ever written *after* its audio file exists on disk.
/// A row cannot exist that promises audio we do not have.
class Segment {
  final int? id;
  final int sessionId;

  /// Position within the session, starting at 1. Explicit rather than
  /// inferred from `id`, so the order survives any future reordering.
  final int seq;

  final String questionText;
  final QuestionSource questionSource;
  final String audioPath;
  final int? durationMs;
  final String? transcriptAr;
  final String? transcriptEn;

  /// True once the user has corrected the transcript by hand. Transcription
  /// must never overwrite a human correction, and this is how it knows.
  final bool editedByUser;

  final TranscribeStatus transcribeStatus;
  final DateTime createdAt;

  const Segment({
    this.id,
    required this.sessionId,
    required this.seq,
    required this.questionText,
    required this.questionSource,
    required this.audioPath,
    this.durationMs,
    this.transcriptAr,
    this.transcriptEn,
    this.editedByUser = false,
    this.transcribeStatus = TranscribeStatus.pending,
    required this.createdAt,
  });

  /// SQLite has no boolean type, so `edited_by_user` is stored as 0 or 1.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'seq': seq,
        'question_text': questionText,
        'question_source': questionSource.db,
        'audio_path': audioPath,
        'duration_ms': durationMs,
        'transcript_ar': transcriptAr,
        'transcript_en': transcriptEn,
        'edited_by_user': editedByUser ? 1 : 0,
        'transcribe_status': transcribeStatus.db,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Segment.fromMap(Map<String, Object?> map) => Segment(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        seq: map['seq'] as int,
        questionText: map['question_text'] as String,
        questionSource:
            QuestionSource.fromDb(map['question_source'] as String),
        audioPath: map['audio_path'] as String,
        durationMs: map['duration_ms'] as int?,
        transcriptAr: map['transcript_ar'] as String?,
        transcriptEn: map['transcript_en'] as String?,
        editedByUser: (map['edited_by_user'] as int) == 1,
        transcribeStatus:
            TranscribeStatus.fromDb(map['transcribe_status'] as String),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}
