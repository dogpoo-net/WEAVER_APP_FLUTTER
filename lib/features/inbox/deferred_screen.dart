import 'package:flutter/material.dart';

import 'desktop_menu_frame.dart';
import 'workspace_routes.dart';

/// A failed download can be retried by opening the action again.
Future<bool> loadScreen(BuildContext context, Future<void> Function() load) async {
  try {
    await load();
    return context.mounted;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('화면을 불러오지 못했습니다. 다시 시도해주세요.')),
      );
    }
    return false;
  }
}

class DeferredScreen extends StatefulWidget {
  const DeferredScreen({super.key, required this.load, required this.builder, required this.selector});

  final Future<void> Function() load;
  final WidgetBuilder builder;
  final Widget selector;

  @override
  State<DeferredScreen> createState() => _DeferredScreenState();
}

class _DeferredScreenState extends State<DeferredScreen> {
  late Future<void> _loading = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _loading,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done || snapshot.hasError) {
        return DesktopMenuFrame(child: Scaffold(
          appBar: AppBar(title: const WorkspaceTitle('전체 보기')),
          body: DesktopMenuBody(child: Column(
            children: [
              widget.selector,
              Expanded(child: Center(
                child: snapshot.hasError
                    ? TextButton(
                        onPressed: () => setState(() => _loading = widget.load()),
                        child: const Text('화면 다시 불러오기'),
                      )
                    : const CircularProgressIndicator(),
              )),
            ],
          )),
        ));
      }
      return widget.builder(context);
    },
  );
}
