import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:letsspeak_trainer/rtc/live_room.dart'; // 🎧 LiveKit audio classes (same names as before)
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:letsspeak_trainer/Api/api_headers.dart';
import 'package:letsspeak_trainer/screens/Home_PortalScreen.dart' show StreamManager;

/// 🎙 Special class — everyone (all languages, stages, sections) in ONE live class.
/// Trainers join muted. Mic button works when Sir lets everyone talk (or allowed this trainer).
/// Attendance is marked for the trainer's stage.
class AssemblyJoinScreen extends StatefulWidget {
  final Map<String, dynamic> teacherData;
  final String title;
  final String startTime;
  const AssemblyJoinScreen({
    super.key,
    required this.teacherData,
    this.title = 'Surendra Sir Special Class',
    this.startTime = '',
  });

  @override
  State<AssemblyJoinScreen> createState() => _AssemblyJoinScreenState();
}

enum _Phase { preparing, waiting, joining, live, error }

class _AssemblyJoinScreenState extends State<AssemblyJoinScreen> {
  final Random _rnd = Random();

  _Phase phase = _Phase.preparing;
  String errorText = '';
  Call? call;
  String? attendanceId;
  Timer? _retry;
  Timer? _sync;
  Timer? _tick;
  bool _leaving = false;
  bool _micBusy = false;

  String get _userId => (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '').toString();
  String get _userName => (widget.teacherData['name'] ?? 'Trainer').toString();

