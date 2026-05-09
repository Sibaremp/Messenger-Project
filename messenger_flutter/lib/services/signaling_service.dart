import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:signalr_netcore/signalr_client.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'call_state.dart';

class SignalingService {
  final AuthService _auth;

  HubConnection? _hub;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final _incomingCallCtrl =
      StreamController<IncomingCallInfo>.broadcast();
  final _offerCtrl = StreamController<OfferData>.broadcast();
  final _answerCtrl = StreamController<AnswerData>.broadcast();
  final _iceCandidateCtrl =
      StreamController<IceCandidateData>.broadcast();
  final _callEndedCtrl = StreamController<String>.broadcast();
  final _participantJoinedCtrl =
      StreamController<ParticipantEvent>.broadcast();
  final _participantLeftCtrl =
      StreamController<ParticipantEvent>.broadcast();

  Stream<IncomingCallInfo> get onIncomingCall => _incomingCallCtrl.stream;
  Stream<OfferData> get onOffer => _offerCtrl.stream;
  Stream<AnswerData> get onAnswer => _answerCtrl.stream;
  Stream<IceCandidateData> get onIceCandidate => _iceCandidateCtrl.stream;
  // Emits callId of the call that ended
  Stream<String> get onCallEnded => _callEndedCtrl.stream;
  Stream<ParticipantEvent> get onParticipantJoined =>
      _participantJoinedCtrl.stream;
  Stream<ParticipantEvent> get onParticipantLeft =>
      _participantLeftCtrl.stream;

  bool get isConnected =>
      _hub?.state == HubConnectionState.Connected;

  SignalingService(this._auth) {
    _connect();
  }

