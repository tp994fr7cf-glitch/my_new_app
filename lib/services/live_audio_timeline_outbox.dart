import 'live_audio_probe_message.dart';

typedef LiveAudioTimelineChunkSaver =
    Future<int> Function({
      required int firstSequence,
      required List<LiveAudioProbeMessage> messages,
    });

class LiveAudioTimelineOutbox {
  final List<LiveAudioProbeMessage> _pending = [];
  List<LiveAudioProbeMessage>? _retryBatch;
  int? _retryFirstSequence;
  Future<void>? _flushFuture;
  int _nextSequence = 0;

  bool get hasMessages => _retryBatch != null || _pending.isNotEmpty;
  bool get hasRetryBatch => _retryBatch != null;
  int get nextSequence => _nextSequence;

  void add(LiveAudioProbeMessage message) {
    _pending.add(message);
  }

  void observeServerSequence(int sequence) {
    if (!hasMessages && _flushFuture == null && sequence > _nextSequence) {
      _nextSequence = sequence;
    }
  }

  Future<void> flushNext(LiveAudioTimelineChunkSaver save) {
    final active = _flushFuture;
    if (active != null) {
      return active;
    }
    late final Future<void> tracked;
    tracked = _flushNext(save).whenComplete(() {
      if (identical(_flushFuture, tracked)) {
        _flushFuture = null;
      }
    });
    _flushFuture = tracked;
    return tracked;
  }

  Future<void> _flushNext(LiveAudioTimelineChunkSaver save) async {
    if (!hasMessages) {
      return;
    }
    final messages = _retryBatch ?? List<LiveAudioProbeMessage>.from(_pending);
    final firstSequence = _retryFirstSequence ?? _nextSequence;
    if (_retryBatch == null) {
      _pending.clear();
      _retryBatch = messages;
      _retryFirstSequence = firstSequence;
    }
    final nextSequence = await save(
      firstSequence: firstSequence,
      messages: messages,
    );
    _nextSequence = nextSequence;
    _retryBatch = null;
    _retryFirstSequence = null;
  }

  void discardRetryBatch() {
    _retryBatch = null;
    _retryFirstSequence = null;
  }

  void rebaseRetryBatch(int firstSequence) {
    if (_retryBatch == null || firstSequence < 0) {
      return;
    }
    _nextSequence = firstSequence;
    _retryFirstSequence = firstSequence;
  }

  void clear() {
    _pending.clear();
    _retryBatch = null;
    _retryFirstSequence = null;
    _nextSequence = 0;
  }
}
