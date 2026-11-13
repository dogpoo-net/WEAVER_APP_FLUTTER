import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'word_badge.dart';
import 'label_links.dart';
import 'document_syntax.dart';
import 'mobile_element_assist.dart';
import 'project_folders.dart';

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
    this.showWhenEmpty = true,
    this.tags = const [],
    this.onTag,
    this.enterSelectsVisible = false,
    this.showShortcutHint = false,
    this.useThoughtLabels = false,
    this.selectionAssist = false,
  });
  final bool useThoughtLabels, selectionAssist;
  final TextEditingController controller;
  final FocusNode focus;
  final List<String> words;
  final List<String> tags;
  final ValueChanged<String>? onTag;
  final FutureOr<void> Function(String) onWord;
  final Widget child;
  final GlobalKey? mobileViewportKey;
  final bool showWhenEmpty;
  final bool enterSelectsVisible;
  final bool showShortcutHint;
  @override
  State<CaretAssist> createState() => CaretAssistState();
}

class CaretAssistState extends State<CaretAssist> with WidgetsBindingObserver {
  final _anchor = GlobalKey();
  final _selectionFilter = TextEditingController();
  final _filterFocus = FocusNode();
  TextEditingValue? _selectionValue;
  bool get _selectionMode => _selectionValue != null;
  void _filterSelected() {
    _query = _selectionFilter.text;
    _tagMode = false;
    _selected = 0;
    _matches = widget.words.where((word) => assistTargetMatches(word, _query)).toList();
  }
  final _suggestionScroll = ScrollController();
  OverlayEntry? _entry;
  WidgetBuilder? _overlayBuilder;
  bool _mobileVisible = false;
  String? _dismissed;
  List<String> _matches = [];
  int _selected = 0;
  String _query = '';
  bool _controlling = false;
  bool _tagMode = false, _spaceShortcutHeld = false, _acceptEnterHeld = false;
  String? _explicitOpenText;
  TextEditingValue? _controlValue;
  bool? _manualSelection;
  TextEditingValue? _manualValue;
  TextEditingValue? _autoCheckedValue;
  final _badgeKeys = <String, GlobalKey>{};
  bool get _desktop =>
      MediaQuery.sizeOf(context).width >= 760 &&
      MediaQuery.viewInsetsOf(context).bottom == 0;
  String _title(String word) => widget.useThoughtLabels ? assistTargetTitle(word) : word;
  void _choose(String word) async {
    _controlling = false;
    _manualSelection = null; _manualValue = null;
    final selected = _selectionValue;
    if (selected != null) {
      if (selected.text != widget.controller.text) { _hide(); return; }
      widget.controller.selection = selected.selection;
    }
    final FutureOr<void> result;
    if (_tagMode) { widget.onTag?.call(word.substring(1)); result = null; } else { result = widget.onWord(word); }
    _selectionValue = null;
    _filterFocus.unfocus();
    _dismissed = widget.controller.text;
    _hide();
    if (result is Future) {
      await result;
      if (!mounted) return;
      _dismissed = widget.controller.text;
      _hide();
    }
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

  bool acceptVisibleCandidate() {
    if (!mounted || _entry == null || _dismissed == widget.controller.text) return false;
    _refreshMatches(widget.controller.value, autoSelect: false);
    if (_matches.isEmpty) return false;
    if (widget.controller.value.composing.isValid && !widget.controller.value.composing.isCollapsed) {
      final committed = widget.controller.value.copyWith(composing: TextRange.empty);
      widget.focus.unfocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      widget.controller.value = committed;
      widget.focus.requestFocus();
    } else {
      widget.controller.clearComposing();
    }
    _refreshMatches(widget.controller.value, autoSelect: false);
    if (_matches.isEmpty) return false;
    _choose(_matches[_selected]);
    return true;
  }

  bool _committingNavigation = false;

  bool _key(KeyEvent event) {
    if (!mounted || !widget.focus.hasFocus || !_desktop) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed || keyboard.physicalKeysPressed.contains(PhysicalKeyboardKey.controlLeft) ||
        keyboard.physicalKeysPressed.contains(PhysicalKeyboardKey.controlRight);
    final controlKey = event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight ||
        event.physicalKey == PhysicalKeyboardKey.controlLeft || event.physicalKey == PhysicalKeyboardKey.controlRight;
    if (controlKey && event is KeyDownEvent) {
      final value = widget.controller.value;
      if (value.composing.isValid && !value.composing.isCollapsed) {
        // Commit the IME before Space arrives, without blurring the input or
        // turning Ctrl alone into assist selection.
        _manualSelection = _manualSelection == true && _controlling;
        _manualValue = value.copyWith(composing: TextRange.empty);
        _autoCheckedValue = _manualValue;
        _committingNavigation = true;
        try { widget.controller.clearComposing(); } finally { _committingNavigation = false; }
        _controlValue = _controlling ? widget.controller.value : null;
        // Web IMEs can retain native composition after clearComposing alone.
        // Close the input connection synchronously, then restore the same caret.
        widget.focus.unfocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
        widget.focus.requestFocus();
      }
    }
    if (event is KeyUpEvent && (event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight || event.physicalKey == PhysicalKeyboardKey.controlLeft ||
        event.physicalKey == PhysicalKeyboardKey.controlRight)) {
      _spaceShortcutHeld = false;
    }
    final space = event.logicalKey == LogicalKeyboardKey.space || event.physicalKey == PhysicalKeyboardKey.space;
    final enter = event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter ||
      event.physicalKey == PhysicalKeyboardKey.enter || event.physicalKey == PhysicalKeyboardKey.numpadEnter;
    if (enter && _acceptEnterHeld) {
      if (event is KeyUpEvent) _acceptEnterHeld = false;
      return true;
    }
    if (widget.enterSelectsVisible && enter && event is KeyDownEvent && _entry != null &&
        _dismissed != widget.controller.text && !control && !keyboard.isMetaPressed &&
        !keyboard.isAltPressed && !keyboard.isShiftPressed) {
      if (acceptVisibleCandidate()) { _acceptEnterHeld = true; return true; }
    }
    if (space && event is KeyUpEvent && _spaceShortcutHeld) {
      _spaceShortcutHeld = false; return true;
    }
    if (space && control && !keyboard.isAltPressed && !keyboard.isMetaPressed && !keyboard.isShiftPressed) {
      if (event is KeyDownEvent && !_spaceShortcutHeld) {
        _spaceShortcutHeld = true;
        // Automatic exact-match highlighting is not a shortcut entry. The first
        // Ctrl+Space must enter control, even if an IME commit highlighted a match.
        final leaveSelection = _controlling && _manualSelection == true &&
            _manualValue?.text == widget.controller.text;
        _dismissed = null;
        _explicitOpenText = widget.controller.text;
        _manualValue = widget.controller.value;
        _manualSelection = !leaveSelection;
        _refreshMatches(widget.controller.value, autoSelect: false);
        _controlling = !leaveSelection && _matches.isNotEmpty;
        _controlValue = _controlling ? widget.controller.value : null;
        _autoCheckedValue = widget.controller.value;
        _entry?.markNeedsBuild(); _update(); _revealSelection();
      }
      return true;
    }
    if (event is KeyUpEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape && _entry != null) {
      if (_controlling) {
        _controlling = false;
        _manualSelection = false; _manualValue = widget.controller.value;
        _controlValue = null;
        _autoCheckedValue = widget.controller.value;
        _entry?.markNeedsBuild();
      } else {
        _dismissed = widget.controller.text;
        _explicitOpenText = null;
        _hide();
      }
      return true;
    }
    if (_matches.isEmpty) return false;
    if (control ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    if (!_controlling) return false;
    final navigation = enter || space || [LogicalKeyboardKey.escape, LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter, LogicalKeyboardKey.space].contains(event.logicalKey);
    if (navigation) {
      _committingNavigation = true;
      try { widget.controller.clearComposing(); } finally { _committingNavigation = false; }
      _controlValue = widget.controller.value;
    }
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
    if (enter || space) {
      if (enter) _acceptEnterHeld = true;
      _choose(_matches[_selected]);
      return true;
    }
    // Typing resumes editing without losing the caret or the typed character.
    _controlling = false;
    _entry?.markNeedsBuild();
    return false;
  }

  FocusOnKeyEventCallback? _previousKeyHandler;
  KeyEventResult _inputKey(FocusNode node, KeyEvent event) {
    if (_key(event)) return KeyEventResult.handled;
    return _previousKeyHandler?.call(node, event) ?? KeyEventResult.ignored;
  }

  ScrollNotificationObserverState? _scrollObserver;
  void _scrolled(ScrollNotification notification) {
    // Mobile assistance is fixed to the viewport. Scrolling neither changes
    // its position nor the query; input and viewport changes update it separately.
    if (!_desktop || _entry == null || !widget.focus.hasFocus) return;
    _update(refreshMatches: false);
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
  void didUpdateWidget(CaretAssist oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.words, widget.words) || !listEquals(oldWidget.tags, widget.tags)) _update();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _previousKeyHandler = widget.focus.onKeyEvent;
    widget.focus.onKeyEvent = _inputKey;
    widget.controller.addListener(_update);
    widget.focus.addListener(_update);
    _filterFocus.addListener(_update);
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

  void _refreshMatches(TextEditingValue value, {bool autoSelect = true}) {
    if (widget.selectionAssist && value.selection.isValid && !value.selection.isCollapsed &&
        (!value.composing.isValid || value.composing.isCollapsed) &&
        !caretInsideCode(value.text, value.selection.start)) {
      if (_selectionValue?.selection != value.selection || _selectionValue?.text != value.text) {
        _selectionFilter.clear();
      }
      _selectionValue = value;
      _filterSelected();
      _controlling = false;
      return;
    }
    _selectionValue = null;
    final manualValue = _manualValue;
    if (manualValue != null && value.text == manualValue.text &&
        (value.selection == manualValue.selection ||
         (value.composing.isValid && !value.composing.isCollapsed) ||
         (manualValue.composing.isValid && !manualValue.composing.isCollapsed))) {
      // IME composition and selection echoes must not override explicit keyboard intent.
      _manualValue = manualValue.copyWith(composing: value.composing);
      value = _manualValue!;
    } else {
      _manualSelection = null; _manualValue = null;
    }
    final controlValue = _controlValue;
    if (!_committingNavigation && _controlling && controlValue != null &&
        (value.text != controlValue.text ||
         ((!value.composing.isValid || value.composing.isCollapsed) &&
          (!controlValue.composing.isValid || controlValue.composing.isCollapsed) &&
          (value.selection.baseOffset != controlValue.selection.baseOffset ||
           value.selection.extentOffset != controlValue.selection.extentOffset)))) {
      _controlling = false;
      _controlValue = null;
    }
    if (widget.useThoughtLabels && caretInsideCode(value.text, value.selection.extentOffset)) {
      _matches = []; _controlling = false; _controlValue = null;
      return;
    }
    final pending = widget.useThoughtLabels ? pendingLabelLink(value) : null;
    final token = pending == null ? tagPrefix(value) : '';
    final tagMode = widget.onTag != null && token.isNotEmpty;
    final query = tagMode ? token.substring(1) : pending?.query ?? completionPrefix(value, widget.words.map(_title).toList());
    if (_query != query || _tagMode != tagMode) _selected = 0;
    _tagMode = tagMode; _query = query;
    _matches = tagMode ? wordSuggestions(widget.tags.where((tag) => !hiddenSearchTags.contains(tag)).toList(), query).map((tag) => '#$tag').toList() : (widget.useThoughtLabels ? widget.words.where((word) => assistTargetMatches(word, query)).toList() : wordSuggestions(widget.words, query));
    if (_selected >= _matches.length) _selected = 0;
    final manual = _manualSelection;
    if (manual != null) {
      _controlling = manual && _matches.isNotEmpty;
      _controlValue = _controlling ? value : null;
      return;
    }
    final checked = _autoCheckedValue;
    final changed = checked == null || checked.text != value.text || checked.selection != value.selection;
    if (autoSelect && changed && (!_tagMode || !value.composing.isValid || value.composing.isCollapsed)) {
      _autoCheckedValue = value;
      final exact = query.isEmpty ? -1 : _matches.indexWhere((word) => (_tagMode ? word.substring(1).toLowerCase() == query.toLowerCase() : _title(word) == query));
      if (exact >= 0) {
        _selected = exact;
        _controlling = true;
        _controlValue = value;
        _revealSelection();
      }
    }
  }

  void _update({bool refreshMatches = true}) {
    final selection = widget.controller.selection;
    if (widget.selectionAssist && selection.isValid && !selection.isCollapsed && selection != _selectionValue?.selection) _dismissed = null;
    if (_dismissed != null && _dismissed != widget.controller.text) _dismissed = null;
    if (_explicitOpenText != widget.controller.text) _explicitOpenText = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_filterFocus.hasFocus && _selectionValue?.text == widget.controller.text) {
        _filterSelected();
        _entry?.markNeedsBuild();
        return;
      }
      if (!widget.focus.hasFocus || _dismissed == widget.controller.text) {
        if (!widget.focus.hasFocus) _acceptEnterHeld = false;
        _controlling = false;
        _spaceShortcutHeld = false; _explicitOpenText = null;
        _controlValue = null;
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
      if (refreshMatches) _refreshMatches(value);
      if (!_selectionMode && (_matches.isEmpty || (!widget.showWhenEmpty && !_tagMode && _query.isEmpty && pendingLabelLink(widget.controller.value) == null && _explicitOpenText == null))) {
        _controlling = false;
        _controlValue = null;
        _hide();
        return;
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_selectionMode) Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 0), child: TextField(
            key: const ValueKey('selection-link-filter'), controller: _selectionFilter, focusNode: _filterFocus,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(isDense: true, hintText: '메모·문서 검색', prefixIcon: Icon(Icons.search, size: 16),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            onChanged: (_) { _filterSelected(); _entry?.markNeedsBuild(); },
            onSubmitted: (_) { if (_matches.isNotEmpty) _choose(_matches.first); },
          )),
          if (_selectionMode && _matches.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('검색 결과가 없습니다.')),
          if (_desktop && widget.showShortcutHint) Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Align(alignment: Alignment.centerRight, child: Text('ctrl + space',
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ),
          Flexible(child: NotificationListener<ScrollNotification>(
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
                              displayText: _tagMode ? word : _title(word),
                              tag: _tagMode,
                              memo: !_tagMode && widget.useThoughtLabels && projectTarget(word) == null && !isLabelAssistTarget(word),
                              labelTarget: !_tagMode && widget.useThoughtLabels && isLabelAssistTarget(word),
                              project: !_tagMode && widget.useThoughtLabels && projectTarget(word) != null,
                              query: _query,
                              selected:
                                  _controlling &&
                                  _matches.indexOf(word) == _selected,
                              onTap: () => _choose(word),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        )),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    widget.focus.onKeyEvent = _previousKeyHandler;
    _suggestionScroll.dispose();
    _filterFocus.removeListener(_update); _filterFocus.dispose(); _selectionFilter.dispose();
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
        onNotification: (notification) {
          _scrolled(notification);
          return false;
        },
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) => _key(event) ? KeyEventResult.handled : KeyEventResult.ignored,
          child: Container(key: _anchor, child: widget.child),
        ),
      );
}
