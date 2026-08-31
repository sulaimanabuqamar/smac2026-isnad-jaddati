import 'package:flutter/material.dart';

import '../widgets/not_built_yet.dart';

/// Placeholder for settings: the offline translation model download, and
/// whatever else earns its place. Deliberately close to empty — every
/// setting is a decision pushed onto the user.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const route = '/settings';

  @override
  Widget build(BuildContext context) {
    return const NotBuiltYet(
      title: 'Settings',
      willDo: 'Downloads the 32 MB Arabic translation model for offline use, '
          'and shows which API keys are configured.',
      scheduledFor: 'Later in the week',
      owner: 'Bilal',
    );
  }
}
