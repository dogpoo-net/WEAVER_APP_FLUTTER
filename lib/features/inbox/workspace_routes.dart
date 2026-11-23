import 'package:flutter/material.dart';

class WorkspaceRouteObserver extends RouteObserver<ModalRoute<dynamic>> {
  ModalRoute<dynamic>? current;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute<dynamic>) current = route;
    super.didPush(route, previousRoute);
  }
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    current = previousRoute is ModalRoute<dynamic> ? previousRoute : null;
    super.didPop(route, previousRoute);
  }
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is ModalRoute<dynamic>) current = newRoute;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
final workspaceRouteObserver = WorkspaceRouteObserver();

/// Start background work once the page has finished animating onto the screen.
void afterWorkspaceRouteEntrance(BuildContext context, VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      action();
      return;
    }
    if (animation.status != AnimationStatus.forward) return;
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.forward) return;
      animation.removeStatusListener(onStatus);
      if (status == AnimationStatus.completed && context.mounted) action();
    }
    animation.addStatusListener(onStatus);
  });
}

/// Respect editors' unsaved-change guards while returning through nested views.
Future<void> navigateHome(BuildContext context) async {
  final navigator = Navigator.of(context);
  final origin = ModalRoute.of(context);
  while (navigator.mounted && navigator.canPop()) {
    final observed = workspaceRouteObserver.current;
    final current = observed?.navigator == navigator ? observed : origin;
    final guarded = current?.popDisposition == RoutePopDisposition.doNotPop;
    if (!await navigator.maybePop() || guarded) return;
    if (identical(current, workspaceRouteObserver.current)) return;
  }
}

class WorkspaceTitle extends StatelessWidget {
  const WorkspaceTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Text(title, style: const TextStyle(fontSize: 18),
    maxLines: 1, overflow: TextOverflow.ellipsis);
}

// Route document links through the active workspace's save/history handlers.
Future<void> Function(String)? openWorkspaceDocument;

Future<void> Function()? refreshWorkspaceForRead;

/// Persist an explicit thought save without fetching a server snapshot.
Future<void> Function()? saveWorkspaceContent;

String Function(String memoId)? workspaceMemoAuthor;

Future<bool> Function()? leaveDocumentEditor;
