/// A person whose stories we are recording — usually a grandparent.
///
/// A plain Dart class with no code generation. What you read here is what
/// runs, which matters when we are asked who wrote it.
class Person {
  final int? id;
  final String name;
  final String? nameAr;
  final String? relation;
  final String? photoPath;
  final DateTime createdAt;

  const Person({
    this.id,
    required this.name,
    this.nameAr,
    this.relation,
    this.photoPath,
    required this.createdAt,
  });

  /// `id` is omitted when null so SQLite assigns one on insert.
  ///
  /// Dates are stored as milliseconds since epoch: an integer sorts and
  /// compares correctly in SQL, which a formatted date string does not.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'name_ar': nameAr,
        'relation': relation,
        'photo_path': photoPath,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Person.fromMap(Map<String, Object?> map) => Person(
        id: map['id'] as int?,
        name: map['name'] as String,
        nameAr: map['name_ar'] as String?,
        relation: map['relation'] as String?,
        photoPath: map['photo_path'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  Person copyWith({
    int? id,
    String? name,
    String? nameAr,
    String? relation,
    String? photoPath,
    DateTime? createdAt,
  }) =>
      Person(
        id: id ?? this.id,
        name: name ?? this.name,
        nameAr: nameAr ?? this.nameAr,
        relation: relation ?? this.relation,
        photoPath: photoPath ?? this.photoPath,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// A person plus the two numbers the home screen shows beside their name.
///
/// This exists so the list can be drawn from one query instead of one query
/// per row. It is a read model: nothing writes it back to the database.
class PersonSummary {
  final Person person;

  /// Every session ever started with this person.
  final int sessionCount;

  /// Sessions that were finished. An unfinished session is not yet a story,
  /// and counting it as one would overstate what the archive holds.
  final int storyCount;

  const PersonSummary({
    required this.person,
    required this.sessionCount,
    required this.storyCount,
  });
}