  Map<String, String> _headers({bool json = false}) => json ? ApiHeaders.json() : ApiHeaders.auth();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _connect();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _sync?.cancel();
    _tick?.cancel();
    WakelockPlus.disable();
    if (!_leaving) _leave(pop: false);
    super.dispose();
  }

  Future<void> _connect() async {
    _retry?.cancel();
    if (mounted) setState(() => phase = _Phase.preparing);
    try {
      final res = await http
          .post(
            Uri.parse("${ApiEndpoints.baseUrl}/rtc/prepare-call"),
            headers: _headers(json: true),
            body: jsonEncode({"userId": _userId, "type": "assembly"}),
          )
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (res.statusCode != 200) {
        throw Exception(data['error'] ?? 'Server busy (${res.statusCode}). Trying again…');
      }
      if (data['assembly'] == false) {
        setState(() {
          phase = _Phase.error;
          errorText = 'The special class has finished.';
        });
        return;
      }
      if (data['started'] != true) {
        // not live yet → the socket wakes us up; also check every ~30 s just in case
        setState(() => phase = _Phase.waiting);
        _retry = Timer(Duration(seconds: 12 + _rnd.nextInt(6)), _connect);
        return;
      }

      setState(() => phase = _Phase.joining);
      final client = await StreamManager.clientFor(userId: _userId, userName: _userName);
      final c = client.makeCall(callType: StreamCallType.defaultType(), id: data['callId'].toString());
      final joined = await c.join(
        connectOptions: CallConnectOptions(
          camera: TrackOption.disabled(),
          microphone: TrackOption.disabled(), // always join muted
        ),
      );
      if (joined.isFailure) throw Exception('Could not connect. Please try again.');
      call = c;
      // refresh once a second (not on every audio change) → smooth with 2,500 people
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
      if (mounted) setState(() => phase = _Phase.live);
      _markAttendance();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        phase = _Phase.error;
        errorText = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ---- Sir's mic rules (from the call's custom data) ----
  ({bool locked, Set<String> allowed}) _rules() {
    final custom = call?.state.value.custom ?? const <String, Object>{};
    final packed = custom['state'];
    if (packed is String && packed.isNotEmpty) {
      try {
        final m = jsonDecode(packed);
        if (m is Map) {
          final a = m['allowed'];
          return (
            locked: m['micLocked'] != false,
            allowed: a is List ? a.map((e) => e.toString()).toSet() : <String>{},
          );
        }
      } catch (_) {}
    }
    return (locked: true, allowed: <String>{}); // no rules yet → stay muted
  }

  bool get _canSpeak {
    final r = _rules();
    return !r.locked || r.allowed.contains(_userId);
  }

  bool get _micOn {
    final me = call?.state.value.callParticipants.where((p) => p.isLocal).toList() ?? const [];
    return me.isNotEmpty && me.first.isAudioEnabled;
  }

  void _onTick() {
    if (!mounted) return;
    // ⚡ Sir ended the special class (or the connection is gone) → leave at once
    final st = call?.state.value;
    if (!_leaving && st != null && (st.endedAt != null || st.status.isDisconnected)) {
      final ended = st.endedAt != null;
      _leave();
      Get.snackbar(ended ? 'Class finished' : 'Disconnected',
          ended ? 'The special class has ended. Thank you!' : 'The connection to the special class was lost.',
          backgroundColor: const Color(0xFF0E466D), colorText: Colors.white, snackPosition: SnackPosition.TOP);
      return;
    }
    // Sir locked the mics while mine was on → turn it off
    if (_micOn && !_canSpeak) call?.setMicrophoneEnabled(enabled: false);
    setState(() {});
  }

  Future<void> _toggleMic() async {
    final c = call;
    if (c == null || _micBusy) return;
    if (!_micOn && !_canSpeak) {
      Get.snackbar('Mic is locked', 'Sir has muted everyone. You can talk when Sir allows.',
          backgroundColor: const Color(0xFF0E466D), colorText: Colors.white, snackPosition: SnackPosition.TOP);
      return;
    }
    setState(() => _micBusy = true);
    try {
      await c.setMicrophoneEnabled(enabled: !_micOn);
    } catch (e) {
      Get.snackbar('Microphone', 'Could not change the microphone. Allow mic permission and try again.',
          backgroundColor: const Color(0xFFE45757), colorText: Colors.white, snackPosition: SnackPosition.TOP);
    } finally {
      if (mounted) setState(() => _micBusy = false);
    }
  }

  // ---- attendance: join once (server marks every stage), sync every minute, leave ----
  Future<void> _markAttendance() async {
    try {
      final res = await http.post(
        Uri.parse("${ApiEndpoints.baseUrl}/user/join-online-class"),
        headers: _headers(json: true),
        body: jsonEncode({"userId": _userId, "assembly": true}),
      );
      if (res.statusCode == 200) {
        attendanceId = jsonDecode(res.body)['attendanceId']?.toString();
        _sync?.cancel();
        // spread the 2,500 syncs over the minute
        Future.delayed(Duration(seconds: _rnd.nextInt(60)), () {
          if (!mounted || attendanceId == null) return;
          _sync = Timer.periodic(const Duration(seconds: 60), (_) => _post("${ApiEndpoints.baseUrl}/user/sync-online-class"));
        });
      }
    } catch (e) {
      debugPrint('Special class attendance error: $e');
    }
  }

  Future<void> _post(String url) async {
    final id = attendanceId;
    if (id == null) return;
    try {
      await http.post(Uri.parse(url), headers: _headers(json: true), body: jsonEncode({"attendanceId": id}));
    } catch (_) {}
  }

  Future<void> _leave({bool pop = true}) async {
    _leaving = true;
    _retry?.cancel();
    _sync?.cancel();
    _tick?.cancel();
    final c = call;
    call = null;
    if (c != null) {
      try {
        await c.leave();
      } catch (_) {}
    }
    await _post("${ApiEndpoints.baseUrl}/user/leave-online-class");
    attendanceId = null;
    if (pop && mounted) Get.back();
  }

  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B2E47),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B2E47), Color(0xFF155A88)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _leave(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                    Expanded(
                      child: Text('Special class',
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                    if (phase == _Phase.live) _liveBadge(),
                  ],
                ),
              ),
              Expanded(child: Center(child: _body())),
              if (phase == _Phase.live) _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final micOn = _micOn;
    final canSpeak = _canSpeak;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Row(
        children: [
          // 🎤 mute / unmute
          SizedBox(
            width: 64,
            height: 56,
            child: ElevatedButton(
              onPressed: _micBusy ? null : _toggleMic,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: micOn ? Colors.white : Colors.white.withOpacity(canSpeak ? 0.18 : 0.08),
                foregroundColor: micOn ? const Color(0xFF155A88) : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _micBusy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(micOn ? Icons.mic_rounded : (canSpeak ? Icons.mic_off_rounded : Icons.lock_rounded), size: 26),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _leave(),
                icon: const Icon(Icons.call_end_rounded),
                label: Text('Leave class', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE45757),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xFFE45757), borderRadius: BorderRadius.circular(8)),
        child: Text('LIVE', style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      );

  Widget _body() {
    switch (phase) {
      case _Phase.preparing:
      case _Phase.joining:
        return _centerInfo(
          icon: null,
          title: phase == _Phase.preparing ? 'Getting ready…' : 'Joining…',
          subtitle: widget.title,
        );
      case _Phase.waiting:
        return _centerInfo(
          icon: Icons.hourglass_top_rounded,
          title: 'Not started yet',
          subtitle:
              '${widget.title}${widget.startTime.isNotEmpty ? ' starts at ${widget.startTime}' : ''}.\nStay on this page — you join automatically when Sir starts.',
        );
      case _Phase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _centerInfo(icon: Icons.error_outline_rounded, title: 'Could not join', subtitle: errorText),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: Text('Try again', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
            ),
          ],
        );
      case _Phase.live:
        final c = call;
        if (c == null) return const SizedBox.shrink();
        final people = c.state.value.callParticipants;
        final speakers = people.where((p) => p.isSpeaking && !p.isLocal).toList();
        final micOn = _micOn;
        final canSpeak = _canSpeak;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                  border: Border.all(
                    color: speakers.isNotEmpty ? const Color(0xFF28C2C2) : Colors.white24,
                    width: speakers.isNotEmpty ? 4 : 2,
                  ),
                ),
                child: const Icon(Icons.record_voice_over_rounded, color: Colors.white, size: 56),
              ),
              const SizedBox(height: 18),
              Text(widget.title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                speakers.isNotEmpty ? '🔊 ${speakers.first.name} is speaking' : 'Listening…',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _pill(Icons.groups_rounded, '${people.length} in class'),
                  _pill(
                    micOn ? Icons.mic_rounded : (canSpeak ? Icons.mic_off_rounded : Icons.lock_rounded),
                    micOn ? 'You are talking' : (canSpeak ? 'You can unmute' : 'Mics locked by Sir'),
                  ),
                  _pill(Icons.check_circle_rounded, 'Attendance counted'),
                ],
              ),
            ],
          ),
        );
    }
  }

  Widget _centerInfo({IconData? icon, required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
          else
            Icon(icon, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 5),
            Text(text, style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
