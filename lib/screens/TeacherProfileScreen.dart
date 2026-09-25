import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:letsspeak_trainer/screens/Home_PortalScreen.dart';
import 'package:letsspeak_trainer/screens/TeacherLoginScreen.dart';
import 'package:letsspeak_trainer/screens/teacher_attdance.dart';

class TeacherProfileScreen extends StatelessWidget {
  final Map<String, dynamic> teacherData;

  const TeacherProfileScreen({super.key, required this.teacherData});

  // ============================================================
  // LETSSPEAK BRAND COLORS
  // ============================================================

  static const Color navy = Color(0xFF155A88);
  static const Color deepNavy = Color(0xFF0E466D);
  static const Color blue = Color(0xFF2C6F9F);

  static const Color teal = Color(0xFF28C2C2);
  static const Color yellow = Color(0xFFF7DF55);
  static const Color periwinkle = Color(0xFF7CA4D8);

  static const Color background = Color(0xFFE8F2F8);
  static const Color backgroundDark = Color(0xFFD9EAF3);

  static const Color white = Colors.white;
  static const Color errorRed = Color(0xFFE45757);

  @override
  Widget build(BuildContext context) {
    final box = GetStorage();

    final String name = (teacherData['name'] ?? 'Trainer').toString();

    final String phone = (teacherData['phone'] ?? 'No phone number').toString();

    final String role = (teacherData['role'] ?? 'Teacher').toString();

    final String mode = (teacherData['mode'] ?? 'Online').toString();

    final String language = (teacherData['language'] ?? 'English').toString();

    final String stage =
        (teacherData['stage'] ?? teacherData['teacherStage'] ?? 'Stage 1')
            .toString();

    final String section =
        (teacherData['section'] ?? teacherData['teacherSection'] ?? 'A')
            .toString();

    return Scaffold(
      backgroundColor: background,

      appBar: _buildAppBar(context),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;

            final bool isDesktop = width >= 1000;
            final bool isTablet = width >= 650 && width < 1000;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),

              padding: EdgeInsets.symmetric(
                horizontal: isDesktop
                    ? 40
                    : isTablet
                    ? 28
                    : 16,
                vertical: 22,
              ),

              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1150),

                  child: isDesktop
                      ? _buildDesktopLayout(
                          context,
                          name,
                          phone,
                          role,
                          mode,
                          language,
                          stage,
                          section,
                          box,
                        )
                      : _buildMobileLayout(
                          context,
                          name,
                          phone,
                          role,
                          mode,
                          language,
                          stage,
                          section,
                          box,
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // APP BAR
  // ============================================================

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: navy,
      toolbarHeight: 64,

      automaticallyImplyLeading: false,

      titleSpacing: 16,

      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,

            decoration: BoxDecoration(
              color: teal,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: teal.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),

            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),

          const SizedBox(width: 12),

