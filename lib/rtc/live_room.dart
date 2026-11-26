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
//
// 🛟 Class keeps running when the person opens another app, gets a phone call
//    or a WhatsApp message:
//    • Android: a small "Live class is on" notification (foreground service)
//      keeps the mic + sound alive in the background
//    • connection lost (bad network / phone call / app paused) → the app joins
//      the class again by itself (no more "0 students" on the trainer side)
// 🔊 Sound: Speaker / Phone (ear) / Bluetooth / Headphones + louder voice
// 🎙 Mic: echo cancel + noise cancel + auto volume + low-hum filter
// 📶 Weak internet is shown for every person (quality from LiveKit)
// 🔆 Screen stays on during the class; power button → screen off, class
//    sound + mic keep running (Android: CPU + Wi-Fi kept awake)
// 📞 Phone / WhatsApp call during class → class sound + my mic pause, and
//    come back by themselves when the call ends (sound route fixed too)
// =========================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:wakelock_plus/wakelock_plus.dart';

/// Text of the Android "class is running" notification
const String _bgTitle = "Let's Speak Trainer • Live class";
const String _bgText =
    'Your class is running. Students can hear you. Tap to go back.';

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

/// Server said no (status code kept, so a rejoin knows when to stop trying)
class _ServerError implements Exception {
  final int code;
  final String message;
  const _ServerError(this.code, this.message);
  @override
  String toString() => 'Exception: $message';
}

Future<Map<String, dynamic>> _post(
  String path,
  Map<String, dynamic> body,
) async {
  final res = await http
      .post(
        Uri.parse('${ApiEndpoints.baseUrl}$path'),
        headers: _headers(),
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 20));
  Map<String, dynamic> data = {};
  try {
    final d = jsonDecode(res.body);
    if (d is Map) data = Map<String, dynamic>.from(d);
  } catch (_) {}
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw _ServerError(
      res.statusCode,
      (data['error'] ?? data['message'] ?? 'Server error ${res.statusCode}')
          .toString(),
    );
  }
  return data;
}

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
bool get _isMobile => _isAndroid || _isIOS;

// -------------------------------------------------------------------------
// 🛟 Android: keep the class alive in the background (native service in
// MainActivity.kt / ClassAudioService.kt). Also lists the sound devices.
// -------------------------------------------------------------------------
// -------------------------------------------------------------------------
// 📺 SMALL WINDOW (Android picture-in-picture)
// In class → student / trainer opens WhatsApp (home button, recent apps) →
// the class shrinks to a small window ON TOP of WhatsApp. Tap it → back to class.
// The class keeps running the whole time (sound + mic as before).
// -------------------------------------------------------------------------
class ClassPip {
  /// true while the app is showing as the small window
  static final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

  /// what the small window shows
  static final ValueNotifier<bool> micOn = ValueNotifier<bool>(false);
  static final ValueNotifier<String> speaking = ValueNotifier<String>('');
  static final ValueNotifier<bool> onCall = ValueNotifier<bool>(false);

  static bool _allowed = false;
  static bool _wired = false;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _Native._ch.setMethodCallHandler((c) async {
      if (c.method == 'pipChanged') inPip.value = c.arguments == true;
      // 🎤 mute / unmute button on the small window (over WhatsApp / other apps)
      if (c.method == 'pipToggleMic') await _toggleMicFromPip();
      return null;
    });
  }

  /// In class → leaving the app shows the small window. Class over → normal again.
  static Future<void> _allow(bool on) async {
    if (!_isAndroid || on == _allowed) return;
    _allowed = on;
    _sentMic = null;
    _wire();
    try {
      await _Native._ch.invokeMethod('pip', {'on': on});
    } catch (e) {
      debugPrint('Small window: $e');
    }
  }

  /// short message on the small window ("Mic locked", "Weak internet")
  static final ValueNotifier<String> note = ValueNotifier<String>('');

  /// 📶 my internet is weak right now (small window shows it)
  static final ValueNotifier<bool> weakNet = ValueNotifier<bool>(false);
  static Timer? _noteTimer;
  static bool? _sentMic;

  static void _flash(String text) {
    note.value = text;
    _noteTimer?.cancel();
    _noteTimer = Timer(const Duration(seconds: 4), () => note.value = '');
  }

  /// 🎤 button on the small window → mic on / off (same rules as in class)
  static Future<void> _toggleMicFromPip() async {
    if (StreamVideo._active.isEmpty) return;
    final c = StreamVideo._active.last;
    final room = c._room;
    if (room == null) return;
    final on = room.localParticipant?.isMicrophoneEnabled() ?? false;
    if (!on && c._inCall) {
      _flash('You are on a phone call');
      return;
    }
    if (!on && !c.canSpeakNow) {
      _flash('Mic locked by your trainer');
      return;
    }
    await c.setMicrophoneEnabled(enabled: !on);
    _update(c, room);
  }

  /// tell Android which button to show (🎤 "Mute" or 🔇 "Unmute")
  static void _sendMic(bool on) {
    if (!_isAndroid || _sentMic == on) return;
    _sentMic = on;
    unawaited(
      _Native._ch.invokeMethod('pipMic', {'on': on}).catchError((_) => null),
    );
  }

  static void _update(Call c, lk.Room? room) {
    if (!_isAndroid || !_allowed || room == null) return;
    micOn.value = room.localParticipant?.isMicrophoneEnabled() ?? false;
    _sendMic(micOn.value);
    final q = room.localParticipant?.connectionQuality;
    weakNet.value =
        q == lk.ConnectionQuality.poor || q == lk.ConnectionQuality.lost;
    onCall.value = c._inCall;
    String who = '';
    for (final p in room.activeSpeakers) {
      if (p is lk.RemoteParticipant && !Call._secret(p)) {
        who = p.name.isEmpty ? p.identity : p.name;
        break;
      }
    }
    speaking.value = who;
  }
}

