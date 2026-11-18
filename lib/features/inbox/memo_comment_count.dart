import 'package:flutter/material.dart';
import 'memo_comments.dart';

/// A comment on one thought must not rebuild every badge in the workspace.
class MemoCommentCount extends StatefulWidget {
  const MemoCommentCount({super.key, required this.id, required this.builder});
  final String? id;
  final Widget Function(BuildContext, int) builder;
  @override State<MemoCommentCount> createState() => _MemoCommentCountState();
}
class _MemoCommentCountState extends State<MemoCommentCount> {
  int get current => memoCommentCounts.value[widget.id] ?? 0;
  late int count;
  @override void initState() {
    super.initState(); count = current;
    memoCommentCounts.addListener(changed);
  }
  void changed() {
    final next = current;
    if (next != count) setState(() => count = next);
  }
  @override void didUpdateWidget(covariant MemoCommentCount oldWidget) {
    super.didUpdateWidget(oldWidget); count = current;
  }
  @override void dispose() {
    memoCommentCounts.removeListener(changed); super.dispose();
  }
  @override Widget build(BuildContext context) => widget.builder(context, count);
}
