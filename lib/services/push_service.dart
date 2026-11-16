import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:letsspeak_trainer/services/trainer_alerts.dart';

/// 🔔 Phone notifications for trainers ("👋 New student: Venkat").
///
///   main():                      await PushService.init();
///   after login (navigation):    PushService.register();
///   logout:                      await PushService.unregister();
///
/// Needs android/app/google-services.json for com.example.letsspeak_trainer
/// (Firebase console → same project as the student app → Add Android app).
/// Without it the app still works — only phone notifications are off.
class PushService {
  static bool _ready = false;
  static String? _sentToken;

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      await fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      // app open → the live pop-up (socket) already shows it; just refresh the list
      FirebaseMessaging.onMessage.listen((_) => TrainerAlerts.load());
      // tapped the notification → open the "New students" tab
      FirebaseMessaging.onMessageOpenedApp.listen((_) => _openAlerts());
      final first = await fm.getInitialMessage();
      if (first != null) _openAlerts();
      fm.onTokenRefresh.listen((t) => _send(t));
      _ready = true;
    } catch (e) {
      debugPrint('🔕 Trainer push is off (google-services.json missing?): $e');
    }
  }

  static void _openAlerts() {
    TrainerAlerts.load();
    TrainerAlerts.openTab.value = TrainerAlerts.openTab.value + 1;
  }

  /// Ask permission once and give this phone to the server. Safe to call often.
  static Future<void> register() async {
    if (kIsWeb || !_ready) return;
    try {
      final login = (GetStorage().read('token') ?? '').toString();
      if (login.isEmpty) return;
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      if (Platform.isIOS) {
        for (var i = 0; i < 5 && await fm.getAPNSToken() == null; i++) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
      final t = await fm.getToken();
      if (t != null) await _send(t);
    } catch (e) {
      debugPrint('Trainer push register error: $e');
    }
  }

  static Future<void> _send(String fcmToken) async {
    final login = (GetStorage().read('token') ?? '').toString();
    if (login.isEmpty || fcmToken == _sentToken) return;
    final res = await http
        .post(
          Uri.parse('${ApiEndpoints.baseUrl}/user/push-token'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $login'},
          body: jsonEncode({'token': fcmToken}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) _sentToken = fcmToken;
  }

  /// Logout: stop notifications for this account on this phone.
  static Future<void> unregister() async {
    TrainerAlerts.stop();
    if (kIsWeb || !_ready) return;
    try {
      final login = (GetStorage().read('token') ?? '').toString();
      final t = await FirebaseMessaging.instance.getToken();
      if (login.isNotEmpty && t != null) {
        await http
            .delete(
              Uri.parse('${ApiEndpoints.baseUrl}/user/push-token'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $login'},
              body: jsonEncode({'token': t}),
            )
            .timeout(const Duration(seconds: 8));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _sentToken = null;
  }
}