class _Native {
  static const MethodChannel _ch = MethodChannel('letsspeak/class_service');
  static bool _on = false;

  static Future<void> keepAlive(bool on) async {
    if (!_isAndroid || on == _on) return;
    _on = on;
    try {
      if (on) {
        await _ch.invokeMethod('start', {'title': _bgTitle, 'text': _bgText});
      } else {
        await _ch.invokeMethod('stop');
      }
    } catch (e) {
      debugPrint('Class background service: $e');
    }
  }

  /// 📞 Is the phone in a call? (normal call or WhatsApp / other app call)
  ///   mode: Android audio mode (0 normal, 1 ringing, 2 phone call, 3 voice chat)
  static Future<({bool inCall, int mode})> callState({
    required bool myMicOn,
  }) async {
    if (!_isAndroid) return (inCall: false, mode: -1);
    try {
      final m = await _ch.invokeMethod<Map<dynamic, dynamic>>('callState', {
        'micOn': myMicOn,
      });
      return (
        inCall: m?['phoneCall'] == true || m?['voipCall'] == true,
        mode: (m?['mode'] as int?) ?? -1,
      );
    } catch (_) {
      return (inCall: false, mode: -1);
    }
  }

  /// 🎤 VOICE GATE on our own mic (Android): between words the room noise and
  /// far-away voices are pushed down before the sound leaves the phone.
  static Future<void> voiceGate(bool on) async {
    if (!_isAndroid) return;
    try {
      final ok = await _ch.invokeMethod('voiceGate', {'on': on});
      debugPrint('🎤 voice gate: ${ok == true ? 'ON' : 'not available'}');
    } catch (e) {
      debugPrint('🎤 voice gate: $e');
    }
  }

  /// 🔊 Class sound plays on the phone's CALL volume. Many students have it low
  /// (media volume high, call volume low) → "even Extra loud is not loud".
  /// min 0.6 = raise to at least 60 % when the class starts; 1.0 = full (Extra loud).
  static Future<void> voiceVolume(double min) async {
    if (!_isAndroid) return;
    try {
      await _ch.invokeMethod('voiceVolume', {'min': min});
    } catch (_) {}
  }

  /// After a call Android may leave the sound in "normal" mode → class sound
  /// goes silent / to the wrong speaker. Put it back to "voice chat" mode.
  static Future<void> restoreMode() async {
    if (!_isAndroid) return;
    try {
      await _ch.invokeMethod('restoreMode');
    } catch (_) {}
  }

