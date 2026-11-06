import 'package:flutter/material.dart';

class DesktopMenuController extends ChangeNotifier {
  Object? _owner;
  WidgetBuilder? builder;
  VoidCallback? openModal;
  bool Function()? alive;
  bool visible = true;
  bool get attached => builder != null && (alive?.call() ?? false);
  void attach(Object owner, WidgetBuilder menu, VoidCallback open, bool Function() isAlive, {bool notify = true}) {
    _owner = owner; builder = menu; openModal = open; alive = isAlive; if (notify) notifyListeners();
  }
  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null; builder = null; openModal = null; alive = null; notifyListeners();
  }
  void setVisible(bool value) { if (visible != value) { visible = value; notifyListeners(); } }
}
final desktopMenu = DesktopMenuController();

class DesktopMenuFrame extends StatelessWidget {
  const DesktopMenuFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: desktopMenu, child: child,
    builder: (context, child) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (MediaQuery.sizeOf(context).width >= 1000 && desktopMenu.visible && desktopMenu.attached)
        desktopMenu.builder!(context),
      Expanded(child: child!),
    ]));
}
class DesktopMenuAction extends StatelessWidget {
  const DesktopMenuAction({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: desktopMenu, builder: (context, _) =>
    MediaQuery.sizeOf(context).width >= 1000 && !desktopMenu.visible && desktopMenu.attached
      ? IconButton(tooltip: '메뉴 열기', onPressed: desktopMenu.openModal, icon: const Icon(Icons.grid_view_rounded))
      : const SizedBox.shrink());
}
