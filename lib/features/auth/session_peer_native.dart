class SessionPeer {
  SessionPeer({required bool Function() available, required Future<void> Function(String, String) attach});
  Future<bool> request(String tab, String proof) async => false;
  void dispose() {}
}
