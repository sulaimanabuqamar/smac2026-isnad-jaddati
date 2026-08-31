/// One sitting with one person: a chain of question-and-answer segments.
///
/// A session is open from the moment recording starts until it is ended.
/// `endedAt` being null is what "unfinished" means, so a session interrupted
/// by a phone call or a flat battery is still there to resume.
///
/// `title`, `place`, `decade` and `summary` are filled in later by the story
/// extraction call. They are nullable because a session is valid without
/// them — the audio and the transcripts are the irreplaceable part.
class Session {
  final int? id;
  final int personId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? title;
  final String? place;
  final String? decade;
  final String? summary;

  const Session({
    this.id,
    required this.personId,
    required this.startedAt,
    this.endedAt,
    this.title,
    this.place,
    this.decade,
    this.summary,
  });

  bool get isFinished => endedAt != null;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'person_id': personId,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'title': title,
        'place': place,
        'decade': decade,
        'summary': summary,
      };

  factory Session.fromMap(Map<String, Object?> map) => Session(
        id: map['id'] as int?,
        personId: map['person_id'] as int,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
        endedAt: map['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['ended_at'] as int),
        title: map['title'] as String?,
        place: map['place'] as String?,
        decade: map['decade'] as String?,
        summary: map['summary'] as String?,
      );
}
