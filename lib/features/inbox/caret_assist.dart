import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'word_badge.dart';
import 'mobile_element_assist.dart';

/// Three badge rows (30 each), two row gaps (6 each), and panel padding (8 each).
double mobileAssistHeight(MediaQueryData media) {
  final rowHeight = 30.0 * media.textScaler.scale(12) / 12;
  final available = media.size.height - media.viewInsets.bottom -
      media.padding.vertical - kToolbarHeight;
  return (rowHeight * 3 + 12 + 16).clamp(0.0, available.clamp(0.0, double.infinity));
}

class CaretAssist extends StatefulWidget {
  const CaretAssist({
    super.key,
    required this.controller,
    required this.focus,
    required this.words,
    required this.onWord,
    required this.child,
    this.mobileViewportKey,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final List<String> words;
  final ValueChanged<String> onWord;
  final Widget child;
  final GlobalKey? mobileViewportKey;
  @override
  State<CaretAssist> createState() => _CaretAssistState();
}

class _CaretAssistState extends State<CaretAssist> with WidgetsBindingObserver {
  final _anchor = GlobalKey();
  final _suggestionScroll = ScrollController();
  OverlayEntry? _entry;
  WidgetBuilder? _overlayBuilder;
  bool _mobileVisible = false;
  String? _dismissed;
  List<String> _matches = [];
  int _selected = 0;
  String _query = '';
  bool _controlling = false;
  bool _controlAlone = false;
  bool _pendingToggle = false;
  final _badgeKeys = <String, GlobalKey>{};
  bool get _desktop =>
      MediaQuery.sizeOf(context).width >= 760 &&
      MediaQuery.viewInsetsOf(context).bottom == 0;
  void _choose(String word) {
    _controlling = false;
    widget.onWord(word);
    _dismissed = widget.controller.text;
    _hide();
  }

  void _revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controlling || _matches.isEmpty) return;
      final target = _badgeKeys[_matches[_selected]]?.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: .5);
    });
  }

  void _move(LogicalKeyboardKey direction) {
    Rect? bounds(int index) {
      final box = _badgeKeys[_matches[index]]?.currentContext
          ?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    final current = bounds(_selected);
    if (current == null) return;
    final vertical =
        direction == LogicalKeyboardKey.arrowUp ||
        direction == LogicalKeyboardKey.arrowDown;
    final positive =
        direction == LogicalKeyboardKey.arrowDown ||
        direction == LogicalKeyboardKey.arrowRight;
    double bestPrimary = double.infinity, bestSecondary = double.infinity;
    var next = _selected;
    for (var i = 0; i < _matches.length; i++) {
      if (i == _selected) continue;
      final candidate = bounds(i);
      if (candidate == null) continue;
      final dx = candidate.center.dx - current.center.dx;
      final dy = candidate.center.dy - current.center.dy;
      final primary = vertical ? dy : dx;
      if ((positive ? primary : -primary) <= 1) continue;
      if (!vertical && dy.abs() > 1) continue;
      final distance = primary.abs();
      final secondary = vertical ? dx.abs() : dy.abs();
      if (distance < bestPrimary - 1 ||
          ((distance - bestPrimary).abs() <= 1 && secondary < bestSecondary)) {
        bestPrimary = distance;
        bestSecondary = secondary;
        next = i;
      }
    }
    _selected = next;
    _entry?.markNeedsBuild();
    _revealSelection();
  }

  bool _key(KeyEvent event) {
    if (!mounted ||
        !widget.focus.hasFocus ||
        !_desktop ||
        _entry == null ||
        _matches.isEmpty) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final control =
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.physicalKey == PhysicalKeyboardKey.controlLeft ||
        event.physicalKey == PhysicalKeyboardKey.controlRight;
    if (control) {
      if (event is KeyDownEvent) {
        _controlAlone =
            !keyboard.isAltPressed &&
            !keyboard.isMetaPressed &&
            !keyboard.isShiftPressed;
      }
      if (event is KeyUpEvent && _controlAlone) {
        _controlAlone = false;
        // Commit the current IME text without moving its selection. Apply the
        // toggle after suggestions have caught up with the committed value.
        final composing = widget.controller.value.composing;
        if (composing.isValid && !composing.isCollapsed) {
          widget.controller.clearComposing();
          _pendingToggle = !_pendingToggle;
          _update();
        } else {
          _controlling = !_controlling;
          _entry?.markNeedsBuild();
          _revealSelection();
        }
      }
      return false;
    }
    if (event is KeyUpEvent) return false;
    _controlAlone = false;
    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) return false;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    if (!_controlling) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _controlling = false;
      _entry?.markNeedsBuild();
      return true;
    }
    if ([
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ].contains(event.logicalKey)) {
      _move(event.logicalKey);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _choose(_matches[_selected]);
      return true;
    }
    // Typing resumes editing without losing the caret or the typed character.
    _controlling = false;
    _entry?.markNeedsBuild();
    return false;
  }

  ScrollNotificationObserverState? _scrollObserver;
  void _scrolled(ScrollNotification notification) {
    _update();
  }

  @override
  void didChangeMetrics() => _update();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollObserver?.removeListener(_scrolled);
    _scrollObserver = ScrollNotificationObserver.maybeOf(context);
    _scrollObserver?.addListener(_scrolled);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_update);
    widget.focus.addListener(_update);
  }

  void _hide({bool immediate = false}) {
    if (!immediate && !_desktop && _entry != null) {
      _mobileVisible = false;
      _entry?.markNeedsBuild();
      return;
    }
    _removeEntry();
  }

  void _removeEntry() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _update() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.focus.hasFocus || _dismissed == widget.controller.text) {
        _controlling = false;
        _controlAlone = false;
        _pendingToggle = false;
        _hide();
        return;
      }
      EditableTextState? editable;
      void visit(Element element) {
        if (element is StatefulElement && element.state is EditableTextState) {
          editable = element.state as EditableTextState;
        }
        element.visitChildren(visit);
      }

      (_anchor.currentContext as Element?)?.visitChildren(visit);
      if (editable == null) {
        _hide();
        return;
      }
      final value = widget.controller.value;
      final query = completionPrefix(value, widget.words);
      final matches = wordSuggestions(widget.words, query);
      if (_query != query) {
        _selected = 0;
        _controlling = false;
      }
      _query = query;
      _matches = matches;
      if (_selected >= matches.length) _selected = 0;
      if (matches.isEmpty) {
        _pendingToggle = false;
        _hide();
        return;
      }
      if (_pendingToggle) {
        _pendingToggle = false;
        _controlling = !_controlling;
        _revealSelection();
      }
      final render = editable!.renderEditable;
      final caret = render.getLocalRectForCaret(
        TextPosition(
          offset: value.selection.isValid
              ? value.selection.extentOffset
              : value.text.length,
        ),
      );
      final point = render.localToGlobal(caret.topLeft);
      final media = MediaQuery.of(context);
      final width = (media.size.width - 24).clamp(0.0, 300.0);
      final bottom =
          media.size.height -
          media.viewInsets.bottom -
          media.padding.bottom -
          8;
      final safeTop = media.padding.top + kToolbarHeight + 8;
      if (bottom - safeTop < 50) {
        _hide();
        return;
      }
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final height = _desktop
          ? (bottom - safeTop).clamp(50.0, 180.0)
          : mobileAssistHeight(media);
      final preferredTop = _desktop
          ? render.localToGlobal(caret.bottomLeft).dy + 4
          : bottom - height;
      final top = preferredTop.clamp(
        safeTop,
        (bottom - height).clamp(safeTop, bottom),
      );
      final left = _desktop
          ? (rtl ? point.dx - width - 8 : point.dx + 8).clamp(
              12.0,
              media.size.width - width - 12,
            )
          : (rtl ? media.size.width - width - 12 : 12.0);
      final body = widget.mobileViewportKey?.currentContext?.findRenderObject();
      final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      final bodyBottom = body is RenderBox && body.hasSize
          ? overlay.globalToLocal(body.localToGlobal(Offset(0, body.size.height))).dy
          : overlay.size.height - media.viewInsets.bottom;
      _mobileVisible = true;
      _overlayBuilder = (_) => Positioned(
        left: _desktop ? left : 0,
        top: _desktop ? top : null,
        bottom: _desktop ? null : (overlay.size.height - bodyBottom).clamp(0.0, overlay.size.height),
        width: _desktop ? width : media.size.width,
        child: TextFieldTapRegion(
          child: _desktop
              ? _panel(height)
              : MobileElementAssist(
                  visible: _mobileVisible,
                  onHidden: () {
                    if (!_mobileVisible) _removeEntry();
                  },
                  child: _panel(height),
                ),
        ),
      );
      if (_entry == null) {
        _entry = OverlayEntry(builder: (context) => _overlayBuilder!(context));
        Overlay.of(context).insert(_entry!);
      } else {
        _entry!.markNeedsBuild();
      }
    });
  }

  Widget _panel(double height) {
    return Material(
      key: const ValueKey("assist-popup"),
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height),
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: SingleChildScrollView(
            controller: _suggestionScroll,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _matches
                        .map(
                          (word) => Container(
                            key: _badgeKeys.putIfAbsent(
                              word,
                              () => GlobalKey(),
                            ),
                            child: WordBadge(
                              key: ValueKey('suggestion-$word'),
                              word: word,
                              selected:
                                  _controlling &&
                                  _matches.indexOf(word) == _selected,
                              onTap: () {
                                widget.onWord(word);
                                _dismissed = widget.controller.text;
                                _controlling = false;
                                _hide();
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _suggestionScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _scrollObserver?.removeListener(_scrolled);
    widget.controller.removeListener(_update);
    widget.focus.removeListener(_update);
    _hide(immediate: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _update();
          return false;
        },
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) =>
              _key(event) ? KeyEventResult.handled : KeyEventResult.ignored,
          child: Container(key: _anchor, child: widget.child),
        ),
      );
}
