abstract interface class OAuthWindowHandle {
  bool get closed;
  Future<void> navigate(String url);
  void close();
}