          Text(
            'My Profile',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MOBILE
  // ============================================================

  Widget _buildMobileLayout(
    BuildContext context,
    String name,
    String phone,
    String role,
    String mode,
    String language,
    String stage,
    String section,
    GetStorage box,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileHeader(name, phone, role),

        const SizedBox(height: 24),

        _buildSectionTitle(
          'Teaching Assignment',
          'Your current training allocation',
        ),

        const SizedBox(height: 12),

        _buildInfoGrid([
          _InfoData('Language', language, Icons.language_rounded, teal),
          _InfoData('Stage', stage, Icons.layers_rounded, navy),
          _InfoData('Section', section, Icons.groups_rounded, yellow),
          _InfoData('Mode', mode, Icons.wifi_rounded, blue),
        ]),

        const SizedBox(height: 24),

        _buildAttendanceCard(context),

        const SizedBox(height: 24),

        _buildSectionTitle('Account', 'Manage your trainer account'),

        const SizedBox(height: 12),

        _buildLogoutButton(box),

        const SizedBox(height: 20),
      ],
    );
  }

  // ============================================================
  // DESKTOP
  // ============================================================

  Widget _buildDesktopLayout(
    BuildContext context,
    String name,
    String phone,
    String role,
    String mode,
    String language,
    String stage,
    String section,
    GetStorage box,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileHeader(name, phone, role),

        const SizedBox(height: 28),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle(
                    'Teaching Assignment',
                    'Your current training allocation',
                  ),

                  const SizedBox(height: 14),

                  _buildInfoGrid([
                    _InfoData(
                      'Language',
                      language,
                      Icons.language_rounded,
                      teal,
                    ),
                    _InfoData('Stage', stage, Icons.layers_rounded, navy),
                    _InfoData('Section', section, Icons.groups_rounded, yellow),
                    _InfoData('Mode', mode, Icons.wifi_rounded, blue),
                  ]),
                ],
              ),
            ),

            const SizedBox(width: 22),

            Expanded(
              flex: 2,
              child: Column(
                children: [
                  _buildAttendanceCard(context),

                  const SizedBox(height: 18),

                  _buildLogoutButton(box),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 25),
      ],
    );
  }

  // ============================================================
  // PROFILE HEADER
  // ============================================================

  Widget _buildProfileHeader(String name, String phone, String role) {
    final String initial = name.trim().isNotEmpty
        ? name.trim()[0].toUpperCase()
        : 'T';

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [navy, blue],
        ),

        borderRadius: BorderRadius.circular(24),

        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.18),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),

      child: Stack(
        children: [
          // Decorative circle
          Positioned(
            right: -45,
            top: -60,

            child: Container(
              width: 170,
              height: 170,

              decoration: BoxDecoration(
                color: teal.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
            ),
          ),

          Positioned(
            right: 70,
            bottom: -80,

            child: Container(
              width: 130,
              height: 130,

              decoration: BoxDecoration(
                color: periwinkle.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),

          Row(
            children: [
              // Avatar
              Container(
                width: 76,
                height: 76,

                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),

                  shape: BoxShape.circle,

                  border: Border.all(
                    color: yellow.withValues(alpha: 0.75),
                    width: 2,
                  ),
                ),

                child: Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.poppins(
                      color: yellow,
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 17),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,

                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      phone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,

                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 11.5,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      children: [
                        _buildHeaderBadge(role, Icons.school_rounded, yellow),

                        _buildHeaderBadge(
                          'Active',
                          Icons.check_circle_rounded,
                          teal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER BADGE
  // ============================================================

  Widget _buildHeaderBadge(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),

      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),

          const SizedBox(width: 5),

          Text(
            text,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _buildSectionTitle(String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 32,

          decoration: BoxDecoration(
            color: teal,
            borderRadius: BorderRadius.circular(5),
          ),
        ),

        const SizedBox(width: 10),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                color: deepNavy,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 2),

            Text(
              subtitle,
              style: GoogleFonts.poppins(
                color: navy.withValues(alpha: 0.58),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // INFO GRID
  // ============================================================

  Widget _buildInfoGrid(List<_InfoData> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          shrinkWrap: true,

          physics: const NeverScrollableScrollPhysics(),

          itemCount: items.length,

          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: constraints.maxWidth < 500 ? 2 : 2,

            crossAxisSpacing: 12,
            mainAxisSpacing: 12,

            childAspectRatio: constraints.maxWidth < 500 ? 1.42 : 2.35,
          ),

          itemBuilder: (context, index) {
            final item = items[index];

            return Container(
              padding: const EdgeInsets.all(15),

              decoration: BoxDecoration(
                color: white,

                borderRadius: BorderRadius.circular(18),

                border: Border.all(color: navy.withValues(alpha: 0.08)),

                boxShadow: [
                  BoxShadow(
                    color: navy.withValues(alpha: 0.055),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 37,
                        height: 37,

                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: 0.12),

                          borderRadius: BorderRadius.circular(11),
                        ),

                        child: Icon(item.icon, color: item.color, size: 19),
                      ),

                      const Spacer(),

                      Icon(
                        Icons.check_circle_rounded,
                        color: item.color.withValues(alpha: 0.70),
                        size: 16,
                      ),
                    ],
                  ),

                  const Spacer(),

                  Text(
                    item.label,
                    style: GoogleFonts.poppins(
                      color: navy.withValues(alpha: 0.50),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,

                    style: GoogleFonts.poppins(
                      color: deepNavy,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // ATTENDANCE CARD
  // ============================================================

  Widget _buildAttendanceCard(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,

          colors: [white, teal.withValues(alpha: 0.06)],
        ),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: teal.withValues(alpha: 0.25)),

        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.06),
            blurRadius: 15,
            offset: const Offset(0, 7),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,

                decoration: BoxDecoration(
                  color: teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),

                child: const Icon(
                  Icons.fact_check_rounded,
                  color: teal,
                  size: 23,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  'Stage Attendance',
                  style: GoogleFonts.poppins(
                    color: deepNavy,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            'View and manage attendance records for your assigned stage.',
            style: GoogleFonts.poppins(
              color: navy.withValues(alpha: 0.58),
              fontSize: 11,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 17),

          SizedBox(
            width: double.infinity,
            height: 46,

            child: ElevatedButton(
              onPressed: () {
                Get.to(() => TeacherAttendanceScreen(teacherData: teacherData));
              },

              style: ElevatedButton.styleFrom(
                backgroundColor: teal,
                foregroundColor: Colors.white,
                elevation: 0,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),

              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View Attendance',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(width: 8),

                  const Icon(Icons.arrow_forward_rounded, size: 17),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LOGOUT BUTTON
  // ============================================================

  Widget _buildLogoutButton(GetStorage box) {
    return SizedBox(
      width: double.infinity,
      height: 48,

      child: OutlinedButton(
        onPressed: () {
          _showLogoutDialog(box);
        },

        style: OutlinedButton.styleFrom(
          foregroundColor: errorRed,

          backgroundColor: Colors.white,

          side: BorderSide(color: errorRed.withValues(alpha: 0.30)),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, size: 18, color: errorRed),

            const SizedBox(width: 8),

            Text(
              'Sign Out',
              style: GoogleFonts.poppins(
                color: errorRed,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOGOUT DIALOG
  // ============================================================

  void _showLogoutDialog(GetStorage box) {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,

        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),

          padding: const EdgeInsets.all(24),

          decoration: BoxDecoration(
            color: white,

            borderRadius: BorderRadius.circular(24),

            boxShadow: [
              BoxShadow(
                color: navy.withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),

          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,

                decoration: BoxDecoration(
                  color: errorRed.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),

                child: const Icon(
                  Icons.logout_rounded,
                  color: errorRed,
                  size: 26,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Sign out?',
                style: GoogleFonts.poppins(
                  color: deepNavy,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 7),

              Text(
                'Are you sure you want to sign out of your trainer account?',
                textAlign: TextAlign.center,

                style: GoogleFonts.poppins(
                  color: navy.withValues(alpha: 0.58),
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 22),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(),

                      style: OutlinedButton.styleFrom(
                        foregroundColor: navy,
                        side: BorderSide(color: navy.withValues(alpha: 0.18)),

                        minimumSize: const Size(0, 45),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),

                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        box.erase();

                        Get.offAll(() => const TeacherLoginScreen());

                        Get.snackbar(
                          'Signed Out',
                          'You have been securely logged out.',
                          backgroundColor: teal,
                          colorText: Colors.white,
                          margin: const EdgeInsets.all(12),
                          borderRadius: 12,
                        );
                      },

                      style: ElevatedButton.styleFrom(
                        backgroundColor: errorRed,
                        foregroundColor: Colors.white,
                        elevation: 0,

                        minimumSize: const Size(0, 45),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),

                      child: Text(
                        'Sign Out',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
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
  }
}

// ================================================================
// INFO DATA
// ================================================================

class _InfoData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoData(this.label, this.value, this.icon, this.color);
}
