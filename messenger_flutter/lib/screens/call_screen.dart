import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import '../services/call_state.dart';
import '../services/signaling_service.dart';
import '../services/auth_service.dart';

class CallScreen extends StatefulWidget {
  final String callId;

  /// For 1-on-1: the remote user's ID.
  /// For group outgoing: the first participant (rest in [groupParticipantIds]).
  final String peerId;
  final String peerName;
  final bool isVideo;

  /// true = we initiated the call; false = we received it.
  final bool isOutgoing;

  final bool isGroup;

  /// All participant IDs for a group call (excluding self).
  final List<String> groupParticipantIds;
  final List<String> groupParticipantNames;

  /// chatId used when starting a group call.
  final String? chatId;

  /// Может ли текущий пользователь говорить.
  /// В сообществах по умолчанию false для не-администраторов.
  final bool canSpeak;

  final SignalingService signalingService;
  final AuthService auth;

  const CallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.isVideo,
    required this.isOutgoing,
    required this.signalingService,
    required this.auth,
    this.isGroup = false,
    this.groupParticipantIds = const [],
    this.groupParticipantNames = const [],
    this.chatId,
    this.canSpeak = true,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  late final CallService _callService;
  CallStatus _status = CallStatus.idle;
  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;

  // Active participants in a group call
  final Map<String, String> _participants = {}; // userId → name

  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _callTimer;
  int _elapsedSeconds = 0;

  // Drag position of the local video overlay
  Offset _localVideoOffset = const Offset(16, 16);

