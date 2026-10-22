// =========================================================================
// 🎧 LIVE ROOM — our own audio classes on LiveKit (replaces Stream Video)
//
// This file gives the SAME names the class screens already use
// (StreamVideo, Call, CallState, CallParticipantState, CallConnectOptions …),
// so the screens and their UI stay exactly as they are. Only the import
// line changes:
//   import 'package:stream_video_flutter/stream_video_flutter.dart';
//   →  import 'package:letsspeak_trainer/rtc/live_room.dart';
//
// Under the hood:
//   • join          → our server gives a LiveKit token for that class → connect
//   • mic on/off    → LiveKit microphone (audio only, camera never used)
//   • update(custom)→ trainer's mic lock + practice state → room metadata
//   • kick / mute / end → our server (only trainers and admins may)
// Made for big classes: audio only, silence is not sent (DTX), screen updates
// are batched so 2,000 people in one room don't freeze the phone.
// =========================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'package:letsspeak_trainer/Api/Apiend_points.dart';

// -------------------------------------------------------------------------
// Server calls (login token from storage, same as the rest of the app)
// -------------------------------------------------------------------------
Map<String, String> _headers() {
  final t = (GetStorage().read('token') ?? '').toString();
  return {
    'Content-Type': 'application/json',
    if (t.isNotEmpty) 'Authorization': 'Bearer $t',
  };
}

Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
  final res = await http
      .post(Uri.parse('${ApiEndpoints.baseUrl}$path'), headers: _headers(), body: jsonEncode(body))
      .timeout(const Duration(seconds: 20));
  Map<String, dynamic> data = {};
  try {
    final d = jsonDecode(res.body);
    if (d is Map) data = Map<String, dynamic>.from(d);
  } catch (_) {}
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception((data['error'] ?? data['message'] ?? 'Server error ${res.statusCode}').toString());
  }
  return data;
}

// -------------------------------------------------------------------------
// Small types with the old names
// -------------------------------------------------------------------------
enum Priority { verbose, debug, info, warning, error }

enum TrackType { audio, video, screenShare }

class StreamVideoOptions {
  final Priority? logPriority;
  const StreamVideoOptions({this.logPriority});
}

class User {
  final String id;
  final String name;
  const User._(this.id, this.name);
  factory User.regular({required String userId, String? name, String? role, String? image}) =>
      User._(userId, name ?? '');
}

class StreamCallType {
  const StreamCallType._();
  factory StreamCallType.defaultType() => const StreamCallType._();
}

class TrackOption {
  final bool isOn;
  const TrackOption._(this.isOn);
  factory TrackOption.enabled() => const TrackOption._(true);
  factory TrackOption.disabled() => const TrackOption._(false);
}

class CallConnectOptions {
  final TrackOption camera;
  final TrackOption microphone;
  const CallConnectOptions({
    this.camera = const TrackOption._(false),
    this.microphone = const TrackOption._(false),
  });
}

class Result<T> {
  final T? data;
  final Object? error;
  const Result._(this.data, this.error);
  static Result<R> success<R>([R? data]) => Result<R>._(data, null);
  static Result<R> failure<R>(Object error) => Result<R>._(null, error);
  bool get isSuccess => error == null;
  bool get isFailure => error != null;
  @override
  String toString() => isSuccess ? 'Success' : 'Failure($error)';
}

class CallStatus {
  final String name; // Idle, Connecting, Connected, Reconnecting, Disconnected
  const CallStatus._(this.name);
  static const idle = CallStatus._('Idle');
  static const connecting = CallStatus._('Connecting');
  static const connected = CallStatus._('Connected');
  static const reconnecting = CallStatus._('Reconnecting');
  static const disconnected = CallStatus._('Disconnected');
  bool get isIdle => name == 'Idle';
  bool get isConnecting => name == 'Connecting';
  bool get isConnected => name == 'Connected';
  bool get isJoined => name == 'Connected';
  bool get isReconnecting => name == 'Reconnecting';
  bool get isDisconnected => name == 'Disconnected';
  @override
  String toString() => 'CallStatus$name';
}

class CallParticipantState {
  final String userId;
  final String name;
  final String sessionId;
  final bool isLocal;
  final bool isSpeaking;
  final bool isAudioEnabled;
  final bool isVideoEnabled;
  final List<String> roles; // ['admin'] = trainer / admin
  final String? image;
  const CallParticipantState({
    required this.userId,
    required this.name,
    required this.sessionId,
    required this.isLocal,
    required this.isSpeaking,
    required this.isAudioEnabled,
    required this.roles,
    this.isVideoEnabled = false,
    this.image,
  });
}

class CallState {
  final String callId;
  final CallStatus status;
  final List<CallParticipantState> callParticipants;
  final Map<String, Object> custom;
  final DateTime? endedAt;
  const CallState({
    required this.callId,
    required this.status,
    required this.callParticipants,
    required this.custom,
    this.endedAt,
  });

