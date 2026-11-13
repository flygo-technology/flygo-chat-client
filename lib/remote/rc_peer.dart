// Điều khiển máy tính từ xa: kết nối WebRTC trực tiếp giữa hai máy (P2P, dự phòng TURN của máy chủ chat).
// Máy bị điều khiển gửi hình màn hình (một track video) và tạo offer; máy điều khiển trả answer và gửi thao tác qua
// data channel "input" (negotiated, id 1: hai bên tự mở, không cần chờ nhau). Chiều ngược lại trên cùng kênh: máy bị
// điều khiển gửi danh sách màn hình (rc_protocol.dart, RcHostMessage); đổi màn hình = thay track bằng replaceTrack,
// không cần đàm phán lại.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Kênh nhập: có thứ tự, chắc chắn tới (bấm / nhả phím không được mất).
RTCDataChannelInit _inputChannel() => RTCDataChannelInit()
  ..negotiated = true
  ..id = 1
  ..ordered = true;

/// Chất lượng hình: tốc độ bit tối đa, giảm độ phân giải, số khung hình.
(int, double, int) rcQualityParams(String level) => switch (level) {
      'high' => (8000000, 1.0, 30),
      'low' => (800000, 2.0, 12),
      _ => (3000000, 1.0, 24),
    };

abstract class RcPeer {
  final List<Map<String, dynamic>> iceServers;
  /// Gửi tín hiệu (offer / answer / ice) qua trạm.
  final void Function(Map<String, dynamic> data) onSignal;
  /// Kết nối đã thông (true) / hỏng hẳn (false).
  final void Function(bool ok) onState;

  RcPeer({required this.iceServers, required this.onSignal, required this.onState});

  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pending = [];
  bool _closed = false;
  bool _connected = false;
  Timer? _lostTimer;

  bool get connected => _connected;

  Future<void> _create() async {
    pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    pc!.onIceCandidate = (c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      onSignal({'type': 'ice', 'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc!.onConnectionState = (s) {
      if (_closed) return;
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _lostTimer?.cancel();
          if (!_connected) {
            _connected = true;
            onState(true);
          }
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Mất kết nối tạm (đổi mạng): chờ 12 giây tự nối lại, không được thì kết thúc.
          _lostTimer ??= Timer(const Duration(seconds: 12), () => onState(false));
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          onState(false);
        default:
      }
    };
    dc = await pc!.createDataChannel('input', _inputChannel());
  }

  /// Tín hiệu từ máy kia (qua trạm).
  Future<void> onRemoteSignal(Map<String, dynamic> d) async {
    final p = pc;
    if (p == null || _closed) return;
    try {
      switch (d['type']) {
        case 'offer':
          await p.setRemoteDescription(RTCSessionDescription(d['sdp'] as String?, 'offer'));
          await _flushIce();
          final answer = await p.createAnswer();
          await p.setLocalDescription(answer);
          onSignal({'type': 'answer', 'sdp': answer.sdp});
        case 'answer':
          await p.setRemoteDescription(RTCSessionDescription(d['sdp'] as String?, 'answer'));
          await _flushIce();
        case 'ice':
          final c = RTCIceCandidate(d['candidate'] as String?, d['sdpMid'] as String?, (d['sdpMLineIndex'] as num?)?.toInt());
          _remoteSet ? await p.addCandidate(c) : _pending.add(c);
      }
    } catch (e) {
      debugPrint('[rc] signal ${d['type']}: $e');
    }
  }

  Future<void> _flushIce() async {
    _remoteSet = true;
    for (final c in _pending) {
      try {
        await pc?.addCandidate(c);
      } catch (_) {}
    }
    _pending.clear();
  }

  bool get canSend => dc?.state == RTCDataChannelState.RTCDataChannelOpen;

  /// Gửi một tin qua data channel (chưa mở thì bỏ).
  void send(String msg) {
    if (!canSend) return;
    try {
      dc!.send(RTCDataChannelMessage(msg));
    } catch (_) {}
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _lostTimer?.cancel();
    try {
      await dc?.close();
    } catch (_) {}
    try {
      await pc?.close();
    } catch (_) {}
    pc = null;
    dc = null;
  }
}

/// Máy bị điều khiển: chụp màn hình [sourceId], gửi hình, nhận thao tác.
class RcHostPeer extends RcPeer {
  /// Nguồn chụp đang gửi (đổi bằng [switchSource]).
  String sourceId;
  final void Function(String msg) onInput;
  /// Data channel đã mở: gửi danh sách màn hình.
  final void Function()? onOpen;
  MediaStream? _stream;
  RTCRtpSender? _sender;
  String _quality = 'auto';