  /// Android sound devices: [{type: bluetooth|headset, name: "..."}]
  static Future<List<Map<String, String>>> outputs() async {
    if (!_isAndroid) return const [];
    try {
      final list = await _ch.invokeMethod<List<dynamic>>('outputs');
      return (list ?? const [])
          .whereType<Map>()
          .map(
            (m) => {'type': '${m['type'] ?? ''}', 'name': '${m['name'] ?? ''}'},
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

// -------------------------------------------------------------------------
// 🔊 SOUND — where the class sound plays + how loud
// -------------------------------------------------------------------------
enum SoundOut { speaker, phone, bluetooth, headset }

class ClassSound {
  ClassSound._();

  /// Where the sound plays now
  static final ValueNotifier<SoundOut> route = ValueNotifier<SoundOut>(
    SoundOut.speaker,
  );

  /// What this phone can use right now (Bluetooth / headphones only when connected)
  static final ValueNotifier<List<SoundOut>> choices =
      ValueNotifier<List<SoundOut>>(const [SoundOut.speaker, SoundOut.phone]);

  /// Name of the Bluetooth device ("boAt Rockerz 255")
  static final ValueNotifier<String> bluetoothName = ValueNotifier<String>('');

  /// 0 = normal, 1 = loud (default), 2 = extra loud
  static final ValueNotifier<int> level = ValueNotifier<int>(1);
  // 🔊 not too high: a big boost also makes the noise loud + breaks echo-cancel (crackle / echo)
  static const List<double> _gains = [1.0, 1.6, 2.2];

  /// Sound choices only exist on phones (Chrome uses the computer's sound)
  static bool get supported => _isMobile;

  static Call? _call;
  static Timer? _poll;
  static bool _firstScan = true;
  static bool _busy = false;

  static void _attach(Call c) {
    _call = c;
    _firstScan = true;
    if (!supported) return;
    _poll?.cancel();
    // new Bluetooth / headphones connected? (cheap check every 3 s while in class)
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    unawaited(refresh(apply: true));
  }

  static void _detach(Call c) {
    if (_call != c) return;
    _call = null;
    _poll?.cancel();
    _poll = null;
  }

  static String label(SoundOut o) {
    switch (o) {
      case SoundOut.speaker:
        return 'Speaker';
      case SoundOut.phone:
        return 'Phone (ear)';
      case SoundOut.bluetooth:
        return bluetoothName.value.isEmpty ? 'Bluetooth' : bluetoothName.value;
      case SoundOut.headset:
        return 'Headphones';
    }
  }

  static String levelLabel(int l) =>
      const ['Normal', 'Loud', 'Extra loud'][l.clamp(0, 2)];

  /// Look which devices are connected. A NEW Bluetooth / headphone → use it.
  static Future<void> refresh({bool apply = false}) async {
    if (!supported || _busy) return;
    _busy = true;
    try {
      final found = <SoundOut>{SoundOut.speaker, SoundOut.phone};
      String bt = '';
      if (_isAndroid) {
        for (final d in await _Native.outputs()) {
          if (d['type'] == 'bluetooth') {
            found.add(SoundOut.bluetooth);
            if (bt.isEmpty) bt = d['name'] ?? '';
          } else if (d['type'] == 'headset') {
            found.add(SoundOut.headset);
          }
        }
      } else {
        try {
          for (final d in await lk.Hardware.instance.audioOutputs()) {
            final l = '${d.label} ${d.deviceId}'.toLowerCase();
            if (l.contains('bluetooth') ||
                l.contains('airpods') ||
                l.contains('hands-free') ||
                l.contains('hfp') ||
                l.contains('a2dp')) {
              found.add(SoundOut.bluetooth);
              if (bt.isEmpty) bt = d.label;
            } else if (l.contains('headphone') || l.contains('headset')) {
              found.add(SoundOut.headset);
            }
          }
        } catch (_) {}
      }
      // Bluetooth / headphones connected → the ear speaker can't be chosen (phone uses the headset)
      if (found.contains(SoundOut.bluetooth) ||
          found.contains(SoundOut.headset))
        found.remove(SoundOut.phone);

      final order = [
        SoundOut.bluetooth,
        SoundOut.headset,
        SoundOut.speaker,
        SoundOut.phone,
      ];
      final now = order.where(found.contains).toList();
      final before = _firstScan ? const <SoundOut>[] : choices.value;
      _firstScan = false;
      bluetoothName.value = bt;
      if (!listEquals(now, choices.value)) choices.value = now;

      final justConnected = [
        SoundOut.bluetooth,
        SoundOut.headset,
      ].where((o) => found.contains(o) && !before.contains(o)).toList();
      if (justConnected.isNotEmpty) {
        route.value = justConnected.first; // 🎧 connected → sound goes there
        apply = true;
      } else if (!found.contains(route.value)) {
        route.value = SoundOut.speaker; // device gone → back to the loudspeaker
        apply = true;
      }
      if (apply) await _apply();
    } finally {
      _busy = false;
    }
  }

  /// Person picked where to hear the class
  static Future<void> select(SoundOut o) async {
    route.value = o;
    await _apply();
  }

  static Future<void> setLevel(int l) async {
    level.value = l.clamp(0, 2);
    // 🔊 Extra loud → phone call volume to the top too
    if (level.value == 2) unawaited(_Native.voiceVolume(1.0));
    await _call?._applyGain();
  }

  static double get gain => _gains[level.value.clamp(0, 2)];

  /// Students' voices are never boosted much (their room noise would get loud too)
  static double get studentGain => gain > 1.3 ? 1.3 : gain;

  static Future<void> _apply() async {
    final room = _call?._room;
    if (room == null || !supported) return;
    try {
      switch (route.value) {
        case SoundOut.speaker:
          // force → loudspeaker even if Bluetooth / headphones are connected
          await room.setSpeakerOn(true, forceSpeakerOutput: true);
          break;
        case SoundOut.phone:
          await room.setSpeakerOn(false);
          break;
        case SoundOut.bluetooth:
        case SoundOut.headset:
          // Bluetooth / headphones first; if they disconnect → loudspeaker (not the quiet ear speaker)
          await room.setSpeakerOn(true, forceSpeakerOutput: false);
          break;
      }
    } catch (e) {
      debugPrint('Sound route error: $e');
    }
  }
}

// -------------------------------------------------------------------------
// Small types with the old names
// -------------------------------------------------------------------------
enum Priority { verbose, debug, info, warning, error }

enum TrackType { audio, video, screenShare }

/// 📶 Internet of one person in the class
enum NetQuality { unknown, excellent, good, poor, lost }

class StreamVideoOptions {
  final Priority? logPriority;
  const StreamVideoOptions({this.logPriority});
}

class User {
  final String id;
  final String name;
  const User._(this.id, this.name);
  factory User.regular({
    required String userId,
    String? name,
    String? role,
    String? image,
  }) => User._(userId, name ?? '');
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

  /// 📶 this person's internet
  final NetQuality quality;
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
    this.quality = NetQuality.unknown,
  });

  /// true → show "weak internet"
  bool get weakNet => quality == NetQuality.poor || quality == NetQuality.lost;

  /// trainer / admin
  bool get isStaff => roles.contains('admin');
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
  final StreamController<CallState> _ctrl =
      StreamController<CallState>.broadcast();

  CallState get value => _value;
  Stream<CallState> asStream() => _ctrl.stream;
  Stream<CallState> get valueStream => _ctrl.stream;

  void _set(CallState v) {
    _value = v;
    if (!_ctrl.isClosed) _ctrl.add(v);
  }
}

/// ✋ A small message inside the class (raise hand, question, trainer reply).
/// Sent with LiveKit data messages — no server call, arrives in ~0.1 s.
class ClassSignal {
  final String from; // user id of the sender
  final String fromName;
  final bool fromStaff;
  final Map<String, dynamic> data;
  const ClassSignal(this.from, this.fromName, this.fromStaff, this.data);
  String get type => (data['t'] ?? '').toString();
}

// -------------------------------------------------------------------------
// StreamVideo (the "client") — keeps who is logged in
// -------------------------------------------------------------------------
class StreamVideo {
  final String apiKey;
  final User user;
  static final Set<Call> _active = <Call>{};

  StreamVideo(
    this.apiKey, {
    required this.user,
    String? userToken,
    StreamVideoOptions? options,
  });

  /// Leaves every open class (e.g. on logout / user change)
  static Future<void> reset({bool disconnect = false}) async {
    if (!disconnect) return;
    for (final c in _active.toList()) {
      await c.leave();
    }
  }

  Call makeCall({required StreamCallType callType, required String id}) =>
      Call._(id, user);
}

// -------------------------------------------------------------------------
// Call — one class (LiveKit room)
// -------------------------------------------------------------------------
class Call {
  Call._(this.id, this._user)
    : state = CallStateHolder(
        CallState(
          callId: id,
          status: CallStatus.idle,
          callParticipants: const [],
          custom: const {},
        ),
      );

  final String id;
  final User _user;
  final CallStateHolder state;

  // ---------------------------------------------------------------------
  // 🌐 WEB SOUND: Chrome only plays sound after the person taps the page.
  // We start the class sound right after joining, on every new voice, and on
  // the next tap anywhere in the app (if Chrome blocked it before).
  // ---------------------------------------------------------------------
  static bool _tapHooked = false;

  static void _webUnlockOnTap() {
    if (_tapHooked) return;
    _tapHooked = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((PointerEvent e) {
      if (e is! PointerDownEvent) return;
      for (final c in StreamVideo._active.toList()) {
        final r = c._room;
        if (r != null && !r.canPlaybackAudio) _webStartAudio(r);
      }
    });
  }

  static void _webStartAudio(lk.Room room) {
    try {
      room.startAudio().catchError((_) {});
    } catch (_) {}
  }

  /// 🌐 true when Chrome is still blocking the class sound (show "Tap to hear")
  bool get soundBlocked => kIsWeb && _room != null && !_room!.canPlaybackAudio;

  Future<void> unlockSound() async {
    final r = _room;
    if (r != null) _webStartAudio(r);
    _emitNow();
  }

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  CallStatus _status = CallStatus.idle;
  DateTime? _endedAt;
  Map<String, Object> _custom = const {};
  String? _metaText;
  Timer? _emitTimer;
  bool _left = false;

  // 🛟 join again by itself after the connection is lost
  bool _wantMic = false; // mic was on → switch it on again after rejoining
  bool _over = false; // 🛑 really finished (ended / removed / gave up) — only then "disconnected"
  Timer? _lostCheck;
  DateTime? _lostAt;
  int _tries = 0;
  Timer? _rejoinTimer;
  bool _rejoining = false;
  AppLifecycleListener? _life;
  static final math.Random _rnd = math.Random();

  // 📞 phone / WhatsApp call during the class
  Timer? _callWatch;
  bool _inCall = false;
  bool _micBeforeCall = false;
  bool _checkingCall = false;
  bool _micStopped = false; // 📞 mic fully switched off for a phone call

  /// true while the person is on a phone / WhatsApp call (screens may show it)
  bool get inPhoneCall => _inCall;

  /// 🎤 May I switch my mic on now? (the trainer can lock all mics;
  /// trainers / admins always can)
  bool get canSpeakNow {
    final room = _room;
    if (room == null) return false;
    if (_isStaffMeta(room.localParticipant?.metadata)) return true;
    Map<dynamic, dynamic> c = _custom;
    final packed = c['state'];
    if (packed is String && packed.isNotEmpty) {
      try {
        final d = jsonDecode(packed);
        if (d is Map) c = d;
      } catch (_) {}
    }
    if (c['micLocked'] != true) return true;
    final a = c['allowed'];
    final ids = a is List
        ? a.map((e) => e.toString()).toSet()
        : '${a ?? ''}'.split(',').toSet();
    return ids.contains(userId);
  }

  /// How long we keep trying before we give up ("connection was lost")
  static const Duration _giveUpAfter = Duration(minutes: 3);

  // ✋ raise hand + class messages
  final StreamController<ClassSignal> _signals =
      StreamController<ClassSignal>.broadcast();
  Stream<ClassSignal> get signals => _signals.stream;

  /// 🕵️ Admin / principal watching the class: NEVER shown in any list or count
  /// (their voice still plays when they speak). Server names them "observer_<id>".
  static bool _secret(lk.Participant p) => p.identity.startsWith('observer_');

  static bool _isStaffMeta(String? meta) {
    try {
      final d = jsonDecode(meta ?? '');
      return d is Map && d['role'] == 'admin';
    } catch (_) {
      return false;
    }
  }

  /// Trainers / admins in the class right now (user ids)
  List<String> get staffIds =>
      (_room?.remoteParticipants.values ?? const <lk.RemoteParticipant>[])
          .where((p) => !_secret(p) && _isStaffMeta(p.metadata))
          .map((p) => p.identity)
          .toList();

  /// 📶 My own internet right now
  NetQuality get myQuality => _q(_room?.localParticipant?.connectionQuality);

  /// Send a small message. to = null → everyone, else only those user ids.
  Future<bool> sendSignal(Map<String, dynamic> data, {List<String>? to}) async {
    final me = _room?.localParticipant;
    if (me == null) return false;
    if (to != null && to.isEmpty) return false;
    try {
      await me.publishData(
        utf8.encode(jsonEncode(data)),
        reliable: true,
        destinationIdentities: to,
        topic: 'class',
      );
      return true;
    } catch (e) {
      debugPrint('Class message error: $e');
      return false;
    }
  }

  void _onData(lk.DataReceivedEvent e) {
    if (e.topic != 'class' || _signals.isClosed) return;
    try {
      final d = jsonDecode(utf8.decode(e.data));
      if (d is! Map) return;
      final p = e.participant;
      if (p != null && _secret(p)) return; // admin never sends class signals
      _signals.add(
        ClassSignal(
          p?.identity ?? '',
          (p == null || p.name.isEmpty) ? (p?.identity ?? '') : p.name,
          _isStaffMeta(p?.metadata),
          Map<String, dynamic>.from(d),
        ),
      );
    } catch (_) {}
  }

  /// 🎙 Big classes (Surendra Sir special class, 2,000 people): don't build a
  /// list of every person 2× a second on every phone — only me + who is speaking.
  bool lightweight = false;

  /// Everyone in the class (works in lightweight mode too)
  int get peopleCount => _room == null
      ? 0
      : _room!.remoteParticipants.values.where((p) => !_secret(p)).length + 1;

  String get callCid => 'default:$id';
  String get userId => _user.id;

  /// The server creates the class (trainer "start"); nothing to do here.
  Future<Result<void>> getOrCreate() async => Result.success<void>();

  Future<Result<void>> join({CallConnectOptions? connectOptions}) async {
    _left = false;
    _over = false;
    _endedAt = null;
    _lostAt = null;
    _tries = 0;
    _rejoinTimer?.cancel();
    _status = CallStatus.connecting;
    _emitNow();
    _wantMic = connectOptions?.microphone.isOn ?? false;
    // 📶 slow / unstable internet: try up to 3 times (2 s, then 4 s apart) before
    // giving up. Only network problems and server hiccups (5xx) are retried —
    // "class not started", "not your class" etc. come back at once.
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _connect();
        _whenConnected();
        return Result.success<void>();
      } catch (e) {
        lastError = e;
        debugPrint('LiveKit join error (try ${attempt + 1}/3): $e');
        await _closeRoom();
        if (_left) break;
        final retry = e is! _ServerError || e.code >= 500;
        if (!retry || attempt == 2) break;
        await Future.delayed(Duration(seconds: 2 + attempt * 2));
        if (_left) break;
      }
    }
    _status = CallStatus.disconnected;
    _emitNow();
    return Result.failure<void>(lastError ?? Exception('Could not join the class'));
  }

