import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:letsspeak_trainer/screens/TeacherLoginScreen.dart';
import 'package:letsspeak_trainer/screens/TeacherMainNavigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  final box = GetStorage();
  final rawProfile = box.read('teacher_profile');
  final token = box.read('token');

  Map<String, dynamic>? teacherProfile;

  // Auto-login ONLY if both profile and token exist.
  // Old sessions (saved before the token update) have a profile but no token →
  // clear them so the trainer logs in once and gets a token.
  if (rawProfile is Map && token is String && token.isNotEmpty) {
    teacherProfile = Map<String, dynamic>.from(rawProfile);
  } else if (rawProfile != null) {
    await box.remove('teacher_profile');
    await box.remove('token');
  }

  runApp(TeacherApp(initialLoggedInUser: teacherProfile));
}

class TeacherApp extends StatelessWidget {
  final Map<String, dynamic>? initialLoggedInUser;

  const TeacherApp({super.key, this.initialLoggedInUser});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Teacher & Trainer Portal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xff0D0D0D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2E90FA),
          brightness: Brightness.dark,
        ),
      ),
      // Go to Main Navigation if a valid session (profile + token) exists, else Login
      home: initialLoggedInUser != null
          ? TeacherMainNavigation(teacherData: initialLoggedInUser!)
          : const TeacherLoginScreen(),
    );
  }
}