  void _connect() {
    if (_disposed || _auth.token == null) return;
    try {
      _hub = HubConnectionBuilder()
          .withUrl(
            ApiConfig.callHubUrl,
            options: HttpConnectionOptions(
              accessTokenFactory: () async => _auth.token ?? '',
            ),
          )
          .build();

      _hub!.on('IncomingCall', _onIncomingCall);
      _hub!.on('ReceiveOffer', _onReceiveOffer);
      _hub!.on('ReceiveAnswer', _onReceiveAnswer);
      _hub!.on('ReceiveIceCandidate', _onReceiveIceCandidate);
      _hub!.on('CallEnded', _onCallEnded);
      _hub!.on('ParticipantJoined', _onParticipantJoined);
      _hub!.on('ParticipantLeft', _onParticipantLeft);

      _hub!.onclose(({error}) => _scheduleReconnect());
      _hub!.start()?.catchError((_) => _scheduleReconnect());
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(ApiConfig.wsReconnectDelay, _connect);
  }

  void _onIncomingCall(List<Object?>? args) {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null || _incomingCallCtrl.isClosed) return;
      _incomingCallCtrl.add(IncomingCallInfo.fromMap(data));
    } catch (e) { _log('IncomingCall parse error: $e  args=$args'); }
  }

  void _onReceiveOffer(List<Object?>? args) {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null || _offerCtrl.isClosed) return;
      _offerCtrl.add(OfferData.fromMap(data));
    } catch (e) { _log('ReceiveOffer parse error: $e  args=$args'); }
  }

  void _onReceiveAnswer(List<Object?>? args) {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null || _answerCtrl.isClosed) return;
      _answerCtrl.add(AnswerData.fromMap(data));
    } catch (e) { _log('ReceiveAnswer parse error: $e  args=$args'); }
  }

  void _onReceiveIceCandidate(List<Object?>? args) {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null || _iceCandidateCtrl.isClosed) return;
      _iceCandidateCtrl.add(IceCandidateData.fromMap(data));
    } catch (e) { _log('ReceiveIceCandidate parse error: $e  args=$args'); }
  }

  void _onCallEnded(List<Object?>? args) {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null || _callEndedCtrl.isClosed) return;
      _callEndedCtrl.add(data['callId'] as String);
    } catch (e) { _log('CallEnded parse error: $e  args=$args'); }
  }

  void _onParticipantJoined(List<Object?>? args) {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null || _participantJoinedCtrl.isClosed) return;
      _log('ParticipantJoined: $data');
      _participantJoinedCtrl.add(ParticipantEvent.fromMap(data));
    } catch (e) { _log('ParticipantJoined parse error: $e  args=$args'); }
  }

  void _onParticipantLeft(List<Object?>? args) {
    try {
      final data = args?.first as Map<String, dynamic>?;
      if (data == null || _participantLeftCtrl.isClosed) return;
      _participantLeftCtrl.add(ParticipantEvent.fromMap(data));
    } catch (e) { _log('ParticipantLeft parse error: $e  args=$args'); }
  }

  // ignore: avoid_print
  void _log(String msg) => print('[SignalingService] $msg');

  // ── REST helpers ──────────────────────────────────────────────────────────

  /// Получает список ICE-серверов с сервера (GET /api/calls/ice-servers).
  /// При любой ошибке возвращает пустой список — вызывающий код должен
  /// использовать fallback (публичные STUN Google).
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    try {
      final r = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/calls/ice-servers'),
        headers: {
          'Authorization': 'Bearer ${_auth.token ?? ""}',
          'Content-Type': 'application/json',
        },
      ).timeout(ApiConfig.httpTimeout);
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final list = data['iceServers'] as List<dynamic>?;
        if (list != null && list.isNotEmpty) {
          return list.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  // ── Hub invocations ───────────────────────────────────────────────────────

  Future<void> startCall({
    required String callId,
    required List<String> targetUserIds,
    required bool isVideo,
    bool isGroup = false,
    String? chatId,
  }) async {
    await _hub?.invoke('StartCall', args: [
      {
        'callId': callId,
        'targetUserIds': targetUserIds,
        'isVideo': isVideo,
        'isGroup': isGroup,
        if (chatId != null) 'chatId': chatId,
      }
    ]);
  }

  Future<void> joinCall(String callId) async {
    await _hub?.invoke('JoinCall', args: [callId]);
  }

  Future<void> leaveCall(String callId) async {
    await _hub?.invoke('LeaveCall', args: [callId]);
  }

  Future<void> sendOffer({
    required String callId,
    required String targetUserId,
    required RTCSessionDescription sdp,
  }) async {
    await _hub?.invoke('SendOffer', args: [
      {
        'callId': callId,
        'targetUserId': targetUserId,
        'sdp': sdp.sdp,
        'type': sdp.type,
      }
    ]);
  }

  Future<void> sendAnswer({
    required String callId,
    required String targetUserId,
    required RTCSessionDescription sdp,
  }) async {
    await _hub?.invoke('SendAnswer', args: [
      {
        'callId': callId,
        'targetUserId': targetUserId,
        'sdp': sdp.sdp,
        'type': sdp.type,
      }
    ]);
  }

  Future<void> sendIceCandidate({
    required String callId,
    required String targetUserId,
    required RTCIceCandidate candidate,
  }) async {
    if (candidate.candidate == null) return;
    await _hub?.invoke('SendIceCandidate', args: [
      {
        'callId': callId,
        'targetUserId': targetUserId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid ?? '0',
        'sdpMLineIndex': candidate.sdpMLineIndex ?? 0,
      }
    ]);
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _hub?.stop();
    if (!_incomingCallCtrl.isClosed) await _incomingCallCtrl.close();
    if (!_offerCtrl.isClosed) await _offerCtrl.close();
    if (!_answerCtrl.isClosed) await _answerCtrl.close();
    if (!_iceCandidateCtrl.isClosed) await _iceCandidateCtrl.close();
    if (!_callEndedCtrl.isClosed) await _callEndedCtrl.close();
    if (!_participantJoinedCtrl.isClosed) await _participantJoinedCtrl.close();
    if (!_participantLeftCtrl.isClosed) await _participantLeftCtrl.close();
  }
}