  /// Token from our server → connect to LiveKit → sound + mic like before
  Future<void> _connect() async {
    _micStopped = false; // new room → new mic
    final data = await _post('/rtc/room-token', {'room': id});
    final url = (data['url'] ?? '').toString();
    final token = (data['token'] ?? '').toString();
    if (url.isEmpty || token.isEmpty) throw Exception('Class access missing');

    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        // 🎙 clear voice: echo cancel + noise cancel + auto volume (quiet voices get louder)
        //    + low-hum filter (fan / AC / traffic rumble)
        defaultAudioCaptureOptions: const lk.AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          highPassFilter: true,
          voiceIsolation: true,
          typingNoiseDetection: true,
          // ⚡ MUTE keeps the mic ready (only switched off), so after UNMUTE the
          //    very first word goes out at once. Before, the mic was restarted on
          //    every unmute (~0.5 s) → "Hii mam" reached the trainer as "Hii…".
          stopAudioCaptureOnMute: false,
        ),
        // 🎧 speech: silence is not sent (dtx) + protection against lost packets (red)
        //    🌐 web (Chrome): plain Opus — RED/DTX can make the voice silent in the browser
        defaultAudioPublishOptions: lk.AudioPublishOptions(
          dtx: !kIsWeb,
          red: !kIsWeb,
          // 🗣 speech quality (24 kbps) instead of music (48 kbps): voice sounds the same,
          //    but 2,000 listeners need half the server bandwidth
          encoding: lk.AudioEncoding.presetSpeech,
        ),
      ),
    );
    _room = room;
    final listener = room.createListener();
    _listener = listener;
    listener.listen((event) => _onRoomEvent(room, event));
    room.addListener(_scheduleEmit);

    await room.connect(
      url,
      token,
      connectOptions: const lk.ConnectOptions(autoSubscribe: true),
    );
    if (kIsWeb) {
      _webUnlockOnTap();
      _webStartAudio(room);
    }
    _status = CallStatus.connected;
    StreamVideo._active.add(this);
    ClassSound._attach(
      this,
    ); // 🔊 speaker / Bluetooth / headphones (headphones win when connected)
    await ClassSound._apply();
    await _applyGain();
    // 🔊 call volume very low on this phone → raise it (Extra loud → full)
    unawaited(_Native.voiceVolume(ClassSound.level.value >= 2 ? 1.0 : 0.6));
    // 🎤 clean our own mic before it is sent (room noise / far voices)
    unawaited(_Native.voiceGate(true));

    if (_wantMic) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(true);
      } catch (e) {
        debugPrint('Mic start error: $e');
      }
    }
  }

  void _onRoomEvent(lk.Room room, lk.RoomEvent event) {
    if (room != _room) return; // old room after a rejoin
    if (event is lk.DataReceivedEvent) {
      _onData(event);
      return;
    }
    if (event is lk.RoomDisconnectedEvent) {
      _onDisconnected(event.reason);
      return;
    }
    // ⚡ someone just switched the mic ON → their first words play at full volume
    //    at once (before, the noise gate waited for "is speaking" → first word cut)
    if (event is lk.TrackUnmutedEvent &&
        event.participant is lk.RemoteParticipant &&
        event.publication.source == lk.TrackSource.microphone) {
      _openGateFor(event.participant.identity);
    }
    // (only when the mic is really ON — a muted / rejoining mic stays quiet)
    if (event is lk.TrackSubscribedEvent &&
        event.track is lk.RemoteAudioTrack &&
        !event.publication.muted) {
      _openGateFor(event.participant.identity);
    }
    // 🔊 every new voice gets the "loud" volume
    if (event is lk.TrackSubscribedEvent &&
        event.track is lk.RemoteAudioTrack) {
      unawaited(_gainFor(event.participant, event.track));
    }
    // 🤫 noise gate: open a student's voice only while they really speak
    if (event is lk.ActiveSpeakersChangedEvent) _onSpeakers(event.speakers);
    // 🌐 web: Chrome blocks sound until a tap → try to start it on every new voice
    if (kIsWeb && event is lk.TrackSubscribedEvent) _webStartAudio(room);
    if (event is lk.RoomReconnectingEvent) _status = CallStatus.reconnecting;
    if (event is lk.RoomReconnectedEvent) {
      _status = CallStatus.connected;
      unawaited(ClassSound._apply());
    }
    _scheduleEmit();
  }

  /// Joined (first time or again) → class runs in the background too
  void _whenConnected() {
    _lostAt = null;
    _tries = 0;
    _status = CallStatus.connected;
    unawaited(_Native.keepAlive(true));
    _keepScreenOn(true); // 🔆 phone does not go to sleep in class
    _startCallWatch();
    _life ??= AppLifecycleListener(onResume: _onAppResume);
    _emitNow();
  }

  static void _keepScreenOn(bool on) {
    try {
      if (on) {
        WakelockPlus.enable();
      } else if (StreamVideo._active.isEmpty) {
        WakelockPlus.disable();
      }
    } catch (_) {}
    // 📺 small window over other apps: only while a class is running
    unawaited(ClassPip._allow(on || StreamVideo._active.isNotEmpty));
  }

  // -------------------------------------------------------------------
  // 📞 Calls: every 2 s look if the phone is in a call
  // -------------------------------------------------------------------
  void _startCallWatch() {
    if (!_isAndroid || _callWatch != null) return;
    _callWatch = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkCall(),
    );
  }

  void _stopCallWatch() {
    _callWatch?.cancel();
    _callWatch = null;
  }

  Future<void> _checkCall() async {
    final room = _room;
    if (room == null || _checkingCall || _left) return;
    _checkingCall = true;
    try {
      final me = room.localParticipant;
      final micOn = me?.isMicrophoneEnabled() ?? false;
      // mic stays ready while muted (fast unmute) → it still counts as MY recording
      final capturing =
          !_micStopped &&
          me?.getTrackPublicationBySource(lk.TrackSource.microphone) != null;
      final st = await _Native.callState(myMicOn: capturing);
      if (st.inCall && !_inCall) {
        // 📞 call started → my mic off (class can't hear the call) + class sound off
        _inCall = true;
        _micBeforeCall = micOn;
        // mic OFF completely (also when muted, because the mic stays ready)
        await _stopMicCapture(me);
        await _applyGain();
        _emitNow();
        debugPrint('📞 Call started → class paused on this phone');
      } else if (!st.inCall && _inCall) {
        // 📞 call ended → sound back where it was + mic back on (if it was on)
        _inCall = false;
        await _Native.restoreMode();
        await ClassSound._apply();
        await _applyGain();
        if (_micBeforeCall && _wantMic) {
          try {
            await _micOn(room);
          } catch (_) {}
        }
        _micBeforeCall = false;
        _emitNow();
        debugPrint('📞 Call ended → class sound + mic back');
      } else if (!st.inCall && st.mode == 0) {
        // another app left the sound in "normal" mode → class may be silent
        await _Native.restoreMode();
        await ClassSound._apply();
      }
    } finally {
      _checkingCall = false;
    }
  }

  void _onDisconnected(lk.DisconnectReason? reason) {
    if (_left) return;
    // final: trainer ended the class / removed this person / same account joined on another phone
    if (reason == lk.DisconnectReason.roomDeleted) {
      _endedAt = DateTime.now(); // trainer ended the class for everyone
      _finish();
      return;
    }
    if (reason == lk.DisconnectReason.participantRemoved ||
        reason == lk.DisconnectReason.duplicateIdentity ||
        reason == lk.DisconnectReason.clientInitiated) {
      _finish();
      return;
    }
    // 📶 network gone / phone call / app was paused → join again by itself
    _scheduleRejoin();
  }

  /// Connection dropped but LiveKit didn't tell us why → start joining again
  /// ourselves (2 s later, so a real "removed / ended" message wins first).
  void _ensureRejoin() {
    if (_left || _over || _endedAt != null || _rejoining) return;
    if (_rejoinTimer?.isActive ?? false) return;
    if (_lostCheck?.isActive ?? false) return;
    _lostCheck = Timer(const Duration(seconds: 2), () {
      final room = _room;
      if (_left || _over || _endedAt != null || _rejoining) return;
      if (_rejoinTimer?.isActive ?? false) return;
      if (room != null && room.connectionState != lk.ConnectionState.disconnected) return;
      _scheduleRejoin();
    });
  }

  /// Give up for good → screens close the class
  void _finish() {
    _over = true;
    _lostCheck?.cancel();
    _rejoinTimer?.cancel();
    _stopCallWatch();
    _life?.dispose();
    _life = null;
    _status = CallStatus.disconnected;
    _emitNow();
    StreamVideo._active.remove(this); // this class is over on this phone
    unawaited(_Native.keepAlive(StreamVideo._active.isNotEmpty));
    _keepScreenOn(false);
    ClassSound._detach(this);
  }

  void _scheduleRejoin() {
    if (_left || _over || _endedAt != null) return;
    final now = DateTime.now();
    _lostAt ??= now;
    if (now.difference(_lostAt!) > _giveUpAfter) {
      unawaited(_closeRoom());
      _finish();
      return;
    }
    _status = CallStatus.reconnecting;
    _emitNow();
    _rejoinTimer?.cancel();
    const steps = [0, 1, 2, 3, 5, 5, 8, 10];
    final secs = steps[math.min(_tries, steps.length - 1)];
    // big special class: spread the rejoins so 2,000 phones don't hit the server together
    final jitter = _rnd.nextInt(lightweight ? 8000 : 1200);
    _tries++;
    _rejoinTimer = Timer(
      Duration(milliseconds: secs * 1000 + jitter),
      _rejoinNow,
    );
  }

  Future<void> _rejoinNow() async {
    if (_left || _endedAt != null || _rejoining) return;
    _rejoining = true;
    try {
      await _closeRoom(keepAlive: true);
      if (_left) return;
      _status = CallStatus.reconnecting;
      await _connect();
      if (_left) {
        await _closeRoom();
        return;
      }
      _whenConnected();
      debugPrint('🛟 Class: joined again');
    } catch (e) {
      debugPrint('🛟 Class rejoin failed: $e');
      await _closeRoom(keepAlive: true);
      // server says no (class ended / not allowed) → stop trying
      if (e is _ServerError &&
          (e.code == 401 || e.code == 403 || e.code == 404)) {
        _finish();
      } else {
        _scheduleRejoin();
      }
    } finally {
      _rejoining = false;
    }
  }

  /// Back in the app → if the class is still rejoining, try right now
  void _onAppResume() {
    if (_left || _endedAt != null) return;
    if (_status.isReconnecting &&
        _rejoinTimer != null &&
        _rejoinTimer!.isActive &&
        !_rejoining) {
      _rejoinTimer!.cancel();
      unawaited(_rejoinNow());
    }
    // after a phone call Android may move the sound → put it back where the person chose
    if (_room != null) unawaited(ClassSound.refresh(apply: true));
    _emitNow();
  }

  Future<Result<void>> leave() async {
    _left = true;
    _rejoinTimer?.cancel();
    _stopCallWatch();
    _inCall = false;
    _life?.dispose();
    _life = null;
    await _closeRoom();
    _keepScreenOn(false);
    _status = CallStatus.disconnected;
    _emitNow();
    return Result.success<void>();
  }

  Future<void> _closeRoom({bool keepAlive = false}) async {
    _clearGate();
    StreamVideo._active.remove(this);
    _emitTimer?.cancel();
    if (!keepAlive) {
      ClassSound._detach(this);
      unawaited(_Native.keepAlive(StreamVideo._active.isNotEmpty));
    }
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

  // ---------------------------------------------------------------------
  // 🔊 louder voices (WebRTC gain 0…10 per voice; 1 = as received)
  // ---------------------------------------------------------------------
  Future<void> _gainFor(lk.Participant p, lk.Track track) async {
    if (kIsWeb) return;
    try {
      await rtc.Helper.setVolume(_volumeFor(p), track.mediaStreamTrack);
    } catch (e) {
      debugPrint('Volume error: $e');
    }
  }

  Future<void> _applyGain() async {
    final room = _room;
    if (room == null || kIsWeb) return;
    for (final p in room.remoteParticipants.values) {
      await _applyGainOf(p);
    }
  }

  Future<void> _applyGainOf(lk.RemoteParticipant p) async {
    for (final pub in p.audioTrackPublications) {
      final t = pub.track;
      if (t != null) await _gainFor(p, t);
    }
  }

  // ---------------------------------------------------------------------
  // 🤫 NOISE GATE (big help in a class with many open mics)
  // A student whose mic is on but who is NOT speaking only sends fan / traffic /
  // TV / room noise. 30 such mics together = a lot of "shhhh". LiveKit tells us
  // who is really speaking → only those voices play at full volume; the rest
  // are almost silent. Trainer / admin / Surendra Sir are always heard fully.
  // ---------------------------------------------------------------------
  // not speaking → ~ -30 dB: fan / pin drop / room noise of open mics is
  // practically gone (was 0.08 = -22 dB → small sounds were still heard)
  static const double _gateFloor = 0.03;
  static const Duration _gateHold = Duration(
    milliseconds: 1500,
  ); // keeps pauses between words
  final Set<String> _gateOpen = <String>{};
  final Map<String, Timer> _gateTimers = <String, Timer>{};

  bool _alwaysHeard(lk.Participant p) => _secret(p) || _isStaffMeta(p.metadata);

  double _volumeFor(lk.Participant p) {
    if (_inCall)
      return 0.0; // 📞 in a phone call → class sound off on this phone
    if (_alwaysHeard(p)) return ClassSound.gain;
    return _gateOpen.contains(p.identity) ? ClassSound.studentGain : _gateFloor;
  }

  void _onSpeakers(List<lk.Participant> speakers) {
    final room = _room;
    if (room == null || kIsWeb) return;
    final now = <String>{
      for (final p in speakers)
        if (p is lk.RemoteParticipant && !_alwaysHeard(p)) p.identity,
    };
    for (final id in now) {
      _gateTimers.remove(id)?.cancel(); // still speaking → keep open
      if (_gateOpen.add(id)) _regain(id);
    }
    for (final id in _gateOpen.toList()) {
      if (now.contains(id) || _gateTimers.containsKey(id)) continue;
      // stopped speaking → close a little later (not between words)
      _gateTimers[id] = Timer(_gateHold, () {
        _gateTimers.remove(id);
        if (_gateOpen.remove(id)) _regain(id);
      });
    }
  }

  void _regain(String identity) {
    final room = _room;
    if (room == null) return;
    for (final p in room.remoteParticipants.values) {
      if (p.identity == identity) {
        unawaited(_applyGainOf(p));
        return;
      }
    }
  }

  /// Mic just switched on → voice open for 4 s (then normal "is speaking" rule)
  void _openGateFor(String identity) {
    if (kIsWeb) return;
    _gateTimers.remove(identity)?.cancel();
    final added = _gateOpen.add(identity);
    _gateTimers[identity] = Timer(const Duration(seconds: 4), () {
      _gateTimers.remove(identity);
      final stillTalking =
          _room?.activeSpeakers.any((p) => p.identity == identity) ?? false;
      if (stillTalking) return; // the speaker rule closes it later
      if (_gateOpen.remove(identity)) _regain(identity);
    });
    if (added) _regain(identity);
  }

  /// 📞 phone call: switch the mic OFF completely (not only muted),
  /// so WhatsApp / the phone call gets the mic
  Future<void> _stopMicCapture(lk.LocalParticipant? me) async {
    final pub = me?.getTrackPublicationBySource(lk.TrackSource.microphone);
    if (pub == null) return;
    try {
      if (pub.muted) {
        await pub.track?.stop();
      } else {
        await pub.mute(stopOnMute: true);
      }
      _micStopped = true;
    } catch (_) {}
  }

  /// Mic ON (fast). After a phone call the mic was switched off → start it again.
  Future<void> _micOn(lk.Room room) async {
    final me = room.localParticipant;
    if (me == null) return;
    final pub = me.getTrackPublicationBySource(lk.TrackSource.microphone);
    if (pub != null && _micStopped) {
      if (!pub.muted) await pub.mute(stopOnMute: false);
      await pub.unmute(stopOnMute: true); // restarts the stopped mic
      _micStopped = false;
      return;
    }
    await me.setMicrophoneEnabled(true);
  }

  void _clearGate() {
    for (final t in _gateTimers.values) {
      t.cancel();
    }
    _gateTimers.clear();
    _gateOpen.clear();
  }

  Future<Result<void>> setMicrophoneEnabled({required bool enabled}) async {
    try {
      if (enabled && _inCall) {
        // 📞 still on a call → turn the mic on when the call ends
        _wantMic = true;
        _micBeforeCall = true;
        return Result.success<void>();
      }
      final room = _room;
      if (room != null) {
        if (enabled) {
          await _micOn(room); // ⚡ fast: the mic is already ready
        } else {
          await room.localParticipant?.setMicrophoneEnabled(false);
        }
      }
      _wantMic = enabled;
      _emitNow();
      return Result.success<void>();
    } catch (e) {
      return Result.failure<void>(e);
    }
  }

  /// Audio classes: the camera is never used
  Future<Result<void>> setCameraEnabled({required bool enabled}) async =>
      Result.success<void>();

  /// Trainer: share mic lock + practice state with everyone in the class
  Future<Result<void>> update({Map<String, Object>? custom}) async {
    try {
      final c = custom ?? const <String, Object>{};
      _custom = Map<String, Object>.from(
        c,
      ); // trainer's own screen updates at once
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
      _rejoinTimer?.cancel();
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
    final wait = lightweight ? 700 : (n > 300 ? 500 : (n > 60 ? 250 : 120));
    _emitTimer = Timer(Duration(milliseconds: wait), _emitNow);
  }

  void _emitNow() {
    _emitTimer?.cancel();
    final room = _room;
    if (room != null && !_rejoining) {
      switch (room.connectionState) {
        case lk.ConnectionState.connected:
          _status = CallStatus.connected;
          break;
        case lk.ConnectionState.reconnecting:
          _status = CallStatus.reconnecting;
          break;
        case lk.ConnectionState.connecting:
          // first join → "connecting"; a rejoin keeps showing "reconnecting"
          if (!_status.isReconnecting) _status = CallStatus.connecting;
          break;
        case lk.ConnectionState.disconnected:
          // 🐞 FIX "kicked out for no reason": the connection dropping is NOT the
          // end of the class. Before, the screen saw "disconnected" for a moment
          // and closed the class. Now it's "reconnecting" and the app joins again
          // by itself. Only a real end (trainer ended / removed / gave up after
          // 3 minutes) becomes "disconnected" (set in _finish).
          if (_over) {
            _status = CallStatus.disconnected;
          } else if (!_status.isIdle && !_status.isConnecting) {
            _status = CallStatus.reconnecting;
            _ensureRejoin();
          }
          break;
      }
      _readMetadata(room.metadata);
    }
    final hasList =
        room != null &&
        !_status.isDisconnected &&
        room.connectionState != lk.ConnectionState.disconnected;
    ClassPip._update(this, room); // 📺 small window text
    state._set(
      CallState(
        callId: id,
        status: _left ? CallStatus.disconnected : _status,
        callParticipants: hasList ? _participants(room) : const [],
        custom: _custom,
        endedAt: _endedAt,
      ),
    );
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
    if (lightweight) {
      for (final p in room.activeSpeakers) {
        if (p is lk.RemoteParticipant && !_secret(p))
          out.add(_toState(p, false));
      }
      return out;
    }
    for (final p in room.remoteParticipants.values) {
      if (_secret(p)) continue; // hidden admin
      out.add(_toState(p, false));
    }
    return out;
  }

  static final Map<String, List<String>> _roleCache = {};

  static NetQuality _q(lk.ConnectionQuality? q) {
    switch (q) {
      case lk.ConnectionQuality.excellent:
        return NetQuality.excellent;
      case lk.ConnectionQuality.good:
        return NetQuality.good;
      case lk.ConnectionQuality.poor:
        return NetQuality.poor;
      case lk.ConnectionQuality.lost:
        return NetQuality.lost;
      default:
        return NetQuality.unknown;
    }
  }

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
      quality: _q(p.connectionQuality),
    );
  }

  @override
  String toString() => 'Call($id)';
}
