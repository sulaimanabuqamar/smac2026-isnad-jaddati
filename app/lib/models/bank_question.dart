/// A question from the offline bank, seeded from `assets/questions/bank.json`.
///
/// The id is the string from the JSON file (`child_01`), not an autoincrement
/// integer. Using the file's own id means re-seeding is idempotent: inserting
/// the same question twice updates one row rather than creating a duplicate.
class BankQuestion {
  final String id;
  final String topic;
  final String textAr;
  final String textEn;

  const BankQuestion({
    required this.id,
    required this.topic,
    required this.textAr,
    required this.textEn,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'topic': topic,
        'text_ar': textAr,
        'text_en': textEn,
      };

  factory BankQuestion.fromMap(Map<String, Object?> map) => BankQuestion(
        id: map['id'] as String,
        topic: map['topic'] as String,
        textAr: map['text_ar'] as String,
        textEn: map['text_en'] as String,
      );

  /// Reads one entry of the `questions` array in `bank.json`, whose keys are
  /// `id`, `topic`, `ar` and `en`.
  factory BankQuestion.fromJson(Map<String, Object?> json) => BankQuestion(
        id: json['id'] as String,
        topic: json['topic'] as String,
        textAr: json['ar'] as String,
        textEn: json['en'] as String,
      );
}
