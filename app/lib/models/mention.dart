/// What kind of thing was mentioned in a session.
enum MentionKind {
  person('person'),
  place('place'),
  year('year');

  const MentionKind(this.db);
  final String db;

  static MentionKind fromDb(String value) =>
      MentionKind.values.firstWhere((k) => k.db == value);
}

/// A person, place or year that the extraction call found in a session's
/// transcripts. This is what makes the archive browsable instead of a pile
/// of voice notes.
///
/// Mentions are deliberately flat text, not links to `person` rows. Deciding
/// that "Fatima" in a transcript is the same Fatima as a row in the database
/// is relationship inference, which section 5 of the spec puts out of scope.
class Mention {
  final int? id;
  final int sessionId;
  final MentionKind kind;
  final String value;

  const Mention({
    this.id,
    required this.sessionId,
    required this.kind,
    required this.value,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'kind': kind.db,
        'value': value,
      };

  factory Mention.fromMap(Map<String, Object?> map) => Mention(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        kind: MentionKind.fromDb(map['kind'] as String),
        value: map['value'] as String,
      );
}
