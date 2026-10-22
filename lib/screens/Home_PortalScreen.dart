import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:letsspeak_trainer/rtc/live_room.dart'; // 🎧 LiveKit audio classes (same names as before)
import 'package:letsspeak_trainer/rtc/live_room.dart' as svf show Priority;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:get_storage/get_storage.dart';
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:letsspeak_trainer/Api/api_headers.dart';
import 'package:letsspeak_trainer/Api/batch_slots.dart';
import 'package:letsspeak_trainer/screens/TeacherLoginScreen.dart';
import 'package:letsspeak_trainer/screens/AssemblyJoinScreen.dart';
import 'package:letsspeak_trainer/screens/BestStudentsScreen.dart';

const double instituteLat = 17.729417;
const double instituteLng = 83.312231;
const double allowedRadius = 40.0;

// =========================================================================
// 🚀 STREAM MANAGER — token + client are prepared when the portal opens,
// so "Start live class" only has to join (no token / connect wait).
// =========================================================================
class StreamManager {
  static StreamVideo? _cachedClient;
  static String? _cachedUserId;
  static String? _token;
  static DateTime? _tokenAt;
  static String _apiKey = 'urzyyp7kctqv';
  static Future<StreamVideo>? _pending;

  // Server tokens last 6 h; renew after 5 h
  static bool get _tokenFresh =>
      _token != null &&
      _tokenAt != null &&
      DateTime.now().difference(_tokenAt!) < const Duration(hours: 5);

  static Future<void> _fetchToken(String userId) async {
    final res = await http
        .post(
          Uri.parse(ApiEndpoints.streamToken),
          headers: ApiHeaders.json(),
          // Server decides the Stream role from the database (trainer → admin)
          body: jsonEncode({"userId": userId}),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode == 401) {
      throw Exception("Session expired. Please log out and log in again.");
    }
    if (res.statusCode != 200) {
      throw Exception("Failed to authorize stream (${res.statusCode})");
    }
    final data = jsonDecode(res.body);
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) throw Exception("Class token missing");
    _token = token;
    _apiKey = data['apiKey']?.toString() ?? _apiKey;
    _tokenAt = DateTime.now();
  }

  /// Returns a connected client. Several callers at once share one request.
  static Future<StreamVideo> clientFor({
    required String userId,
    required String userName,
  }) {
    final cached = _cachedClient;
    if (cached != null && _cachedUserId == userId) {
      // Never swap the client while a class is running on it
      if (_tokenFresh || ClassroomController.instance.call != null) {
        return Future.value(cached);
      }
    }
    return _pending ??= _create(userId, userName).whenComplete(() {
      _pending = null;
    });
  }

  static Future<StreamVideo> _create(String userId, String userName) async {
    if (!_tokenFresh || _cachedUserId != userId) await _fetchToken(userId);
    try {
      await StreamVideo.reset(disconnect: true);
    } catch (_) {}
    _cachedClient = StreamVideo(
      _apiKey,
      user: User.regular(userId: userId, name: userName),
      userToken: _token!,
      options: StreamVideoOptions(logPriority: svf.Priority.warning),
    );
    _cachedUserId = userId;
    return _cachedClient!;
  }

  /// Old API (kept so any other screen that still calls it keeps working)
  static Future<StreamVideo> getClient({
    required String userId,
    required String userName,
    required String token,
    String apiKey = 'urzyyp7kctqv',
  }) async {
    if (_cachedClient != null && _cachedUserId == userId) return _cachedClient!;
    _token = token;
    _tokenAt = DateTime.now();
    _apiKey = apiKey;
    try {
      await StreamVideo.reset(disconnect: true);
    } catch (_) {}
    _cachedClient = StreamVideo(
      apiKey,
      user: User.regular(userId: userId, name: userName),
      userToken: token,
      options: StreamVideoOptions(logPriority: svf.Priority.warning),
    );
    _cachedUserId = userId;
    return _cachedClient!;
  }

  /// Fire-and-forget warm-up (called when the trainer portal opens)
  static void prewarm({required String userId, required String userName}) {
    if (userId.isEmpty) return;
    clientFor(userId: userId, userName: userName).then(
      (_) => debugPrint("Stream ready ✅"),
      onError: (e) => debugPrint("Stream prewarm failed: $e"),
    );
  }

  static Future<void> reset() async {
    try {
      await StreamVideo.reset(disconnect: true);
    } catch (_) {}
    _cachedClient = null;
    _cachedUserId = null;
    _token = null;
    _tokenAt = null;
  }
}

/// After a failed join, Stream finishes leaving the call a moment later and
/// stores the real reason in the call status. Wait for it (max 4 s).
Future<String> joinFailReason(Call call, Object result) async {
  var status = "${call.state.value.status}";
  for (var i = 0; i < 40 && !status.contains('Disconnected'); i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    status = "${call.state.value.status}";
  }
  final text = "$result\n$status";
  return text.length > 600 ? text.substring(0, 600) : text;
}

// =========================================================================
// 🎤 CLASSROOM CONTROLLER — mic lock + speaking-practice queue
//
// The state is shared with students through the Stream call's custom data
// (call.update(custom: ...)), so every student sees it instantly:
//   micLocked  → students cannot unmute
//   allowed    → students the trainer allowed to speak while locked
//   pCurrent   → who is practicing now, pNext → who is next
// It lives outside the screen, so it survives minimize (PiP) and reopen.
// =========================================================================
class PracticeEntry {
  final String id;
  final String name;
  const PracticeEntry(this.id, this.name);
}

class ClassroomController {
  ClassroomController._();
  static final ClassroomController instance = ClassroomController._();

  Call? call;
  String language = 'English';
  String stage = 'stage1';
  String section = '';
  String teacherId = '';
  DateTime? startedAt;

  final RxBool micLocked = false.obs;
  final RxSet<String> allowed = <String>{}.obs;

  final Rxn<PracticeEntry> current = Rxn<PracticeEntry>();
  final RxList<PracticeEntry> queue = <PracticeEntry>[].obs; // waiting (current not included)
  final RxList<PracticeEntry> done = <PracticeEntry>[].obs; // practiced in this round
  final RxSet<String> practicedToday = <String>{}.obs; // whole day, from the server
  final RxMap<String, int> ratings = <String, int>{}.obs; // ⭐ studentId → 1..5 (today)
  final Rxn<DateTime> currentSince = Rxn<DateTime>();
  final RxBool saving = false.obs;

  // Students in this class today who are NOT in this batch time (not counted)
  final RxList<Map<String, dynamic>> otherBatch = <Map<String, dynamic>>[].obs;
  Timer? _visitorTimer;

  bool isOtherBatch(String userId) =>
      otherBatch.any((v) => v['userId']?.toString() == userId);

  // 🔀 SECTION MERGE — other sections sitting in THIS class today
  // (their attendance + practice are still saved in their own section)
  final RxList<String> guestSections = <String>[].obs; // ["B", "C"]
  final RxMap<String, String> mergedFrom = <String, String>{}.obs; // studentId → "B"
  final RxList<Map<String, dynamic>> guestStudents = <Map<String, dynamic>>[].obs;

  Future<void> loadMerge() async {
    if (language.toLowerCase() == 'hindi' || section.isEmpty) {
      guestSections.clear();
      mergedFrom.clear();
      guestStudents.clear();
      return;
    }
    try {
      final res = await http
          .get(
            Uri.parse(
              "${ApiEndpoints.trainerRoster}?stage=$stage&language=$language&section=$section&mode=online&_t=${DateTime.now().millisecondsSinceEpoch}",
            ),
            headers: ApiHeaders.auth(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final merge = data['merge'];
      final List students = data['students'] ?? [];
      final guests = students
          .whereType<Map>()
          .where((s) => (s['mergedFrom'] ?? '').toString().isNotEmpty)
          .map((s) => Map<String, dynamic>.from(s))
          .toList();
      guestSections.assignAll(
        merge is Map && merge['guestSections'] is List
            ? (merge['guestSections'] as List).map((e) => e.toString())
            : const <String>[],
      );
      guestStudents.assignAll(guests);
      mergedFrom
        ..clear()
        ..addAll({for (final g in guests) g['_id'].toString(): g['mergedFrom'].toString()});
    } catch (e) {
      debugPrint("Merge info error: $e");
    }
  }

  StreamSubscription<CallState>? _stateSub;
  Timer? _publishTimer;
  final Map<String, DateTime> _lastAutoMute = {};

  bool get practiceActive => current.value != null || queue.isNotEmpty;
  int get practiceTotal =>
      done.length + queue.length + (current.value == null ? 0 : 1);

  bool isStaff(CallParticipantState p) =>
      p.roles.contains('admin') || p.userId == teacherId;

  int queuePosition(String id) {
    final i = queue.indexWhere((e) => e.id == id);
    return i < 0 ? 0 : i + 1;
  }

  bool isQueued(String id) =>
      current.value?.id == id || queue.any((e) => e.id == id);

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------
  void begin({
    required Call call,
    required String language,
    required String stage,
    required String section,
    required String teacherId,
  }) {
    _stateSub?.cancel();
    this.call = call;
    this.language = language;
    this.stage = stage;
    this.section = section;
    this.teacherId = teacherId;
    startedAt = DateTime.now();
    micLocked.value = false;
    allowed.clear();
    current.value = null;
    currentSince.value = null;
    queue.clear();
    done.clear();
    _lastAutoMute.clear();

    // Enforce the lock even while the trainer is on another screen / PiP
    _stateSub = call.state.asStream().listen(_enforce);

    _publishNow(); // fresh class: mics open, no practice
    loadPracticedToday();
    otherBatch.clear();
    loadOtherBatch();
    _visitorTimer?.cancel();
    guestSections.clear();
    mergedFrom.clear();
    guestStudents.clear();
    loadMerge();
    _visitorTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      loadOtherBatch();
      loadMerge();
    });
  }

