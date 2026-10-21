import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:letsspeak_trainer/screens/best_students_view.dart';

/// 🏆 Best students of the month (trainer app) — your class first, then all classes.
/// Students only — trainer rankings are never shown here.
class BestStudentsScreen extends StatelessWidget {
  const BestStudentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffE8F2F8),
      appBar: AppBar(
        backgroundColor: const Color(0xffF4F8FB),
        surfaceTintColor: const Color(0xffF4F8FB),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xff16324A)),
          onPressed: () => Get.back(),
        ),
        title: Text('Best Students',
            style: GoogleFonts.poppins(color: const Color(0xff155A88), fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: const BestStudentsView(audience: 'trainer'),
          ),
        ),
      ),
    );
  }
}
