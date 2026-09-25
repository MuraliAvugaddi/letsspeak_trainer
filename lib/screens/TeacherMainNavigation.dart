import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:letsspeak_trainer/screens/Home_PortalScreen.dart';
import 'package:letsspeak_trainer/screens/TeacherMaterialsScreen.dart';
import 'package:letsspeak_trainer/screens/TeacherProfileScreen.dart';

class TeacherMainNavigation extends StatefulWidget {
  final Map<String, dynamic> teacherData;

  const TeacherMainNavigation({super.key, required this.teacherData});

  @override
  State<TeacherMainNavigation> createState() => _TeacherMainNavigationState();
}

class _TeacherMainNavigationState extends State<TeacherMainNavigation> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  // ============================================================
  // LETSSPEAK BRAND COLORS
  // ============================================================

  static const Color brandNavy = Color(0xFF155A8A);
  static const Color brandBlue = Color(0xFF2C6F9F);
  static const Color brandLightBlue = Color(0xFF7CA4D8);

  static const Color brandTeal = Color(0xFF27BFC0);
  static const Color brandYellow = Color(0xFFF5DD55);

  static const Color pageBackground = Color(0xFFEAF2F8);
  static const Color navigationBackground = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();

    _screens = [
      TeacherPortalScreen(teacherData: widget.teacherData),
      TeacherMaterialsScreen(teacherData: widget.teacherData),
      TeacherProfileScreen(teacherData: widget.teacherData),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool isWeb = MediaQuery.of(context).size.width >= 700;

    return Scaffold(
      backgroundColor: pageBackground,

      // ----------------------------------------------------------
      // KEEP ALL SCREENS ALIVE
      // ----------------------------------------------------------
      body: IndexedStack(index: _currentIndex, children: _screens),

      // ----------------------------------------------------------
      // RESPONSIVE NAVIGATION
      // ----------------------------------------------------------
      bottomNavigationBar: isWeb
          ? _buildWebNavigation()
          : _buildMobileNavigation(),
    );
  }

  // ============================================================
  // MOBILE NAVIGATION
  // ============================================================

  Widget _buildMobileNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: navigationBackground,
        boxShadow: [
          BoxShadow(
            color: brandNavy.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
        border: Border(
          top: BorderSide(color: brandNavy.withValues(alpha: 0.08), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  index: 0,
                  icon: Icons.dashboard_rounded,
                  label: 'Classroom',
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 1,
                  icon: Icons.menu_book_rounded,
                  label: 'Materials',
                ),
              ),
              Expanded(
                child: _buildNavItem(
                  index: 2,
                  icon: Icons.person_rounded,
                  label: 'Profile',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MOBILE NAV ITEM
  // ============================================================

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool selected = _currentIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (_currentIndex == index) return;

        setState(() {
          _currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? brandTeal.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: selected ? 44 : 38,
              height: selected ? 32 : 30,
              decoration: BoxDecoration(
                color: selected
                    ? brandTeal.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: selected ? 23 : 22,
                color: selected ? brandNavy : brandNavy.withValues(alpha: 0.48),
              ),
            ),

            const SizedBox(height: 3),

            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? brandNavy : brandNavy.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WEB NAVIGATION
  // ============================================================

  Widget _buildWebNavigation() {
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: navigationBackground,
        border: Border(
          top: BorderSide(color: brandNavy.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: brandNavy.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildWebNavItem(
                  index: 0,
                  icon: Icons.dashboard_rounded,
                  label: 'Classroom',
                ),
                const SizedBox(width: 12),
                _buildWebNavItem(
                  index: 1,
                  icon: Icons.menu_book_rounded,
                  label: 'Materials',
                ),
                const SizedBox(width: 12),
                _buildWebNavItem(
                  index: 2,
                  icon: Icons.person_rounded,
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WEB NAV ITEM
  // ============================================================

  Widget _buildWebNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final bool selected = _currentIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        if (_currentIndex == index) return;

        setState(() {
          _currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 180,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected
              ? brandNavy.withValues(alpha: 0.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? brandTeal.withValues(alpha: 0.28)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? brandTeal
                    : brandLightBlue.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 21,
                color: selected
                    ? Colors.white
                    : brandNavy.withValues(alpha: 0.62),
              ),
            ),

            const SizedBox(width: 11),

            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? brandNavy : brandNavy.withValues(alpha: 0.60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