  Future<void> loadOtherBatch() async {
    try {
      final res = await http
          .get(
            // Only students of THIS trainer's section (+ merged sections)
            Uri.parse(
              "${ApiEndpoints.batchVisitors}?language=$language&stage=$stage&section=${section.isEmpty ? 'all' : section}",
            ),
            headers: ApiHeaders.auth(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['visitors'] ?? [];
        otherBatch.assignAll(list.whereType<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint("Other batch load error: $e");
    }
  }

  /// Trainer leaves (students may stay): open the mics so nobody is stuck muted.
  Future<void> finish() async {
    if (micLocked.value || practiceActive) {
      micLocked.value = false;
      allowed.clear();
      current.value = null;
      queue.clear();
      await _publishNow();
    }
    _stateSub?.cancel();
    _stateSub = null;
    _publishTimer?.cancel();
    _visitorTimer?.cancel();
    call = null;
    startedAt = null;
  }

  // ---------------------------------------------------------------------
  // Mic lock
  // ---------------------------------------------------------------------
  Future<void> setMicLock(bool locked) async {
    micLocked.value = locked;
    allowed.clear();
    if (locked) {
      final cur = current.value;
      if (cur != null) allowed.add(cur.id); // practicing student keeps the mic
      await _muteStudents();
    }
    await _publishNow();
  }

  Future<void> setAllowed(String userId, bool allow) async {
    if (allow) {
      allowed.add(userId);
    } else {
      allowed.remove(userId);
      _mute([userId]);
    }
    await _publishNow();
  }

  Future<void> muteOne(String userId) async => _mute([userId]);

  Future<void> _muteStudents() async {
    final c = call;
    if (c == null) return;
    final ids = c.state.value.callParticipants
        .where((p) => !isStaff(p) && !allowed.contains(p.userId))
        .map((p) => p.userId)
        .toSet()
        .toList();
    _mute(ids);
  }

  void _mute(List<String> ids) {
    final c = call;
    if (c == null || ids.isEmpty) return;
    c.muteUsers(userIds: ids).then((r) {
      if (r.isFailure) debugPrint("Mute failed: $r");
    });
  }

  // A student on an old app version (or a race) unmuted while locked → mute again
  void _enforce(CallState state) {
    if (!micLocked.value || call == null) return;
    final now = DateTime.now();
    final offenders = <String>[];
    for (final p in state.callParticipants) {
      if (isStaff(p) || allowed.contains(p.userId) || !p.isAudioEnabled) continue;
      final last = _lastAutoMute[p.userId];
      if (last != null && now.difference(last).inSeconds < 3) continue;
      _lastAutoMute[p.userId] = now;
      offenders.add(p.userId);
    }
    if (offenders.isNotEmpty) _mute(offenders);
  }

  // ---------------------------------------------------------------------
  // Practice queue
  // ---------------------------------------------------------------------
  void addToQueue(List<PracticeEntry> entries) {
    for (final e in entries) {
      if (isQueued(e.id)) continue;
      done.removeWhere((d) => d.id == e.id); // picked again → practice again
      queue.add(e);
    }
    if (current.value == null) _advance();
    _schedulePublish();
  }

  void makeCurrent(PracticeEntry e) {
    final cur = current.value;
    if (cur?.id == e.id) return;
    queue.removeWhere((q) => q.id == e.id);
    done.removeWhere((d) => d.id == e.id);
    if (cur != null) {
      _releaseSpeaker(cur.id);
      queue.insert(0, cur); // previous one goes back to the front
    }
    _setCurrent(e);
    _schedulePublish();
  }

  void removeFromQueue(String id) {
    if (current.value?.id == id) {
      _releaseSpeaker(id);
      _advance();
    } else {
      queue.removeWhere((q) => q.id == id);
    }
    _schedulePublish();
  }

  void moveUp(String id) {
    final i = queue.indexWhere((q) => q.id == id);
    if (i <= 0) return;
    final e = queue.removeAt(i);
    queue.insert(i - 1, e);
    _schedulePublish();
  }

  /// Saves to the server first; only then moves on (so nothing is lost offline).
  Future<bool> markCurrentPracticed() async {
    final cur = current.value;
    if (cur == null || saving.value) return false;
    saving.value = true;
    final ok = await _savePractice(cur, true);
    saving.value = false;
    if (!ok) return false;
    practicedToday.add(cur.id);
    done.removeWhere((d) => d.id == cur.id);
    done.add(cur);
    _releaseSpeaker(cur.id);
    _advance();
    await _publishNow();
    return true;
  }

  /// Not ready / not answering → goes to the end of the line
  void skipCurrent() {
    final cur = current.value;
    if (cur == null) return;
    _releaseSpeaker(cur.id);
    queue.add(cur);
    _advance();
    _schedulePublish();
  }

  Future<bool> undoPractice(PracticeEntry e) async {
    final ok = await _savePractice(e, false);
    if (ok) {
      practicedToday.remove(e.id);
      done.removeWhere((d) => d.id == e.id);
      _schedulePublish();
    }
    return ok;
  }

  void endRound() {
    final cur = current.value;
    if (cur != null) _releaseSpeaker(cur.id);
    current.value = null;
    currentSince.value = null;
    queue.clear();
    done.clear();
    _schedulePublish();
  }

  void _advance() {
    if (queue.isEmpty) {
      current.value = null;
      currentSince.value = null;
      return;
    }
    _setCurrent(queue.removeAt(0));
  }

  void _setCurrent(PracticeEntry e) {
    current.value = e;
    currentSince.value = DateTime.now();
    if (micLocked.value) allowed.add(e.id); // their turn → mic unlocked for them
  }

  // Their turn is over → take the mic back
  void _releaseSpeaker(String id) {
    allowed.remove(id);
    _mute([id]);
  }

  // ---------------------------------------------------------------------
  // Server
  // ---------------------------------------------------------------------
  Future<bool> _savePractice(PracticeEntry e, bool practiced) async {
    try {
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.practiceMark),
            headers: ApiHeaders.json(),
            body: jsonEncode({
              "studentId": e.id,
              "studentName": e.name,
              "language": language,
              "stage": stage,
              "section": section,
              "practiced": practiced,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return true;
      debugPrint("Practice save failed: ${res.statusCode} ${res.body}");
    } catch (err) {
      debugPrint("Practice save error: $err");
    }
    return false;
  }

  /// ⭐ Trainer's 1–5 rating for today's practice (+ optional quick tags)
  Future<bool> ratePractice(PracticeEntry e, int rating, List<String> tags) async {
    try {
      final res = await http
          .post(
            Uri.parse("${ApiEndpoints.baseUrl}/practice/rate"),
            headers: ApiHeaders.json(),
            body: jsonEncode({
              "studentId": e.id,
              "language": language,
              "stage": stage,
              "rating": rating,
              "tags": tags,
              "note": tags.join(', '),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        ratings[e.id] = rating;
        return true;
      }
      debugPrint("Rate failed: ${res.statusCode} ${res.body}");
    } catch (err) {
      debugPrint("Rate error: $err");
    }
    return false;
  }

  Future<void> loadPracticedToday() async {
    try {
      final res = await http
          .get(
            Uri.parse(
              "${ApiEndpoints.practiceList}?language=$language&stage=$stage",
            ),
            headers: ApiHeaders.auth(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List records = data['records'] ?? [];
        practicedToday
          ..clear()
          ..addAll(records.map((r) => r['userId'].toString()));
        ratings.clear();
        for (final r in records) {
          final v = int.tryParse('${r['rating'] ?? 0}') ?? 0;
          if (v > 0) ratings[r['userId'].toString()] = v;
        }
      }
    } catch (e) {
      debugPrint("Load practice error: $e");
    }
  }

  void _schedulePublish() {
    _publishTimer?.cancel();
    _publishTimer = Timer(const Duration(milliseconds: 200), _publishNow);
  }

  Future<void> _publishNow() async {
    _publishTimer?.cancel();
    final c = call;
    if (c == null) return;
    final cur = current.value;
    final next = queue.isNotEmpty ? queue.first : null;
    try {
      // ⚠️ Everything is packed into ONE text value. Stream turns empty
      // lists/strings into null, and ONE null in the call's custom data makes
      // every join crash in Stream 1.5 ("connect cancelled"). A JSON text is
      // never empty, so it can never become null.
      final state = jsonEncode({
        'micLocked': micLocked.value,
        'allowed': allowed.toList(),
        'pActive': practiceActive,
        'pCurrent': cur?.id ?? '',
        'pCurrentName': cur?.name ?? '',
        'pNext': next?.id ?? '',
        'pNextName': next?.name ?? '',
        'pQueue': queue.map((e) => e.id).toList(),
        'pDone': done.length,
        'pTotal': practiceTotal,
      });
      final r = await c.update(
        custom: <String, Object>{
          'state': state,
          'ts': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (r.isFailure) debugPrint("Class state publish failed: $r");
    } catch (e) {
      debugPrint("Class state publish error: $e");
    }
  }
}

// =========================================================================
// ⏱️ TRAINER ONLINE ATTENDANCE SESSION (join → sync every minute → leave)
// The server counts minutes from its own clock; the app only sends checkpoints.
// =========================================================================
class TrainerOnlineSession {
  static String? attendanceId;
  static Timer? _syncTimer;

  static Future<void> start({
    required String teacherId,
    required String language,
    required String stage,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("${ApiEndpoints.baseUrl}/user/join-online-class"),
        headers: ApiHeaders.json(),
        body: jsonEncode({
          "userId": teacherId,
          "language": language,
          "stage": stage,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        attendanceId = data['attendanceId']?.toString();
      } else {
        debugPrint("Join class failed: ${res.statusCode} ${res.body}");
      }
    } catch (e) {
      debugPrint("Join class error: $e");
    }

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) => sync());
  }

  static Future<void> sync() async {
    final id = attendanceId;
    if (id == null) return;
    try {
      await http.post(
        Uri.parse("${ApiEndpoints.baseUrl}/user/sync-online-class"),
        headers: ApiHeaders.json(),
        body: jsonEncode({"attendanceId": id}),
      );
    } catch (e) {
      debugPrint("Sync class error: $e");
    }
  }

  static Future<void> leave() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    final id = attendanceId;
    attendanceId = null;
    if (id == null) return;
    try {
      await http.post(
        Uri.parse("${ApiEndpoints.baseUrl}/user/leave-online-class"),
        headers: ApiHeaders.json(),
        body: jsonEncode({"attendanceId": id}),
      );
    } catch (e) {
      debugPrint("Leave class error: $e");
    }
  }
}

// 🌐 Safe Global Overlay Controller
class GlobalAudioOverlayController {
  static OverlayEntry? _overlayEntry;
  static Call? currentCall;
  static String? currentTeacherId;
  static String? currentClassName;
  static Map<String, dynamic>? currentTeacherData;
  static List<dynamic>? currentStudents;

  static final RxBool isCallActive = false.obs;

  static void showOverlay(
    BuildContext context,
    Call call,
    String teacherId,
    String className,
    Map<String, dynamic> teacherData,
    List<dynamic> students,
  ) {
    if (_overlayEntry != null) return;
    currentCall = call;
    currentTeacherId = teacherId;
    currentClassName = className;
    currentTeacherData = teacherData;
    currentStudents = students;
    isCallActive.value = true;

    final overlayState = Overlay.of(context);
    if (overlayState == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => const FloatingTrainerPiPWidget(),
    );

    overlayState.insert(_overlayEntry!);
  }

  static void removeOverlay() {
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    _overlayEntry = null;
    currentCall = null;
    isCallActive.value = false;
  }
}

class FloatingTrainerPiPWidget extends StatefulWidget {
  const FloatingTrainerPiPWidget({super.key});

  @override
  State<FloatingTrainerPiPWidget> createState() =>
      _FloatingTrainerPiPWidgetState();
}

class _FloatingTrainerPiPWidgetState extends State<FloatingTrainerPiPWidget> {
  Offset _position = const Offset(20, 100);

  static const Color navy = Color(0xFF155A88);
  static const Color deepNavy = Color(0xFF0E466D);
  static const Color blue = Color(0xFF2C6F9F);
  static const Color teal = Color(0xFF28C2C2);
  static const Color yellow = Color(0xFFF7DF55);
  static const Color lightBlue = Color(0xFFE8F2F8);
  static const Color textDark = Color(0xFF123B57);
  static const Color mutedText = Color(0xFF6B8294);
  static const Color red = Color(0xFFE45757);

  String _participantInitial(String name) {
    final value = name.trim();
    if (value.isEmpty) return "?";
    return value.substring(0, 1).toUpperCase();
  }

  String _speakerName(dynamic speaker) {
    if (speaker == null) return "";
    final name = speaker.name?.toString().trim() ?? "";
    if (name.isNotEmpty) return name;
    final userId = speaker.userId?.toString().trim() ?? "";
    if (userId.isNotEmpty) return userId;
    return "Someone";
  }

  @override
  Widget build(BuildContext context) {
    final call = GlobalAudioOverlayController.currentCall;
    final teacherId = GlobalAudioOverlayController.currentTeacherId;
    final teacherData = GlobalAudioOverlayController.currentTeacherData;
    final students = GlobalAudioOverlayController.currentStudents;

    if (call == null || teacherId == null || teacherData == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 270,
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: teal, width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: navy.withOpacity(0.22),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: StreamBuilder<CallState>(
              stream: call.state.asStream(),
              builder: (context, snapshot) {
                final callState = snapshot.data;
                final rawParticipants = callState?.callParticipants ?? [];

                final seenIds = <String>{};
                final participants = rawParticipants.where((p) {
                  if (seenIds.contains(p.userId)) return false;
                  seenIds.add(p.userId);
                  return true;
                }).toList();

                final localParticipant = participants.firstWhereOrNull(
                  (p) => p.userId == teacherId,
                );

                final bool isMuted = localParticipant != null
                    ? !localParticipant.isAudioEnabled
                    : false;

                final speakingParticipants = participants
                    .where((p) => p.isSpeaking)
                    .toList();

                final speaker = speakingParticipants.isNotEmpty
                    ? speakingParticipants.first
                    : null;

                final speakerName = _speakerName(speaker);
                final int studentCount = participants
                    .where((p) => !p.roles.contains('admin') && p.userId != teacherId)
                    .length;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [navy, blue],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.graphic_eq_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF20A879),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    "LIVE STUDIO",
                                    style: GoogleFonts.poppins(
                                      color: teal,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .3,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                "Live classroom",
                                style: GoogleFonts.poppins(
                                  color: mutedText,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            GlobalAudioOverlayController.removeOverlay();
                            final String lang =
                                teacherData['language']?.toString() ??
                                    'English';
                            final String stg =
                                (teacherData['teacherStage'] ??
                                        teacherData['stage'] ??
                                        'stage1')
                                    .toString();
                            final String sec =
                                (teacherData['teacherSection'] ??
                                        teacherData['section'] ??
                                        'a')
                                    .toString();

                            Get.to(
                              () => TeacherBroadcastScreen(
                                call: call,
                                language: lang,
                                stage: stg,
                                section: sec,
                                enrolledStudents: students ?? [],
                                teacherData: teacherData,
                              ),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.open_in_full_rounded,
                              color: navy,
                              size: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: speaker != null
                            ? const Color(0xFFE9FBFB)
                            : lightBlue,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: speaker != null
                              ? teal.withOpacity(.45)
                              : const Color(0xFFD5E4ED),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (speaker != null) ...[
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: teal,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: teal.withOpacity(.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _participantInitial(speakerName),
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.graphic_eq_rounded,
                                        color: teal,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "NOW SPEAKING",
                                        style: GoogleFonts.poppins(
                                          color: teal,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: .4,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    speakerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      color: textDark,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const _SpeakingBars(),
                          ] else ...[
                            Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: Color(0xFFDCEAF3),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.mic_none_rounded,
                                color: blue,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "NO ONE SPEAKING",
                                    style: GoogleFonts.poppins(
                                      color: mutedText,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .35,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    "Waiting for audio…",
                                    style: GoogleFonts.poppins(
                                      color: textDark,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Obx(() {
                      final cc = ClassroomController.instance;
                      final cur = cc.current.value;
                      final locked = cc.micLocked.value;
                      if (cur == null && !locked) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              cur != null
                                  ? Icons.record_voice_over_rounded
                                  : Icons.lock_rounded,
                              size: 13,
                              color: cur != null ? teal : const Color(0xFFC78B00),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                cur != null
                                    ? "${cur.name} practicing • ${cc.done.length}/${cc.practiceTotal}"
                                    : "Student mics locked",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  color: textDark,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: isMuted
                                  ? const Color(0xFFE8F2F8)
                                  : const Color(0xFFFFF4D5),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isMuted
                                    ? const Color(0xFFD5E4ED)
                                    : yellow.withOpacity(.75),
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                try {
                                  await call.setMicrophoneEnabled(
                                    enabled: isMuted,
                                  );
                                  setState(() {});
                                } catch (e) {
                                  debugPrint("PiP Audio Toggle Error: $e");
                                }
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isMuted
                                        ? Icons.mic_off_rounded
                                        : Icons.mic_rounded,
                                    color: isMuted ? navy : deepNavy,
                                    size: 15,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isMuted ? "UNMUTE" : "MUTE",
                                    style: GoogleFonts.poppins(
                                      color: deepNavy,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(
                            color: lightBlue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.people_alt_rounded,
                                color: navy,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                "$studentCount",
                                style: GoogleFonts.poppins(
                                  color: textDark,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeakingBars extends StatelessWidget {
  const _SpeakingBars();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 25,
      height: 22,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [_bar(7), _bar(14), _bar(10), _bar(18), _bar(9)],
      ),
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF28C2C2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class TeacherPortalScreen extends StatefulWidget {
  final Map<String, dynamic> teacherData;

  const TeacherPortalScreen({super.key, required this.teacherData});

  @override
  State<TeacherPortalScreen> createState() => _TeacherPortalScreenState();
}

class _TeacherPortalScreenState extends State<TeacherPortalScreen>
    with WidgetsBindingObserver {
  List<dynamic> allAssignedStudents = [];
  String activeFilter = "all";
  String activeBatch = "all"; // "all" | "none" | canonical batch label
  bool isStartingBroadcast = false;
  IO.Socket? _ioSocket;
  Timer? _pollingTimer;

  // 🌐 offline-online day / 🎙 special class — switched by the admin
  Map<String, dynamic>? _rainMode;
  Map<String, dynamic>? _assemblyMode;

  // 🔀 today's section merge for this trainer (from the roster)
  Map<String, dynamic>? _merge;
  bool _unmerging = false;
  String? get _mergedIntoHost {
    final m = _merge?['mergedInto'];
    return m is Map ? m['hostSection']?.toString() : null;
  }

  String? get _mergeId {
    final m = _merge?['mergedInto'];
    return m is Map ? m['id']?.toString() : null;
  }

  List<String> get _guestSections {
    final g = _merge?['guestSections'];
    return g is List ? g.map((e) => e.toString()).toList() : const [];
  }
  bool get _rainOn => _rainMode?['active'] == true;
  bool get _assemblyOn => _assemblyMode?['active'] == true;

  static const Color backgroundColor = Color(0xffE8F2F8);
  static const Color cardColor = Color(0xffFFFFFF);
  static const Color surfaceColor = Color(0xffF5F9FC);
  static const Color brandNavy = Color(0xff155A88);
  static const Color brandBlue = Color(0xff2C6F9F);
  static const Color accentBlue = Color(0xff7CA4D8);
  static const Color accentGreen = Color(0xff28C2C2);
  static const Color goldenYellow = Color(0xffF7DF55);
  static const Color accentRed = Color(0xffE85D5D);
  static const Color textPrimary = Color(0xff16324A);
  static const Color textSecondary = Color(0xff667F95);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fetchAssignedStudentsSilent();
    _initSocket();

    // ⚡ Get the class token + Stream connection ready now, so "Start live
    // audio class" only has to join (saves several seconds).
    // (Offline trainers too: online days and the special class are online.)
    StreamManager.prewarm(
      userId: (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
          .toString(),
      userName: widget.teacherData['name']?.toString() ?? 'Teacher',
    );
    _fetchClassMode();

    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      fetchAssignedStudentsSilent();
      _fetchClassMode();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _ioSocket?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      fetchAssignedStudentsSilent();
      _fetchClassMode();
    }
  }

  Future<void> _fetchClassMode() async {
    try {
      final res = await http
          .get(Uri.parse("${ApiEndpoints.baseUrl}/class-mode"))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(res.body);
      final rain = data['rain'] is Map ? Map<String, dynamic>.from(data['rain']) : null;
      final assembly = data['assembly'] is Map ? Map<String, dynamic>.from(data['assembly']) : null;
      if (jsonEncode(rain) != jsonEncode(_rainMode) || jsonEncode(assembly) != jsonEncode(_assemblyMode)) {
        setState(() {
          _rainMode = rain;
          _assemblyMode = assembly;
        });
      }
    } catch (e) {
      debugPrint("Class mode error: $e");
    }
  }

  void _initSocket() {
    try {
      final String teacherId =
          (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
              .toString();

      // Socket.IO must connect to the server root, NOT ".../api"
      // (the path would be treated as a namespace and never receive events).
      final uri = Uri.parse(ApiEndpoints.baseUrl);
      final host = "${uri.scheme}://${uri.host}:${uri.port}";

      _ioSocket = IO.io(host, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'auth': {'token': ApiHeaders.token ?? ''},
      });

      _ioSocket?.onConnect((_) {
        debugPrint("Trainer Socket connected for instant updates");
        _ioSocket?.emit('join_user_room', teacherId);
      });

      _ioSocket?.on('permissions_updated', (_) {
        fetchAssignedStudentsSilent();
      });

      _ioSocket?.on('student_update', (_) {
        fetchAssignedStudentsSilent();
      });
      _ioSocket?.on('attendance_update', (_) {
        fetchAssignedStudentsSilent();
      });
      // 🔀 admin merged / unmerged sections → roster + live class update instantly
      _ioSocket?.on('merge_updated', _onMergeUpdated);
      // admin switched online-day / special class → update instantly (state comes with the event)
      _ioSocket?.on('class_mode_update', (data) {
        if (data is Map && data.containsKey('rain') && mounted) {
          setState(() {
            _rainMode = data['rain'] is Map ? Map<String, dynamic>.from(data['rain']) : null;
            _assemblyMode = data['assembly'] is Map ? Map<String, dynamic>.from(data['assembly']) : null;
          });
        } else {
          _fetchClassMode();
        }
      });
    } catch (e) {
      debugPrint("Socket error: $e");
    }
  }

  void _onMergeUpdated(dynamic data) {
    if (data is! Map) {
      fetchAssignedStudentsSilent();
      return;
    }
    final myStage = (widget.teacherData['teacherStage'] ?? widget.teacherData['stage'] ?? 'stage1')
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
    final mySection = (widget.teacherData['teacherSection'] ?? widget.teacherData['section'] ?? '')
        .toString()
        .toUpperCase();
    final stage = (data['stage'] ?? '').toString().toLowerCase();
    final host = (data['hostSection'] ?? '').toString().toUpperCase();
    final guests = (data['guestSections'] is List ? data['guestSections'] as List : const [])
        .map((e) => e.toString().toUpperCase())
        .toList();
    if (stage != myStage || (host != mySection && !guests.contains(mySection))) return;

    fetchAssignedStudentsSilent();
    if (ClassroomController.instance.call != null) ClassroomController.instance.loadMerge();

    final merged = data['action'] == 'merged';
    final iAmHost = host == mySection;
    final text = iAmHost
        ? (merged
            ? 'Section ${guests.join(', ')} joined your class today. Their students are moving in now.'
            : 'Section ${guests.join(', ')} went back to their own class.')
        : (merged
            ? 'Your section is merged into Section $host today. Your students are in Section $host\'s class.'
            : 'Unmerged — Section $mySection is your own class again. Start your class.');
    Get.snackbar(
      merged ? 'Section merge' : 'Section unmerged',
      text,
      backgroundColor: merged ? brandNavy : accentGreen,
      colorText: Colors.white,
      icon: const Icon(Icons.merge_type_rounded, color: Colors.white),
      duration: const Duration(seconds: 5),
      margin: const EdgeInsets.all(14),
    );
  }

  /// Section B's trainer is back → ends the merge, students go back to B
  Future<void> _unmergeMine() async {
    final id = _mergeId;
    final host = _mergedIntoHost;
    if (id == null || _unmerging) return;
    final ok = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text("I'm back — unmerge?",
            style: GoogleFonts.poppins(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text(
          'Your students leave Section $host\'s class and come back to yours. Start your live class right after.',
          style: GoogleFonts.poppins(color: textSecondary, fontSize: 12.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Not now', style: GoogleFonts.poppins(color: textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(backgroundColor: brandNavy, foregroundColor: Colors.white, elevation: 0),
            child: Text('Unmerge', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _unmerging = true);
    try {
      final res = await http.delete(
        Uri.parse("${ApiEndpoints.baseUrl}/admin/section-merges/$id"),
        headers: ApiHeaders.auth(),
      );
      if (res.statusCode == 200) {
        await fetchAssignedStudentsSilent();
      } else {
        String msg = 'Could not unmerge (${res.statusCode}).';
        try {
          msg = (jsonDecode(res.body)['message'] ?? msg).toString();
        } catch (_) {}
        Get.snackbar('Not unmerged', msg, backgroundColor: accentRed, colorText: Colors.white, margin: const EdgeInsets.all(14));
      }
    } catch (e) {
      Get.snackbar('Connection error', '$e', backgroundColor: accentRed, colorText: Colors.white, margin: const EdgeInsets.all(14));
    } finally {
      if (mounted) setState(() => _unmerging = false);
    }
  }

  Future<void> fetchAssignedStudentsSilent() async {
    try {
      final String language =
          widget.teacherData['language']?.toString() ?? 'English';

      var rawStage =
          widget.teacherData['teacherStage'] ??
          widget.teacherData['stage'] ??
          widget.teacherData['assignedStage'] ??
          'stage1';
      final String stage = rawStage.toString().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        '',
      );

      var rawSection =
          widget.teacherData['teacherSection'] ??
          widget.teacherData['section'] ??
          widget.teacherData['assignedSection'] ??
          'A';
      final String section = rawSection.toString().toUpperCase().trim();

      final String teacherMode =
          widget.teacherData['mode']?.toString().toLowerCase() ?? 'online';

      final querySection = (language.toLowerCase() == 'hindi')
          ? 'all'
          : section;

      final response = await http.get(
        Uri.parse(
          "${ApiEndpoints.trainerRoster}?stage=$stage&language=$language&section=$querySection&mode=$teacherMode",
        ),
        headers: ApiHeaders.auth(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List students = data['students'] ?? [];

        if (mounted) {
          setState(() {
            _merge = data['merge'] is Map ? Map<String, dynamic>.from(data['merge']) : null;
            allAssignedStudents = students.where((s) {
              final role = (s['role'] ?? 'student').toString().toLowerCase();
              return role == 'student';
            }).toList();
          });
        }
      } else if (response.statusCode == 401) {
        debugPrint("Roster 401: session expired, please log in again.");
      } else {
        debugPrint("Roster failed: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    }
  }

  Future<void> _handleOfflineGeoCheckIn() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Get.snackbar(
          "GPS Disabled",
          "Please enable location services.",
          backgroundColor: accentRed,
          colorText: Colors.white,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Get.snackbar(
            "Permission Denied",
            "Location required for check-in.",
            backgroundColor: accentRed,
            colorText: Colors.white,
          );
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        instituteLat,
        instituteLng,
      );

      if (distance > allowedRadius) {
        Get.snackbar(
          "Out of Range",
          "You are ${distance.toInt()}m away from institute.",
          backgroundColor: accentRed,
          colorText: Colors.white,
        );
        return;
      }

      final teacherId =
          (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
              .toString();
      final res = await http.post(
        Uri.parse(ApiEndpoints.markAttendance),
        headers: ApiHeaders.json(),
        body: jsonEncode({
          "userId": teacherId,
          "stage":
              widget.teacherData['stage'] ??
              widget.teacherData['teacherStage'] ??
              "Stage 1",
          "lat": position.latitude,
          "lng": position.longitude,
          "language": widget.teacherData['language']?.toString() ?? "English",
        }),
      );

      if (res.statusCode == 200) {
        Get.snackbar(
          "Success",
          "Attendance Marked Successfully!",
          backgroundColor: accentGreen,
          colorText: Colors.white,
        );
        fetchAssignedStudentsSilent();
      } else {
        final data = jsonDecode(res.body);
        Get.snackbar(
          "Notice",
          data['message']?.toString() ?? "Check-in failed.",
          backgroundColor: goldenYellow,
          colorText: Colors.black,
        );
      }
    } catch (e) {
      Get.snackbar(
        "Error",
        "Check-in error: $e",
        backgroundColor: accentRed,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _startTeacherAudioBroadcast() async {
    if (isStartingBroadcast) return;
    setState(() => isStartingBroadcast = true);
    final String language =
        widget.teacherData['language']?.toString() ?? "English";
    final String stage =
        (widget.teacherData['stage'] ??
                widget.teacherData['teacherStage'] ??
                "stage1")
            .toString()
            .toLowerCase();

    final String section = language.toLowerCase() == "hindi"
        ? "none"
        : (widget.teacherData['section'] ??
                widget.teacherData['teacherSection'] ??
                'A')
            .toString()
            .toLowerCase();

    final String teacherId =
        (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
            .toString();
    final String teacherName =
        widget.teacherData['name']?.toString() ?? 'Teacher';

    try {
      // In parallel: Stream client (usually already ready) + server creates today's class
      final results = await Future.wait<Object>([
        StreamManager.clientFor(userId: teacherId, userName: teacherName),
        _prepareCallOnServer(language, stage, section),
      ]);
      final client = results[0] as StreamVideo;
      final callId = results[1] as String;

      // load the call → join → turn the mic on (Stream 1.5 order)
      final call = client.makeCall(
        callType: StreamCallType.defaultType(),
        id: callId,
      );
      final loaded = await call.getOrCreate();
      if (loaded.isFailure) debugPrint("getOrCreate failed: $loaded");

      // Stream retries 3 times inside join(). No extra retry here, so the
      // REAL reason is not overwritten.
      // 🎧 AUDIO ONLY: camera off from the start → Chrome/phone never asks
      // for camera permission, only the microphone.
      final joined = await call.join(
        connectOptions: CallConnectOptions(
          camera: TrackOption.disabled(),
          microphone: TrackOption.enabled(),
        ),
      );
      if (joined.isFailure) {
        final reason = await joinFailReason(call, joined);
        debugPrint("❌ JOIN FAILED: $reason");
        throw Exception("Could not connect to the classroom.\n$reason");
      }

      try {
        await call.setCameraEnabled(enabled: false); // audio class: never video
        await call.setMicrophoneEnabled(enabled: true);
      } catch (e) {
        debugPrint("Mic Error: $e");
      }

      ClassroomController.instance.begin(
        call: call,
        language: language,
        stage: stage,
        section: section == 'none' ? '' : section.toUpperCase(),
        teacherId: teacherId,
      );

      // The trainer is live now — everything below runs in the background.
      unawaited(
        TrainerOnlineSession.start(
          teacherId: teacherId,
          language: language,
          stage: stage,
        ),
      );
      unawaited(_publishLiveLink(callId, language, stage, section));

      GlobalAudioOverlayController.removeOverlay();

      Get.to(
        () => TeacherBroadcastScreen(
          call: call,
          language: language,
          stage: stage,
          section: section,
          enrolledStudents: allAssignedStudents,
          teacherData: widget.teacherData,
          onCallEnded: () {
            if (mounted) setState(() {});
          },
        ),
      );
    } catch (e) {
      Get.snackbar(
        "Broadcast Error",
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: accentRed,
        colorText: Colors.white,
        duration: const Duration(seconds: 12),
      );
    } finally {
      if (mounted) setState(() => isStartingBroadcast = false);
    }
  }

  /// The server creates the call (one per class per day) and returns its id.
  /// Any Stream problem comes back as a readable message.
  Future<String> _prepareCallOnServer(
    String language,
    String stage,
    String section,
  ) async {
    final teacherId =
        (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '').toString();
    final res = await http
        .post(
          Uri.parse(ApiEndpoints.prepareCall),
          headers: ApiHeaders.json(),
          body: jsonEncode({
            "userId": teacherId,
            "language": language,
            "stage": stage,
            "section": section,
            "type": "class",
          }),
        )
        .timeout(const Duration(seconds: 25));
    final data = jsonDecode(res.body);
    if (res.statusCode == 200 && (data['callId'] ?? '').toString().isNotEmpty) {
      return data['callId'].toString();
    }
    if (res.statusCode == 401) {
      throw Exception("Session expired. Please log out and log in again.");
    }
    if (data is Map && data['merged'] == true) {
      fetchAssignedStudentsSilent(); // show the "merged" card
      throw Exception((data['error'] ?? 'Your section is merged into another section today.').toString());
    }
    throw Exception(
      "Server could not create the class: ${data['error'] ?? res.statusCode}",
    );
  }

  Future<void> _publishLiveLink(
    String callId,
    String language,
    String stage,
    String section,
  ) async {
    try {
      final linkRes = await http.post(
        Uri.parse(ApiEndpoints.updateLiveLink),
        headers: ApiHeaders.json(),
        body: jsonEncode({
          "language": language,
          "stage": stage,
          "section": section,
          "type": "class",
          "link": "stream_active_$callId",
        }),
      );
      if (linkRes.statusCode != 200 && linkRes.statusCode != 201) {
        debugPrint(
          "Live link update failed: ${linkRes.statusCode} ${linkRes.body}",
        );
        Get.snackbar(
          "Notice",
          "Class started, but students may not see it yet (live link not saved).",
          backgroundColor: goldenYellow,
          colorText: Colors.black,
        );
      }
    } catch (e) {
      debugPrint("Live link error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final String stageName =
        (widget.teacherData['teacherStage'] ??
                widget.teacherData['stage'] ??
                'Stage 1')
            .toString()
            .toUpperCase();
    final String section =
        (widget.teacherData['teacherSection'] ??
                widget.teacherData['section'] ??
                'A')
            .toString()
            .toUpperCase();
    final String mode = (widget.teacherData['mode'] ?? 'online').toString();
    final String language =
        widget.teacherData['language']?.toString() ?? 'English';
    final bool isOnline = mode.toLowerCase() == 'online';
    final bool hasSection = isOnline && language.toLowerCase() == 'english';

    final int totalCount = allAssignedStudents.length;
    final int paidCount = allAssignedStudents
        .where(
          (s) =>
              (s['feeStatus'] ?? 'unpaid').toString().toLowerCase() == 'paid',
        )
        .length;
    final int unpaidCount = totalCount - paidCount;
    final int presentCount = allAssignedStudents
        .where(
          (s) =>
              (s['attendanceStatus'] ?? 'Absent').toString().toLowerCase() ==
              'present',
        )
        .length;
    final int absentCount = totalCount - presentCount;

    List<dynamic> filteredStudents = List<dynamic>.from(allAssignedStudents);
    if (activeFilter == 'paid') {
      filteredStudents = filteredStudents
          .where(
            (s) =>
                (s['feeStatus'] ?? 'unpaid').toString().toLowerCase() == 'paid',
          )
          .toList();
    } else if (activeFilter == 'unpaid') {
      filteredStudents = filteredStudents
          .where(
            (s) =>
                (s['feeStatus'] ?? 'unpaid').toString().toLowerCase() != 'paid',
          )
          .toList();
    } else if (activeFilter == 'present') {
      filteredStudents = filteredStudents
          .where(
            (s) =>
                (s['attendanceStatus'] ?? 'Absent').toString().toLowerCase() ==
                'present',
          )
          .toList();
    } else if (activeFilter == 'absent') {
      filteredStudents = filteredStudents
          .where(
            (s) =>
                (s['attendanceStatus'] ?? 'Absent').toString().toLowerCase() ==
                'absent',
          )
          .toList();
    }

    // ⏰ Batch timing filter
    if (activeBatch != 'all') {
      filteredStudents = filteredStudents
          .where((s) => BatchSlots.labelOf(s['batchTime']) == (activeBatch == 'none' ? '' : activeBatch))
          .toList();
    }
    // Sort by batch (earliest first), students without a timing last
    filteredStudents.sort((a, b) {
      final ba = BatchSlots.find(a['batchTime'])?.number ?? 99;
      final bb = BatchSlots.find(b['batchTime'])?.number ?? 99;
      if (ba != bb) return ba.compareTo(bb);
      return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
    });

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildPortalAppBar(
        stageName,
        section,
        language,
        mode,
        hasSection,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 1000;
            final double horizontalPadding = constraints.maxWidth >= 1300
                ? 32
                : constraints.maxWidth >= 700
                ? 24
                : 16;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isDesktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _buildClassArea(isOnline),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 4,
                              child: _buildOverviewCard(
                                totalCount,
                                presentCount,
                                absentCount,
                                paidCount,
                                unpaidCount,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildClassArea(isOnline),
                        const SizedBox(height: 16),
                        _buildOverviewCard(
                          totalCount,
                          presentCount,
                          absentCount,
                          paidCount,
                          unpaidCount,
                        ),
                      ],
                      const SizedBox(height: 22),
                      _buildRosterHeader(filteredStudents.length),
                      const SizedBox(height: 12),
                      _buildFilterBar(
                        totalCount,
                        paidCount,
                        unpaidCount,
                        presentCount,
                        absentCount,
                      ),
                      const SizedBox(height: 10),
                      _buildBatchBar(),
                      const SizedBox(height: 16),
                      if (filteredStudents.isEmpty)
                        _buildEmptyRoster()
                      else if (isDesktop)
                        _buildDesktopRoster(filteredStudents)
                      else
                        _buildMobileRoster(filteredStudents),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await ClassroomController.instance.finish();
    try {
      final activeCall = GlobalAudioOverlayController.currentCall;
      if (activeCall != null) await activeCall.leave();
    } catch (_) {}
    await TrainerOnlineSession.leave();
    GlobalAudioOverlayController.removeOverlay();
    await StreamManager.reset();

    final box = GetStorage();
    await box.remove('teacher_profile');
    await box.remove('token');

    Get.offAll(() => const TeacherLoginScreen());
  }

  PreferredSizeWidget _buildPortalAppBar(
    String stageName,
    String section,
    String language,
    String mode,
    bool hasSection,
  ) {
    return AppBar(
      elevation: 0,
      backgroundColor: const Color(0xffF4F8FB),
      surfaceTintColor: const Color(0xffF4F8FB),
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [brandNavy, accentBlue]),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Trainer Classroom',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: brandNavy,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$language • $stageName • ${hasSection ? 'Section $section' : mode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: const Color(0xff71859A),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // 🏆 best students of the month (students only)
        IconButton(
          tooltip: 'Best students',
          onPressed: () => Get.to(() => const BestStudentsScreen()),
          icon: const Icon(Icons.emoji_events_rounded),
          color: const Color(0xffE3B21B),
        ),
        IconButton(
          tooltip: 'Refresh students',
          onPressed: fetchAssignedStudentsSilent,
          icon: const Icon(Icons.refresh_rounded),
          color: const Color(0xff294A67),
        ),
        const SizedBox(width: 2),
        IconButton(
          tooltip: 'Logout',
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded),
          color: const Color(0xffC94B4B),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // Normal class card, or 🎙 special class / 🌐 offline-online day versions
  Widget _buildClassArea(bool isOnline) {
    if (_assemblyOn) return _buildAssemblyCard();
    if (!isOnline && _rainOn) {
      return Column(
        children: [
          _buildRainBanner(),
          const SizedBox(height: 10),
          _buildLiveClassCard(true), // offline trainer teaches ONLINE today
        ],
      );
    }
    // 🔀 section merge (English online)
    if (_mergedIntoHost != null) return _buildMergedAwayCard();
    if (_guestSections.isNotEmpty) {
      return Column(
        children: [
          _buildHostMergeBanner(),
          const SizedBox(height: 10),
          _buildLiveClassCard(isOnline),
        ],
      );
    }
    return _buildLiveClassCard(isOnline);
  }

  /// This trainer's section is merged into another section today
  Widget _buildMergedAwayCard() {
    final host = _mergedIntoHost ?? '';
    final mySection = (widget.teacherData['teacherSection'] ?? widget.teacherData['section'] ?? '').toString().toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffF3D58A)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: const Color(0xffFFF4D5), borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.merge_type_rounded, color: Color(0xffC78B00)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Section $mySection is merged into Section $host',
                        style: GoogleFonts.poppins(color: brandNavy, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      'Your students are in Section $host\'s class today. Their attendance & practice are still saved in Section $mySection.',
                      style: GoogleFonts.poppins(color: const Color(0xff71859A), fontSize: 11.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _unmerging ? null : _unmergeMine,
              icon: _unmerging
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.call_split_rounded),
              label: Text(_unmerging ? 'Unmerging…' : "I'm back — unmerge",
                  style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: brandNavy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Other sections joined this trainer's class today
  Widget _buildHostMergeBanner() {
    final guests = _guestSections;
    final count = allAssignedStudents.where((s) => (s['mergedFrom'] ?? '').toString().isNotEmpty).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xffF1EDFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xff7A5AF8).withOpacity(.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.merge_type_rounded, color: Color(0xff7A5AF8), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Section ${guests.join(', ')} ${guests.length > 1 ? 'are' : 'is'} merged into your class today • $count student${count == 1 ? '' : 's'}. '
              'Do their practice & rating as usual — it is saved in their own section.',
              style: GoogleFonts.poppins(color: const Color(0xff4A3AA8), fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRainBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: brandBlue.withOpacity(.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brandBlue.withOpacity(.30)),
      ),
      child: Row(
        children: [
          const Text('🌐', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${(_rainMode?['note'] ?? '').toString().isNotEmpty ? 'Reason: ${_rainMode?['note']}\n' : ''}Today your offline class is ONLINE (set by admin). Start the live audio class — your offline students join from their app. Attendance is online today.',
              style: GoogleFonts.poppins(color: brandNavy, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssemblyCard() {
    final rawTitle = (_assemblyMode?['title'] ?? '').toString().trim();
    final title = rawTitle.isEmpty ? 'Surendra Sir Special Class' : rawTitle;
    final time = (_assemblyMode?['startTime'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFFD6336C)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFFD6336C).withOpacity(.25), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.record_voice_over_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(
                      'Today${time.isNotEmpty ? ' at $time' : ''} • all students & trainers in one class',
                      style: GoogleFonts.poppins(color: Colors.white.withOpacity(.85), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Normal classes are paused while the special class is on. Join — your attendance is marked. You can talk when Sir opens the mics.',
            style: GoogleFonts.poppins(color: Colors.white.withOpacity(.9), fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => Get.to(() => AssemblyJoinScreen(
                    teacherData: widget.teacherData,
                    title: title,
                    startTime: time,
                  )),
              icon: const Icon(Icons.headphones_rounded, size: 20),
              label: Text('Join special class',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF7B2FF7),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveClassCard(bool isOnline) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffD4E2EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isOnline
                      ? accentGreen.withOpacity(.10)
                      : accentBlue.withOpacity(.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isOnline
                      ? Icons.graphic_eq_rounded
                      : Icons.location_on_rounded,
                  color: isOnline ? accentGreen : brandNavy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnline ? 'Live Classroom' : 'Institute Attendance',
                      style: GoogleFonts.poppins(
                        color: brandNavy,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOnline
                          ? 'Start or return to your live audio class.'
                          : 'Verify your location and mark institute attendance.',
                      style: GoogleFonts.poppins(
                        color: const Color(0xff71859A),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(
                isOnline ? 'ONLINE MODE' : 'OFFLINE MODE',
                isOnline ? accentGreen : brandNavy,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Builder(
            builder: (context) {
              final bool isLiveActive =
                  GlobalAudioOverlayController.currentCall != null;
              final activeCall = GlobalAudioOverlayController.currentCall;

              return SizedBox(
                width: double.infinity,
                height: 50,
                child: isOnline
                    ? ElevatedButton.icon(
                        onPressed: isStartingBroadcast
                            ? null
                            : () {
                                if (isLiveActive && activeCall != null) {
                                  GlobalAudioOverlayController.removeOverlay();
                                  Get.to(
                                    () => TeacherBroadcastScreen(
                                      call: activeCall,
                                      language:
                                          widget.teacherData['language']
                                                  ?.toString() ??
                                              'English',
                                      stage:
                                          (widget.teacherData['teacherStage'] ??
                                                  widget.teacherData['stage'] ??
                                                  'stage1')
                                              .toString(),
                                      section:
                                          (widget.teacherData[
                                                      'teacherSection'] ??
                                                  widget.teacherData[
                                                      'section'] ??
                                                  'a')
                                              .toString(),
                                      enrolledStudents: allAssignedStudents,
                                      teacherData: widget.teacherData,
                                      onCallEnded: () => setState(() {}),
                                    ),
                                  );
                                } else {
                                  _startTeacherAudioBroadcast();
                                }
                              },
                        icon: isStartingBroadcast
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isLiveActive
                                    ? Icons.open_in_new_rounded
                                    : Icons.mic_rounded,
                                size: 20,
                              ),
                        label: Text(
                          isStartingBroadcast
                              ? 'Starting live classroom...'
                              : isLiveActive
                              ? 'Return to live classroom'
                              : 'Start live audio class',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLiveActive
                              ? brandNavy
                              : accentGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: accentGreen.withOpacity(.55),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _handleOfflineGeoCheckIn,
                        icon: const Icon(Icons.my_location_rounded, size: 20),
                        label: Text(
                          'Mark institute attendance',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(
    int total,
    int present,
    int absent,
    int paid,
    int unpaid,
  ) {
    final double attendance = total == 0 ? 0 : (present / total) * 100;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffD4E2EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Class overview',
                style: GoogleFonts.poppins(
                  color: brandNavy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${attendance.toStringAsFixed(0)}% present',
                style: GoogleFonts.poppins(
                  color: accentGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _overviewProgress('Attendance', present, total, brandNavy),
          const SizedBox(height: 13),
          _overviewProgress('Payments', paid, total, accentGreen),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniOverview('Present', '$present', accentGreen),
              ),
              const SizedBox(width: 8),
              Expanded(child: _miniOverview('Absent', '$absent', accentRed)),
              const SizedBox(width: 8),
              Expanded(child: _miniOverview('Unpaid', '$unpaid', goldenYellow)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewProgress(String title, int value, int total, Color color) {
    final double progress = total == 0 ? 0 : (value / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                color: const Color(0xff4F6680),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$value / $total',
              style: GoogleFonts.poppins(
                color: const Color(0xff294A67),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: progress,
            backgroundColor: const Color(0xffE7EEF5),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _miniOverview(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: const Color(0xff71859A),
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRosterHeader(int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Student roster',
                style: GoogleFonts.poppins(
                  color: brandNavy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'View attendance and payment status at a glance.',
                style: GoogleFonts.poppins(
                  color: const Color(0xff71859A),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xffEEF4F8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count ${count == 1 ? 'student' : 'students'}',
            style: GoogleFonts.poppins(
              color: const Color(0xff4F6680),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(
    int total,
    int paid,
    int unpaid,
    int present,
    int absent,
  ) {
    final filters = [
      ('all', 'All', total, brandNavy),
      ('present', 'Present', present, accentGreen),
      ('absent', 'Absent', absent, accentRed),
      ('paid', 'Paid', paid, accentBlue),
      ('unpaid', 'Unpaid', unpaid, const Color(0xffD5A800)),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = filters[index];
          final String key = item.$1;
          final String label = item.$2;
          final int count = item.$3;
          final Color color = item.$4;
          final bool selected = activeFilter == key;

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => activeFilter = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: selected ? color : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? color : const Color(0xffDCE7F0),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      color: selected ? Colors.white : const Color(0xff4F6680),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withOpacity(.18)
                          : color.withOpacity(.09),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.poppins(
                        color: selected ? Colors.white : color,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBatchBar() {
    int countFor(String key) {
      if (key == 'all') return allAssignedStudents.length;
      final want = key == 'none' ? '' : key;
      return allAssignedStudents.where((s) => BatchSlots.labelOf(s['batchTime']) == want).length;
    }

    final items = <(String, String)>[
      ('all', 'All timings'),
      ...BatchSlots.all.map((b) => (b.label, b.shortLabel)),
      ('none', 'No timing'),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final key = items[index].$1;
          final label = items[index].$2;
          final count = countFor(key);
          final selected = activeBatch == key;
          if (key == 'none' && count == 0 && !selected) return const SizedBox.shrink();

          return InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: () => setState(() => activeBatch = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: selected ? brandBlue : Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: selected ? brandBlue : const Color(0xffDCE7F0)),
              ),
              child: Row(
                children: [
                  Icon(
                    key == 'all' ? Icons.schedule_rounded : Icons.access_time_filled_rounded,
                    size: 13,
                    color: selected ? Colors.white : brandBlue,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      color: selected ? Colors.white : const Color(0xff4F6680),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white.withOpacity(.18) : brandBlue.withOpacity(.09),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.poppins(
                        color: selected ? Colors.white : brandBlue,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopRoster(List<dynamic> students) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffDCE7F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 760),
            child: DataTable(
              headingRowHeight: 48,
              dataRowMinHeight: 68,
              dataRowMaxHeight: 76,
              horizontalMargin: 18,
              columnSpacing: 28,
              headingTextStyle: GoogleFonts.poppins(
                color: const Color(0xff71859A),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
              dataTextStyle: GoogleFonts.poppins(
                color: const Color(0xff294A67),
                fontSize: 11,
              ),
              headingRowColor: const WidgetStatePropertyAll(Color(0xffF9FAFB)),
              columns: [
                const DataColumn(label: Text('STUDENT')),
                const DataColumn(label: Text('TIMING')),
                const DataColumn(label: Text('ATTENDANCE')),
                const DataColumn(label: Text('PAYMENT')),
                if (_isOfflineTrainer) const DataColumn(label: Text('PRACTICE ⭐')),
              ],
              rows: students.map((student) {
                final String name =
                    student['name']?.toString().trim().isNotEmpty == true
                    ? student['name'].toString()
                    : 'Student';
                final String attendance =
                    student['attendanceStatus']?.toString() ?? 'Absent';
                final bool paid =
                    (student['feeStatus'] ?? 'unpaid')
                        .toString()
                        .toLowerCase() ==
                    'paid';

                return DataRow(
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _studentAvatar(name),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 170,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    color: brandNavy,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if ((student['mergedFrom'] ?? '').toString().isNotEmpty)
                                  Text(
                                    'From Section ${student['mergedFrom']}',
                                    style: GoogleFonts.poppins(
                                      color: const Color(0xff7A5AF8),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      _statusBadge(
                        BatchSlots.shortOf(student['batchTime'], fallback: 'No timing'),
                        brandBlue,
                      ),
                    ),
                    DataCell(
                      _statusBadge(
                        attendance,
                        attendance.toLowerCase() == 'present'
                            ? accentGreen
                            : accentRed,
                      ),
                    ),
                    DataCell(
                      _statusBadge(
                        paid ? 'Paid' : 'Unpaid',
                        paid ? accentGreen : const Color(0xffD5A800),
                      ),
                    ),
                    if (_isOfflineTrainer) DataCell(_practiceAction(student)),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileRoster(List<dynamic> students) {
    return Column(
      children: students.map((student) {
        final String name =
            student['name']?.toString().trim().isNotEmpty == true
            ? student['name'].toString()
            : 'Student';
        final String attendance =
            student['attendanceStatus']?.toString() ?? 'Absent';
        final bool paid =
            (student['feeStatus'] ?? 'unpaid').toString().toLowerCase() ==
            'paid';
        final bool present = attendance.toLowerCase() == 'present';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xffDCE7F0)),
          ),
          child: Row(
            children: [
              _studentAvatar(name, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: brandNavy,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        if ((student['mergedFrom'] ?? '').toString().isNotEmpty)
                          _statusBadge('From Sec ${student['mergedFrom']}', const Color(0xff7A5AF8)),
                        _statusBadge(
                          BatchSlots.shortOf(student['batchTime'], fallback: 'No timing'),
                          brandBlue,
                        ),
                        _statusBadge(
                          present ? 'Present' : 'Absent',
                          present ? accentGreen : accentRed,
                        ),
                        _statusBadge(
                          paid ? 'Paid' : 'Unpaid',
                          paid ? accentGreen : const Color(0xffD5A800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_isOfflineTrainer)
                _practiceAction(student, compact: true)
              else
                const Icon(Icons.chevron_right_rounded, color: Color(0xff98A2B3)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // =====================================================================
  // ⭐ OFFLINE TRAINER: practice done + rating for each student (after class)
  // =====================================================================
  bool get _isOfflineTrainer =>
      (widget.teacherData['mode'] ?? 'online').toString().toLowerCase() == 'offline';
  String get _trainerLanguage => widget.teacherData['language']?.toString() ?? 'English';
  String get _trainerStage => (widget.teacherData['teacherStage'] ?? widget.teacherData['stage'] ?? 'stage1')
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '');

  static const List<String> _practiceTags = [
    'Fluency',
    'Pronunciation',
    'Grammar',
    'Vocabulary',
    'Confidence',
    'Needs practice',
  ];

  Widget _practiceAction(dynamic student, {bool compact = false}) {
    final bool done = student['practiced'] == true;
    final int rating = int.tryParse('${student['practiceRating'] ?? 0}') ?? 0;
    if (done) {
      return Tooltip(
        message: 'Tap to change rating • long-press to undo',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openPracticeSheet(student),
          onLongPress: () => _undoPractice(student),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: accentGreen.withOpacity(.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentGreen.withOpacity(.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 14, color: accentGreen),
                const SizedBox(width: 4),
                Text(rating > 0 ? '★$rating' : (compact ? 'Done' : 'Practiced'),
                    style: GoogleFonts.poppins(color: accentGreen, fontSize: 10.5, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        onPressed: () => _openPracticeSheet(student),
        icon: const Icon(Icons.star_border_rounded, size: 15),
        label: Text(compact ? 'Rate' : 'Practice',
            style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700)),
        style: OutlinedButton.styleFrom(
          foregroundColor: brandNavy,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          side: BorderSide(color: brandNavy.withOpacity(.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  void _openPracticeSheet(dynamic student) {
    final String name = (student['name'] ?? 'Student').toString();
    int rating = int.tryParse('${student['practiceRating'] ?? 0}') ?? 0;
    final Set<String> tags = <String>{};
    bool saving = false;
    const labels = ['', 'Needs work', 'Okay', 'Good', 'Very good', 'Excellent'];

    Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setSheet) => Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(color: const Color(0xffD4E2EC), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('How did $name do today?',
                    style: GoogleFonts.poppins(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                Text('Offline class • speaking practice',
                    style: GoogleFonts.poppins(color: textSecondary, fontSize: 11)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final v = i + 1;
                    return IconButton(
                      onPressed: () => setSheet(() => rating = v),
                      icon: Icon(v <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: const Color(0xffE3B21B), size: 36),
                    );
                  }),
                ),
                Center(
                  child: Text(rating == 0 ? 'Tap the stars' : labels[rating],
                      style: GoogleFonts.poppins(color: brandNavy, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _practiceTags
                      .map((t) => ChoiceChip(
                            label: Text(t, style: GoogleFonts.poppins(fontSize: 11)),
                            selected: tags.contains(t),
                            selectedColor: accentGreen.withOpacity(.2),
                            onSelected: (v) => setSheet(() => v ? tags.add(t) : tags.remove(t)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () async {
                                setSheet(() => saving = true);
                                final ok = await _saveOfflinePractice(student, 0, const {});
                                if (ok) Get.back();
                                setSheet(() => saving = false);
                              },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Practiced, no rating',
                            style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700, color: brandNavy)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (saving || rating == 0)
                            ? null
                            : () async {
                                setSheet(() => saving = true);
                                final ok = await _saveOfflinePractice(student, rating, tags);
                                if (ok) Get.back();
                                setSheet(() => saving = false);
                              },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          backgroundColor: accentGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Save rating', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<bool> _saveOfflinePractice(dynamic student, int rating, Set<String> tags) async {
    final String studentId = (student['_id'] ?? student['id'] ?? '').toString();
    try {
      final mark = await http.post(
        Uri.parse("${ApiEndpoints.baseUrl}/practice/mark"),
        headers: ApiHeaders.json(),
        body: jsonEncode({
          "studentId": studentId,
          "studentName": student['name']?.toString() ?? '',
          "language": _trainerLanguage,
          "stage": _trainerStage,
          "section": "",
          "practiced": true,
          if (rating > 0) "rating": rating,
        }),
      );
      if (mark.statusCode != 200) throw Exception('mark ${mark.statusCode}');
      if (rating > 0) {
        await http.post(
          Uri.parse("${ApiEndpoints.baseUrl}/practice/rate"),
          headers: ApiHeaders.json(),
          body: jsonEncode({
            "studentId": studentId,
            "language": _trainerLanguage,
            "stage": _trainerStage,
            "rating": rating,
            "tags": tags.toList(),
          }),
        );
      }
      Get.snackbar('Saved', rating > 0 ? '${student['name']} • ★$rating' : '${student['name']} marked practiced',
          backgroundColor: accentGreen, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
      fetchAssignedStudentsSilent();
      return true;
    } catch (e) {
      Get.snackbar('Not saved', 'Could not save practice. Try again.',
          backgroundColor: accentRed, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
      return false;
    }
  }

  Future<void> _undoPractice(dynamic student) async {
    final ok = await Get.dialog<bool>(AlertDialog(
      title: Text('Undo practice?', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      content: Text('Remove today\'s practice and rating for ${student['name']}?', style: GoogleFonts.poppins(fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        TextButton(onPressed: () => Get.back(result: true), child: const Text('Undo', style: TextStyle(color: accentRed))),
      ],
    ));
    if (ok != true) return;
    try {
      await http.post(
        Uri.parse("${ApiEndpoints.baseUrl}/practice/mark"),
        headers: ApiHeaders.json(),
        body: jsonEncode({
          "studentId": (student['_id'] ?? student['id'] ?? '').toString(),
          "language": _trainerLanguage,
          "stage": _trainerStage,
          "practiced": false,
        }),
      );
      fetchAssignedStudentsSilent();
    } catch (_) {}
  }

  Widget _studentAvatar(String name, {double radius = 19}) {
    final String initial = name.trim().isNotEmpty
        ? name.trim()[0].toUpperCase()
        : 'S';
    return CircleAvatar(
      radius: radius,
      backgroundColor: accentBlue.withOpacity(.14),
      child: Text(
        initial,
        style: GoogleFonts.poppins(
          color: brandNavy,
          fontSize: radius * .62,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEmptyRoster() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffDCE7F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              color: Color(0xffF2F4F7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              color: Color(0xff98A2B3),
              size: 29,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No students found',
            style: GoogleFonts.poppins(
              color: brandNavy,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            activeFilter == 'all'
                ? 'No students are currently assigned to this classroom.'
                : 'Try another filter to see more students.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: const Color(0xff71859A),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// 🎙️ TRAINER LIVE CLASSROOM
// Two tabs instead of one long list:
//   • Practice  → who is speaking now, "Mark practiced", who is next, who is done
//   • Students  → compact grid (30 students fit on ~1.5 screens) + search/filters
// Bottom bar: Mute me • Mute all / Unlock all • Practice • Minimize • End
// =========================================================================
class TeacherBroadcastScreen extends StatefulWidget {
  final Call call;
  final String language;
  final String stage;
  final String section;
  final List<dynamic> enrolledStudents;
  final VoidCallback? onCallEnded;
  final Map<String, dynamic> teacherData;

  const TeacherBroadcastScreen({
    super.key,
    required this.call,
    required this.language,
    required this.stage,
    required this.section,
    required this.enrolledStudents,
    this.onCallEnded,
    required this.teacherData,
  });

  @override
  State<TeacherBroadcastScreen> createState() => _TeacherBroadcastScreenState();
}

class _TeacherBroadcastScreenState extends State<TeacherBroadcastScreen> {
  final ClassroomController cc = ClassroomController.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  int tab = 0; // 0 = Practice, 1 = Students
  String search = '';
  String studentFilter = 'all'; // all | speaking | mic | practiced | pending
  bool _leaving = false;

  static const Color navy = Color(0xFF155A88);
  static const Color deepNavy = Color(0xFF0E466D);
  static const Color blue = Color(0xFF2C6F9F);
  static const Color teal = Color(0xFF28C2C2);
  static const Color yellow = Color(0xFFF7DF55);
  static const Color amber = Color(0xFFC78B00);
  static const Color periwinkle = Color(0xFF7CA4D8);
  static const Color background = Color(0xFFE8F2F8);
  static const Color border = Color(0xFFD7E5EE);
  static const Color green = Color(0xFF20A879);
  static const Color red = Color(0xFFE45757);
  static const Color textDark = Color(0xFF123B57);
  static const Color textSecondary = Color(0xFF6B8193);

  static const List<Color> _avatarColors = [
    Color(0xFF155A88),
    Color(0xFF7A5AF8),
    Color(0xFF0E9384),
    Color(0xFFDD6B20),
    Color(0xFFC11574),
    Color(0xFF2C6F9F),
    Color(0xFF4E5BA6),
    Color(0xFF16A34A),
  ];

  String get teacherId =>
      (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    GlobalAudioOverlayController.removeOverlay();
    // Safety: screen opened for a call the controller doesn't know yet
    if (cc.call != widget.call) {
      cc.begin(
        call: widget.call,
        language: widget.language,
        stage: widget.stage.toLowerCase(),
        section: widget.language.toLowerCase() == 'hindi'
            ? ''
            : widget.section.toUpperCase(),
        teacherId: teacherId,
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------
  String _nameOf(CallParticipantState p) {
    final n = p.name.trim();
    return n.isEmpty ? 'Student' : n;
  }

  String _initial(String name) {
    final v = name.trim();
    return v.isEmpty ? '?' : v[0].toUpperCase();
  }

  Color _colorFor(String name) {
    int sum = 0;
    for (final c in name.codeUnits) {
      sum += c;
    }
    return _avatarColors[sum % _avatarColors.length];
  }

  PracticeEntry _entry(CallParticipantState p) =>
      PracticeEntry(p.userId, _nameOf(p));

  Map<String, dynamic>? _enrolled(CallParticipantState p) {
    final name = _nameOf(p).toLowerCase();
    final match = widget.enrolledStudents.firstWhereOrNull(
          (s) =>
              s['_id']?.toString() == p.userId ||
              s['name']?.toString().toLowerCase().trim() == name,
        ) ??
        // 🔀 merged-in students (Section B in Section A's class today)
        cc.guestStudents.firstWhereOrNull((s) => s['_id']?.toString() == p.userId);
    return match is Map<String, dynamic> ? match : null;
  }

  bool _isPaid(CallParticipantState p) {
    final s = _enrolled(p);
    if (s == null) return true; // unknown → don't flag
    return (s['feeStatus'] ?? 'unpaid').toString().toLowerCase() == 'paid';
  }

  List<CallParticipantState> _dedupe(List<CallParticipantState> raw) {
    final seen = <String>{};
    return raw.where((p) => seen.add(p.userId)).toList();
  }

  void _toast(String message, {Color color = deepNavy, IconData? icon}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: const Duration(milliseconds: 2200),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _minimize() {
    Get.until((route) => route.isFirst);
    GlobalAudioOverlayController.showOverlay(
      context,
      widget.call,
      teacherId,
      "Live Studio",
      widget.teacherData,
      widget.enrolledStudents,
    );
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------
  Future<void> _toggleTeacherMic(bool currentlyOn) async {
    try {
      await widget.call.setMicrophoneEnabled(enabled: !currentlyOn);
    } catch (e) {
      debugPrint("Teacher Mic Error: $e");
    }
  }

  Future<void> _toggleLock() async {
    final lock = !cc.micLocked.value;
    HapticFeedback.mediumImpact();
    await cc.setMicLock(lock);
    _toast(
      lock
          ? 'All students muted. They can speak only when you allow them.'
          : 'Mics unlocked. Students can unmute themselves now.',
      color: lock ? amber : green,
      icon: lock ? Icons.lock_rounded : Icons.lock_open_rounded,
    );
  }

  Future<void> _markPracticed() async {
    final PracticeEntry? entry = cc.current.value;
    final name = entry?.name ?? '';
    HapticFeedback.mediumImpact();
    final ok = await cc.markCurrentPracticed();
    if (!ok) {
      _toast(
        'Could not save. Check the internet and tap again.',
        color: red,
        icon: Icons.wifi_off_rounded,
      );
      return;
    }
    final next = cc.current.value;
    _toast(
      next != null ? '$name practiced ✓  Now: ${next.name}' : '$name practiced ✓',
      color: green,
      icon: Icons.check_circle_rounded,
    );
    if (entry != null) _askRating(entry);
  }

  // ⭐ After "Mark practiced": how did the student do? (1–5 stars + quick tags)
  // Admin sees it daily; it counts 30% in "Best student of the month".
  void _askRating(PracticeEntry e) {
    int stars = cc.ratings[e.id] ?? 0;
    final Set<String> picked = <String>{};
    const tags = ['Fluency', 'Pronunciation', 'Grammar', 'Vocabulary', 'Confidence', 'Needs practice'];
    const labels = ['', 'Needs work', 'Fair', 'Good', 'Very good', 'Excellent'];
    bool saving = false;

    Get.bottomSheet(
      StatefulBuilder(
        builder: (context, setSheet) {
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'How did ${e.name} do?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rate today\'s speaking practice',
                    style: GoogleFonts.poppins(color: textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final on = i < stars;
                      return IconButton(
                        iconSize: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setSheet(() => stars = i + 1);
                        },
                        icon: Icon(
                          on ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: on ? const Color(0xFFF5B83D) : border,
                        ),
                      );
                    }),
                  ),
                  SizedBox(
                    height: 20,
                    child: Text(
                      labels[stars],
                      style: GoogleFonts.poppins(
                        color: amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    alignment: WrapAlignment.center,
                    children: tags.map((t) {
                      final sel = picked.contains(t);
                      return ChoiceChip(
                        label: Text(
                          t,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : textDark,
                          ),
                        ),
                        selected: sel,
                        selectedColor: navy,
                        backgroundColor: background,
                        showCheckmark: false,
                        onSelected: (_) => setSheet(() {
                          sel ? picked.remove(t) : picked.add(t);
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: saving ? null : () => Get.back(),
                          child: Text(
                            'Skip',
                            style: GoogleFonts.poppins(
                              color: textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: stars == 0 || saving
                              ? null
                              : () async {
                                  setSheet(() => saving = true);
                                  final ok = await cc.ratePractice(e, stars, picked.toList());
                                  if (Get.isBottomSheetOpen == true) Get.back();
                                  _toast(
                                    ok ? '${e.name}: ${'★' * stars} saved' : 'Rating not saved — check internet',
                                    color: ok ? green : red,
                                    icon: ok ? Icons.star_rounded : Icons.wifi_off_rounded,
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: navy,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: navy.withOpacity(.35),
                            minimumSize: const Size(0, 48),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            saving ? 'Saving…' : 'Save rating',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _leaveClassOnly() async {
    if (_leaving) return;
    _leaving = true;
    await cc.finish(); // opens mics so students aren't stuck muted
    try {
      await widget.call.leave();
    } catch (_) {}
    await TrainerOnlineSession.leave();
    GlobalAudioOverlayController.removeOverlay();
    widget.onCallEnded?.call();
    Get.back();
    Get.snackbar(
      "Left Classroom",
      "You left. Students can stay in the room.",
      backgroundColor: navy,
      colorText: Colors.white,
    );
  }

  Future<void> _endClassAndBroadcast() async {
    if (_leaving) return;
    _leaving = true;
    final c = widget.call;
    final studentIds = c.state.value.callParticipants
        .where((p) => !cc.isStaff(p))
        .map((p) => p.userId)
        .toSet();

    await cc.finish();
    // ⚡ Close the class for EVERYONE in one step: every student's app gets
    // "class ended" at the same moment (also when minimized).
    final ended = await c.end();
    if (ended.isFailure) {
      // fallback: remove students one by one
      await Future.wait(
        studentIds.map((id) => c.kickUser(id).then((_) {}, onError: (_) {})),
      );
    }
    try {
      await c.leave();
    } catch (_) {}
    await TrainerOnlineSession.leave();
    unawaited(_deleteLiveLink());

    GlobalAudioOverlayController.removeOverlay();
    widget.onCallEnded?.call();
    Get.until((route) => route.isFirst);
    Get.snackbar(
      "Class Ended",
      "The live classroom has been closed for everyone.",
      backgroundColor: red,
      colorText: Colors.white,
    );
  }

  Future<void> _deleteLiveLink() async {
    try {
      final request = http.Request("DELETE", Uri.parse(ApiEndpoints.deleteLiveLink));
      request.headers.addAll(ApiHeaders.json());
      request.body = jsonEncode({
        "language": widget.language,
        "stage": widget.stage.toLowerCase(),
        "section": widget.section.toLowerCase(),
        "type": "class",
      });
      final streamed = await request.send();
      await http.Response.fromStream(streamed);
    } catch (e) {
      debugPrint("Delete live link error: $e");
    }
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _minimize();
      },
      child: Scaffold(
        backgroundColor: background,
        appBar: _buildAppBar(),
        body: StreamBuilder<CallState>(
          stream: widget.call.state.asStream(),
          initialData: widget.call.state.value,
          builder: (context, snapshot) {
            final state = snapshot.data ?? widget.call.state.value;
            final participants = _dedupe(state.callParticipants);
            final students = participants.where((p) => !cc.isStaff(p)).toList();
            final me =
                participants.firstWhereOrNull((p) => p.userId == teacherId) ??
                participants.firstWhereOrNull((p) => p.isLocal);
            final speaker = participants.firstWhereOrNull((p) => p.isSpeaking);

            return SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    children: [
                      _liveStrip(students.length, speaker),
                      Obx(() => _mergeBar()),
                      Obx(() => _micLockBar()),
                      _tabBar(students.length),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: tab == 0
                              ? KeyedSubtree(
                                  key: const ValueKey('practice'),
                                  child: _practiceTab(students),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey('students'),
                                  child: _studentsTab(students),
                                ),
                        ),
                      ),
                      _controlBar(me, students),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final bool english = widget.language.toLowerCase() == 'english';
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: navy,
      foregroundColor: Colors.white,
      automaticallyImplyLeading: false,
      toolbarHeight: 62,
      leading: IconButton(
        tooltip: 'Minimize (class keeps running)',
        onPressed: _minimize,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
      ),
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live Classroom',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${widget.language} • ${widget.stage.toUpperCase()}${english ? ' • Section ${widget.section.toUpperCase()}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(.70),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        Obx(() {
          final n = cc.otherBatch.length;
          return IconButton(
            tooltip: 'Joined from another batch',
            onPressed: _openOtherBatchSheet,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.swap_horiz_rounded, size: 23),
                if (n > 0)
                  Positioned(
                    right: -6,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: yellow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$n',
                        style: GoogleFonts.poppins(
                          color: deepNavy,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () {
            cc.loadPracticedToday();
            cc.loadOtherBatch();
          },
          icon: const Icon(Icons.sync_rounded, size: 21),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Top: live strip + mic lock
  // ---------------------------------------------------------------------
  Widget _liveStrip(int joined, CallParticipantState? speaker) {
    final int enrolled = widget.enrolledStudents.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          const _LiveDot(),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: GoogleFonts.poppins(
              color: red,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(width: 6),
          _Elapsed(
            since: cc.startedAt,
            style: GoogleFonts.poppins(
              color: textDark,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: border,
          ),
          const Icon(Icons.people_alt_rounded, size: 15, color: navy),
          const SizedBox(width: 5),
          Text(
            enrolled > 0 ? '$joined/$enrolled' : '$joined',
            style: GoogleFonts.poppins(
              color: textDark,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: speaker == null
                  ? Text(
                      'Quiet',
                      style: GoogleFonts.poppins(
                        color: textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: teal.withOpacity(.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.graphic_eq_rounded, size: 13, color: teal),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              speaker.userId == teacherId ? 'You' : _nameOf(speaker),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                color: deepNavy,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // 🔀 Sections merged into this class today
  Widget _mergeBar() {
    final guests = cc.guestSections.toList();
    if (guests.isEmpty) return const SizedBox.shrink();
    final n = cc.guestStudents.length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xffF1EDFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff7A5AF8).withOpacity(.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.merge_type_rounded, size: 16, color: Color(0xff7A5AF8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Section ${guests.join(', ')} merged in • $n student${n == 1 ? '' : 's'} (badge on their photo). Practice is saved in their own section.',
              style: GoogleFonts.poppins(color: const Color(0xff4A3AA8), fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _micLockBar() {
    final bool locked = cc.micLocked.value;
    final int allowedCount = cc.allowed.length;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: locked ? const Color(0xFFFFF7DD) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: locked ? const Color(0xFFF1D57A) : border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: locked ? amber.withOpacity(.15) : teal.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              locked ? Icons.lock_rounded : Icons.mic_rounded,
              color: locked ? amber : teal,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locked ? 'Student mics locked' : 'Student mics open',
                  style: GoogleFonts.poppins(
                    color: textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  locked
                      ? (allowedCount > 0
                          ? '$allowedCount allowed to speak • others can’t unmute'
                          : 'Nobody can unmute until you allow them')
                      : 'Students can unmute themselves',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _toggleLock,
            icon: Icon(
              locked ? Icons.lock_open_rounded : Icons.mic_off_rounded,
              size: 16,
            ),
            label: Text(
              locked ? 'Unlock all' : 'Mute all',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: locked ? green : deepNavy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(int studentCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _tab(
                0,
                Icons.record_voice_over_rounded,
                'Practice',
                Obx(() {
                  final total = cc.practiceTotal;
                  return _tabCount(
                    total == 0 ? '' : '${cc.done.length}/$total',
                    tab == 0,
                  );
                }),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _tab(
                1,
                Icons.groups_rounded,
                'Students',
                _tabCount('$studentCount', tab == 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int index, IconData icon, String label, Widget badge) {
    final bool selected = tab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => setState(() => tab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 40,
        decoration: BoxDecoration(
          color: selected ? navy : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: selected ? Colors.white : textDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            badge,
          ],
        ),
      ),
    );
  }

  Widget _tabCount(String text, bool selected) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withOpacity(.2) : navy.withOpacity(.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          color: selected ? Colors.white : navy,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // PRACTICE TAB
  // ---------------------------------------------------------------------
  Widget _practiceTab(List<CallParticipantState> students) {
    return Obx(() {
      final PracticeEntry? cur = cc.current.value;
      final List<PracticeEntry> queue = cc.queue.toList();
      final List<PracticeEntry> done = cc.done.toList();
      final bool saving = cc.saving.value;
      final int practicedToday = cc.practicedToday.length;
      final bool locked = cc.micLocked.value;

      if (cur == null && queue.isEmpty && done.isEmpty) {
        return _practiceEmpty(students, practicedToday);
      }

      final byId = {for (final p in students) p.userId: p};
      final int total = done.length + queue.length + (cur == null ? 0 : 1);

      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
        children: [
          _progressCard(done.length, total, students),
          const SizedBox(height: 12),
          if (cur != null)
            _currentCard(cur, byId[cur.id], saving, locked)
          else
            _roundDoneCard(done.length, students),
          if (queue.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionTitle('Up next', queue.length, Icons.queue_music_rounded),
            const SizedBox(height: 8),
            for (int i = 0; i < queue.length; i++)
              _queueRow(i, queue[i], byId[queue[i].id]),
          ],
          if (done.isNotEmpty) ...[
            const SizedBox(height: 14),
            _sectionTitle('Practiced', done.length, Icons.check_circle_rounded),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: done.map(_doneChip).toList(),
            ),
          ],
        ],
      );
    });
  }

  Widget _practiceEmpty(List<CallParticipantState> students, int practicedToday) {
    final notDone = students
        .where((p) => !cc.practicedToday.contains(p.userId))
        .toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: teal.withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.record_voice_over_rounded,
                  color: teal,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Speaking practice',
                style: GoogleFonts.poppins(
                  color: textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pick students and call them one by one. When a student finishes, tap “Mark practiced” and the next one is called automatically.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: textSecondary,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _step('1', 'Pick'),
                  _stepLine(),
                  _step('2', 'Listen'),
                  _stepLine(),
                  _step('3', 'Mark'),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: students.isEmpty ? null : () => _openPicker(students),
                  icon: const Icon(Icons.playlist_add_rounded, size: 20),
                  label: Text(
                    students.isEmpty ? 'Waiting for students…' : 'Pick students',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: teal.withOpacity(.35),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (notDone.isNotEmpty) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () {
                    cc.addToQueue(notDone.map(_entry).toList());
                    _toast('${notDone.length} students added to the practice line');
                  },
                  icon: const Icon(Icons.group_add_rounded, size: 18, color: navy),
                  label: Text(
                    'Add all ${notDone.length} not practiced today',
                    style: GoogleFonts.poppins(
                      color: navy,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (practicedToday > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded, color: green, size: 15),
                const SizedBox(width: 6),
                Text(
                  '$practicedToday ${practicedToday == 1 ? 'student has' : 'students have'} practiced today',
                  style: GoogleFonts.poppins(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _step(String n, String label) {
    return Column(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: navy.withOpacity(.10),
          child: Text(
            n,
            style: GoogleFonts.poppins(
              color: navy,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: textDark,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _stepLine() => Expanded(
    child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 18, left: 6, right: 6),
      color: border,
    ),
  );

  Widget _progressCard(int doneCount, int total, List<CallParticipantState> students) {
    final double progress = total == 0 ? 0 : doneCount / total;
    final int left = total - doneCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$doneCount',
                style: GoogleFonts.poppins(
                  color: green,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                ' of $total done',
                style: GoogleFonts.poppins(
                  color: textDark,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              if (left > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: yellow.withOpacity(.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$left left',
                    style: GoogleFonts.poppins(
                      color: deepNavy,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openPicker(students),
                icon: const Icon(Icons.add_rounded, size: 18, color: navy),
                label: Text(
                  'Add',
                  style: GoogleFonts.poppins(
                    color: navy,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                color: Colors.white,
                icon: const Icon(Icons.more_vert_rounded, color: textSecondary, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'end') _confirmEndRound();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'end',
                    child: Row(
                      children: [
                        const Icon(Icons.stop_circle_outlined, color: red, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          'End practice round',
                          style: GoogleFonts.poppins(
                            color: textDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE7EEF5),
                valueColor: const AlwaysStoppedAnimation<Color>(green),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentCard(
    PracticeEntry cur,
    CallParticipantState? p,
    bool saving,
    bool locked,
  ) {
    final bool inClass = p != null;
    final bool speaking = p?.isSpeaking ?? false;
    final bool micOn = p?.isAudioEnabled ?? false;
    final String status = !inClass
        ? 'Left the class — tap Skip'
        : speaking
        ? 'Speaking…'
        : micOn
        ? 'Mic on'
        : locked
        ? 'Allowed to speak — waiting for them to unmute'
        : 'Muted — ask them to unmute';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [deepNavy, blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: navy.withOpacity(.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: yellow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'NOW PRACTICING',
                  style: GoogleFonts.poppins(
                    color: deepNavy,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .4,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.timer_outlined, color: Colors.white70, size: 15),
              const SizedBox(width: 4),
              _Elapsed(
                since: cc.currentSince.value,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _avatar(cur.name, 28, ring: speaking, onDark: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cur.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          !inClass
                              ? Icons.person_off_rounded
                              : micOn
                              ? Icons.mic_rounded
                              : Icons.mic_off_rounded,
                          size: 14,
                          color: micOn ? teal : Colors.white70,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            status,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(.80),
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (speaking) const _SpeakingBars(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                // Icon + text inside a FittedBox: never wraps or overflows
                child: OutlinedButton(
                  onPressed: saving ? null : cc.skipCurrent,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(.45)),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.skip_next_rounded, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Later',
                          maxLines: 1,
                          softWrap: false,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: saving ? null : _markPracticed,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 20),
                  label: Text(
                    saving ? 'Saving…' : 'Mark practiced',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: teal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: teal.withOpacity(.6),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundDoneCard(int doneCount, List<CallParticipantState> students) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: green.withOpacity(.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: green.withOpacity(.30)),
      ),
      child: Column(
        children: [
          const Icon(Icons.celebration_rounded, color: green, size: 34),
          const SizedBox(height: 8),
          Text(
            'Round complete!',
            style: GoogleFonts.poppins(
              color: textDark,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '$doneCount ${doneCount == 1 ? 'student' : 'students'} practiced',
            style: GoogleFonts.poppins(color: textSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: cc.endRound,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: navy,
                    side: BorderSide(color: navy.withOpacity(.25)),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Close round',
                    style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _openPicker(students),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Pick more',
                    style: GoogleFonts.poppins(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, int count, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: navy),
        const SizedBox(width: 6),
        Text(
          title,
          style: GoogleFonts.poppins(
            color: textDark,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: GoogleFonts.poppins(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _queueRow(int index, PracticeEntry e, CallParticipantState? p) {
    final bool inClass = p != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: index == 0 ? yellow : border, width: index == 0 ? 1.4 : 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _avatar(e.name, 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: textDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  !inClass ? 'Not in class now' : index == 0 ? 'Next' : 'Waiting',
                  style: GoogleFonts.poppins(
                    color: !inClass ? red : index == 0 ? amber : textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (index > 0)
            _iconBtn(Icons.arrow_upward_rounded, 'Move up', textSecondary, () => cc.moveUp(e.id)),
          _iconBtn(Icons.play_circle_fill_rounded, 'Call now', teal, () => cc.makeCurrent(e)),
          _iconBtn(Icons.close_rounded, 'Remove', red, () => cc.removeFromQueue(e.id)),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, Color color, VoidCallback onTap) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      icon: Icon(icon, color: color, size: 21),
    );
  }

  Widget _doneChip(PracticeEntry e) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _askRating(e), // tap → rate / change rating
      onLongPress: () => _confirmUndo(e), // long-press → undo
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
        decoration: BoxDecoration(
          color: green.withOpacity(.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: green.withOpacity(.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: green, size: 16),
            const SizedBox(width: 5),
            Text(
              e.name,
              style: GoogleFonts.poppins(
                color: textDark,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Obx(() {
              final r = cc.ratings[e.id] ?? 0;
              return Text(
                r > 0 ? '  ★$r' : '  ☆ rate',
                style: GoogleFonts.poppins(
                  color: r > 0 ? const Color(0xFFC78B00) : textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // STUDENTS TAB (compact grid)
  // ---------------------------------------------------------------------
  Widget _studentsTab(List<CallParticipantState> students) {
    return Obx(() {
      final bool locked = cc.micLocked.value;
      final Set<String> allowed = cc.allowed.toSet();
      final Set<String> practiced = cc.practicedToday.toSet();
      final String currentId = cc.current.value?.id ?? '';
      final List<String> queueIds = cc.queue.map((e) => e.id).toList();
      final Set<String> otherBatchIds =
          cc.otherBatch.map((v) => v['userId']?.toString() ?? '').toSet();

      final int speakingCount = students.where((p) => p.isSpeaking).length;
      final int micCount = students.where((p) => p.isAudioEnabled).length;
      final int practicedCount = students.where((p) => practiced.contains(p.userId)).length;
      final int pendingCount = students.length - practicedCount;

      final q = search.trim().toLowerCase();
      final list = students.where((p) {
        if (q.isNotEmpty && !_nameOf(p).toLowerCase().contains(q)) return false;
        switch (studentFilter) {
          case 'speaking':
            return p.isSpeaking;
          case 'mic':
            return p.isAudioEnabled;
          case 'practiced':
            return practiced.contains(p.userId);
          case 'pending':
            return !practiced.contains(p.userId);
          default:
            return true;
        }
      }).toList()
        ..sort((a, b) {
          if (a.isSpeaking != b.isSpeaking) return a.isSpeaking ? -1 : 1;
          if (a.isAudioEnabled != b.isAudioEnabled) return a.isAudioEnabled ? -1 : 1;
          return _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
        });

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => search = v),
                style: GoogleFonts.poppins(color: textDark, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search student…',
                  hintStyle: GoogleFonts.poppins(color: textSecondary, fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, color: navy, size: 19),
                  suffixIcon: search.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => search = '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 17, color: textSecondary),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: navy, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _filterChip('all', 'All', students.length),
                _filterChip('speaking', 'Speaking', speakingCount),
                _filterChip('mic', 'Mic on', micCount),
                _filterChip('pending', 'Not practiced', pendingCount),
                _filterChip('practiced', 'Practiced', practicedCount),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? _emptyStudents(students.isEmpty)
                : GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 110,
                      mainAxisExtent: 114,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final p = list[i];
                      final pos = queueIds.indexOf(p.userId);
                      return _studentTile(
                        p,
                        locked: locked,
                        allowed: allowed.contains(p.userId),
                        practiced: practiced.contains(p.userId),
                        isCurrent: currentId == p.userId,
                        queuePos: pos < 0 ? 0 : pos + 1,
                        otherBatch: otherBatchIds.contains(p.userId),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  Widget _filterChip(String key, String label, int count) {
    final bool selected = studentFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => studentFilter = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? navy : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? navy : border),
          ),
          child: Text(
            '$label  $count',
            style: GoogleFonts.poppins(
              color: selected ? Colors.white : textDark,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _studentTile(
    CallParticipantState p, {
    required bool locked,
    required bool allowed,
    required bool practiced,
    required bool isCurrent,
    required int queuePos,
    bool otherBatch = false,
  }) {
    final String name = _nameOf(p);
    final String first = name.split(' ').first;
    final bool speaking = p.isSpeaking;
    final bool micOn = p.isAudioEnabled;
    final bool canSpeak = !locked || allowed;
    final bool paid = _isPaid(p);

    final IconData micIcon = micOn
        ? Icons.mic_rounded
        : canSpeak
        ? Icons.mic_off_rounded
        : Icons.lock_rounded;
    final Color micColor = micOn ? green : canSpeak ? red : amber;

    String tag = '';
    Color tagColor = textSecondary;
    if (isCurrent) {
      tag = 'Speaking turn';
      tagColor = amber;
    } else if (otherBatch) {
      tag = 'Other batch';
      tagColor = red;
    } else if (queuePos > 0) {
      tag = '#$queuePos in line';
      tagColor = navy;
    } else if (practiced) {
      tag = '✓ Practiced';
      tagColor = green;
    } else if (locked && allowed) {
      tag = 'Allowed';
      tagColor = green;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openStudentActions(p),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
        decoration: BoxDecoration(
          color: isCurrent ? const Color(0xFFFFFBEA) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: speaking
                ? teal
                : isCurrent
                ? yellow
                : border,
            width: speaking || isCurrent ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _avatar(name, 22, ring: speaking),
                if (cc.mergedFrom[p.userId] != null)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xff7A5AF8),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white, width: 1.2),
                      ),
                      child: Text(
                        cc.mergedFrom[p.userId]!,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 21,
                    height: 21,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: micColor.withOpacity(.5)),
                    ),
                    child: Icon(micIcon, size: 12, color: micColor),
                  ),
                ),
                if (!paid)
                  Positioned(
                    left: -3,
                    top: -3,
                    child: Container(
                      width: 17,
                      height: 17,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: yellow,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '₹',
                        style: GoogleFonts.poppins(
                          color: deepNavy,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: textDark,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: tagColor,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyStudents(bool nobody) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: teal.withOpacity(.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline_rounded, color: teal, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              nobody ? 'Waiting for students' : 'No students match',
              style: GoogleFonts.poppins(
                color: textDark,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              nobody
                  ? 'Your class is live. Students appear here as they join.'
                  : 'Try another filter or search.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Bottom sheets
  // ---------------------------------------------------------------------
  void _openStudentActions(CallParticipantState p) {
    final String name = _nameOf(p);
    final bool isCurrent = cc.current.value?.id == p.userId;
    final bool queued = cc.isQueued(p.userId);
    final bool practiced = cc.practicedToday.contains(p.userId);
    final bool locked = cc.micLocked.value;
    final bool allowed = cc.allowed.contains(p.userId);
    final bool paid = _isPaid(p);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        void run(VoidCallback action) {
          Navigator.pop(ctx);
          action();
        }

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetHandle(),
                  Row(
                    children: [
                      _avatar(name, 24, ring: p.isSpeaking),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.poppins(
                                color: textDark,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${paid ? 'Fee paid' : 'Fee unpaid'} • ${practiced ? 'Practiced today ✓' : 'Not practiced yet'}',
                              style: GoogleFonts.poppins(
                                color: textSecondary,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isCurrent)
                    _actionTile(Icons.check_circle_rounded, 'Mark practiced', green,
                        () => run(_markPracticed))
                  else
                    _actionTile(Icons.record_voice_over_rounded, 'Practice now', navy, () {
                      run(() {
                        cc.makeCurrent(_entry(p));
                        setState(() => tab = 0);
                      });
                    }),
                  if (!queued)
                    _actionTile(Icons.playlist_add_rounded, 'Add to practice line', blue, () {
                      run(() {
                        cc.addToQueue([_entry(p)]);
                        _toast('$name added to the practice line');
                      });
                    })
                  else if (!isCurrent)
                    _actionTile(Icons.remove_circle_outline_rounded, 'Remove from practice line',
                        textSecondary, () => run(() => cc.removeFromQueue(p.userId))),
                  if (locked)
                    allowed
                        ? _actionTile(Icons.lock_rounded, 'Stop allowing (mute)', amber,
                            () => run(() => cc.setAllowed(p.userId, false)))
                        : _actionTile(Icons.lock_open_rounded, 'Allow to speak', green,
                            () => run(() => cc.setAllowed(p.userId, true))),
                  if (p.isAudioEnabled)
                    _actionTile(Icons.mic_off_rounded, 'Mute mic', textSecondary,
                        () => run(() => cc.muteOne(p.userId))),
                  if (practiced)
                    _actionTile(Icons.undo_rounded, 'Undo “practiced”', textSecondary,
                        () => run(() => _confirmUndo(_entry(p)))),
                  const Divider(height: 18),
                  _actionTile(Icons.person_remove_rounded, 'Remove from class', red,
                      () => run(() => _kickParticipant(p))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Students who joined this class outside their own batch time
  void _openOtherBatchSheet() {
    cc.loadOtherBatch();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Obx(() {
            final list = cc.otherBatch.toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                _sheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.swap_horiz_rounded, color: amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Joined from another batch',
                              style: GoogleFonts.poppins(
                                color: textDark,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Today • attendance counted, shown as "joined another timing"',
                              style: GoogleFonts.poppins(color: textSecondary, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
                    child: Text(
                      'Everyone in your class is in their own batch 👍',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(color: textSecondary, fontSize: 12),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final v = list[i];
                        final name = (v['userName'] ?? 'Student').toString();
                        final own = BatchSlots.shortOf(v['ownBatch'], fallback: 'Not set');
                        final joinedRaw = (v['joinedBatch'] ?? '').toString();
                        final joined = BatchSlots.shortOf(joinedRaw, fallback: joinedRaw);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: background,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              _avatar(name, 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        color: textDark,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Own batch: $own',
                                      style: GoogleFonts.poppins(
                                        color: green,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Joined: $joined',
                                      style: GoogleFonts.poppins(
                                        color: red,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _sheetHandle() => Container(
    width: 42,
    height: 4,
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFD0DCE5),
      borderRadius: BorderRadius.circular(4),
    ),
  );

  Widget _actionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(.11),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: color == textSecondary ? textDark : color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pick students in the order they should speak
  void _openPicker(List<CallParticipantState> students) {
    final available = students.where((p) => !cc.isQueued(p.userId)).toList()
      ..sort((a, b) {
        final pa = cc.practicedToday.contains(a.userId);
        final pb = cc.practicedToday.contains(b.userId);
        if (pa != pb) return pa ? 1 : -1; // not practiced first
        return _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      });

    if (available.isEmpty) {
      _toast(
        students.isEmpty
            ? 'No students in the class yet.'
            : 'Everyone in class is already in the practice line.',
      );
      return;
    }

    final List<String> picked = [];
    String q = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final visible = available
              .where((p) => _nameOf(p).toLowerCase().contains(q.trim().toLowerCase()))
              .toList();
          final notPracticed = available
              .where((p) => !cc.practicedToday.contains(p.userId))
              .map((p) => p.userId)
              .toList();

          return DraggableScrollableSheet(
            initialChildSize: .86,
            minChildSize: .5,
            maxChildSize: .95,
            expand: false,
            builder: (ctx, scroll) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _sheetHandle(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pick students',
                                style: GoogleFonts.poppins(
                                  color: textDark,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Tap in the order they should speak',
                                style: GoogleFonts.poppins(
                                  color: textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        onChanged: (v) => setSheet(() => q = v),
                        style: GoogleFonts.poppins(color: textDark, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Search…',
                          hintStyle: GoogleFonts.poppins(color: textSecondary, fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded, color: navy, size: 19),
                          filled: true,
                          fillColor: background,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        if (notPracticed.isNotEmpty)
                          TextButton(
                            onPressed: () => setSheet(() {
                              for (final id in notPracticed) {
                                if (!picked.contains(id)) picked.add(id);
                              }
                            }),
                            child: Text(
                              'Select all not practiced (${notPracticed.length})',
                              style: GoogleFonts.poppins(
                                color: navy,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (picked.isNotEmpty)
                          TextButton(
                            onPressed: () => setSheet(picked.clear),
                            child: Text(
                              'Clear',
                              style: GoogleFonts.poppins(
                                color: red,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: visible.length,
                      itemBuilder: (ctx, i) {
                        final p = visible[i];
                        final name = _nameOf(p);
                        final order = picked.indexOf(p.userId);
                        final selected = order >= 0;
                        final done = cc.practicedToday.contains(p.userId);
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setSheet(() {
                            if (selected) {
                              picked.remove(p.userId);
                            } else {
                              picked.add(p.userId);
                            }
                          }),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? teal.withOpacity(.08) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected ? teal : Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected ? teal : const Color(0xFFC5D5E0),
                                      width: 1.6,
                                    ),
                                  ),
                                  child: selected
                                      ? Text(
                                          '${order + 1}',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                _avatar(name, 17),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                          color: textDark,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        done ? 'Practiced today ✓' : 'Not practiced yet',
                                        style: GoogleFonts.poppins(
                                          color: done ? green : textSecondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  p.isAudioEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                                  size: 17,
                                  color: p.isAudioEnabled ? green : const Color(0xFFB0BFCB),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: picked.isEmpty
                              ? null
                              : () {
                                  final byId = {for (final p in available) p.userId: p};
                                  final entries = picked
                                      .where(byId.containsKey)
                                      .map((id) => _entry(byId[id]!))
                                      .toList();
                                  final wasActive = cc.practiceActive;
                                  Navigator.pop(ctx);
                                  cc.addToQueue(entries);
                                  setState(() => tab = 0);
                                  _toast(
                                    wasActive
                                        ? '${entries.length} added to the practice line'
                                        : 'Practice started: ${entries.first.name} first',
                                    color: green,
                                    icon: Icons.record_voice_over_rounded,
                                  );
                                },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            picked.isEmpty
                                ? 'Select students'
                                : cc.practiceActive
                                ? 'Add ${picked.length} to the line'
                                : 'Start practice (${picked.length})',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: teal,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFD5E2EA),
                            disabledForegroundColor: textSecondary,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Confirm dialogs
  // ---------------------------------------------------------------------
  Future<bool> _confirm({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await Get.dialog<bool>(
      Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(.11),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 27),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: textSecondary,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(result: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: navy,
                        side: BorderSide(color: navy.withOpacity(.2)),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Get.back(result: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  Future<void> _confirmUndo(PracticeEntry e) async {
    final yes = await _confirm(
      icon: Icons.undo_rounded,
      color: amber,
      title: 'Undo practice for ${e.name}?',
      message: 'They will show as “not practiced” for today (also for the admin).',
      confirmLabel: 'Undo',
    );
    if (!yes) return;
    final ok = await cc.undoPractice(e);
    _toast(ok ? 'Undone' : 'Could not undo. Check the internet.', color: ok ? deepNavy : red);
  }

  Future<void> _confirmEndRound() async {
    final yes = await _confirm(
      icon: Icons.stop_circle_outlined,
      color: red,
      title: 'End this practice round?',
      message: 'The line is cleared. Students already marked stay saved as practiced.',
      confirmLabel: 'End round',
    );
    if (yes) cc.endRound();
  }

  Future<void> _kickParticipant(CallParticipantState p) async {
    final name = _nameOf(p);
    final yes = await _confirm(
      icon: Icons.person_remove_rounded,
      color: red,
      title: 'Remove $name?',
      message: 'They will be removed from this live class.',
      confirmLabel: 'Remove',
    );
    if (!yes) return;
    cc.removeFromQueue(p.userId);
    final r = await widget.call.kickUser(p.userId);
    _toast(
      r.isFailure ? 'Could not remove $name' : '$name was removed',
      color: r.isFailure ? red : deepNavy,
    );
  }

  // ---------------------------------------------------------------------
  // Bottom control bar
  // ---------------------------------------------------------------------
  Widget _controlBar(CallParticipantState? me, List<CallParticipantState> students) {
    final bool myMicOn = me?.isAudioEnabled ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: border)),
        boxShadow: [
          BoxShadow(
            color: navy.withOpacity(.07),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          _roundAction(
            icon: myMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: myMicOn ? 'Mute me' : 'Unmute me',
            color: myMicOn ? teal : red,
            filled: !myMicOn,
            onTap: () => _toggleTeacherMic(myMicOn),
          ),
          Obx(() {
            final locked = cc.micLocked.value;
            return _roundAction(
              icon: locked ? Icons.lock_open_rounded : Icons.mic_off_rounded,
              label: locked ? 'Unlock all' : 'Mute all',
              color: locked ? amber : blue,
              filled: locked,
              onTap: _toggleLock,
            );
          }),
          _roundAction(
            icon: Icons.playlist_add_rounded,
            label: 'Practice',
            color: navy,
            onTap: () => _openPicker(students),
          ),
          _roundAction(
            icon: Icons.picture_in_picture_alt_rounded,
            label: 'Minimize',
            color: periwinkle,
            onTap: _minimize,
          ),
          _roundAction(
            icon: Icons.call_end_rounded,
            label: 'End',
            color: red,
            filled: true,
            onTap: _showEndClassDialog,
          ),
        ],
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: filled ? color : color.withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: filled ? Colors.white : color, size: 22),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: textDark,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEndClassDialog() {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: red.withOpacity(.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_end_rounded, color: red, size: 27),
              ),
              const SizedBox(height: 14),
              Text(
                'Leave or end the class?',
                style: GoogleFonts.poppins(
                  color: textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Leaving keeps the room open for students. Ending closes it for everyone.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: textSecondary,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Get.back();
                    _leaveClassOnly();
                  },
                  icon: const Icon(Icons.logout_rounded, color: navy),
                  label: Text(
                    'Leave (students stay)',
                    style: GoogleFonts.poppins(
                      color: navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: navy.withOpacity(.25)),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Get.back();
                    _endClassAndBroadcast();
                  },
                  icon: const Icon(Icons.stop_circle_rounded),
                  label: Text(
                    'End class for everyone',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Get.back(),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    color: textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(String name, double radius, {bool ring = false, bool onDark = false}) {
    final Color color = _colorFor(name);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.all(ring ? 2 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring ? Border.all(color: teal, width: 2.5) : null,
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: onDark ? Colors.white.withOpacity(.16) : color.withOpacity(.14),
        child: Text(
          _initial(name),
          style: GoogleFonts.poppins(
            color: onDark ? Colors.white : color,
            fontSize: radius * .78,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// Pulsing red "live" dot
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: .35, end: 1).animate(_c),
      child: Container(
        width: 9,
        height: 9,
        decoration: const BoxDecoration(
          color: Color(0xFFE45757),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// mm:ss (or h:mm:ss) since a moment; ticks by itself so the screen doesn't rebuild
class _Elapsed extends StatefulWidget {
  final DateTime? since;
  final TextStyle style;
  const _Elapsed({required this.since, required this.style});

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.since;
    if (since == null) return Text('00:00', style: widget.style);
    final d = DateTime.now().difference(since);
    String two(int n) => n.toString().padLeft(2, '0');
    final text = d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
    return Text(text, style: widget.style);
  }
}
