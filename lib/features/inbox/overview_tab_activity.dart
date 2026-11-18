import 'package:flutter/material.dart';

/// Retained tabs keep their state, but only the foreground tab does live UI work.
class OverviewTabActivity extends InheritedWidget {
  const OverviewTabActivity({super.key, required this.active, required super.child});
  final bool active;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OverviewTabActivity>()?.active ?? true;
  @override bool updateShouldNotify(OverviewTabActivity oldWidget) => active != oldWidget.active;
}

mixin RetainedOverviewTab<T extends StatefulWidget> on State<T> {
  bool tabActive = true;
  void onTabPaused() {}
  void onTabResumed() {}
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    final active = OverviewTabActivity.of(context);
    if (tabActive == active) return;
    tabActive = active;
    if (active) { onTabResumed(); } else { onTabPaused(); }
  }
}