  CallParticipantState? get localParticipant {
    for (final p in callParticipants) {
      if (p.isLocal) return p;
    }
    return null;
  }

  int get participantCount => callParticipants.length;
}

/// `call.state.value` and `call.state.asStream()` — like before
class CallStateHolder {
  CallStateHolder(this._value);
  CallState _value;
  final StreamController<CallState> _ctrl = StreamController<CallState>.broadcast();

  CallState get value => _value;
  Stream<CallState> asStream() => _ctrl.stream;
  Stream<CallState> get valueStream => _ctrl.stream;

  void _set(CallState v) {
    _value = v;
    if (!_ctrl.isClosed) _ctrl.add(v);
  }
}

// -------------------------------------------------------------------------
// StreamVideo (the "client") — keeps who is logged in
// -------------------------------------------------------------------------
class StreamVideo {
  final String apiKey;
  final User user;
  static final Set<Call> _active = <Call>{};

  StreamVideo(this.apiKey, {required this.user, String? userToken, StreamVideoOptions? options});

  /// Leaves every open class (e.g. on logout / user change)
  static Future<void> reset({bool disconnect = false}) async {
    if (!disconnect) return;
    for (final c in _active.toList()) {
      await c.leave();
    }
  }

  Call makeCall({required StreamCallType callType, required String id}) => Call._(id, user);
}

// -------------------------------------------------------------------------
// Call — one class (LiveKit room)
// -------------------------------------------------------------------------
class Call {
  Call._(this.id, this._user)
      : state = CallStateHolder(CallState(
          callId: id,
          status: CallStatus.idle,
          callParticipants: const [],
          custom: const {},
        ));

  final String id;
  final User _user;
  final CallStateHolder state;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  CallStatus _status = CallStatus.idle;
  DateTime? _endedAt;
  Map<String, Object> _custom = const {};
  String? _metaText;
  Timer? _emitTimer;
  bool _left = false;

  String get callCid => 'default:$id';
  String get userId => _user.id;

  /// The server creates the class (trainer "start"); nothing to do here.
  Future<Result<void>> getOrCreate() async => Result.success<void>();

