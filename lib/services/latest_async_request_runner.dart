class LatestAsyncRequestRunner<T> {
  T? _pendingRequest;
  bool _hasPendingRequest = false;
  Future<void>? _activeRun;

  bool get isRunning => _activeRun != null;

  Future<void> run(T request, Future<void> Function(T request) operation) {
    _pendingRequest = request;
    _hasPendingRequest = true;
    return _activeRun ??= _drain(operation).whenComplete(() {
      _activeRun = null;
      _pendingRequest = null;
      _hasPendingRequest = false;
    });
  }

  Future<void> _drain(Future<void> Function(T request) operation) async {
    while (_hasPendingRequest) {
      final request = _pendingRequest as T;
      _pendingRequest = null;
      _hasPendingRequest = false;
      await operation(request);
    }
  }
}
