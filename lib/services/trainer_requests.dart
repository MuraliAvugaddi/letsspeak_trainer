import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:letsspeak_trainer/Api/api_headers.dart';

/// 🙋 Student requests for THIS trainer
///   (e.g. "can't come to 5:30 AM batch today, can I join 6:30 PM?")
/// Accept • Reply • Send to manager. Live updates come on the socket
/// "request_update" (TrainerAlerts listens and calls load()).
class TrainerRequests {
  TrainerRequests._();

  static final ValueNotifier<List<Map<String, dynamic>>> items =
      ValueNotifier<List<Map<String, dynamic>>>(const []);
  static final ValueNotifier<int> open = ValueNotifier<int>(
    0,
  ); // waiting for me
  static final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  static final ValueNotifier<int> tick = ValueNotifier<int>(
    0,
  ); // something changed

  /// set by a notification tap → the inbox opens this request
  static final ValueNotifier<String> openId = ValueNotifier<String>('');

  static String get _base => '${ApiEndpoints.baseUrl}/requests';

  static String _err(http.Response r, String fallback) {
    try {
      final d = jsonDecode(r.body);
      if (d is Map && d['message'] != null) return '${d['message']}';
    } catch (_) {}
    return fallback;
  }

  static Future<void> load() async {
    loading.value = items.value.isEmpty;
    try {
      final res = await http
          .get(
            Uri.parse(
              '$_base/trainer?_t=${DateTime.now().millisecondsSinceEpoch}',
            ),
            headers: ApiHeaders.auth(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        items.value = ((d['requests'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        open.value = int.tryParse('${d['open'] ?? 0}') ?? 0;
        tick.value++;
      }
    } catch (e) {
      debugPrint('🙋 trainer requests: $e');
    } finally {
      loading.value = false;
    }
  }

  static Future<Map<String, dynamic>?> get(String id) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/$id'), headers: ApiHeaders.auth())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200)
        return Map<String, dynamic>.from(
          jsonDecode(res.body)['request'] as Map,
        );
    } catch (_) {}
    return null;
  }

  static Future<String?> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/$path'),
            headers: ApiHeaders.json(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        await load();
        return null;
      }
      return _err(res, 'Something went wrong (${res.statusCode}).');
    } catch (_) {
      return 'No internet. Try again.';
    }
  }

  static Future<String?> reply(String id, String text) =>
      _post('$id/reply', {'text': text});
  static Future<String?> accept(String id, String text) =>
      _post('$id/accept', {'text': text});
  static Future<String?> escalate(String id, String text) =>
      _post('$id/escalate', {'text': text});
}
