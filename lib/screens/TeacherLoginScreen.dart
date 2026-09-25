import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:letsspeak_trainer/screens/TeacherMainNavigation.dart';

class TeacherLoginScreen extends StatefulWidget {
  const TeacherLoginScreen({super.key});

  @override
  State<TeacherLoginScreen> createState() => _TeacherLoginScreenState();
}

class _TeacherLoginScreenState extends State<TeacherLoginScreen> {
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  final isLoading = false.obs;
  bool _obscurePassword = true;

  // Letsspeak brand colors
  static const Color navy = Color(0xFF155A88);
  static const Color deepNavy = Color(0xFF0E466D);
  static const Color blue = Color(0xFF2C6F9F);
  static const Color teal = Color(0xFF28C2C2);
  static const Color yellow = Color(0xFFF7DF55);
  static const Color background = Color(0xFFE8F2F8);
  static const Color textDark = Color(0xFF123B57);
  static const Color mutedText = Color(0xFF71889A);
  static const Color border = Color(0xFFD3E2EB);
  static const Color errorRed = Color(0xFFE45757);

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submitTeacherLogin() async {
    final phone = phoneController.text.trim();
    final password = passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      Get.snackbar(
        "Required",
        "Enter your phone number and password.",
        backgroundColor: errorRed,
        colorText: Colors.white,
        margin: const EdgeInsets.all(14),
        borderRadius: 12,
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    isLoading.value = true;

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.login),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone, "password": password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final userRole = (data['user']['role'] ?? '').toString().toLowerCase();

        if (userRole == 'teacher' || userRole == 'manager') {
          // 🚀 Session cleared on restart so login is required every time

          Get.offAll(() => TeacherMainNavigation(teacherData: data['user']));

          Get.snackbar(
            "Welcome back 👋",
            "Login successful",
            backgroundColor: navy,
            colorText: Colors.white,
            margin: const EdgeInsets.all(14),
            borderRadius: 12,
            snackPosition: SnackPosition.BOTTOM,
          );
        } else {
          Get.snackbar(
            "Access Denied",
            "This app is restricted to teachers and trainers.",
            backgroundColor: errorRed,
            colorText: Colors.white,
            margin: const EdgeInsets.all(14),
            borderRadius: 12,
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      } else {
        Get.snackbar(
          "Login Failed",
          data['message'] ?? "Invalid phone number or password",
          backgroundColor: errorRed,
          colorText: Colors.white,
          margin: const EdgeInsets.all(14),
          borderRadius: 12,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      Get.snackbar(
        "Connection Error",
        "Unable to connect. Please check your internet connection.",
        backgroundColor: errorRed,
        colorText: Colors.white,
        margin: const EdgeInsets.all(14),
        borderRadius: 12,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
        color: mutedText,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: navy, size: 19),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF4F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: teal, width: 1.6),
      ),
    );
  }

  Widget _logo() {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [navy, blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: navy.withOpacity(.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(Icons.school_rounded, color: Colors.white, size: 31),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: yellow,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 410),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: navy.withOpacity(.10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Obx(
        () => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _logo()),
            const SizedBox(height: 16),
            Center(
              child: Text(
                "Trainer Login",
                style: GoogleFonts.poppins(
                  color: deepNavy,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                "Sign in to continue",
                style: GoogleFonts.poppins(
                  color: mutedText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "PHONE NUMBER",
              style: GoogleFonts.poppins(
                color: textDark,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              style: GoogleFonts.poppins(
                color: textDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: _inputDecoration(
                hint: "Enter phone number",
                icon: Icons.phone_android_rounded,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "PASSWORD",
              style: GoogleFonts.poppins(
                color: textDark,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 7),
            TextField(
              controller: passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              style: GoogleFonts.poppins(
                color: textDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              onSubmitted: (_) => submitTeacherLogin(),
              decoration: _inputDecoration(
                hint: "Enter password",
                icon: Icons.lock_rounded,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: mutedText,
                    size: 19,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [navy, blue]),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: navy.withOpacity(.20),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: isLoading.value ? null : submitTeacherLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: isLoading.value
                      ? const SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Sign In",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 7),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_rounded, color: teal, size: 13),
                  const SizedBox(width: 5),
                  Text(
                    "Secure staff login",
                    style: GoogleFonts.poppins(
                      color: mutedText,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: _loginCard(),
          ),
        ),
      ),
    );
  }
}
