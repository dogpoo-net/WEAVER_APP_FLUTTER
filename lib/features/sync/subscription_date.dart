import 'package:flutter/services.dart';

// An inclusive Korean calendar date is stored as an exclusive UTC instant.
DateTime? subscriptionExpiry(String date) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return null;
  final parts = date.split('-').map(int.parse).toList();
  final day = DateTime.utc(parts[0], parts[1], parts[2]);
  if (day.year != parts[0] || day.month != parts[1] || day.day != parts[2]) return null;
  return day.add(const Duration(days: 1)).subtract(const Duration(hours: 9));
}

String subscriptionEndDate(String? instant) {
  final end = instant == null ? null : DateTime.tryParse(instant);
  if (end == null) return '';
  final day = end.toUtc().add(const Duration(hours: 9)).subtract(const Duration(microseconds: 1));
  return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

class SubscriptionDateFormatter extends TextInputFormatter {
  const SubscriptionDateFormatter();
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    var before = newValue.text.substring(0, newValue.selection.extentOffset.clamp(0, newValue.text.length)).replaceAll(RegExp(r'\D'), '').length;
    // Backspacing a separator also removes its preceding digit.
    if (newValue.text.length < oldValue.text.length && digits == oldValue.text.replaceAll(RegExp(r'\D'), '') && before > 0) {
      digits = digits.substring(0, before - 1) + digits.substring(before);
      before--;
    }
    if (digits.length > 8) digits = digits.substring(0, 8);
    final buffer = StringBuffer();
    var cursor = 0;
    for (var i = 0; i < digits.length; i++) {
      if (i == 4 || i == 6) buffer.write('-');
      buffer.write(digits[i]);
      if (i < before) cursor = buffer.length;
    }
    return TextEditingValue(text: buffer.toString(), selection: TextSelection.collapsed(offset: cursor));
  }
}
