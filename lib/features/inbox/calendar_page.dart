import 'package:flutter/material.dart';

import 'desktop_menu_frame.dart';
import 'element_store.dart';
import 'thought_filters.dart';
import 'thought_settings.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _time(int? minutes) =>
    minutes == null ? '시간 미정' : '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
typedef _Entry = ({ElementRecord thought, String date, int? minutes});

List<_Entry> _entries() {
  final result = [
    for (final thought in elements.records.values.where(canBrowseThought))
      for (final e in thought.calendar.entries)
        (thought: thought, date: e.key, minutes: e.value),
  ];
  return result..sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : (a.minutes ?? -1).compareTo(b.minutes ?? -1);
  });
}

class HomeCalendar extends StatelessWidget {
  const HomeCalendar({super.key, required this.open});
  final VoidCallback open;
  @override
  Widget build(BuildContext context) {
    final upcoming = _entries()
        .where((e) => e.date.compareTo(_day(DateTime.now())) >= 0)
        .take(5);
    return Column(
      children: [
        ListTile(
          title: const Text('캘린더 일정'),
          trailing: const Icon(Icons.chevron_right),
          onTap: open,
        ),
        if (upcoming.isEmpty)
          ListTile(title: const Text('예정된 일정이 없어요'), onTap: open),
        for (final e in upcoming)
          ListTile(
            title: Text(
              e.thought.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${e.date} · ${_time(e.minutes)}'),
            onTap: open,
          ),
      ],
    );
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.selector,
    required this.filters,
    required this.writable,
    required this.changed,
  });
  final Widget selector;
  final ThoughtFilterSelection filters;
  final bool writable;
  final VoidCallback changed;
  @override
  State<CalendarPage> createState() => _CalendarState();
}

class _CalendarState extends State<CalendarPage> {
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  bool thoughtsOpen = true, boxesOpen = true;
  String query = '';
  void schedule(String id, DateTime day) {
    final thought = elements.byId(id);
    if (!widget.writable || thought == null) return;
    setState(() {
      selected = day;
      thought.calendar.putIfAbsent(_day(day), () => null);
    });
    widget.changed();
  }

  Future<void> edit(_Entry event) async {
    final minutes = event.minutes;
    final time = await showTimePicker(
      context: context,
      helpText: '시작 시간',
      initialTime: minutes == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (!mounted || time == null || !widget.writable) return;
    final thought = elements.byId(event.thought.id);
    if (thought == null || !thought.calendar.containsKey(event.date)) return;
    setState(() => thought.calendar[event.date] = time.hour * 60 + time.minute);
    widget.changed();
  }

  Widget calendar() {
    final entries = _entries();
    final first = DateTime(selected.year, selected.month);
    final days = DateUtils.getDaysInMonth(selected.year, selected.month);
    final offset = first.weekday % 7;
    return ListView(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '이전 달',
              onPressed: () => setState(
                () => selected = DateTime(selected.year, selected.month - 1),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${selected.year}년 ${selected.month}월'),
            IconButton(
              tooltip: '다음 달',
              onPressed: () => setState(
                () => selected = DateTime(selected.year, selected.month + 1),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final name in '일월화수목금토'.split(''))
              Expanded(child: Center(child: Text(name))),
          ],
        ),
        for (var week = 0; week < (offset + days + 6) ~/ 7; week++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final n = week * 7 + col - offset + 1;
                      if (n < 1 || n > days) return const SizedBox.shrink();
                      final date = DateTime(selected.year, selected.month, n);
                      final events = entries.where((e) => e.date == _day(date));
                      return DragTarget<String>(
                        onWillAcceptWithDetails: (_) => widget.writable,
                        onAcceptWithDetails: (d) => schedule(d.data, date),
                        builder: (context, hover, _) => Material(
                          color: hover.isNotEmpty || date == selected
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => selected = date),
                            child: SizedBox(
                              height: 48,
                              child: Column(
                                children: [
                                  Text('$n'),
                                  if (events.isNotEmpty)
                                    InkWell(
                                      onTap: () {
                                        setState(() => selected = date);
                                        if (widget.writable) edit(events.first);
                                      },
                                      child: Text(
                                        events.first.thought.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        for (final e in entries.where((e) => e.date == _day(selected)))
          ListTile(
            title: Text(e.thought.title),
            subtitle: Text(_time(e.minutes)),
            onTap: widget.writable ? () => edit(e) : null,
            trailing: widget.writable
                ? IconButton(
                    tooltip: '일정에서 빼기',
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    onPressed: () {
                      setState(() => e.thought.calendar.remove(e.date));
                      widget.changed();
                    },
                  )
                : null,
          ),
      ],
    );
  }

  Widget panel(bool wide) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    child: Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '생각 찾기',
            isDense: true,
          ),
          onChanged: (s) => setState(() => query = s.trim().toLowerCase()),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final thought in elements.records.values.where(
                (r) =>
                    canBrowseThought(r) &&
                    widget.filters.matches(r) &&
                    (r.text.toLowerCase().contains(query) ||
                        r.title.toLowerCase().contains(query)),
              ))
                Builder(
                  builder: (context) {
                    final tile = ListTile(
                      dense: true,
                      title: Text(
                        thought.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                    final feedback = Material(
                      elevation: 3,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(thought.title, maxLines: 2),
                      ),
                    );
                    if (!widget.writable) return tile;
                    return wide
                        ? Draggable<String>(
                            data: thought.id,
                            feedback: feedback,
                            child: tile,
                          )
                        : LongPressDraggable<String>(
                            data: thought.id,
                            feedback: feedback,
                            child: tile,
                          );
                  },
                ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('캘린더')),
    body: DesktopMenuBody(
      child: Column(
        children: [
          widget.selector,
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 800;
                final toggle = IconButton(
                  tooltip: thoughtsOpen ? '생각 패널 숨기기' : '생각 패널 보이기',
                  onPressed: () => setState(() => thoughtsOpen = !thoughtsOpen),
                  icon: Icon(
                    wide
                        ? (thoughtsOpen
                              ? Icons.chevron_right
                              : Icons.chevron_left)
                        : (thoughtsOpen
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up),
                  ),
                );
                return wide
                    ? Row(
                        children: [
                          Expanded(child: calendar()),
                          if (thoughtsOpen)
                            SizedBox(
                              width: (c.maxWidth * .45).clamp(300, 560),
                              child: panel(true),
                            ),
                          toggle,
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: calendar()),
                          toggle,
                          if (thoughtsOpen)
                            SizedBox(
                              height: c.maxHeight * .30,
                              child: panel(false),
                            ),
                        ],
                      );
              },
            ),
          ),
          TextButton(
            onPressed: () => setState(() => boxesOpen = !boxesOpen),
            child: Text(boxesOpen ? '상자 패널 숨기기' : '상자 패널 보이기'),
          ),
          if (boxesOpen)
            ThoughtFilters(
              tags: elements.tags.toList()..sort(),
              selection: widget.filters,
              onFilter: (box, tag) =>
                  setState(() => widget.filters.toggle(box, tag)),
              onChanged: widget.changed,
            ),
        ],
      ),
    ),
  );
}
