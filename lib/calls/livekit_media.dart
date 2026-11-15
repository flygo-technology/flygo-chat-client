import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../i18n/i18n.dart';
import 'call_media.dart';
import 'calls_client.dart';

/// Ép đi qua TURN (kiểm thử mạng chặn UDP): `--dart-define=LK_FORCE_RELAY=true`.
const _forceRelay = bool.fromEnvironment('LK_FORCE_RELAY');
const _topic = 'flygo';

/// Cuộc họp qua LiveKit SFU tự host. Relay cấp sẵn [url] + [token] (chỉ cho người được vào phòng); TURN do máy chủ
/// LiveKit tự gửi. Sự kiện người tham gia đổi sang tên sự kiện của plugin Calls để [CallService] và màn hình cuộc họp
/// dùng chung: phiên = sid của người tham gia, user = identity (id người dùng chat).
/// Giơ tay = thuộc tính `hand` của người tham gia (người vào sau vẫn thấy), cảm xúc = tin dữ liệu chủ đề `flygo`.
class LiveKitMedia implements CallMedia {
  final String url;
  final String token;
  final void Function() onConnected;
  final void Function(String reason) onClosed;
  final void Function(String type, String sessionId, MediaStream stream, MediaStreamTrack track) onRemoteTrack;
  final void Function(String trackId) onRemoteTrackEnded;
  final void Function(String event, Map<String, dynamic> data)? onEvent;
  final void Function(bool ok)? onHealth;
  final void Function()? onLost;

  LiveKitMedia({
    required this.url,
    required this.token,
    required this.onConnected,
    required this.onClosed,
    required this.onRemoteTrack,
    required this.onRemoteTrackEnded,
    this.onEvent,
    this.onHealth,
    this.onLost,
  });

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  bool _closed = false;
  final Set<String> _speaking = {};

  @override
  String get sessionId => _room?.localParticipant?.sid ?? '';

  @override
  MediaStream? get localVideo => _cameraTrack?.mediaStream;

  lk.LocalVideoTrack? get _cameraTrack => _room?.localParticipant?.videoTrackPublications
      .where((p) => p.source == lk.TrackSource.camera)
      .firstOrNull
      ?.track;

  lk.CameraCaptureOptions get _camOpts => lk.CameraCaptureOptions(
        deviceId: CallsClient.videoInputId,
        params: lk.VideoParametersPresets.h540_169,
      );