  Future<Result<void>> join({CallConnectOptions? connectOptions}) async {
    try {
      _left = false;
      _endedAt = null;
      _status = CallStatus.connecting;
      _emitNow();

      final data = await _post('/rtc/room-token', {'room': id});
      final url = (data['url'] ?? '').toString();
      final token = (data['token'] ?? '').toString();
      if (url.isEmpty || token.isEmpty) throw Exception('Class access missing');

      final room = lk.Room(
        roomOptions: const lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          // 🎧 speech: silence is not sent (dtx) + protection against lost packets (red)
          defaultAudioPublishOptions: lk.AudioPublishOptions(dtx: true, red: true),
        ),
      );
      _room = room;
      final listener = room.createListener();
      _listener = listener;
      listener.listen((event) {
        if (event is lk.RoomDisconnectedEvent) {
          if (event.reason == lk.DisconnectReason.roomDeleted) {
            _endedAt = DateTime.now(); // trainer ended the class for everyone
          }
          _status = CallStatus.disconnected;
          _emitNow();
          return;
        }
        if (event is lk.RoomReconnectingEvent) _status = CallStatus.reconnecting;
        if (event is lk.RoomReconnectedEvent) _status = CallStatus.connected;
        _scheduleEmit();
      });
      room.addListener(_scheduleEmit);

      await room.connect(url, token, connectOptions: const lk.ConnectOptions(autoSubscribe: true));
      _status = CallStatus.connected;
      StreamVideo._active.add(this);
      try {
        await room.setSpeakerOn(true); // 🔊 class on the loudspeaker (headphones / Bluetooth still win)
      } catch (_) {}

      final micOn = connectOptions?.microphone.isOn ?? false;
      if (micOn) {
        try {
          await room.localParticipant?.setMicrophoneEnabled(true);
        } catch (e) {
          debugPrint('Mic start error: $e');
        }
      }
      _emitNow();
      return Result.success<void>();
    } catch (e) {
      debugPrint('LiveKit join error: $e');
      await _closeRoom();
      _status = CallStatus.disconnected;
      _emitNow();
      return Result.failure<void>(e);
    }
  }

  Future<Result<void>> leave() async {
    _left = true;
    await _closeRoom();
    _status = CallStatus.disconnected;
    _emitNow();
    return Result.success<void>();
  }

  Future<void> _closeRoom() async {
    StreamVideo._active.remove(this);
    _emitTimer?.cancel();
    final room = _room;
    final listener = _listener;
    _room = null;
    _listener = null;
    try {
      room?.removeListener(_scheduleEmit);
    } catch (_) {}
    try {
      await listener?.dispose();
    } catch (_) {}
    try {
      await room?.disconnect();
    } catch (_) {}
    try {
      await room?.dispose();
    } catch (_) {}
  }

  Future<Result<void>> setMicrophoneEnabled({required bool enabled}) async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
      _emitNow();
      return Result.success<void>();
    } catch (e) {
      return Result.failure<void>(e);
    }
  }

  /// Audio classes: the camera is never used
  Future<Result<void>> setCameraEnabled({required bool enabled}) async => Result.success<void>();

  /// Trainer: share mic lock + practice state with everyone in the class
  Future<Result<void>> update({Map<String, Object>? custom}) async {
    try {
      final c = custom ?? const <String, Object>{};
      _custom = Map<String, Object>.from(c); // trainer's own screen updates at once
      _emitNow();
      await _post('/rtc/room/state', {'room': id, 'custom': c});
      return Result.success<void>();
    } catch (e) {
      return Result.failure<void>(e);
    }
  }

  Future<Result<void>> kickUser(String userId) async {
    try {
      await _post('/rtc/room/kick', {'room': id, 'userId': userId});
      return Result.success<void>();
    } catch (e) {
      return Result.failure<void>(e);
    }
  }

  Future<Result<void>> muteUsers({required List<String> userIds}) async {
    try {
      if (userIds.isEmpty) return Result.success<void>();
      await _post('/rtc/room/mute', {'room': id, 'userIds': userIds});
      return Result.success<void>();
    } catch (e) {
      return Result.failure<void>(e);
    }
  }

  Future<Result<void>> muteOthers({TrackType track = TrackType.audio}) async {
    try {
      await _post('/rtc/room/mute', {'room': id, 'all': true});
      return Result.success<void>();
    } catch (e) {
      return Result.failure<void>(e);
    }
  }

  /// Ends the class for EVERYONE (students see "The trainer ended the class")
  Future<Result<void>> end() async {
    try {
      await _post('/rtc/room/end', {'room': id});
      _endedAt = DateTime.now();
      _emitNow();
      return Result.success<void>();
    } catch (e) {
      return Result.failure<void>(e);
    }
  }

  // ---------------------------------------------------------------------
  // State → screens (batched: big classes change many times per second)
  // ---------------------------------------------------------------------
  void _scheduleEmit() {
    if (_emitTimer?.isActive ?? false) return;
    final n = _room?.remoteParticipants.length ?? 0;
    final wait = n > 300 ? 500 : (n > 60 ? 250 : 120);
    _emitTimer = Timer(Duration(milliseconds: wait), _emitNow);
  }

  void _emitNow() {
    _emitTimer?.cancel();
    final room = _room;
    if (room != null) {
      switch (room.connectionState) {
        case lk.ConnectionState.connected:
          _status = CallStatus.connected;
          break;
        case lk.ConnectionState.reconnecting:
          _status = CallStatus.reconnecting;
          break;
        case lk.ConnectionState.connecting:
          _status = CallStatus.connecting;
          break;
        case lk.ConnectionState.disconnected:
          if (!_status.isIdle && !_status.isConnecting) _status = CallStatus.disconnected;
          break;
      }
      _readMetadata(room.metadata);
    }
    state._set(CallState(
      callId: id,
      status: _left ? CallStatus.disconnected : _status,
      callParticipants: room == null || _status.isDisconnected ? const [] : _participants(room),
      custom: _custom,
      endedAt: _endedAt,
    ));
  }

  void _readMetadata(String? text) {
    if (text == null || text == _metaText) return;
    _metaText = text;
    try {
      final d = text.isEmpty ? const {} : jsonDecode(text);
      if (d is Map) {
        final m = <String, Object>{};
        d.forEach((k, v) {
          if (v != null) m[k.toString()] = v as Object;
        });
        _custom = m;
      }
    } catch (_) {}
  }

  List<CallParticipantState> _participants(lk.Room room) {
    final out = <CallParticipantState>[];
    final me = room.localParticipant;
    if (me != null) out.add(_toState(me, true));
    for (final p in room.remoteParticipants.values) {
      out.add(_toState(p, false));
    }
    return out;
  }

  static final Map<String, List<String>> _roleCache = {};

  CallParticipantState _toState(lk.Participant p, bool local) {
    final meta = p.metadata ?? '';
    final roles = _roleCache[meta] ??= () {
      try {
        final d = jsonDecode(meta);
        if (d is Map && d['role'] == 'admin') return const ['admin'];
      } catch (_) {}
      return const ['user'];
    }();
    final name = p.name.isNotEmpty ? p.name : p.identity;
    return CallParticipantState(
      userId: p.identity,
      name: name,
      sessionId: p.sid,
      isLocal: local,
      isSpeaking: p.isSpeaking,
      isAudioEnabled: p.isMicrophoneEnabled(),
      roles: roles,
    );
  }

  @override
  String toString() => 'Call($id)';
}
