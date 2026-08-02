import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import 'live_audio_probe_message.dart';

enum LiveAudioProbePermission {
  publisher,
  subscriber;

  bool get canPublish => this == publisher;

  static LiveAudioProbePermission fromStorage(Object? value) {
    return value == 'publisher' ? publisher : subscriber;
  }
}

class LiveAudioProbeCredentials {
  const LiveAudioProbeCredentials({
    required this.appId,
    required this.channelName,
    required this.rtcUid,
    required this.token,
    required this.permission,
    required this.expiresInSec,
    this.hlsManifestUrl = '',
  });

  final String appId;
  final String channelName;
  final int rtcUid;
  final String token;
  final LiveAudioProbePermission permission;
  final int expiresInSec;
  final String hlsManifestUrl;

  factory LiveAudioProbeCredentials.fromMap(Map<Object?, Object?> data) {
    return LiveAudioProbeCredentials(
      appId: data['appId'] as String? ?? '',
      channelName: data['channelName'] as String? ?? '',
      rtcUid: (data['rtcUid'] as num?)?.toInt() ?? 0,
      token: data['token'] as String? ?? '',
      permission: LiveAudioProbePermission.fromStorage(data['permission']),
      expiresInSec: (data['expiresInSec'] as num?)?.toInt() ?? 0,
      hlsManifestUrl: data['hlsManifestUrl'] as String? ?? '',
    );
  }
}

class LiveAudioProbeSession {
  const LiveAudioProbeSession({
    required this.id,
    required this.ownerUid,
    required this.status,
    required this.presenterUids,
    required this.activePresenterUid,
    required this.startedAtMs,
    required this.archiveStatus,
    required this.boardSet,
    this.archiveError = '',
    this.hlsManifestUrl = '',
    this.hlsAvailableDurationSec = 0,
    this.courseId = '',
    this.lessonId = '',
    this.segmentId = '',
    this.timelineNextSequence = 0,
    this.boardSetRevision = 0,
    this.segmentStartSec = 0,
    this.archiveTimelineOffsetSec = 0,
  });

  final String id;
  final String ownerUid;
  final String status;
  final Set<String> presenterUids;
  final String activePresenterUid;
  final int startedAtMs;
  final String archiveStatus;
  final String archiveError;
  final String hlsManifestUrl;
  final double hlsAvailableDurationSec;
  final String courseId;
  final String lessonId;
  final String segmentId;
  final BoardSet boardSet;
  final int timelineNextSequence;
  final int boardSetRevision;
  final double segmentStartSec;
  final double archiveTimelineOffsetSec;

  bool get isActive => status == 'active' || status == 'live';
  bool get isFinalizing => status == 'finalizing';
  bool get isDraftReady => status == 'draftReady';
  bool get archiveFailed =>
      archiveStatus == 'archiveFailed' || archiveStatus == 'failed';

  factory LiveAudioProbeSession.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final presenterUids = data['presenterUids'];
    return LiveAudioProbeSession(
      id: snapshot.id,
      ownerUid: data['ownerUid'] as String? ?? '',
      status: data['status'] as String? ?? 'ended',
      presenterUids: presenterUids is List
          ? presenterUids.whereType<String>().toSet()
          : const {},
      activePresenterUid:
          data['activePresenterUid'] as String? ??
          data['ownerUid'] as String? ??
          '',
      startedAtMs: (data['startedAtMs'] as num?)?.toInt() ?? 0,
      archiveStatus: data['archiveStatus'] as String? ?? 'notConfigured',
      archiveError: data['archiveError'] as String? ?? '',
      hlsManifestUrl: data['hlsManifestUrl'] as String? ?? '',
      hlsAvailableDurationSec:
          (data['hlsAvailableDurationSec'] as num?)?.toDouble() ?? 0,
      courseId: data['courseId'] as String? ?? '',
      lessonId: data['lessonId'] as String? ?? '',
      segmentId: data['segmentId'] as String? ?? '',
      boardSet: (data['boardSetSnapshot'] ?? data['boardSet']) is Map
          ? BoardSet.fromMap(
              (data['boardSetSnapshot'] ?? data['boardSet']) as Map,
            )
          : const BoardSet(),
      timelineNextSequence:
          (data['timelineNextSequence'] as num?)?.toInt() ?? 0,
      boardSetRevision: (data['boardSetRevision'] as num?)?.toInt() ?? 0,
      segmentStartSec: (data['segmentStartSec'] as num?)?.toDouble() ?? 0,
      archiveTimelineOffsetSec:
          (data['archiveTimelineOffsetSec'] as num?)?.toDouble() ?? 0,
    );
  }
}

class LiveAudioSavedStroke {
  const LiveAudioSavedStroke({required this.boardId, required this.stroke});

  final String boardId;
  final WhiteboardStroke stroke;
}

class LiveAudioTimelineChunk {
  const LiveAudioTimelineChunk({
    required this.id,
    required this.firstSequence,
    required this.messages,
  });

  final String id;
  final int firstSequence;
  final List<LiveAudioProbeMessage> messages;
}

