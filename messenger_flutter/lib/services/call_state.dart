enum CallStatus { idle, calling, ringing, connected, ended, failed }

class CallParticipant {
  final String userId;
  final String name;
  final bool isMuted;
  final bool isCameraOff;

  const CallParticipant({
    required this.userId,
    required this.name,
    this.isMuted = false,
    this.isCameraOff = false,
  });

  CallParticipant copyWith({
    bool? isMuted,
    bool? isCameraOff,
  }) =>
      CallParticipant(
        userId: userId,
        name: name,
        isMuted: isMuted ?? this.isMuted,
        isCameraOff: isCameraOff ?? this.isCameraOff,
      );
}

class IncomingCallInfo {
  final String callId;
  final String callerId;
  final String callerName;
  final bool isVideo;
  final bool isGroup;
  final String? callerAvatarUrl;
  final String? chatId;

  const IncomingCallInfo({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.isVideo,
    this.isGroup = false,
    this.callerAvatarUrl,
    this.chatId,
  });

  factory IncomingCallInfo.fromMap(Map<String, dynamic> m) => IncomingCallInfo(
        callId: m['callId'] as String,
        callerId: m['callerId'] as String,
        callerName: m['callerName'] as String,
        isVideo: m['isVideo'] as bool? ?? false,
        isGroup: m['isGroup'] as bool? ?? false,
        callerAvatarUrl: m['callerAvatarUrl'] as String?,
        chatId: m['chatId'] as String?,
      );
}

class OfferData {
  final String callId;
  final String fromUserId;
  final String sdp;
  final String type;

  const OfferData({
    required this.callId,
    required this.fromUserId,
    required this.sdp,
    required this.type,
  });

  factory OfferData.fromMap(Map<String, dynamic> m) => OfferData(
        callId: m['callId'] as String,
        fromUserId: m['fromUserId'] as String,
        sdp: m['sdp'] as String,
        type: m['type'] as String,
      );
}

class AnswerData {
  final String callId;
  final String fromUserId;
  final String sdp;
  final String type;

  const AnswerData({
    required this.callId,
    required this.fromUserId,
    required this.sdp,
    required this.type,
  });

  factory AnswerData.fromMap(Map<String, dynamic> m) => AnswerData(
        callId: m['callId'] as String,
        fromUserId: m['fromUserId'] as String,
        sdp: m['sdp'] as String,
        type: m['type'] as String,
      );
}

class IceCandidateData {
  final String callId;
  final String fromUserId;
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;

  const IceCandidateData({
    required this.callId,
    required this.fromUserId,
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  factory IceCandidateData.fromMap(Map<String, dynamic> m) => IceCandidateData(
        callId: m['callId'] as String,
        fromUserId: m['fromUserId'] as String,
        candidate: m['candidate'] as String,
        sdpMid: m['sdpMid'] as String? ?? '0',
        sdpMLineIndex: (m['sdpMLineIndex'] as num?)?.toInt() ?? 0,
      );
}

class ParticipantEvent {
  final String callId;
  final String userId;
  final String name;

  const ParticipantEvent({
    required this.callId,
    required this.userId,
    required this.name,
  });

  factory ParticipantEvent.fromMap(Map<String, dynamic> m) => ParticipantEvent(
        callId: m['callId'] as String,
        userId: m['userId'] as String,
        name: m['name'] as String? ?? m['userId'] as String,
      );
}
