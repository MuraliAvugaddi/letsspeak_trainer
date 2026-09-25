import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:letsspeak_trainer/Api/Apiend_points.dart';

const double instituteLat = 17.729417;
const double instituteLng = 83.312231;
const double allowedRadius = 40.0;

class TeacherAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> teacherData;

  const TeacherAttendanceScreen({super.key, required this.teacherData});

  @override
  State<TeacherAttendanceScreen> createState() =>
      _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen>
    with WidgetsBindingObserver {
  bool isLoading = true;
  bool isCheckingIn = false;

  List<Map<String, dynamic>> attendanceList = [];
  Map<String, dynamic>? teacherAttendanceRecord;
  DateTime selectedDate = DateTime.now();

  static const Color navy = Color(0xFF155A88);
  static const Color deepNavy = Color(0xFF0E466D);
  static const Color blue = Color(0xFF2C6F9F);
  static const Color teal = Color(0xFF28C2C2);
  static const Color yellow = Color(0xFFF7DF55);
  static const Color background = Color(0xFFE8F2F8);
  static const Color green = Color(0xFF20A879);
  static const Color red = Color(0xFFE45757);
  static const Color textSecondary = Color(0xFF6B8193);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 🚀 Register lifecycle observer
    fetchTeacherAndClassroomAttendance();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 🚀 Clean up observer
    super.dispose();
  }

  // 🚀 Automatically re-fetches attendance records when returning to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      fetchTeacherAndClassroomAttendance();
    }
  }

  Future<void> fetchTeacherAndClassroomAttendance() async {
    if (!mounted) return;
    setState(() => isLoading = true);

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
      final String loggedInTeacherId =
          (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
              .toString();

      final String day = selectedDate.day.toString().padLeft(2, '0');
      final String month = selectedDate.month.toString().padLeft(2, '0');
      final String year = selectedDate.year.toString();
      final String dateStr = "$day-$month-$year";

      final querySection = (language.toLowerCase() == 'hindi') ? 'all' : section;

      final rosterRes = await http.get(
        Uri.parse(
          "${ApiEndpoints.baseUrl}/admin/trainer-roster?stage=$stage&language=$language&section=$querySection&mode=$teacherMode&date=$dateStr",
        ),
      );

      final attendanceRes = await http.get(
        Uri.parse("${ApiEndpoints.baseUrl}/admin/attendance?date=$dateStr&stage=$stage&language=$language"),
      );

      if (rosterRes.statusCode == 200 && attendanceRes.statusCode == 200) {
        final decodedRoster = jsonDecode(rosterRes.body);
        List<dynamic> students = decodedRoster['students'] ?? [];
        List<dynamic> attendanceRecords = jsonDecode(attendanceRes.body);

        var myRecord = attendanceRecords.firstWhere(
          (att) => att['userId']?.toString() == loggedInTeacherId,
          orElse: () => null,
        );

        String? teacherTime;
        if (myRecord != null &&
            (myRecord['markedAt'] != null || myRecord['joinTime'] != null)) {
          try {
            DateTime dt = DateTime.parse(
              myRecord['markedAt'] ?? myRecord['joinTime'],
            ).toLocal();
            teacherTime = DateFormat('hh:mm a').format(dt);
          } catch (_) {
            teacherTime = "Today";
          }
        }

        teacherAttendanceRecord = {
          "name": "${widget.teacherData['name'] ?? 'Trainer'} (You)",
          "status": myRecord != null
              ? (myRecord['status'] ?? "Present")
              : "Absent",
          "totalMinutes": myRecord != null
              ? (myRecord['totalMinutes'] ?? myRecord['totalMinutesSpent'] ?? 0)
              : 0,
          "markedAtTime": teacherTime,
        };

        List<Map<String, dynamic>> tempList = [];
        for (var student in students) {
          String? formattedTime;
          if (student['markedAt'] != null) {
            try {
              DateTime dt = DateTime.parse(student['markedAt']).toLocal();
              formattedTime = DateFormat('hh:mm a').format(dt);
            } catch (_) {
              formattedTime = "Today";
            }
          }

          tempList.add({
            "userName": student['name'] ?? "Unknown Student",
            "status": student['attendanceStatus'] ?? "Absent",
            "totalMinutes": student['totalMinutesSpent'] ?? 0,
            "markedAtTime": formattedTime,
          });
        }

        if (mounted) {
          setState(() {
            attendanceList = tempList;
            isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("Classroom Attendance Fetch Error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleTeacherGeoCheckIn() async {
    setState(() => isCheckingIn = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Get.snackbar(
          "GPS Disabled",
          "Please turn on location services.",
          backgroundColor: red,
          colorText: Colors.white,
          margin: const EdgeInsets.all(14),
          borderRadius: 14,
        );
        setState(() => isCheckingIn = false);
        return;
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
          "You are ${distance.toInt()}m away from the institute.",
          backgroundColor: red,
          colorText: Colors.white,
          margin: const EdgeInsets.all(14),
          borderRadius: 14,
        );
        setState(() => isCheckingIn = false);
        return;
      }

      final teacherId = widget.teacherData['_id'] ?? widget.teacherData['id'];

      final res = await http.post(
        Uri.parse("${ApiEndpoints.baseUrl}/user/mark-attendance"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": teacherId,
          "stage":
              widget.teacherData['stage'] ??
              widget.teacherData['teacherStage'] ??
              "Stage 1",
          "lat": position.latitude,
          "lng": position.longitude,
          "language": widget.teacherData['language'] ?? "English",
        }),
      );

      if (res.statusCode == 200) {
        Get.snackbar(
          "Attendance Marked",
          "Your attendance was marked successfully.",
          backgroundColor: green,
          colorText: Colors.white,
          margin: const EdgeInsets.all(14),
          borderRadius: 14,
          icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
        );
        fetchTeacherAndClassroomAttendance();
      } else {
        final data = jsonDecode(res.body);
        Get.snackbar(
          "Check-In Notice",
          data['message'] ?? "Check-in failed.",
          backgroundColor: yellow,
          colorText: deepNavy,
          margin: const EdgeInsets.all(14),
          borderRadius: 14,
        );
      }
    } catch (e) {
      Get.snackbar(
        "Check-In Error",
        "Unable to complete GPS check-in.",
        backgroundColor: red,
        colorText: Colors.white,
        margin: const EdgeInsets.all(14),
        borderRadius: 14,
      );
    } finally {
      if (mounted) setState(() => isCheckingIn = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate.isAfter(today) ? today : selectedDate,
      firstDate: DateTime(2024),
      lastDate: today,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: navy,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: deepNavy,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = DateTime(picked.year, picked.month, picked.day));
      fetchTeacherAndClassroomAttendance();
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

    final String language =
        widget.teacherData['language']?.toString() ?? 'English';

    final String teacherMode = (widget.teacherData['mode'] ?? 'online')
        .toString()
        .toLowerCase();

    final String dateLabel = DateFormat('EEE, d MMM yyyy').format(selectedDate);

    final int totalCount = attendanceList.length;
    final int presentCount = attendanceList
        .where((s) => s['status'] == 'Present')
        .length;
    final int lateCount = attendanceList
        .where((s) => s['status'] == 'Late' || s['status'] == 'Partial')
        .length;
    final int absentCount = attendanceList
        .where((s) => s['status'] == 'Absent')
        .length;

    String trainerStatus =
        teacherAttendanceRecord?['status']?.toString() ?? "ABSENT";
    Color trainerStatusColor = _statusColor(trainerStatus);

    return Scaffold(
      backgroundColor: background,
      appBar: _buildAppBar(context, language, stageName, section),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool desktop = constraints.maxWidth >= 1000;
            final bool tablet =
                constraints.maxWidth >= 650 && constraints.maxWidth < 1000;

            final double horizontal = desktop
                ? 38
                : tablet
                ? 26
                : 16;

            return RefreshIndicator(
              color: teal,
              backgroundColor: Colors.white,
              onRefresh: fetchTeacherAndClassroomAttendance,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      18,
                      horizontal,
                      30,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDateAndActionBar(
                              context,
                              dateLabel,
                              teacherMode,
                            ),
                            const SizedBox(height: 16),
                            if (teacherAttendanceRecord != null)
                              _buildTrainerStatus(
                                trainerStatus,
                                trainerStatusColor,
                                teacherMode,
                                desktop,
                              ),
                            const SizedBox(height: 16),
                            _buildSummary(
                              totalCount,
                              presentCount,
                              lateCount,
                              absentCount,
                            ),
                            const SizedBox(height: 22),
                            Text(
                              'Classroom attendance',
                              style: GoogleFonts.poppins(
                                color: deepNavy,
                                fontSize: desktop ? 20 : 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 13),
                            if (isLoading)
                              _buildLoading()
                            else if (attendanceList.isEmpty)
                              _buildEmptyState()
                            else if (desktop)
                              _buildDesktopStudents(attendanceList)
                            else
                              _buildMobileStudents(attendanceList),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    String language,
    String stage,
    String section,
  ) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: navy,
      foregroundColor: Colors.white,
      automaticallyImplyLeading: true,
      toolbarHeight: 68,
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Classroom Attendance',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$language • $stage • Section $section',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(.70),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Choose date',
          onPressed: () => _selectDate(context),
          icon: const Icon(Icons.calendar_month_rounded, size: 21),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: fetchTeacherAndClassroomAttendance,
          icon: const Icon(Icons.refresh_rounded, size: 22),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildDateAndActionBar(
    BuildContext context,
    String dateLabel,
    String teacherMode,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: navy.withOpacity(.10)),
        boxShadow: [
          BoxShadow(
            color: navy.withOpacity(.06),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool compact = constraints.maxWidth < 500;
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dateButton(dateLabel),
                    if (teacherMode == 'offline') ...[
                      const SizedBox(height: 10),
                      _geoButton(),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _dateButton(dateLabel)),
                    if (teacherMode == 'offline') ...[
                      const SizedBox(width: 12),
                      _geoButton(),
                    ],
                  ],
                );
        },
      ),
    );
  }

  Widget _dateButton(String dateLabel) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => _selectDate(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: navy.withOpacity(.10)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: navy.withOpacity(.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.event_rounded, color: navy, size: 20),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SELECTED DATE',
                  style: GoogleFonts.poppins(
                    color: textSecondary,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: GoogleFonts.poppins(
                    color: deepNavy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: navy,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _geoButton() {
    return SizedBox(
      height: 62,
      child: ElevatedButton.icon(
        onPressed: isCheckingIn ? null : _handleTeacherGeoCheckIn,
        icon: isCheckingIn
            ? const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.location_on_rounded, size: 18),
        label: Text(
          isCheckingIn ? 'Checking location...' : 'Geo Check-In',
          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: teal.withOpacity(.45),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  Widget _buildTrainerStatus(
    String status,
    Color statusColor,
    String teacherMode,
    bool desktop,
  ) {
    final String? markedTime = teacherAttendanceRecord?['markedAtTime'];
    final int minutes = teacherAttendanceRecord?['totalMinutes'] ?? 0;
    String subtitle;

    if (markedTime != null) {
      subtitle = 'Marked at $markedTime • Active for $minutes mins';
    } else if (teacherMode == 'online') {
      subtitle = 'Start the live audio class to record your presence.';
    } else {
      subtitle = 'Complete GPS check-in to mark your attendance.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [navy, blue],
        ),
        borderRadius: BorderRadius.circular(21),
        boxShadow: [
          BoxShadow(
            color: navy.withOpacity(.16),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: desktop ? 52 : 46,
            height: desktop ? 52 : 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.12),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withOpacity(.12)),
            ),
            child: Icon(
              status == 'Present'
                  ? Icons.check_circle_rounded
                  : status == 'Absent'
                  ? Icons.person_off_rounded
                  : Icons.schedule_rounded,
              color: statusColor == yellow ? yellow : statusColor,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Trainer Status',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(.68),
                    fontSize: 10.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _statusBadge(status.toUpperCase(), statusColor, darkBackground: true),
        ],
      ),
    );
  }

  Widget _buildSummary(int total, int present, int late, int absent) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool small = constraints.maxWidth < 500;
        return GridView.count(
          crossAxisCount: small ? 2 : 4,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: small ? 1.85 : 2.35,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _summaryCard('Total', total, navy, Icons.groups_rounded),
            _summaryCard(
              'Present',
              present,
              teal,
              Icons.check_circle_outline_rounded,
            ),
            _summaryCard('Late', late, yellow, Icons.schedule_rounded),
            _summaryCard('Absent', absent, red, Icons.cancel_outlined),
          ],
        );
      },
    );
  }

  Widget _summaryCard(String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withOpacity(.18)),
        boxShadow: [
          BoxShadow(
            color: navy.withOpacity(.045),
            blurRadius: 13,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: color.withOpacity(.11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$value',
                style: GoogleFonts.poppins(
                  color: deepNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: textSecondary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopStudents(List<Map<String, dynamic>> students) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: navy.withOpacity(.10)),
        boxShadow: [
          BoxShadow(
            color: navy.withOpacity(.045),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: DataTable(
          headingRowHeight: 52,
          dataRowMinHeight: 70,
          dataRowMaxHeight: 78,
          horizontalMargin: 20,
          columnSpacing: 35,
          headingRowColor: const WidgetStatePropertyAll(Color(0xFFF2F7FA)),
          headingTextStyle: GoogleFonts.poppins(
            color: textSecondary,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
          dataTextStyle: GoogleFonts.poppins(color: deepNavy, fontSize: 11),
          columns: const [
            DataColumn(label: Text('STUDENT')),
            DataColumn(label: Text('STATUS')),
            DataColumn(label: Text('TIME')),
            DataColumn(label: Text('ACTIVE')),
          ],
          rows: students.map((student) {
            final String name =
                student['userName']?.toString().trim().isNotEmpty == true
                ? student['userName'].toString()
                : 'Unknown Student';
            final String status = student['status']?.toString() ?? 'Absent';
            final String? time = student['markedAtTime']?.toString();
            final int mins = _toInt(student['totalMinutes']);
            final Color color = _statusColor(status);

            return DataRow(
              cells: [
                DataCell(
                  Row(
                    children: [
                      _studentAvatar(name, color),
                      const SizedBox(width: 11),
                      SizedBox(
                        width: 210,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: deepNavy,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(_statusBadge(status.toUpperCase(), color)),
                DataCell(
                  Text(
                    time ?? 'Not joined',
                    style: GoogleFonts.poppins(
                      color: textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    '$mins mins',
                    style: GoogleFonts.poppins(
                      color: deepNavy,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileStudents(List<Map<String, dynamic>> students) {
    return Column(
      children: students.map((student) {
        final String name =
            student['userName']?.toString().trim().isNotEmpty == true
            ? student['userName'].toString()
            : 'Unknown Student';
        final String status = student['status']?.toString() ?? 'Absent';
        final String? time = student['markedAtTime']?.toString();
        final int mins = _toInt(student['totalMinutes']);
        final Color color = _statusColor(status);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 11),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(.18)),
            boxShadow: [
              BoxShadow(
                color: navy.withOpacity(.045),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              _studentAvatar(name, color, radius: 22),
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
                        color: deepNavy,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          time != null
                              ? Icons.login_rounded
                              : Icons.schedule_rounded,
                          color: textSecondary,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            time != null
                                ? 'Joined at $time • $mins mins'
                                : 'Not joined class yet',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: textSecondary,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(status.toUpperCase(), color),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _studentAvatar(String name, Color color, {double radius = 19}) {
    final String initial = name.trim().isNotEmpty
        ? name.trim()[0].toUpperCase()
        : 'S';
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withOpacity(.12),
      child: Text(
        initial,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: radius * .62,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _statusBadge(
    String label,
    Color color, {
    bool darkBackground = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: darkBackground ? color.withOpacity(.18) : color.withOpacity(.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: darkBackground
              ? color.withOpacity(.45)
              : color.withOpacity(.18),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: darkBackground ? Colors.white : color,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .2,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(45),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: teal, strokeWidth: 2.5),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 55),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: navy.withOpacity(.08)),
      ),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: teal.withOpacity(.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_outlined, color: teal, size: 32),
          ),
          const SizedBox(height: 15),
          Text(
            'No students enrolled',
            style: GoogleFonts.poppins(
              color: deepNavy,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'There are no students assigned to this classroom for the selected date.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: textSecondary,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return teal;
      case 'late':
      case 'partial':
        return yellow;
      case 'absent':
      default:
        return red;
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }
}