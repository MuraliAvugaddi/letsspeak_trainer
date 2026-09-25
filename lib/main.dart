import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:letsspeak_trainer/screens/TeacherLoginScreen.dart';
import 'package:letsspeak_trainer/screens/TeacherMainNavigation.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  
  final box = GetStorage();
  final teacherProfile = box.read('teacher_profile');

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
      // Automatically navigate to Main Navigation if session exists, else Login
      home: initialLoggedInUser != null
          ? TeacherMainNavigation(teacherData: initialLoggedInUser!)
          : const TeacherLoginScreen(),
    );
  }
}