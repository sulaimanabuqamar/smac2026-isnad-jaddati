import 'package:flutter/material.dart';

import '../widgets/not_built_yet.dart';

/// Placeholder for the archive: browse by person, filter by decade or place,
/// search transcripts, and see the pending transcription queue.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  static const route = '/archive';

  @override
  Widget build(BuildContext context) {
    return const NotBuiltYet(
      title: 'Archive',
      willDo: 'Every story, browsable by person, place and decade, with a '
          'search across the transcripts.',
      scheduledFor: 'Coming later this week',
    );
  }
}
