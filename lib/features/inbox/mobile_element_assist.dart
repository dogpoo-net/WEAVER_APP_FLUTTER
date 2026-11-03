import 'package:flutter/material.dart';

/// Keeps a mobile overlay mounted until its slide-out animation finishes.
class MobileElementAssist extends StatefulWidget {
  const MobileElementAssist({
    super.key,
    required this.visible,
    required this.onHidden,
    required this.child,
  });

  final bool visible;
  final VoidCallback onHidden;
  final Widget child;

  @override
  State<MobileElementAssist> createState() => _MobileElementAssistState();
}

class _MobileElementAssistState extends State<MobileElementAssist>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addStatusListener(_statusChanged);
  late final Animation<Offset> _offset = Tween(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.visible) {
      _notifyHidden();
    }
  }

  void _notifyHidden() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.visible && _animation.isDismissed) {
        widget.onHidden();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.visible) _animation.forward();
  }

  @override
  void didUpdateWidget(MobileElementAssist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _animation.forward();
      } else {
        _animation.reverse();
        if (_animation.isDismissed) _notifyHidden();
      }
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !widget.visible,
    child: ClipRect(
      child: SlideTransition(position: _offset, child: widget.child),
    ),
  );
}
