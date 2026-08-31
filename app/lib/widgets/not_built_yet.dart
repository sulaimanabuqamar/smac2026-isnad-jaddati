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
    required this.owner,
  });

  final String title;

  /// One sentence on what this screen will do once it is built.
  final String willDo;

  /// The day from the schedule in docs/spec.md section 12.
  final String scheduledFor;

  /// Who on the team owns it, from the ownership table in CLAUDE.md.
  final String owner;

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
                '$scheduledFor · $owner',
                style: JaddatiTheme.english.copyWith(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