class LiveAudioArchivePlaybackStatus {
  const LiveAudioArchivePlaybackStatus({
    required this.archiveStatus,
    this.hlsManifestUrl = '',
    this.hlsAvailableDurationSec = 0,
    this.archiveError = '',
  });

  final String archiveStatus;
  final String hlsManifestUrl;
  final double hlsAvailableDurationSec;
  final String archiveError;
}

class LiveAudioProbeParticipant {
  const LiveAudioProbeParticipant({
    required this.uid,
    required this.rtcUid,
    required this.displayName,
    required this.permission,
  });

  final String uid;
  final int rtcUid;
  final String displayName;
  final LiveAudioProbePermission permission;

  factory LiveAudioProbeParticipant.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return LiveAudioProbeParticipant(
      uid: data['uid'] as String? ?? snapshot.id,
      rtcUid: (data['rtcUid'] as num?)?.toInt() ?? 0,
      displayName: data['displayName'] as String? ?? '参加者',
      permission: LiveAudioProbePermission.fromStorage(data['permission']),
    );
  }
}

class LiveAudioProbeService {
  LiveAudioProbeService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  }) : _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1'),
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _firestore.collection('liveAudioProbeSessions');

  Future<String> createSession({
    String? courseId,
    String? lessonId,
    String? segmentId,
    BoardSet? initialBoardSet,
    double segmentStartSec = 0,
  }) async {
    final result = await _functions
        .httpsCallable('createLiveAudioProbeSession')
        .call({
          if (courseId?.isNotEmpty == true) 'courseId': courseId,
          if (lessonId?.isNotEmpty == true) 'lessonId': lessonId,
          if (segmentId?.isNotEmpty == true) 'segmentId': segmentId,
          if (initialBoardSet?.isNotEmpty == true)
            'initialBoardSet': initialBoardSet!.toMap(),
          'segmentStartSec': segmentStartSec,
        });
    final data = _resultMap(result.data);
    final sessionId = data['sessionId'] as String? ?? '';
    if (sessionId.isEmpty) {
      throw StateError('配信コードを受け取れませんでした。');
    }
    return sessionId;
  }

  Future<LiveAudioProbeCredentials> issueToken(String sessionId) async {
    final result = await _functions
        .httpsCallable('issueLiveAudioProbeToken')
        .call({'sessionId': sessionId});
    final credentials = LiveAudioProbeCredentials.fromMap(
      _resultMap(result.data),
    );
    if (credentials.appId.isEmpty ||
        credentials.channelName.isEmpty ||
        credentials.rtcUid <= 0 ||
        credentials.token.isEmpty) {
      throw StateError('Agora接続情報が不完全です。');
    }
    return credentials;
  }

  Future<void> setPresenter({
    required String sessionId,
    required String participantUid,
    required bool enabled,
  }) async {
    await _functions.httpsCallable('setLiveAudioProbePresenter').call({
      'sessionId': sessionId,
      'participantUid': participantUid,
      'enabled': enabled,
    });
  }

  Future<void> saveStroke({
    required String sessionId,
    String boardId = LessonWhiteboardBoard.defaultBoardId,
    required WhiteboardStroke stroke,
  }) async {
    await _functions.httpsCallable('saveLiveAudioProbeStroke').call({
      'sessionId': sessionId,
      'boardId': boardId,
      'stroke': stroke.toMap(),
    });
  }

  Future<int> saveBoardSnapshot({
    required String sessionId,
    required BoardSet boardSet,
    required int expectedRevision,
  }) async {
    final result = await _functions
        .httpsCallable('saveLiveAudioProbeBoardSet')
        .call({
          'sessionId': sessionId,
          'boardSet': boardSet.toMap(),
          'expectedRevision': expectedRevision,
        });
    final data = _resultMap(result.data);
    return (data['revision'] as num?)?.toInt() ?? expectedRevision + 1;
  }

  Future<int> saveTimelineChunk({
    required String sessionId,
    required int firstSequence,
    required List<LiveAudioProbeMessage> messages,
  }) async {
    if (messages.isEmpty) {
      return firstSequence;
    }
    final result = await _functions
        .httpsCallable('appendLiveAudioProbeTimelineChunk')
        .call({
          'sessionId': sessionId,
          'expectedNextSequence': firstSequence,
          'chunkId': 'chunk-$firstSequence',
          'events': messages
              .map((message) => message.toTimelineStorageMap())
              .toList(),
        });
    final data = _resultMap(result.data);
    return (data['nextSequence'] as num?)?.toInt() ??
        firstSequence + messages.length;
  }

  Future<void> retryArchive(String sessionId) async {
    await _functions.httpsCallable('retryLiveAudioProbeArchive').call({
      'sessionId': sessionId,
    });
  }

  Future<LiveAudioArchivePlaybackStatus> refreshArchiveStatus(
    String sessionId,
  ) async {
    final result = await _functions
        .httpsCallable('getLiveAudioProbeArchiveStatus')
        .call({'sessionId': sessionId});
    final data = _resultMap(result.data);
    return LiveAudioArchivePlaybackStatus(
      archiveStatus: data['archiveStatus'] as String? ?? '',
      hlsManifestUrl: data['hlsManifestUrl'] as String? ?? '',
      hlsAvailableDurationSec:
          (data['hlsAvailableDurationSec'] as num?)?.toDouble() ?? 0,
      archiveError: data['archiveError'] as String? ?? '',
    );
  }

  Future<void> closeSession(String sessionId) async {
    await _functions.httpsCallable('closeLiveAudioProbeSession').call({
      'sessionId': sessionId,
    });
  }

  Future<int> closeOwnedActiveSessions() async {
    final result = await _functions
        .httpsCallable('closeOwnedLiveAudioProbeSessions')
        .call();
    final data = _resultMap(result.data);
    final failedCount = (data['failedCount'] as num?)?.toInt() ?? 0;
    if (failedCount > 0) {
      throw StateError('$failedCount件の配信を終了できませんでした。もう一度お試しください。');
    }
    return (data['closedCount'] as num?)?.toInt() ?? 0;
  }

  Stream<LiveAudioProbeSession> watchSession(String sessionId) {
    return _sessions.doc(sessionId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        throw StateError('検証配信が見つかりません。');
      }
      return LiveAudioProbeSession.fromSnapshot(snapshot);
    });
  }

  Stream<List<LiveAudioProbeParticipant>> watchParticipants(String sessionId) {
    return _sessions
        .doc(sessionId)
        .collection('participants')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(LiveAudioProbeParticipant.fromSnapshot).toList()
                ..sort(
                  (a, b) => a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  ),
                ),
        );
  }

  Stream<List<WhiteboardStroke>> watchSavedStrokes(String sessionId) {
    return watchSavedBoardStrokes(
      sessionId,
    ).map((records) => records.map((record) => record.stroke).toList());
  }

  Stream<List<LiveAudioSavedStroke>> watchSavedBoardStrokes(String sessionId) {
    return _sessions
        .doc(sessionId)
        .collection('whiteboardStrokes')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map(
                    (doc) => LiveAudioSavedStroke(
                      boardId:
                          doc.data()['boardId'] as String? ??
                          LessonWhiteboardBoard.defaultBoardId,
                      stroke: WhiteboardStroke.fromMap(doc.data()),
                    ),
                  )
                  .toList()
                ..sort((a, b) {
                  final timestampCompare = a.stroke.timestampSec.compareTo(
                    b.stroke.timestampSec,
                  );
                  return timestampCompare != 0
                      ? timestampCompare
                      : a.stroke.id.compareTo(b.stroke.id);
                }),
        );
  }

  Stream<List<LiveAudioTimelineChunk>> watchTimelineChunks(String sessionId) {
    return _sessions
        .doc(sessionId)
        .collection('timelineChunks')
        .orderBy('sequenceStart')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                final rawEvents = data['events'];
                final messages = rawEvents is List
                    ? rawEvents
                          .whereType<Map>()
                          .map(_timelineMessageFromMap)
                          .whereType<LiveAudioProbeMessage>()
                          .toList(growable: false)
                    : const <LiveAudioProbeMessage>[];
                return LiveAudioTimelineChunk(
                  id: doc.id,
                  firstSequence: (data['sequenceStart'] as num?)?.toInt() ?? 0,
                  messages: messages,
                );
              })
              .toList(growable: false),
        );
  }
}