  late AnimationController _fadeCtrl;
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1,
    );
    _callService = CallService();
    _initCall();
  }

  Future<void> _initCall() async {
    setState(() => _status = CallStatus.calling);
    try {
      // Запрашиваем ICE-серверы у сервера; при ошибке используется fallback.
      final iceServers = await widget.signalingService.fetchIceServers();
      _callService.setIceServers(iceServers);

      await _callService.initialize();
      await _callService.getUserMedia(video: widget.isVideo);
      // В сообществах: если пользователь не может говорить — сразу глушим микрофон.
      if (!widget.canSpeak) {
        _callService.toggleMute(); // включаем mute
        if (mounted) setState(() => _isMuted = true);
      }
      _subscribeToSignaling();

      if (widget.isOutgoing) {
        await _startOutgoing();
      } else {
        await _acceptIncoming();
      }
    } catch (e) {
      if (mounted) setState(() => _status = CallStatus.failed);
    }
  }

  void _subscribeToSignaling() {
    _subs.add(widget.signalingService.onOffer.listen(_handleOffer));
    _subs.add(widget.signalingService.onAnswer.listen(_handleAnswer));
    _subs.add(widget.signalingService.onIceCandidate.listen(_handleIceCandidate));
    _subs.add(widget.signalingService.onCallEnded.listen(_handleCallEnded));
    _subs.add(widget.signalingService.onParticipantJoined.listen(_handleParticipantJoined));
    _subs.add(widget.signalingService.onParticipantLeft.listen(_handleParticipantLeft));
    _subs.add(_callService.remoteStreams.listen(_handleRemoteStream));
    _subs.add(_callService.connectionStates.listen(_handleConnectionState));
  }

  // ── Outgoing call ─────────────────────────────────────────────────────────

  // ignore: avoid_print
  void _log(String msg) => print('[CallScreen] $msg');

  Future<void> _startOutgoing() async {
    setState(() => _status = CallStatus.calling);
    _log('startOutgoing callId=${widget.callId} peerId=${widget.peerId} isGroup=${widget.isGroup}');

    if (widget.isGroup) {
      // Notify server; server sends IncomingCall to all participants
      await widget.signalingService.startCall(
        callId: widget.callId,
        targetUserIds: [widget.peerId, ...widget.groupParticipantIds],
        isVideo: widget.isVideo,
        isGroup: true,
        chatId: widget.chatId,
      );
      // Add known participants to local map
      _participants[widget.peerId] = widget.peerName;
      for (var i = 0; i < widget.groupParticipantIds.length; i++) {
        final id = widget.groupParticipantIds[i];
        _participants[id] =
            i < widget.groupParticipantNames.length
                ? widget.groupParticipantNames[i]
                : id;
      }
    } else {
      // 1-on-1: только уведомляем сервер. Offer будет отправлен в
      // _handleParticipantJoined, когда собеседник примет звонок и
      // вызовет JoinCall. К тому моменту его подписка на onOffer уже
      // будет активна, поэтому offer гарантированно не потеряется.
      await widget.signalingService.startCall(
        callId: widget.callId,
        targetUserIds: [widget.peerId],
        isVideo: widget.isVideo,
      );
    }
  }

  // ── Incoming call ─────────────────────────────────────────────────────────

  Future<void> _acceptIncoming() async {
    _log('acceptIncoming callId=${widget.callId} peerId=${widget.peerId}');
    setState(() => _status = CallStatus.ringing);
    // Signal server that we're joining
    await widget.signalingService.joinCall(widget.callId);
    _log('acceptIncoming: joinCall sent');
    // Offer will arrive via ReceiveOffer event — handled in _handleOffer
    setState(() => _status = CallStatus.calling);
  }

  // ── Signaling handlers ────────────────────────────────────────────────────

  Future<void> _handleOffer(OfferData data) async {
    _log('handleOffer from=${data.fromUserId} callId=${data.callId} myCallId=${widget.callId}');
    if (data.callId != widget.callId) return;
    final fromId = data.fromUserId;

    // Подписываемся ДО initPeerConnection, чтобы не потерять ICE-кандидаты,
    // собранные во время createAnswer / setLocalDescription.
    _subs.add(_callService.iceCandidates.listen((e) {
      if (e.peerId == fromId) {
        widget.signalingService.sendIceCandidate(
          callId: widget.callId,
          targetUserId: fromId,
          candidate: e.candidate,
        );
      }
    }));

    await _callService.initPeerConnection(fromId);

    final sdp = RTCSessionDescription(data.sdp, data.type);
    await _callService.setRemoteDescription(fromId, sdp);
    final answer = await _callService.createAnswer(fromId);

    await widget.signalingService.sendAnswer(
      callId: widget.callId,
      targetUserId: fromId,
      sdp: answer,
    );
  }

  Future<void> _handleAnswer(AnswerData data) async {
    _log('handleAnswer from=${data.fromUserId} callId=${data.callId}');
    if (data.callId != widget.callId) return;
    final sdp = RTCSessionDescription(data.sdp, data.type);
    await _callService.setRemoteDescription(data.fromUserId, sdp);
  }

  Future<void> _handleIceCandidate(IceCandidateData data) async {
    if (data.callId != widget.callId) return;
    final candidate = RTCIceCandidate(
      data.candidate,
      data.sdpMid,
      data.sdpMLineIndex,
    );
    await _callService.addIceCandidate(data.fromUserId, candidate);
  }

  void _handleCallEnded(String callId) {
    if (callId != widget.callId) return;
    if (mounted) {
      setState(() => _status = CallStatus.ended);
      Future.delayed(const Duration(seconds: 2), _leaveScreen);
    }
  }

  Future<void> _handleParticipantJoined(ParticipantEvent event) async {
    _log('handleParticipantJoined userId=${event.userId} callId=${event.callId} myCallId=${widget.callId}');
    if (event.callId != widget.callId) return;
    final myId = widget.auth.currentUser?.id ?? '';
    _log('handleParticipantJoined myId=$myId — proceeding=${event.userId != myId}');
    if (event.userId == myId) return;

    setState(() => _participants[event.userId] = event.name);

    // Подписываемся ДО initPeerConnection, чтобы не потерять ICE-кандидаты
    _subs.add(_callService.iceCandidates.listen((e) {
      if (e.peerId == event.userId) {
        widget.signalingService.sendIceCandidate(
          callId: widget.callId,
          targetUserId: e.peerId,
          candidate: e.candidate,
        );
      }
    }));

    await _callService.initPeerConnection(event.userId);
    final offer = await _callService.createOffer(event.userId);
    await widget.signalingService.sendOffer(
      callId: widget.callId,
      targetUserId: event.userId,
      sdp: offer,
    );
  }

  void _handleParticipantLeft(ParticipantEvent event) {
    if (event.callId != widget.callId) return;
    setState(() => _participants.remove(event.userId));
    _callService.closePeerConnection(event.userId);

    // В 1-на-1 звонке: собеседник ушёл — завершаем звонок.
    // (В группе один уход не прерывает сессию.)
    if (!widget.isGroup) {
      setState(() => _status = CallStatus.ended);
      Future.delayed(const Duration(seconds: 1), _leaveScreen);
    }
  }

  void _handleRemoteStream(({String peerId, MediaStream stream}) e) {
    _callService.setRemoteStream(e.peerId, e.stream);
    if (mounted) setState(() {});
  }

  void _handleConnectionState(
      ({String peerId, RTCPeerConnectionState state}) e) {
    _log('connectionState peer=${e.peerId} state=${e.state}');
    if (!mounted) return;
    if (e.state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      setState(() => _status = CallStatus.connected);
      _startTimer();
    } else if (e.state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      setState(() => _status = CallStatus.failed);
    }
  }

  void _startTimer() {
    _callTimer?.cancel();
    _elapsedSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void _toggleMute() {
    _callService.toggleMute();
    setState(() => _isMuted = _callService.isMuted);
  }

  void _toggleCamera() {
    _callService.toggleCamera();
    setState(() => _isCameraOff = _callService.isCameraOff);
  }

  Future<void> _switchCamera() async {
    await _callService.switchCamera();
    setState(() => _isFrontCamera = _callService.isFrontCamera);
  }

  Future<void> _endCall() async {
    await widget.signalingService.leaveCall(widget.callId);
    setState(() => _status = CallStatus.ended);
    await _leaveScreen();
  }

  Future<void> _leaveScreen() async {
    if (mounted) Navigator.of(context).pop();
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _fadeCtrl.forward();
    }
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _status == CallStatus.connected && widget.isVideo) {
        setState(() => _controlsVisible = false);
        _fadeCtrl.reverse();
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _timerLabel {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusLabel => switch (_status) {
        CallStatus.calling   => 'Исходящий…',
        CallStatus.ringing   => 'Подключение…',
        CallStatus.connected => _timerLabel,
        CallStatus.ended     => 'Звонок завершён',
        CallStatus.failed    => 'Нет соединения',
        _                    => '',
      };

  @override
  void dispose() {
    _callTimer?.cancel();
    _controlsTimer?.cancel();
    _fadeCtrl.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _callService.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: widget.isVideo ? _resetControlsTimer : null,
        child: Stack(
          children: [
            // ── Remote video / avatar ──────────────────────────────
            _buildMainContent(),

            // ── Local video overlay ────────────────────────────────
            if (widget.isVideo) _buildLocalVideoOverlay(),

            // ── Top bar ────────────────────────────────────────────
            _buildTopBar(),

            // ── Control buttons ────────────────────────────────────
            _buildControlBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (widget.isGroup && _participants.isNotEmpty) {
      return _buildGroupGrid();
    }
    if (widget.isVideo &&
        _callService.remoteRenderers.containsKey(widget.peerId)) {
      return Positioned.fill(
        child: RTCVideoView(
          _callService.remoteRenderers[widget.peerId]!,
          // contain сохраняет ориентацию видео без обрезки:
          // портрет остаётся портретом, ландшафт — ландшафтом.
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        ),
      );
    }
    return _buildAvatarBackground();
  }

  Widget _buildAvatarBackground() {
    final showStatus = _status != CallStatus.connected;
    // Для группового звонка показываем нейтральный аватар и "Групповой звонок"
    final displayName = widget.isGroup ? 'Групповой звонок' : widget.peerName;
    final avatarLetter = widget.isGroup ? '👥' : (widget.peerName.isNotEmpty
        ? widget.peerName[0].toUpperCase()
        : '?');
    final isPulsing = _status == CallStatus.calling || _status == CallStatus.ringing;

    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Пульсирующее кольцо
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding: EdgeInsets.all(isPulsing ? 14 : 0),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPulsing
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.transparent,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  padding: EdgeInsets.all(isPulsing ? 8 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPulsing
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.transparent,
                  ),
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: widget.isGroup
                        ? const Color(0xFF1565C0)
                        : const Color(0xFF0F3460),
                    child: widget.isGroup
                        ? const Text('👥',
                            style: TextStyle(fontSize: 44))
                        : Text(
                            avatarLetter,
                            style: const TextStyle(
                                fontSize: 48,
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                displayName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              if (showStatus) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPulsing) ...[
                      _PulsingDot(),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _statusLabel,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      widget.isVideo ? Icons.videocam : Icons.call,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ],
                ),
              ],
              // Предупреждение для пользователей без права голоса
              if (!widget.canSpeak) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_off, color: Colors.orange, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Только прослушивание',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupGrid() {
    final peers = _participants.keys.toList();
    return Positioned.fill(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: peers.length == 1 ? 1 : 2,
        ),
        itemCount: peers.length,
        itemBuilder: (_, i) {
          final peerId = peers[i];
          final name = _participants[peerId] ?? peerId;
          final renderer = _callService.remoteRenderers[peerId];
          return Stack(
            fit: StackFit.expand,
            children: [
              if (renderer != null && widget.isVideo)
                RTCVideoView(renderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
              else
                Container(
                  color: Colors.blueGrey[900],
                  child: Center(
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.blueGrey[700],
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(name,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLocalVideoOverlay() {
    final size = MediaQuery.of(context).size;
    const w = 100.0;
    const h = 140.0;

    return Positioned(
      right: _localVideoOffset.dx,
      bottom: _localVideoOffset.dy + 100,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _localVideoOffset = Offset(
              (_localVideoOffset.dx - d.delta.dx).clamp(0, size.width - w),
              (_localVideoOffset.dy - d.delta.dy).clamp(0, size.height - h),
            );
          });
        },
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 8)
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: _isCameraOff
              ? Container(
                  color: Colors.blueGrey[900],
                  child: const Icon(Icons.videocam_off,
                      color: Colors.white54, size: 32),
                )
              : RTCVideoView(
                  _callService.localRenderer,
                  mirror: _isFrontCamera,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeCtrl,
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            bottom: 16,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isGroup ? 'Групповой звонок' : widget.peerName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                    if (_statusLabel.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Зелёная точка когда подключено
                          if (_status == CallStatus.connected) ...[
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF4CAF50),
                              ),
                            ),
                          ],
                          Text(
                            _statusLabel,
                            style: TextStyle(
                                color: _status == CallStatus.connected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.75),
                                fontSize: 13,
                                fontWeight: _status == CallStatus.connected
                                    ? FontWeight.w600
                                    : FontWeight.normal),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (widget.isGroup)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '👥 ${_participants.length + 1}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeCtrl,
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            top: 24,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Микрофон: заблокирован если !canSpeak
              Tooltip(
                message: !widget.canSpeak ? 'В сообществе говорить могут только администраторы' : '',
                child: _ControlButton(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  label: _isMuted ? 'Вкл. мик.' : 'Выкл. мик.',
                  onTap: widget.canSpeak ? _toggleMute : () {},
                  active: _isMuted,
                  locked: !widget.canSpeak,
                ),
              ),
              if (widget.isVideo) ...[
                _ControlButton(
                  icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                  label: _isCameraOff ? 'Вкл. камеру' : 'Выкл. камеру',
                  onTap: _toggleCamera,
                  active: _isCameraOff,
                ),
                _ControlButton(
                  icon: Icons.flip_camera_ios,
                  label: 'Перевернуть',
                  onTap: _switchCamera,
                ),
              ],
              _EndCallButton(onTap: _endCall),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable control button ──────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool locked;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: locked ? 0.4 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.15),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon,
                      color: active ? Colors.black87 : Colors.white, size: 26),
                  if (locked)
                    Positioned(
                      right: 6, bottom: 6,
                      child: Container(
                        width: 14, height: 14,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.orange,
                        ),
                        child: const Icon(Icons.lock, size: 9, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── Пульсирующая точка статуса ────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(
            shape: BoxShape.circle, color: Colors.white54),
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 6),
          const Text('Завершить',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Incoming call overlay ────────────────────────────────────────────────────

class IncomingCallOverlay extends StatefulWidget {
  final IncomingCallInfo callInfo;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallOverlay({
    super.key,
    required this.callInfo,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.callInfo.callerName;
    final isVideo = widget.callInfo.isVideo;
    final isGroup = widget.callInfo.isGroup;
    final callTypeLabel = isGroup
        ? 'Групповой ${isVideo ? 'видео' : 'аудио'}звонок'
        : 'Входящий ${isVideo ? 'видео' : 'аудио'}звонок';

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D1B2A), Color(0xFF1B2838)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Аватар с пульсирующим кольцом ────────────────────────
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, child) => Stack(
                  alignment: Alignment.center,
                  children: [
                    // Внешнее кольцо
                    Container(
                      width: 140 + 20 * _pulseCtrl.value,
                      height: 140 + 20 * _pulseCtrl.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white
                            .withValues(alpha: 0.04 * (1 - _pulseCtrl.value)),
                      ),
                    ),
                    // Среднее кольцо
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white
                            .withValues(alpha: 0.06 * (1 - _pulseCtrl.value * 0.5)),
                      ),
                    ),
                    child!,
                  ],
                ),
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: isGroup
                      ? const Color(0xFF1565C0)
                      : const Color(0xFF0F3460),
                  child: isGroup
                      ? const Text('👥', style: TextStyle(fontSize: 40))
                      : Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              fontSize: 44,
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Имя ───────────────────────────────────────────────────
              Text(
                name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),

              // ── Тип звонка ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam_outlined : Icons.call_outlined,
                      color: Colors.white70, size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      callTypeLabel,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 14),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // ── Кнопки ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _RingButton(
                      icon: Icons.call_end,
                      color: const Color(0xFFE53935),
                      label: 'Отклонить',
                      onTap: widget.onDecline,
                    ),
                    _RingButton(
                      icon: isVideo ? Icons.videocam : Icons.call,
                      color: const Color(0xFF43A047),
                      label: 'Принять',
                      onTap: widget.onAccept,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RingButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }
}