  RcHostPeer({
    required super.iceServers,
    required super.onSignal,
    required super.onState,
    required this.sourceId,
    required this.onInput,
    this.onOpen,
  });

  static Future<MediaStream> _capture(String id) => navigator.mediaDevices.getDisplayMedia({
        'audio': false,
        'video': {
          'deviceId': {'exact': id},
          'mandatory': {'frameRate': 30.0},
        },
      });

  MediaStreamTrack _watch(MediaStream s) {
    final track = s.getVideoTracks().first;
    track.onEnded = () {
      if (!_closed && identical(s, _stream)) onState(false);
    };
    return track;
  }

  /// Báo lỗi (không chụp được màn hình...) bằng ngoại lệ.
  Future<void> start() async {
    _stream = await _capture(sourceId);
    await _create();
    dc!.onMessage = (m) {
      if (!m.isBinary) onInput(m.text);
    };
    dc!.onDataChannelState = (st) {
      if (st == RTCDataChannelState.RTCDataChannelOpen && !_closed) onOpen?.call();
    };
    final track = _watch(_stream!);
    _sender = await pc!.addTrack(track, _stream!);
    await setQuality(_quality);
    final offer = await pc!.createOffer({'offerToReceiveAudio': false, 'offerToReceiveVideo': false});
    await pc!.setLocalDescription(offer);
    onSignal({'type': 'offer', 'sdp': offer.sdp});
  }

  /// Đổi sang chụp màn hình [id]: thay track đang gửi (replaceTrack), không đàm phán lại. Lỗi thì giữ màn hình cũ
  /// và báo bằng ngoại lệ.
  Future<void> switchSource(String id) async {
    final sender = _sender;
    if (sender == null || _closed || id == sourceId) return;
    final next = await _capture(id);
    if (_closed) {
      await _dispose(next);
      return;
    }
    final old = _stream;
    try {
      await sender.replaceTrack(_watch(next));
    } catch (_) {
      await _dispose(next);
      rethrow;
    }
    _stream = next;
    sourceId = id;
    if (old != null) await _dispose(old);
    await setQuality(_quality);
  }

  static Future<void> _dispose(MediaStream s) async {
    for (final t in s.getTracks()) {
      t.onEnded = null;
      try {
        await t.stop();
      } catch (_) {}
    }
    try {
      await s.dispose();
    } catch (_) {}
  }

  Future<void> setQuality(String level) async {
    _quality = level;
    final s = _sender;
    if (s == null) return;
    final (bitrate, scale, fps) = rcQualityParams(level);
    try {
      final p = s.parameters;
      final enc = p.encodings;
      if (enc == null || enc.isEmpty) {
        p.encodings = [RTCRtpEncoding(maxBitrate: bitrate, scaleResolutionDownBy: scale, maxFramerate: fps, active: true)];
      } else {
        for (final e in enc) {
          e.maxBitrate = bitrate;
          e.scaleResolutionDownBy = scale;
          e.maxFramerate = fps;
        }
      }
      // Màn hình có chữ: giữ độ nét, giảm số khung hình khi mạng yếu.
      p.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
      await s.setParameters(p);
    } catch (e) {
      debugPrint('[rc] quality: $e');
    }
  }

  @override
  Future<void> close() async {
    await super.close();
    final s = _stream;
    _stream = null;
    if (s != null) await _dispose(s);
  }
}

/// Máy điều khiển: nhận hình, gửi thao tác.
class RcViewerPeer extends RcPeer {
  final RTCVideoRenderer renderer;

  /// Tin từ máy bị điều khiển (danh sách màn hình).
  final void Function(String msg)? onHostMessage;

  RcViewerPeer({required super.iceServers, required super.onSignal, required super.onState, required this.renderer, this.onHostMessage});

  Future<void> start() async {
    await _create();
    dc!.onMessage = (m) {
      if (!m.isBinary) onHostMessage?.call(m.text);
    };
    pc!.onTrack = (e) {
      if (e.track.kind == 'video' && e.streams.isNotEmpty) renderer.srcObject = e.streams.first;
    };
  }
}