Map<Object?, Object?> _resultMap(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<Object?, Object?>.from(value);
  }
  throw StateError('サーバーから不正な応答を受け取りました。');
}

LiveAudioProbeMessage? _timelineMessageFromMap(Map data) {
  final type = data['type'];
  final boardId = data['boardId'];
  final timestamp = data['globalTimestampSec'];
  if (boardId is! String ||
      boardId.isEmpty ||
      timestamp is! num ||
      !timestamp.isFinite ||
      timestamp < 0) {
    return null;
  }
  switch (type) {
    case 'boardCreate':
      final order = data['boardOrder'];
      final title = data['boardTitle'];
      if (order is! num || title is! String) {
        return null;
      }
      return LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.boardCreate,
        boardId: boardId,
        timestampSec: timestamp.toDouble(),
        boardOrder: order.toInt(),
        boardTitle: title,
      );
    case 'boardSwitch':
      return LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.boardSwitch,
        boardId: boardId,
        timestampSec: timestamp.toDouble(),
      );
    case 'viewport':
      final centerX = data['centerX'];
      final centerY = data['centerY'];
      final scale = data['scale'];
      final interactionId = data['interactionId'];
      if (centerX is! num ||
          centerY is! num ||
          scale is! num ||
          interactionId is! num) {
        return null;
      }
      return LiveAudioProbeMessage(
        kind: LiveAudioProbeMessageKind.viewport,
        boardId: boardId,
        timestampSec: timestamp.toDouble(),
        interactionId: interactionId.toInt(),
        viewport: LessonWhiteboardViewport.normalized(
          centerX: centerX.toDouble(),
          centerY: centerY.toDouble(),
          scale: scale.toDouble(),
        ),
      );
    default:
      return null;
  }
}
