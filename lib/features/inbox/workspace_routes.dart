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
  Widget build(BuildContext context) => MediaQuery.sizeOf(context).width >= 1000
    ? Row(children: [TextButton(onPressed: () => navigateHome(context), child: const Text('WEAVER',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 2))),
        const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis))])
    : Text(title, style: const TextStyle(fontSize: 18));
}
