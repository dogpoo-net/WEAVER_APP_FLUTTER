import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'element_store.dart';
import 'element_usage.dart';
import 'word_badge.dart';
import 'workspace_routes.dart';
import 'workspace_storage.dart';

class AllThoughtsPage extends StatefulWidget {
  const AllThoughtsPage({super.key, required this.notes});
  final List<Note> notes;
  @override
  State<AllThoughtsPage> createState() => _AllThoughtsPageState();
}

class _AllThoughtsPageState extends State<AllThoughtsPage> with RouteAware {
  String? _selectedId;
  String _query = '';
  ModalRoute<dynamic>? _route;
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void initState() { super.initState(); elements.addListener(_refresh); }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      workspaceRouteObserver.unsubscribe(this);
      workspaceRouteObserver.subscribe(this, route);
      _route = route;
    }
  }
  @override
  void didPopNext() => _refresh();
  @override
  void dispose() {
    workspaceRouteObserver.unsubscribe(this);
    elements.removeListener(_refresh);
    super.dispose();
  }
  ElementRecord? get _selected {
    for (final record in elements.records.values) { if (record.id == _selectedId) return record; }
    return null;
  }
  void _select(String word) => setState(() => _selectedId = elements.records[word]?.id);
  Widget _badge(String word, bool desktop) => WordBadge(
    word: word, query: _query, selected: elements.records[word]?.id == _selectedId,
    onTap: desktop ? () => _select(word) : () => showElementMetadata(context, word),
    onDoubleTap: desktop ? () { _select(word); showElementMetadata(context, word); } : null,
  );
  Widget _tile(ElementRecord record, ElementUsage usage, int maximum, bool desktop) {
    final count = usage.counts[record.text] ?? 0;
    final colors = Theme.of(context).colorScheme;
    final selected = record.id == _selectedId;
    return Container(key: ValueKey('thought-${record.id}'), width: 280,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
        color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
        border: Border.all(color: selected ? colors.primary : colors.outlineVariant)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Expanded(child: _badge(record.text, desktop)), const SizedBox(width: 8),
          Semantics(label: '사용 $count회', child: Text('$count회', key: ValueKey('usage-${record.id}'),
            style: TextStyle(fontWeight: FontWeight.w700, color: colors.primary))),
          if (!elements.isSearchable(record.text)) const Padding(padding: EdgeInsetsDirectional.only(start: 4),
            child: Tooltip(message: '메인·어시스트 검색에서 숨긴 원소', child: Icon(Icons.visibility_off_outlined, size: 14))),
        ]),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: maximum == 0 ? 0 : count / maximum, minHeight: 3,
          borderRadius: BorderRadius.circular(3), backgroundColor: colors.surfaceContainerHighest),
      ]));
  }
  Widget _relations(ElementUsage usage, bool desktop) {
    final selected = _selected;
    final colors = Theme.of(context).colorScheme;
    if (selected == null) { return const Center(child: Padding(padding: EdgeInsets.all(24),
      child: Text('원소를 클릭하면\n함께 쓰인 원소를 보여줍니다.', textAlign: TextAlign.center))); }
    final related = (usage.together[selected.text] ?? {}).entries.toList()
      ..sort((a, b) { final frequency = b.value.compareTo(a.value); return frequency != 0 ? frequency : a.key.compareTo(b.key); });
    final maximum = related.isEmpty ? 1 : related.first.value;
    return SingleChildScrollView(key: const ValueKey('thought-relations'), padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('함께 쓰인 원소', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 20),
        Center(child: _badge(selected.text, desktop)),
        const SizedBox(height: 6),
        Text('총 ${usage.counts[selected.text] ?? 0}회 사용', textAlign: TextAlign.center),
        const Icon(Icons.keyboard_arrow_down, size: 30),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
          color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(20), border: Border.all(color: colors.outlineVariant)),
          child: Column(children: [
            if (related.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('함께 쓰인 원소가 없어요.')),
            for (final entry in related) Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Column(children: [
                Row(children: [Expanded(child: _badge(entry.key, desktop)), const SizedBox(width: 6),
                  Text('${entry.value}문장', key: ValueKey('together-${elements.records[entry.key]!.id}'))]),
                const SizedBox(height: 5),
                LinearProgressIndicator(value: entry.value / maximum, minHeight: 3,
                  borderRadius: BorderRadius.circular(3), backgroundColor: colors.surfaceContainerHighest),
              ])),
          ])),
        const SizedBox(height: 16),
        const Text('같은 문단·프로젝트 문장에서 함께 등장한 횟수입니다.', style: TextStyle(fontSize: 12)),
      ]));
  }
  @override
  Widget build(BuildContext context) {
    final usage = ElementUsage.fromNotes(widget.notes, elements);
    final allRecords = elements.records.values.toList();
    final records = allRecords.where((record) => record.text.toLowerCase().contains(_query.toLowerCase())).toList();
    final maximum = usage.counts.values.fold<int>(0, math.max);
    final desktop = {TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux}.contains(Theme.of(context).platform);
    final grid = SingleChildScrollView(key: const ValueKey('all-thoughts-grid'), padding: const EdgeInsets.all(24),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: Column(children: [
        Text(_query.isEmpty ? '원소 ${records.length}개' : '원소 ${records.length}개 / 전체 ${allRecords.length}개', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('사용 횟수는 저장된 문단·프로젝트 문장 안의 등장 횟수입니다.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(key: const ValueKey('all-thoughts-search'),
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(hintText: '원소에서 찾기', prefixIcon: Icon(Icons.search), isDense: true)),
        const SizedBox(height: 20),
        if (records.isEmpty) Padding(padding: const EdgeInsets.all(40),
          child: Text(allRecords.isEmpty ? '아직 원소가 없어요.' : '일치하는 원소가 없어요.')),
        Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12,
          children: [for (final record in records) _tile(record, usage, maximum, desktop)]),
      ]))));
    return Scaffold(appBar: AppBar(title: const Text('모든 생각 보기')),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        if (desktop && constraints.maxWidth >= 760) { return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: grid), const VerticalDivider(width: 1), SizedBox(width: 320, child: _relations(usage, desktop)),
        ]); }
        if (desktop) { return Column(children: [Expanded(child: grid),
          if (_selected != null) SizedBox(height: 260, child: _relations(usage, desktop))]); }
        return grid;
      })),
    );
  }
}
