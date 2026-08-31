import 'package:flutter/material.dart';

import '../data/person_repository.dart';
import '../models/person.dart';
import '../theme.dart';
import '../widgets/bilingual.dart';

/// Add someone to record. Three fields, one of them required.
///
/// Pops with `true` when a person was saved and `false` (or null, on a back
/// gesture) when nothing changed, so the caller knows whether to reload.
class AddPersonScreen extends StatefulWidget {
  const AddPersonScreen({super.key, required this.people});

  final PersonRepository people;

  @override
  State<AddPersonScreen> createState() => _AddPersonScreenState();
}

class _AddPersonScreenState extends State<AddPersonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nameAr = TextEditingController();
  final _relation = TextEditingController();

  /// Guards against a second tap while the insert is in flight, which would
  /// otherwise write the person twice.
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _nameAr.dispose();
    _relation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final person = Person(
      name: _name.text.trim(),
      nameAr: _nameAr.text.trim().isEmpty ? null : _nameAr.text.trim(),
      relation: _relation.text.trim().isEmpty ? null : _relation.text.trim(),
      createdAt: DateTime.now(),
    );

    await widget.people.create(person);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add someone')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Only the name is required. You can fill in the rest later.',
              style: JaddatiTheme.english,
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Fatima',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'A name is needed to save'
                  : null,
            ),
            const SizedBox(height: 20),

            // The Arabic field sets its own direction so the caret starts on
            // the right and punctuation lands correctly, regardless of which
            // keyboard the phone happens to open with.
            const Text('Name in Arabic', style: JaddatiTheme.english),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.rtl,
              child: TextFormField(
                controller: _nameAr,
                style: JaddatiTheme.arabic,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(hintText: 'فاطمة'),
              ),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _relation,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Relation',
                hintText: 'Grandmother',
              ),
            ),
            const SizedBox(height: 32),

            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: 24),
            const Center(
              child: BilingualText(
                arabic: 'من تريدين أن تسمعي منه؟',
                english: 'Who do you want to hear from?',
                crossAxisAlignment: CrossAxisAlignment.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
