import 'package:flutter/material.dart';

import '../theme.dart';

/// A screen that exists so navigation can be built and walked through before
/// the screen behind it is written.
///
/// Deliberately blunt. A placeholder that looks half-finished invites a judge
/// to think it is broken; one that says plainly what it will be, and which
/// day it is scheduled for, reads as a plan instead of a gap.
class NotBuiltYet extends StatelessWidget {
  const NotBuiltYet({
    super.key,
    required this.title,
    required this.willDo,
    required this.scheduledFor,
  });

  final String title;

  /// One sentence on what this screen will do once it is built.
  final String willDo;

  /// When it is scheduled, from docs/spec.md section 12.
  ///
  /// No owner is named. These screens are read by judges, and a name on an
  /// unbuilt screen tells them nothing they need and dates badly the moment
  /// the team changes.
  final String scheduledFor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.construction_outlined,
                  size: 48, color: JaddatiTheme.inkSoft),
              const SizedBox(height: 20),
              Text(
                'Not built yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                willDo,
                textAlign: TextAlign.center,
                style: JaddatiTheme.english.copyWith(height: 1.6),
              ),
              const SizedBox(height: 20),
              Text(
                scheduledFor,
                style: JaddatiTheme.english.copyWith(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
