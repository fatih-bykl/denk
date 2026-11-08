import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../money/money.dart';

/// Kuruş değeri girmek için metin alanı. Değeri [Money.parse] ile okunur.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.allowNegative = false,
    this.required = true,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final bool allowNegative;
  final bool required;
  final String? helperText;

  /// Alan boşsa ve zorunlu değilse 0 kabul edilir.
  static int? read(
    TextEditingController controller, {
    bool allowNegative = false,
  }) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    return Money.parse(text, allowNegative: allowNegative);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        suffixText: '₺',
        helperText: helperText,
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: allowNegative,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(allowNegative ? r'[0-9.,\-]' : r'[0-9.,]'),
        ),
      ],
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return required ? 'Tutar gerekli.' : null;
        if (Money.parse(text, allowNegative: allowNegative) == null) {
          return 'Geçerli bir tutar gir (ör. 1.250,50).';
        }
        return null;
      },
    );
  }
}
