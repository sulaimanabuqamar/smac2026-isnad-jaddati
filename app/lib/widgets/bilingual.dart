import 'package:flutter/material.dart';

import '../theme.dart';

/// Arabic text, laid out right-to-left.
///
/// Flutter lays out according to the ambient [Directionality], which for
/// this app is left-to-right because the interface chrome is English. Arabic
/// placed inside that inherits the wrong direction: punctuation lands on the
/// wrong end of the line and mixed Arabic-and-digits strings come out in the
/// wrong order. Wrapping each piece of Arabic in its own Directionality is
/// what fixes that, and it has to be done at every site — there is no
/// app-level switch that gets it right when both languages are on screen at
/// once.
class ArabicText extends StatelessWidget {
  const ArabicText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        style: style ?? JaddatiTheme.arabic,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        textAlign: TextAlign.right,
      ),
    );
  }
}

/// Arabic above, English below, as one block.
///
/// The order is fixed and deliberate: the Arabic is what she said, and the
/// English is a translation of it. Putting the English first would quietly
/// make the translation the real text and her words the annotation.
///
/// [english] is optional because a translation may not exist yet — a segment
/// that has been transcribed but not translated shows the Arabic alone,
/// rather than an empty space where the English will eventually go.
class BilingualText extends StatelessWidget {
  const BilingualText({
    super.key,
    required this.arabic,
    this.english,
    this.arabicStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String arabic;
  final String? english;
  final TextStyle? arabicStyle;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final translation = english;
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        SizedBox(
          width: double.infinity,
          child: ArabicText(arabic, style: arabicStyle),
        ),
        if (translation != null && translation.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(translation, style: JaddatiTheme.english),
        ],
      ],
    );
  }
}
