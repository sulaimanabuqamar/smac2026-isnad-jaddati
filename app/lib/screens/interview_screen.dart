import 'package:flutter/material.dart';

import '../models/person.dart';
import '../widgets/not_built_yet.dart';

/// Placeholder for the interview loop: question, hold to record, segment
/// saved, follow-up appears.
///
/// It takes a [Person] through its constructor rather than through named
/// route arguments. Route arguments arrive as `Object?` and have to be cast
/// at the far end, which turns a wrong navigation into a crash at runtime;
/// a constructor parameter turns the same mistake into a compile error.
class InterviewScreen extends StatelessWidget {
  const InterviewScreen({super.key, required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    return NotBuiltYet(
      title: person.name,
      willDo: 'Shows one question at a time, records the answer to a file on '
          'this phone, and asks a follow-up drawn from what was just said.',
      scheduledFor: 'Tue 2 Sep — record, save, play back',
      owner: 'Adel',
    );
  }
}