  @override
  Future<void> start({bool video = false, bool muted = false}) async {
    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: _camOpts,
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(deviceId: CallsClient.audioInputId),
        defaultVideoPublishOptions: const lk.VideoPublishOptions(simulcast: true),
      ),
    );
    _room = room;
    _listen(room);
    try {
      await room.connect(
        url,
        token,
        connectOptions: const lk.ConnectOptions(
          rtcConfiguration: lk.RTCConfiguration(iceTransportPolicy: _forceRelay ? lk.RTCIceTransportPolicy.relay : null),
        ),
      );
    } catch (e) {
      debugPrint('[livekit] connect: $e');
      if (!_closed) _cleanup();
      rethrow;
    }
    if (_closed) return;
    final me = room.localParticipant!;
    // Micro luôn được xin quyền và xuất bản (tắt sẵn nếu vào im lặng) để bật mic sau không phải chờ.
    try {
      await me.setMicrophoneEnabled(true);
      if (muted) await me.setMicrophoneEnabled(false);
    } catch (e) {
      debugPrint('[livekit] mic: $e');
    }
    if (video) {
      try {
        await me.setCameraEnabled(true, cameraCaptureOptions: _camOpts);
      } catch (e) {
        debugPrint('[livekit] camera: $e');
      }
    }
    onConnected();
    // Người đã có sẵn trong phòng.
    for (final p in room.remoteParticipants.values) {
      _joined(p);
    }
  }

  void _emit(String ev, lk.Participant p, [Map<String, dynamic> extra = const {}]) =>
      onEvent?.call(ev, {'session_id': p.sid, 'user_id': p.identity, ...extra});

  void _joined(lk.RemoteParticipant p) {
    _emit('user_joined', p);
    final mic = p.audioTrackPublications.where((t) => t.source == lk.TrackSource.microphone).firstOrNull;
    _emit(mic != null && !mic.muted ? 'user_unmuted' : 'user_muted', p);
    if ((p.attributes['hand'] ?? '').isNotEmpty) _emit('user_raise_hand', p);
  }

  static String _typeOf(lk.TrackSource s, lk.Track t) => switch (s) {
        lk.TrackSource.camera => 'video',
        lk.TrackSource.screenShareVideo => 'screen',
        _ => t.kind == lk.TrackType.VIDEO ? 'video' : 'voice',
      };

  void _listen(lk.Room room) {
    final l = room.createListener();
    _events = l;
    l
      ..on<lk.ParticipantConnectedEvent>((e) => _joined(e.participant))
      ..on<lk.ParticipantDisconnectedEvent>((e) {
        _speaking.remove(e.participant.sid);
        _emit('user_left', e.participant);
      })
      ..on<lk.TrackSubscribedEvent>((e) {
        final t = e.track;
        onRemoteTrack(_typeOf(e.publication.source, t), e.participant.sid, t.mediaStream, t.mediaStreamTrack);
        if (e.publication.source == lk.TrackSource.screenShareVideo) _emit('user_screen_on', e.participant);
        if (e.publication.source == lk.TrackSource.camera && e.publication.muted) _emit('user_video_off', e.participant);
      })
      ..on<lk.TrackUnsubscribedEvent>((e) {
        final id = e.track.mediaStreamTrack.id;
        if (id != null) onRemoteTrackEnded(id);
        if (e.publication.source == lk.TrackSource.screenShareVideo) _emit('user_screen_off', e.participant);
        if (e.publication.source == lk.TrackSource.camera) _emit('user_video_off', e.participant);
      })
      ..on<lk.TrackUnpublishedEvent>((e) {
        if (e.publication.source == lk.TrackSource.microphone) _emit('user_muted', e.participant);
      })
      ..on<lk.TrackPublishedEvent>((e) {
        if (e.publication.source == lk.TrackSource.microphone && !e.publication.muted) _emit('user_unmuted', e.participant);
      })
      ..on<lk.TrackMutedEvent>((e) {
        if (e.participant is! lk.RemoteParticipant) return;
        switch (e.publication.source) {
          case lk.TrackSource.microphone:
            _emit('user_muted', e.participant);
          case lk.TrackSource.camera:
            _emit('user_video_off', e.participant);
          default:
        }
      })
      ..on<lk.TrackUnmutedEvent>((e) {
        if (e.participant is! lk.RemoteParticipant) return;
        switch (e.publication.source) {
          case lk.TrackSource.microphone:
            _emit('user_unmuted', e.participant);
          case lk.TrackSource.camera:
            _emit('user_video_on', e.participant);
          default:
        }
      })
      ..on<lk.ActiveSpeakersChangedEvent>((e) {
        final now = {for (final p in e.speakers) p.sid: p};
        for (final sid in _speaking.difference(now.keys.toSet()).toList()) {
          _speaking.remove(sid);
          onEvent?.call('user_voice_off', {'session_id': sid});
        }
        for (final p in now.values) {
          if (_speaking.add(p.sid)) _emit('user_voice_on', p);
        }
      })
      ..on<lk.ParticipantAttributesChanged>((e) {
        if (e.participant is! lk.RemoteParticipant || !e.attributes.containsKey('hand')) return;
        _emit((e.participant.attributes['hand'] ?? '').isNotEmpty ? 'user_raise_hand' : 'user_unraise_hand', e.participant);
      })
      ..on<lk.DataReceivedEvent>((e) {
        final p = e.participant;
        if (e.topic != _topic || p == null) return;
        try {
          final m = (jsonDecode(utf8.decode(e.data)) as Map).cast<String, dynamic>();
          if (m['t'] == 'react') {
            _emit('user_reacted', p, {'emoji': m['emoji'], 'timestamp': DateTime.now().microsecondsSinceEpoch});
          }
        } catch (_) {}
      })
      ..on<lk.RoomReconnectingEvent>((_) => onHealth?.call(false))
      ..on<lk.RoomReconnectedEvent>((_) => onHealth?.call(true))
      ..on<lk.RoomDisconnectedEvent>((e) {
        if (_closed) return;
        debugPrint('[livekit] disconnected: ${e.reason}');
        switch (e.reason) {
          case lk.DisconnectReason.participantRemoved:
            _cleanup();
            onClosed(tr('Bạn đã được mời ra khỏi cuộc họp'));
          case lk.DisconnectReason.roomDeleted:
            _cleanup();
            onClosed(tr('Cuộc họp đã kết thúc'));
          case lk.DisconnectReason.duplicateIdentity:
            _cleanup();
            onClosed(tr('Bạn đã vào cuộc họp này trên thiết bị khác'));
          default:
            onLost?.call();
        }
      });
  }

  @override
  void action(String action, [Map<String, dynamic>? data]) {
    final me = _room?.localParticipant;
    if (me == null || _closed) return;
    switch (action) {
      case 'raise_hand' || 'unraise_hand':
        me.setAttributes({'hand': action == 'raise_hand' ? '1' : ''}).catchError((Object e) {
          debugPrint('[livekit] hand: $e');
          return false;
        });
      case 'react':
        Object? emoji;
        try {
          emoji = jsonDecode(data?['data'] as String? ?? '{}');
        } catch (_) {}
        me
            .publishData(utf8.encode(jsonEncode({'t': 'react', 'emoji': emoji})), reliable: true, topic: _topic)
            .catchError((Object e) => debugPrint('[livekit] react: $e'));
    }
  }

  @override
  Future<MediaStream?> startVideo({bool front = true}) async {
    final me = _room?.localParticipant;
    if (me == null || _closed) return null;
    await me.setCameraEnabled(true,
        cameraCaptureOptions: front ? _camOpts : _camOpts.copyWith(cameraPosition: lk.CameraPosition.back));
    return localVideo;
  }

  @override
  Future<void> stopVideo() async {
    // Tắt camera là dừng thu hình hẳn (đèn camera tắt), bật lại là mở camera mới.
    await _room?.localParticipant?.setCameraEnabled(false);
  }

  @override
  Future<void> switchCamera() async {
    final t = _cameraTrack;
    if (t == null) return;
    final pos = t.currentOptions is lk.CameraCaptureOptions ? (t.currentOptions as lk.CameraCaptureOptions).cameraPosition : lk.CameraPosition.front;
    await t.setCameraPosition(pos.switched());
  }

  /// Chia sẻ màn hình qua LiveKit: LiveKit tự mở luồng màn hình [sourceId] (`desktopCapturer.getSources`).
  Future<MediaStream?> shareScreen(String sourceId) async {
    final me = _room?.localParticipant;
    if (me == null || _closed) return null;
    final pub = await me.setScreenShareEnabled(
      true,
      screenShareCaptureOptions: lk.ScreenShareCaptureOptions(sourceId: sourceId, maxFrameRate: 15),
    );
    return pub?.track?.mediaStream;
  }

  /// Luồng có sẵn: LiveKit không nhận luồng ngoài, dùng [shareScreen].
  @override
  Future<void> startScreen(MediaStream stream) async {}

  @override
  Future<void> stopScreen() async {
    await _room?.localParticipant?.setScreenShareEnabled(false);
    for (final p in [...?_room?.localParticipant?.trackPublications.values]) {
      if (p.source == lk.TrackSource.screenShareVideo || p.source == lk.TrackSource.screenShareAudio) {
        await _room?.localParticipant?.removePublishedTrack(p.sid).catchError((_) {});
      }
    }
  }

  @override
  void setMuted(bool mute) {
    final me = _room?.localParticipant;
    if (me == null) return;
    me.setMicrophoneEnabled(!mute).then((_) {}, onError: (Object e) => debugPrint('[livekit] mute: $e'));
  }

  @override
  Future<void> leave() async {
    if (_closed) return;
    final r = _room;
    await _stopOwnTracks(screen: true);
    _cleanup();
    try {
      await r?.disconnect();
      await r?.dispose();
    } catch (_) {}
  }

  /// Micro / camera của mình; [screen]: cả màn hình đang chia sẻ.
  Future<void> _stopOwnTracks({bool screen = false}) async {
    for (final p in [...?_room?.localParticipant?.trackPublications.values]) {
      if (!screen && (p.source == lk.TrackSource.screenShareVideo || p.source == lk.TrackSource.screenShareAudio)) continue;
      try {
        await p.track?.stop();
      } catch (_) {}
    }
  }

  @override
  void abandon() {
    if (_closed) return;
    final r = _room;
    _stopOwnTracks(screen: true);
    _cleanup();
    if (r != null) unawaited(_close(r));
  }

  static Future<void> _close(lk.Room r) async {
    try {
      await r.disconnect();
      await r.dispose();
    } catch (_) {}
  }

  void _cleanup() {
    _closed = true;
    _events?.dispose();
    _events = null;
    _speaking.clear();
  }
}
