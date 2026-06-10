import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallService {
  /// ICE-конфигурация для WebRTC. Обновляется через [setIceServers]
  /// значениями, полученными от сервера (GET /api/calls/ice-servers).
  /// Fallback — публичные STUN Google/Cloudflare.
  Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun.cloudflare.com:3478'},
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
  };

  /// Заменяет список ICE-серверов значениями с сервера.
  /// Вызывается из [CallScreen] до [initPeerConnection].
  void setIceServers(List<Map<String, dynamic>> servers) {
    if (servers.isEmpty) return;
    _iceConfig = {
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 10,
    };
  }

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peerConnections = {};

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> remoteRenderers = {};

  // Buffered candidates received before the peer connection was initialized
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _isSpeaker = true;
  bool _initialized = false;

  final _iceCandidateCtrl =
      StreamController<({String peerId, RTCIceCandidate candidate})>.broadcast();
  final _remoteStreamCtrl =
      StreamController<({String peerId, MediaStream stream})>.broadcast();
  final _connectionStateCtrl =
      StreamController<({String peerId, RTCPeerConnectionState state})>.broadcast();

  Stream<({String peerId, RTCIceCandidate candidate})> get iceCandidates =>
      _iceCandidateCtrl.stream;
  Stream<({String peerId, MediaStream stream})> get remoteStreams =>
      _remoteStreamCtrl.stream;
  Stream<({String peerId, RTCPeerConnectionState state})> get connectionStates =>
      _connectionStateCtrl.stream;

  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  bool get isFrontCamera => _isFrontCamera;
  bool get isSpeaker => _isSpeaker;
  MediaStream? get localStream => _localStream;

  bool hasPeerConnection(String peerId) => _peerConnections.containsKey(peerId);

  Future<void> initialize() async {
    if (_initialized) return;
    await localRenderer.initialize();
    _initialized = true;
  }

  Future<void> getUserMedia({required bool video}) async {
    // Сначала пробуем с видео (если нужно). Если не работает — пробуем только аудио.
    // На веб-браузере камера может быть не подключена или заблокирована.
    final audioConstraints = <String, dynamic>{
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
      'sampleRate': 48000,
    };
    final constraints = <String, dynamic>{
      'audio': audioConstraints,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    } catch (e) {
      if (video) {
        // Видеокамера недоступна — пробуем только аудио
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': true,
            'video': false,
          });
        } catch (audioErr) {
          // Даже аудио недоступно (web без разрешения или нет устройства)
          // Создаём пустой стрим чтобы не падать
          _localStream = await createLocalMediaStream('empty');
        }
      } else {
        // Только аудио уже запрашивали, но не получили
        _localStream = await createLocalMediaStream('empty');
      }
    }
    localRenderer.srcObject = _localStream;
  }

  Future<RTCPeerConnection> initPeerConnection(String peerId) async {
    // Close existing connection for this peer if any
    await closePeerConnection(peerId);

    final pc = await createPeerConnection(_iceConfig);
    _peerConnections[peerId] = pc;

    // Add local tracks to the new peer connection
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null && !_iceCandidateCtrl.isClosed) {
        _iceCandidateCtrl.add((peerId: peerId, candidate: candidate));
      }
    };

    pc.onTrack = (event) {
      if (event.streams.isNotEmpty && !_remoteStreamCtrl.isClosed) {
        _remoteStreamCtrl.add((peerId: peerId, stream: event.streams[0]));
      }
    };

    pc.onConnectionState = (state) {
      if (!_connectionStateCtrl.isClosed) {
        _connectionStateCtrl.add((peerId: peerId, state: state));
      }
    };

    // Initialize renderer for this peer
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    remoteRenderers[peerId] = renderer;

    // Flush any candidates that arrived before the connection was ready
    final pending = _pendingCandidates.remove(peerId) ?? [];
    for (final c in pending) {
      await pc.addCandidate(c);
    }

    return pc;
  }

  Future<RTCSessionDescription> createOffer(String peerId) async {
    final pc = _peerConnections[peerId]!;
    final offer = await pc.createOffer(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await pc.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer(String peerId) async {
    final pc = _peerConnections[peerId]!;
    final answer = await pc.createAnswer(<String, dynamic>{});
    await pc.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(
      String peerId, RTCSessionDescription sdp) async {
    final pc = _peerConnections[peerId]!;
    await pc.setRemoteDescription(sdp);
  }

  Future<void> addIceCandidate(
      String peerId, RTCIceCandidate candidate) async {
    final pc = _peerConnections[peerId];
    if (pc != null) {
      await pc.addCandidate(candidate);
    } else {
      // Buffer until peer connection is ready
      _pendingCandidates.putIfAbsent(peerId, () => []).add(candidate);
    }
  }

  void setRemoteStream(String peerId, MediaStream stream) {
    remoteRenderers[peerId]?.srcObject = stream;
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMuted);
  }

  void toggleCamera() {
    _isCameraOff = !_isCameraOff;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !_isCameraOff);
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
    _isFrontCamera = !_isFrontCamera;
  }

  /// Возвращает список доступных аудиовыходов (наушники, динамик, BT и т.д.)
  Future<List<MediaDeviceInfo>> getAudioOutputDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      return devices.where((d) => d.kind == 'audiooutput').toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> selectAudioOutput(String deviceId) async {
    try {
      await Helper.selectAudioOutput(deviceId);
      _isSpeaker = true;
    } catch (_) {}
  }

  Future<bool> toggleSpeaker() async {
    _isSpeaker = !_isSpeaker;
    try {
      // Мобильные платформы: переключаем динамик/трубку
      await Helper.setSpeakerphoneOn(_isSpeaker);
      return true; // сработало
    } catch (_) {
      // На десктопе setSpeakerphoneOn не работает — откатываем флаг
      _isSpeaker = !_isSpeaker;
      return false; // не поддерживается
    }
  }

  Future<void> closePeerConnection(String peerId) async {
    final pc = _peerConnections.remove(peerId);
    if (pc != null) await pc.close();
    final renderer = remoteRenderers.remove(peerId);
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
    _pendingCandidates.remove(peerId);
  }

  Future<void> dispose() async {
    for (final pc in _peerConnections.values) {
      await pc.close();
    }
    _peerConnections.clear();

    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;
    localRenderer.srcObject = null;
    await localRenderer.dispose();

    for (final r in remoteRenderers.values) {
      r.srcObject = null;
      await r.dispose();
    }
    remoteRenderers.clear();
    _pendingCandidates.clear();
    _initialized = false;

    if (!_iceCandidateCtrl.isClosed) await _iceCandidateCtrl.close();
    if (!_remoteStreamCtrl.isClosed) await _remoteStreamCtrl.close();
    if (!_connectionStateCtrl.isClosed) await _connectionStateCtrl.close();
  }
}
