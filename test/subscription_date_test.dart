import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weaver/features/sync/subscription_date.dart';
void main() {
  test('inclusive Korean end date ends within the selected date regardless of device timezone', () {
    expect(subscriptionExpiry('2026-12-31'), DateTime.utc(2026,12,31,14,59,59,999,999));
    expect(subscriptionEndDate('2026-12-31T15:00:00Z'), '2026-12-31');
    expect(subscriptionExpiry('2028-02-29'), DateTime.utc(2028,2,29,14,59,59,999,999));
    expect(subscriptionExpiry('9999-12-31'),DateTime.utc(9999,12,31,14,59,59,999,999));
    expect(subscriptionEndDate(subscriptionExpiry('9999-12-31')!.toIso8601String()),'9999-12-31');
    expect(subscriptionExpiry('2026-02-29'), isNull);
    expect(subscriptionExpiry('2026-13-01'), isNull);
    expect(subscriptionExpiry('2026-12-31T12:00:00Z'), isNull);
  });
  test('date formatter handles typing paste and separator backspace', () {
    const f=SubscriptionDateFormatter();
    TextEditingValue value(String text)=>TextEditingValue(text:text,selection:TextSelection.collapsed(offset:text.length));
    expect(f.formatEditUpdate(value(''),value('20261231')).text,'2026-12-31');
    expect(f.formatEditUpdate(value(''),value('2026-12-31')).text,'2026-12-31');
    expect(f.formatEditUpdate(value('2026-12'),const TextEditingValue(text:'202612',selection:TextSelection.collapsed(offset:4))).text,'2021-2');
  });
}
