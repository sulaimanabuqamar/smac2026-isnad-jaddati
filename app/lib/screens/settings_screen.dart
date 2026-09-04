import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import '../theme.dart';

/// Settings, plus — temporarily — the microphone diagnostics.
///
/// The settings this screen will eventually hold are not built. What is here
/// now is a button that runs the encoder probe, parked on this screen because
/// it is the one place in the app that is not part of the interview and
/// cannot get in a grandmother's way.
///
/// **The probe comes out once the recording config is settled.** It is here
/// to answer one question in one device run rather than six rebuilds.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const route = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _running = false;
  String? _status;

  Future<void> _runProbe() async {
    setState(() {
      _running = true;
      _status = null;
    });

    // Its own recorder, disposed straight after. The interview screen owns
    // the real one and this must not touch it.
    final audio = AudioService();
    try {
      if (!await audio.hasPermission()) {
        if (mounted) {
          setState(() => _status = 'The microphone permission was refused, '
              'so the probe cannot run.');
        }
        return;
      }
      await audio.probeEncoderConfigs();
      if (mounted) {
        setState(() => _status = 'Done. The results are in the console — '
            'read them off `flutter run`.');
      }
    } finally {
      await audio.dispose();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          Text(
            'Settings are not built yet. They will hold the offline '
            'translation model download and show which API keys are '
            'configured. Coming later this week.',
            style: JaddatiTheme.english.copyWith(height: 1.5),
          ),
          const Divider(height: 40),
          Text(
            'Microphone diagnostics',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Records a 1.5 second clip with six different encoder settings '
            'and prints how many bytes each one produced. Every recording '
            'this app has made so far is an empty container, and this is how '
            'we find out which setting iOS is refusing.\n\n'
            'Takes about ten seconds. Temporary — it comes out once the '
            'recording settings are decided.',
            style: JaddatiTheme.english.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _running ? null : _runProbe,
            child: Text(_running ? 'Recording…' : 'Run the encoder probe'),
          ),
          if (_status case final status?) ...[
            const SizedBox(height: 16),
            Text(status, style: JaddatiTheme.english),
          ],
        ],
      ),
    );
  }
}
