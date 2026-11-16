import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:letsspeak_trainer/Api/api_headers.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

/// 👋 "New student in your class" for the trainer
///
/// The admin / online manager gives a student your class (stage + section +
/// timing) → the server sends:
///   • a phone notification (push_service.dart)
///   • a live pop-up here (socket "new_student")
///   • an entry in the "New students" tab (GET /api/trainer/alerts)
class TrainerAlerts {
  TrainerAlerts._();

  static final ValueNotifier<List<Map<String, dynamic>>> items =
      ValueNotifier<List<Map<String, dynamic>>>(const []);
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);
  static final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// Changes when the trainer taps a pop-up / notification → open the tab
  static final ValueNotifier<int> openTab = ValueNotifier<int>(0);

  static IO.Socket? _socket;
  static String _who = '';

  static String get _url => '${ApiEndpoints.baseUrl}/trainer/alerts';

  /// Call once after login (TeacherMainNavigation does this)
  static void start(String teacherId) {
    if (teacherId.isEmpty) return;
    if (_who == teacherId && _socket != null) {
      load();
      return;
    }
    stop();
    _who = teacherId;
    try {
      // Socket.IO connects to the server root, NOT ".../api"
      final uri = Uri.parse(ApiEndpoints.baseUrl);
      final host = '${uri.scheme}://${uri.host}:${uri.port}';
      final s = IO.io(host, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'forceNew': true,
        'auth': {'token': ApiHeaders.token ?? ''},
      });
      s.onConnect((_) {
        s.emit('join_user_room', teacherId);
        load(); // anything that came while the app was closed
      });
      s.on('new_student', _onNew);
      _socket = s;
    } catch (e) {
      debugPrint('Trainer alerts socket error: $e');
    }
    load();
  }

  static void stop() {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _who = '';
    items.value = const [];
    unread.value = 0;
  }

  static void _onNew(dynamic data) {
    if (data is! Map) return;
    final a = Map<String, dynamic>.from(data);
    final id = (a['_id'] ?? '').toString();
    if (id.isNotEmpty && items.value.any((x) => (x['_id'] ?? '').toString() == id)) return;
    items.value = [a, ...items.value];
    unread.value = unread.value + 1;

    Get.snackbar(
      (a['title'] ?? '👋 New student').toString(),
      (a['body'] ?? '').toString(),
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.white,
      colorText: const Color(0xFF16324A),
      borderColor: const Color(0xFF27BFC0),
      borderWidth: 1.4,
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 6),
      icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF155A8A)),
      onTap: (_) => openTab.value = openTab.value + 1,
    );
  }

  static Future<void> load() async {
    loading.value = true;
    try {
      final res = await http.get(Uri.parse(_url), headers: ApiHeaders.auth()).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (d is Map) {
          final list = (d['alerts'] is List ? d['alerts'] as List : const [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
          items.value = list;
          unread.value = int.tryParse('${d['unread'] ?? 0}') ?? 0;
        }
      }
    } catch (e) {
      debugPrint('Trainer alerts load error: $e');
    } finally {
      loading.value = false;
    }
  }

  static Future<void> markAllRead() async {
    if (unread.value == 0) return;
    unread.value = 0;
    items.value = items.value.map((a) => {...a, 'read': true}).toList();
    try {
      await http
          .post(Uri.parse('$_url/read'), headers: ApiHeaders.json(), body: jsonEncode({}))
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
