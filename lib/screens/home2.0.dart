// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart';
// import 'package:http/http.dart' as http;
// import 'package:intl/intl.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:get/get.dart';
// import 'package:stream_video_flutter/stream_video_flutter.dart';
// import 'package:socket_io_client/socket_io_client.dart' as IO;
// import 'package:letsspeak_trainer/Api/Apiend_points.dart';
// import 'package:letsspeak_trainer/screens/TeacherLoginScreen.dart';

// const double instituteLat = 17.729417;
// const double instituteLng = 83.312231;
// const double allowedRadius = 40.0;

// // 🌐 Safe Global Overlay Controller
// class GlobalAudioOverlayController {
//   static OverlayEntry? _overlayEntry;
//   static Call? currentCall;
//   static String? currentTeacherId;
//   static String? currentClassName;
//   static Map<String, dynamic>? currentTeacherData;
//   static List<dynamic>? currentStudents;

//   static final RxBool isCallActive = false.obs;

//   static void showOverlay(
//     BuildContext context,
//     Call call,
//     String teacherId,
//     String className,
//     Map<String, dynamic> teacherData,
//     List<dynamic> students,
//   ) {
//     if (_overlayEntry != null) return;
//     currentCall = call;
//     currentTeacherId = teacherId;
//     currentClassName = className;
//     currentTeacherData = teacherData;
//     currentStudents = students;
//     isCallActive.value = true;

//     final overlayState = Overlay.of(context);
//     if (overlayState == null) return;

//     _overlayEntry = OverlayEntry(
//       builder: (context) => const FloatingTrainerPiPWidget(),
//     );

//     overlayState.insert(_overlayEntry!);
//   }

//   static void removeOverlay() {
//     try {
//       _overlayEntry?.remove();
//     } catch (_) {}
//     _overlayEntry = null;
//     currentCall = null;
//     isCallActive.value = false;
//   }
// }

// class FloatingTrainerPiPWidget extends StatefulWidget {
//   const FloatingTrainerPiPWidget({super.key});

//   @override
//   State<FloatingTrainerPiPWidget> createState() =>
//       _FloatingTrainerPiPWidgetState();
// }

// class _FloatingTrainerPiPWidgetState extends State<FloatingTrainerPiPWidget> {
//   Offset _position = const Offset(20, 100);

//   static const Color navy = Color(0xFF155A88);
//   static const Color deepNavy = Color(0xFF0E466D);
//   static const Color blue = Color(0xFF2C6F9F);
//   static const Color teal = Color(0xFF28C2C2);
//   static const Color yellow = Color(0xFFF7DF55);
//   static const Color lightBlue = Color(0xFFE8F2F8);
//   static const Color textDark = Color(0xFF123B57);
//   static const Color mutedText = Color(0xFF6B8294);
//   static const Color red = Color(0xFFE45757);

//   String _participantInitial(String name) {
//     final value = name.trim();
//     if (value.isEmpty) return "?";
//     return value.substring(0, 1).toUpperCase();
//   }

//   String _speakerName(dynamic speaker) {
//     if (speaker == null) return "";
//     final name = speaker.name?.toString().trim() ?? "";
//     if (name.isNotEmpty) return name;
//     final userId = speaker.userId?.toString().trim() ?? "";
//     if (userId.isNotEmpty) return userId;
//     return "Someone";
//   }

//   @override
//   Widget build(BuildContext context) {
//     final call = GlobalAudioOverlayController.currentCall;
//     final teacherId = GlobalAudioOverlayController.currentTeacherId;
//     final teacherData = GlobalAudioOverlayController.currentTeacherData;
//     final students = GlobalAudioOverlayController.currentStudents;

//     if (call == null || teacherId == null || teacherData == null) {
//       return const SizedBox.shrink();
//     }

//     return Positioned(
//       left: _position.dx,
//       top: _position.dy,
//       child: GestureDetector(
//         onPanUpdate: (details) {
//           setState(() {
//             _position += details.delta;
//           });
//         },
//         child: Material(
//           color: Colors.transparent,
//           child: Container(
//             width: 270,
//             padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
//             decoration: BoxDecoration(
//               color: Colors.white,
//               borderRadius: BorderRadius.circular(20),
//               border: Border.all(color: teal, width: 1.6),
//               boxShadow: [
//                 BoxShadow(
//                   color: navy.withOpacity(0.22),
//                   blurRadius: 24,
//                   spreadRadius: 1,
//                   offset: const Offset(0, 10),
//                 ),
//               ],
//             ),
//             child: StreamBuilder<CallState>(
//               stream: call.state.asStream(),
//               builder: (context, snapshot) {
//                 final callState = snapshot.data;
//                 final rawParticipants = callState?.callParticipants ?? [];

//                 final seenIds = <String>{};
//                 final participants = rawParticipants.where((p) {
//                   if (seenIds.contains(p.userId)) return false;
//                   seenIds.add(p.userId);
//                   return true;
//                 }).toList();

//                 final localParticipant = participants.firstWhereOrNull(
//                   (p) => p.userId == teacherId,
//                 );

//                 final bool isMuted = localParticipant != null
//                     ? !localParticipant.isAudioEnabled
//                     : false;

//                 final speakingParticipants = participants
//                     .where((p) => p.isSpeaking)
//                     .toList();

//                 final speaker = speakingParticipants.isNotEmpty
//                     ? speakingParticipants.first
//                     : null;

//                 final speakerName = _speakerName(speaker);
//                 final int studentCount = students?.length ?? 0;

//                 return Column(
//                   mainAxisSize: MainAxisSize.min,
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // Header
//                     Row(
//                       children: [
//                         Container(
//                           width: 30,
//                           height: 30,
//                           decoration: BoxDecoration(
//                             gradient: const LinearGradient(
//                               colors: [navy, blue],
//                               begin: Alignment.topLeft,
//                               end: Alignment.bottomRight,
//                             ),
//                             borderRadius: BorderRadius.circular(9),
//                           ),
//                           child: const Icon(
//                             Icons.graphic_eq_rounded,
//                             color: Colors.white,
//                             size: 17,
//                           ),
//                         ),
//                         const SizedBox(width: 9),
//                         Expanded(
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Row(
//                                 children: [
//                                   Container(
//                                     width: 7,
//                                     height: 7,
//                                     decoration: const BoxDecoration(
//                                       color: Color(0xFF20A879),
//                                       shape: BoxShape.circle,
//                                     ),
//                                   ),
//                                   const SizedBox(width: 5),
//                                   Text(
//                                     "LIVE STUDIO",
//                                     style: GoogleFonts.poppins(
//                                       color: teal,
//                                       fontSize: 10,
//                                       fontWeight: FontWeight.w800,
//                                       letterSpacing: .3,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                               const SizedBox(height: 1),
//                               Text(
//                                 "Live classroom",
//                                 style: GoogleFonts.poppins(
//                                   color: mutedText,
//                                   fontSize: 9,
//                                   fontWeight: FontWeight.w500,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                         InkWell(
//                           borderRadius: BorderRadius.circular(8),
//                           onTap: () {
//                             GlobalAudioOverlayController.removeOverlay();
//                             Get.to(
//                               () => TeacherBroadcastScreen(
//                                 call: call,
//                                 language:
//                                     teacherData['language']?.toString() ??
//                                     "English",
//                                 stage:
//                                     (teacherData['stage'] ??
//                                             teacherData['teacherStage'] ??
//                                             "stage1")
//                                         .toString(),
//                                 section:
//                                     (teacherData['section'] ??
//                                             teacherData['teacherSection'] ??
//                                             "a")
//                                         .toString(),
//                                 enrolledStudents: students ?? [],
//                                 teacherData: teacherData,
//                                 onCallEnded: () {},
//                               ),
//                             );
//                           },
//                           child: const Padding(
//                             padding: EdgeInsets.all(4),
//                             child: Icon(
//                               Icons.open_in_full_rounded,
//                               color: navy,
//                               size: 17,
//                             ),
//                           ),
//                         ),
//                         const SizedBox(width: 2),
//                         InkWell(
//                           borderRadius: BorderRadius.circular(8),
//                           onTap: () async {
//                             await call.leave();
//                             GlobalAudioOverlayController.removeOverlay();
//                           },
//                           child: const Padding(
//                             padding: EdgeInsets.all(4),
//                             child: Icon(
//                               Icons.close_rounded,
//                               color: red,
//                               size: 19,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),

//                     const SizedBox(height: 10),

//                     // Current speaker card.
//                     AnimatedContainer(
//                       duration: const Duration(milliseconds: 220),
//                       width: double.infinity,
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 10,
//                         vertical: 8,
//                       ),
//                       decoration: BoxDecoration(
//                         color: speaker != null
//                             ? const Color(0xFFE9FBFB)
//                             : lightBlue,
//                         borderRadius: BorderRadius.circular(13),
//                         border: Border.all(
//                           color: speaker != null
//                               ? teal.withOpacity(.45)
//                               : const Color(0xFFD5E4ED),
//                         ),
//                       ),
//                       child: Row(
//                         children: [
//                           if (speaker != null) ...[
//                             Container(
//                               width: 34,
//                               height: 34,
//                               decoration: BoxDecoration(
//                                 color: teal,
//                                 shape: BoxShape.circle,
//                                 boxShadow: [
//                                   BoxShadow(
//                                     color: teal.withOpacity(.25),
//                                     blurRadius: 8,
//                                     offset: const Offset(0, 3),
//                                   ),
//                                 ],
//                               ),
//                               alignment: Alignment.center,
//                               child: Text(
//                                 _participantInitial(speakerName),
//                                 style: GoogleFonts.poppins(
//                                   color: Colors.white,
//                                   fontSize: 13,
//                                   fontWeight: FontWeight.w800,
//                                 ),
//                               ),
//                             ),
//                             const SizedBox(width: 9),
//                             Expanded(
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Row(
//                                     children: [
//                                       const Icon(
//                                         Icons.graphic_eq_rounded,
//                                         color: teal,
//                                         size: 14,
//                                       ),
//                                       const SizedBox(width: 4),
//                                       Text(
//                                         "NOW SPEAKING",
//                                         style: GoogleFonts.poppins(
//                                           color: teal,
//                                           fontSize: 8.5,
//                                           fontWeight: FontWeight.w800,
//                                           letterSpacing: .4,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                   const SizedBox(height: 1),
//                                   Text(
//                                     speakerName,
//                                     maxLines: 1,
//                                     overflow: TextOverflow.ellipsis,
//                                     style: GoogleFonts.poppins(
//                                       color: textDark,
//                                       fontSize: 12,
//                                       fontWeight: FontWeight.w800,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                             _SpeakingBars(),
//                           ] else ...[
//                             Container(
//                               width: 34,
//                               height: 34,
//                               decoration: const BoxDecoration(
//                                 color: Color(0xFFDCEAF3),
//                                 shape: BoxShape.circle,
//                               ),
//                               child: const Icon(
//                                 Icons.mic_none_rounded,
//                                 color: blue,
//                                 size: 18,
//                               ),
//                             ),
//                             const SizedBox(width: 9),
//                             Expanded(
//                               child: Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   Text(
//                                     "NO ONE SPEAKING",
//                                     style: GoogleFonts.poppins(
//                                       color: mutedText,
//                                       fontSize: 8.5,
//                                       fontWeight: FontWeight.w800,
//                                       letterSpacing: .35,
//                                     ),
//                                   ),
//                                   const SizedBox(height: 1),
//                                   Text(
//                                     "Waiting for audio…",
//                                     style: GoogleFonts.poppins(
//                                       color: textDark,
//                                       fontSize: 11,
//                                       fontWeight: FontWeight.w600,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ],
//                         ],
//                       ),
//                     ),

//                     const SizedBox(height: 9),

//                     // Bottom controls / participant count.
//                     Row(
//                       children: [
//                         Expanded(
//                           child: Container(
//                             height: 32,
//                             decoration: BoxDecoration(
//                               color: isMuted
//                                   ? const Color(0xFFE8F2F8)
//                                   : const Color(0xFFFFF4D5),
//                               borderRadius: BorderRadius.circular(10),
//                               border: Border.all(
//                                 color: isMuted
//                                     ? const Color(0xFFD5E4ED)
//                                     : yellow.withOpacity(.75),
//                               ),
//                             ),
//                             child: InkWell(
//                               borderRadius: BorderRadius.circular(10),
//                               onTap: () async {
//                                 try {
//                                   await call.setMicrophoneEnabled(
//                                     enabled: isMuted,
//                                   );
//                                 } catch (e) {
//                                   debugPrint("PiP Audio Toggle Error: $e");
//                                 }
//                               },
//                               child: Row(
//                                 mainAxisAlignment: MainAxisAlignment.center,
//                                 children: [
//                                   Icon(
//                                     isMuted
//                                         ? Icons.mic_off_rounded
//                                         : Icons.mic_rounded,
//                                     color: isMuted ? navy : deepNavy,
//                                     size: 15,
//                                   ),
//                                   const SizedBox(width: 6),
//                                   Text(
//                                     isMuted ? "UNMUTE" : "MUTE",
//                                     style: GoogleFonts.poppins(
//                                       color: deepNavy,
//                                       fontSize: 9.5,
//                                       fontWeight: FontWeight.w800,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ),
//                         ),
//                         const SizedBox(width: 7),
//                         Container(
//                           height: 32,
//                           padding: const EdgeInsets.symmetric(horizontal: 9),
//                           decoration: BoxDecoration(
//                             color: lightBlue,
//                             borderRadius: BorderRadius.circular(10),
//                           ),
//                           child: Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               const Icon(
//                                 Icons.people_alt_rounded,
//                                 color: navy,
//                                 size: 14,
//                               ),
//                               const SizedBox(width: 5),
//                               Text(
//                                 "$studentCount",
//                                 style: GoogleFonts.poppins(
//                                   color: textDark,
//                                   fontSize: 10,
//                                   fontWeight: FontWeight.w800,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 );
//               },
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _SpeakingBars extends StatelessWidget {
//   const _SpeakingBars();

//   @override
//   Widget build(BuildContext context) {
//     return SizedBox(
//       width: 25,
//       height: 22,
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//         crossAxisAlignment: CrossAxisAlignment.center,
//         children: [_bar(7), _bar(14), _bar(10), _bar(18), _bar(9)],
//       ),
//     );
//   }

//   Widget _bar(double height) {
//     return Container(
//       width: 3,
//       height: height,
//       decoration: BoxDecoration(
//         color: const Color(0xFF28C2C2),
//         borderRadius: BorderRadius.circular(4),
//       ),
//     );
//   }
// }

// class TeacherAttendanceScreen extends StatefulWidget {
//   final Map<String, dynamic> teacherData;

//   const TeacherAttendanceScreen({super.key, required this.teacherData});

//   @override
//   State<TeacherAttendanceScreen> createState() =>
//       _TeacherAttendanceScreenState();
// }

// class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen> {
//   bool isLoading = true;
//   bool isCheckingIn = false;

//   List<Map<String, dynamic>> attendanceList = [];
//   Map<String, dynamic>? teacherAttendanceRecord;

//   DateTime selectedDate = DateTime.now();

//   // ============================================================
//   // LETSSPEAK BRAND COLORS
//   // ============================================================

//   static const Color navy = Color(0xFF155A88);
//   static const Color deepNavy = Color(0xFF0E466D);
//   static const Color blue = Color(0xFF2C6F9F);
//   static const Color teal = Color(0xFF28C2C2);
//   static const Color yellow = Color(0xFFF7DF55);
//   static const Color periwinkle = Color(0xFF7CA4D8);

//   static const Color background = Color(0xFFE8F2F8);
//   static const Color backgroundDark = Color(0xFFD9EAF3);
//   static const Color card = Colors.white;

//   static const Color green = Color(0xFF20A879);
//   static const Color red = Color(0xFFE45757);
//   static const Color textSecondary = Color(0xFF6B8193);

//   @override
//   void initState() {
//     super.initState();
//     fetchTeacherAndClassroomAttendance();
//   }

//   // ============================================================
//   // BACKEND LOGIC - UNCHANGED
//   // ============================================================

//   Future<void> fetchTeacherAndClassroomAttendance() async {
//     if (!mounted) return;
//     setState(() => isLoading = true);

//     try {
//       final String language =
//           widget.teacherData['language']?.toString() ?? 'English';

//       var rawStage =
//           widget.teacherData['teacherStage'] ??
//           widget.teacherData['stage'] ??
//           widget.teacherData['assignedStage'] ??
//           'stage1';

//       final String stage = rawStage.toString().toLowerCase().replaceAll(
//         RegExp(r'\s+'),
//         '',
//       );

//       var rawSection =
//           widget.teacherData['teacherSection'] ??
//           widget.teacherData['section'] ??
//           widget.teacherData['assignedSection'] ??
//           'A';

//       final String section = rawSection.toString().toUpperCase().trim();
//       final String teacherMode =
//           widget.teacherData['mode']?.toString().toLowerCase() ?? 'online';
//       final String loggedInTeacherId =
//           (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
//               .toString();

//       // 🚀 Strict zero-padding formatting for date matching
//       final String day = selectedDate.day.toString().padLeft(2, '0');
//       final String month = selectedDate.month.toString().padLeft(2, '0');
//       final String year = selectedDate.year.toString();
//       final String dateStr = "$day-$month-$year";

//       final rosterRes = await http.get(
//         Uri.parse(
//           "${ApiEndpoints.baseUrl}/admin/trainer-roster"
//           "?stage=$stage"
//           "&language=$language"
//           "&section=$section"
//           "&mode=$teacherMode"
//           "&date=$dateStr",
//         ),
//       );

//       final attendanceRes = await http.get(
//         Uri.parse("${ApiEndpoints.baseUrl}/admin/attendance?date=$dateStr"),
//       );

//       if (rosterRes.statusCode == 200 && attendanceRes.statusCode == 200) {
//         final decodedRoster = jsonDecode(rosterRes.body);

//         List<dynamic> students = decodedRoster['students'] ?? [];

//         List<dynamic> attendanceRecords = jsonDecode(attendanceRes.body);

//         var myRecord = attendanceRecords.firstWhere(
//           (att) => att['userId']?.toString() == loggedInTeacherId,
//           orElse: () => null,
//         );

//         String? teacherTime;

//         if (myRecord != null &&
//             (myRecord['markedAt'] != null || myRecord['joinTime'] != null)) {
//           try {
//             DateTime dt = DateTime.parse(
//               myRecord['markedAt'] ?? myRecord['joinTime'],
//             );

//             teacherTime = DateFormat('hh:mm a').format(dt);
//           } catch (_) {
//             teacherTime = "Today";
//           }
//         }

//         teacherAttendanceRecord = {
//           "name": "${widget.teacherData['name'] ?? 'Trainer'} (You)",
//           "status": myRecord != null
//               ? (myRecord['status'] ?? "Present")
//               : "Absent",
//           "totalMinutes": myRecord != null
//               ? (myRecord['totalMinutes'] ?? myRecord['totalMinutesSpent'] ?? 0)
//               : 0,
//           "markedAtTime": teacherTime,
//         };

//         List<Map<String, dynamic>> tempList = [];

//         for (var student in students) {
//           String? formattedTime;

//           if (student['markedAt'] != null) {
//             try {
//               DateTime dt = DateTime.parse(student['markedAt']);

//               formattedTime = DateFormat('hh:mm a').format(dt);
//             } catch (_) {
//               formattedTime = "Today";
//             }
//           }

//           tempList.add({
//             "userName": student['name'] ?? "Unknown Student",
//             "status": student['attendanceStatus'] ?? "Absent",
//             "totalMinutes": student['totalMinutesSpent'] ?? 0,
//             "markedAtTime": formattedTime,
//           });
//         }

//         if (mounted) {
//           setState(() {
//             attendanceList = tempList;
//             isLoading = false;
//           });
//         }
//       } else {
//         if (mounted) {
//           setState(() => isLoading = false);
//         }
//       }
//     } catch (e) {
//       debugPrint("Classroom Attendance Fetch Error: $e");

//       if (mounted) {
//         setState(() => isLoading = false);
//       }
//     }
//   }

//   Future<void> _handleTeacherGeoCheckIn() async {
//     setState(() => isCheckingIn = true);

//     try {
//       bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

//       if (!serviceEnabled) {
//         Get.snackbar(
//           "GPS Disabled",
//           "Please turn on location services.",
//           backgroundColor: red,
//           colorText: Colors.white,
//           margin: const EdgeInsets.all(14),
//           borderRadius: 14,
//         );

//         setState(() => isCheckingIn = false);
//         return;
//       }

//       Position position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//       );

//       double distance = Geolocator.distanceBetween(
//         position.latitude,
//         position.longitude,
//         instituteLat,
//         instituteLng,
//       );

//       if (distance > allowedRadius) {
//         Get.snackbar(
//           "Out of Range",
//           "You are ${distance.toInt()}m away from the institute.",
//           backgroundColor: red,
//           colorText: Colors.white,
//           margin: const EdgeInsets.all(14),
//           borderRadius: 14,
//         );

//         setState(() => isCheckingIn = false);
//         return;
//       }

//       final teacherId = widget.teacherData['_id'] ?? widget.teacherData['id'];

//       final res = await http.post(
//         Uri.parse("${ApiEndpoints.baseUrl}/user/mark-attendance"),
//         headers: {"Content-Type": "application/json"},
//         body: jsonEncode({
//           "userId": teacherId,
//           "stage":
//               widget.teacherData['stage'] ??
//               widget.teacherData['teacherStage'] ??
//               "Stage 1",
//           "lat": position.latitude,
//           "lng": position.longitude,
//           "language": widget.teacherData['language'] ?? "English",
//         }),
//       );

//       if (res.statusCode == 200) {
//         Get.snackbar(
//           "Attendance Marked",
//           "Your attendance was marked successfully.",
//           backgroundColor: green,
//           colorText: Colors.white,
//           margin: const EdgeInsets.all(14),
//           borderRadius: 14,
//           icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
//         );

//         fetchTeacherAndClassroomAttendance();
//       } else {
//         final data = jsonDecode(res.body);

//         Get.snackbar(
//           "Check-In Notice",
//           data['message'] ?? "Check-in failed.",
//           backgroundColor: yellow,
//           colorText: deepNavy,
//           margin: const EdgeInsets.all(14),
//           borderRadius: 14,
//         );
//       }
//     } catch (e) {
//       Get.snackbar(
//         "Check-In Error",
//         "Unable to complete GPS check-in.",
//         backgroundColor: red,
//         colorText: Colors.white,
//         margin: const EdgeInsets.all(14),
//         borderRadius: 14,
//       );
//     } finally {
//       if (mounted) {
//         setState(() => isCheckingIn = false);
//       }
//     }
//   }

//   Future<void> _selectDate(BuildContext context) async {
//     final now = DateTime.now();
//     final today = DateTime(now.year, now.month, now.day);

//     final DateTime? picked = await showDatePicker(
//       context: context,
//       initialDate: selectedDate.isAfter(today) ? today : selectedDate,
//       firstDate: DateTime(2024),
//       lastDate: today, // 🚀 Restricts calendar selection so teachers cannot pick future dates past today
//       builder: (context, child) {
//         return Theme(
//           data: Theme.of(context).copyWith(
//             colorScheme: const ColorScheme.light(
//               primary: navy,
//               onPrimary: Colors.white,
//               surface: Colors.white,
//               onSurface: deepNavy,
//             ),
//             dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
//           ),
//           child: child!,
//         );
//       },
//     );

//     if (picked != null && picked != selectedDate) {
//       setState(() => selectedDate = DateTime(picked.year, picked.month, picked.day));
//       fetchTeacherAndClassroomAttendance();
//     }
//   }

//   // ============================================================
//   // UI
//   // ============================================================

//   @override
//   Widget build(BuildContext context) {
//     final String stageName =
//         (widget.teacherData['teacherStage'] ??
//                 widget.teacherData['stage'] ??
//                 'Stage 1')
//             .toString()
//             .toUpperCase();

//     final String section =
//         (widget.teacherData['teacherSection'] ??
//                 widget.teacherData['section'] ??
//                 'A')
//             .toString()
//             .toUpperCase();

//     final String language =
//         widget.teacherData['language']?.toString() ?? 'English';

//     final String teacherMode = (widget.teacherData['mode'] ?? 'online')
//         .toString()
//         .toLowerCase();

//     final String dateLabel = DateFormat('EEE, d MMM yyyy').format(selectedDate);

//     final int totalCount = attendanceList.length;

//     final int presentCount = attendanceList
//         .where((s) => s['status'] == 'Present')
//         .length;

//     final int lateCount = attendanceList
//         .where((s) => s['status'] == 'Late' || s['status'] == 'Partial')
//         .length;

//     final int absentCount = attendanceList
//         .where((s) => s['status'] == 'Absent')
//         .length;

//     String trainerStatus =
//         teacherAttendanceRecord?['status']?.toString() ?? "ABSENT";

//     Color trainerStatusColor = _statusColor(trainerStatus);

//     return Scaffold(
//       backgroundColor: background,

//       appBar: _buildAppBar(context, language, stageName, section),

//       body: SafeArea(
//         child: LayoutBuilder(
//           builder: (context, constraints) {
//             final bool desktop = constraints.maxWidth >= 1000;

//             final bool tablet =
//                 constraints.maxWidth >= 650 && constraints.maxWidth < 1000;

//             final double horizontal = desktop
//                 ? 38
//                 : tablet
//                 ? 26
//                 : 16;

//             return RefreshIndicator(
//               color: teal,
//               backgroundColor: Colors.white,
//               onRefresh: fetchTeacherAndClassroomAttendance,

//               child: CustomScrollView(
//                 physics: const AlwaysScrollableScrollPhysics(
//                   parent: BouncingScrollPhysics(),
//                 ),

//                 slivers: [
//                   SliverPadding(
//                     padding: EdgeInsets.fromLTRB(
//                       horizontal,
//                       18,
//                       horizontal,
//                       30,
//                     ),

//                     sliver: SliverToBoxAdapter(
//                       child: ConstrainedBox(
//                         constraints: const BoxConstraints(maxWidth: 1320),

//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             _buildDateAndActionBar(
//                               context,
//                               dateLabel,
//                               teacherMode,
//                             ),

//                             const SizedBox(height: 16),

//                             if (teacherAttendanceRecord != null)
//                               _buildTrainerStatus(
//                                 trainerStatus,
//                                 trainerStatusColor,
//                                 teacherMode,
//                                 desktop,
//                               ),

//                             const SizedBox(height: 16),

//                             _buildSummary(
//                               totalCount,
//                               presentCount,
//                               lateCount,
//                               absentCount,
//                               desktop,
//                             ),

//                             const SizedBox(height: 22),

//                             Row(
//                               crossAxisAlignment: CrossAxisAlignment.end,
//                               children: [
//                                 Expanded(
//                                   child: Column(
//                                     crossAxisAlignment:
//                                         CrossAxisAlignment.start,
//                                     children: [
//                                       Text(
//                                         'Classroom attendance',
//                                         style: GoogleFonts.poppins(
//                                           color: deepNavy,
//                                           fontSize: desktop ? 20 : 17,
//                                           fontWeight: FontWeight.w700,
//                                         ),
//                                       ),
//                                       const SizedBox(height: 3),
//                                       Text(
//                                         'Track who attended, joined late, or is absent.',
//                                         style: GoogleFonts.poppins(
//                                           color: textSecondary,
//                                           fontSize: 11,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ),

//                                 if (desktop)
//                                   _smallInfoPill('$totalCount students', navy),
//                               ],
//                             ),

//                             const SizedBox(height: 13),

//                             if (isLoading)
//                               _buildLoading()
//                             else if (attendanceList.isEmpty)
//                               _buildEmptyState()
//                             else if (desktop)
//                               _buildDesktopStudents(attendanceList)
//                             else
//                               _buildMobileStudents(attendanceList),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           },
//         ),
//       ),
//     );
//   }

//   PreferredSizeWidget _buildAppBar(
//     BuildContext context,
//     String language,
//     String stage,
//     String section,
//   ) {
//     return AppBar(
//       elevation: 0,
//       scrolledUnderElevation: 0,
//       backgroundColor: navy,
//       foregroundColor: Colors.white,
//       automaticallyImplyLeading: true,

//       toolbarHeight: 68,

//       titleSpacing: 4,

//       title: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             'Classroom Attendance',
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//             style: GoogleFonts.poppins(
//               color: Colors.white,
//               fontSize: 15.5,
//               fontWeight: FontWeight.w700,
//             ),
//           ),
//           const SizedBox(height: 2),
//           Text(
//             '$language • $stage • Section $section',
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//             style: GoogleFonts.poppins(
//               color: Colors.white.withOpacity(.70),
//               fontSize: 10.5,
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//         ],
//       ),

//       actions: [
//         IconButton(
//           tooltip: 'Choose date',
//           onPressed: () => _selectDate(context),
//           icon: const Icon(Icons.calendar_month_rounded, size: 21),
//         ),

//         IconButton(
//           tooltip: 'Refresh',
//           onPressed: fetchTeacherAndClassroomAttendance,
//           icon: const Icon(Icons.refresh_rounded, size: 22),
//         ),

//         const SizedBox(width: 6),
//       ],
//     );
//   }

//   Widget _buildDateAndActionBar(
//     BuildContext context,
//     String dateLabel,
//     String teacherMode,
//   ) {
//     return Container(
//       width: double.infinity,

//       padding: const EdgeInsets.all(16),

//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: navy.withOpacity(.10)),
//         boxShadow: [
//           BoxShadow(
//             color: navy.withOpacity(.06),
//             blurRadius: 18,
//             offset: const Offset(0, 7),
//           ),
//         ],
//       ),

//       child: LayoutBuilder(
//         builder: (context, constraints) {
//           final bool compact = constraints.maxWidth < 500;

//           return compact
//               ? Column(
//                   crossAxisAlignment: CrossAxisAlignment.stretch,
//                   children: [
//                     _dateButton(dateLabel),

//                     if (teacherMode == 'offline') ...[
//                       const SizedBox(height: 10),
//                       _geoButton(),
//                     ],
//                   ],
//                 )
//               : Row(
//                   children: [
//                     Expanded(child: _dateButton(dateLabel)),

//                     if (teacherMode == 'offline') ...[
//                       const SizedBox(width: 12),
//                       _geoButton(),
//                     ],
//                   ],
//                 );
//         },
//       ),
//     );
//   }

//   Widget _dateButton(String dateLabel) {
//     return InkWell(
//       borderRadius: BorderRadius.circular(15),
//       onTap: () => _selectDate(context),

//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

//         decoration: BoxDecoration(
//           color: background,
//           borderRadius: BorderRadius.circular(15),
//           border: Border.all(color: navy.withOpacity(.10)),
//         ),

//         child: Row(
//           children: [
//             Container(
//               width: 38,
//               height: 38,

//               decoration: BoxDecoration(
//                 color: navy.withOpacity(.10),
//                 borderRadius: BorderRadius.circular(11),
//               ),

//               child: const Icon(Icons.event_rounded, color: navy, size: 20),
//             ),

//             const SizedBox(width: 11),

//             Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'SELECTED DATE',
//                   style: GoogleFonts.poppins(
//                     color: textSecondary,
//                     fontSize: 8,
//                     fontWeight: FontWeight.w700,
//                     letterSpacing: .7,
//                   ),
//                 ),
//                 const SizedBox(height: 2),
//                 Text(
//                   dateLabel,
//                   style: GoogleFonts.poppins(
//                     color: deepNavy,
//                     fontSize: 12,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//               ],
//             ),

//             const Spacer(),

//             const Icon(
//               Icons.keyboard_arrow_down_rounded,
//               color: navy,
//               size: 20,
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _geoButton() {
//     return SizedBox(
//       height: 62,

//       child: ElevatedButton.icon(
//         onPressed: isCheckingIn ? null : _handleTeacherGeoCheckIn,

//         icon: isCheckingIn
//             ? const SizedBox(
//                 width: 17,
//                 height: 17,
//                 child: CircularProgressIndicator(
//                   strokeWidth: 2,
//                   color: Colors.white,
//                 ),
//               )
//             : const Icon(Icons.location_on_rounded, size: 18),

//         label: Text(
//           isCheckingIn ? 'Checking location...' : 'Geo Check-In',
//           style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700),
//         ),

//         style: ElevatedButton.styleFrom(
//           backgroundColor: teal,
//           foregroundColor: Colors.white,
//           disabledBackgroundColor: teal.withOpacity(.45),
//           elevation: 0,
//           padding: const EdgeInsets.symmetric(horizontal: 18),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(15),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildTrainerStatus(
//     String status,
//     Color statusColor,
//     String teacherMode,
//     bool desktop,
//   ) {
//     final String? markedTime = teacherAttendanceRecord?['markedAtTime'];

//     final int minutes = teacherAttendanceRecord?['totalMinutes'] ?? 0;

//     String subtitle;

//     if (markedTime != null) {
//       subtitle = 'Started at $markedTime • Active for $minutes mins';
//     } else if (teacherMode == 'online') {
//       subtitle = 'Start the live audio class to record your presence.';
//     } else {
//       subtitle = 'Complete GPS check-in to mark your attendance.';
//     }

//     return Container(
//       width: double.infinity,

//       padding: const EdgeInsets.all(18),

//       decoration: BoxDecoration(
//         gradient: const LinearGradient(
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//           colors: [navy, blue],
//         ),

//         borderRadius: BorderRadius.circular(21),

//         boxShadow: [
//           BoxShadow(
//             color: navy.withOpacity(.16),
//             blurRadius: 22,
//             offset: const Offset(0, 8),
//           ),
//         ],
//       ),

//       child: Row(
//         children: [
//           Container(
//             width: desktop ? 52 : 46,
//             height: desktop ? 52 : 46,

//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(.12),
//               borderRadius: BorderRadius.circular(15),
//               border: Border.all(color: Colors.white.withOpacity(.12)),
//             ),

//             child: Icon(
//               status == 'Present'
//                   ? Icons.check_circle_rounded
//                   : status == 'Absent'
//                   ? Icons.person_off_rounded
//                   : Icons.schedule_rounded,
//               color: statusColor == yellow ? yellow : statusColor,
//               size: 25,
//             ),
//           ),

//           const SizedBox(width: 13),

//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Your Trainer Status',
//                   style: GoogleFonts.poppins(
//                     color: Colors.white,
//                     fontSize: 13.5,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),

//                 const SizedBox(height: 3),

//                 Text(
//                   subtitle,
//                   maxLines: 2,
//                   overflow: TextOverflow.ellipsis,
//                   style: GoogleFonts.poppins(
//                     color: Colors.white.withOpacity(.68),
//                     fontSize: 10.5,
//                     height: 1.35,
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           const SizedBox(width: 10),

//           _statusBadge(status.toUpperCase(), statusColor, darkBackground: true),
//         ],
//       ),
//     );
//   }

//   Widget _buildSummary(
//     int total,
//     int present,
//     int late,
//     int absent,
//     bool desktop,
//   ) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final bool small = constraints.maxWidth < 500;

//         return GridView.count(
//           crossAxisCount: small ? 2 : 4,
//           crossAxisSpacing: 10,
//           mainAxisSpacing: 10,
//           childAspectRatio: small ? 1.85 : 2.35,
//           shrinkWrap: true,
//           physics: const NeverScrollableScrollPhysics(),

//           children: [
//             _summaryCard('Total', total, navy, Icons.groups_rounded),
//             _summaryCard(
//               'Present',
//               present,
//               teal,
//               Icons.check_circle_outline_rounded,
//             ),
//             _summaryCard('Late', late, yellow, Icons.schedule_rounded),
//             _summaryCard('Absent', absent, red, Icons.cancel_outlined),
//           ],
//         );
//       },
//     );
//   }

//   Widget _summaryCard(String label, int value, Color color, IconData icon) {
//     return Container(
//       padding: const EdgeInsets.all(14),

//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(17),
//         border: Border.all(color: color.withOpacity(.18)),
//         boxShadow: [
//           BoxShadow(
//             color: navy.withOpacity(.045),
//             blurRadius: 13,
//             offset: const Offset(0, 5),
//           ),
//         ],
//       ),

//       child: Row(
//         children: [
//           Container(
//             width: 37,
//             height: 37,

//             decoration: BoxDecoration(
//               color: color.withOpacity(.11),
//               borderRadius: BorderRadius.circular(11),
//             ),

//             child: Icon(icon, color: color, size: 19),
//           ),

//           const SizedBox(width: 10),

//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Text(
//                 '$value',
//                 style: GoogleFonts.poppins(
//                   color: deepNavy,
//                   fontSize: 17,
//                   fontWeight: FontWeight.w800,
//                 ),
//               ),
//               Text(
//                 label,
//                 style: GoogleFonts.poppins(
//                   color: textSecondary,
//                   fontSize: 9.5,
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDesktopStudents(List<Map<String, dynamic>> students) {
//     return Container(
//       width: double.infinity,

//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: navy.withOpacity(.10)),
//         boxShadow: [
//           BoxShadow(
//             color: navy.withOpacity(.045),
//             blurRadius: 16,
//             offset: const Offset(0, 6),
//           ),
//         ],
//       ),

//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(20),

//         child: DataTable(
//           headingRowHeight: 52,
//           dataRowMinHeight: 70,
//           dataRowMaxHeight: 78,

//           horizontalMargin: 20,
//           columnSpacing: 35,

//           headingRowColor: const WidgetStatePropertyAll(Color(0xFFF2F7FA)),

//           headingTextStyle: GoogleFonts.poppins(
//             color: textSecondary,
//             fontSize: 9.5,
//             fontWeight: FontWeight.w700,
//             letterSpacing: .5,
//           ),

//           dataTextStyle: GoogleFonts.poppins(color: deepNavy, fontSize: 11),

//           columns: const [
//             DataColumn(label: Text('STUDENT')),
//             DataColumn(label: Text('STATUS')),
//             DataColumn(label: Text('TIME')),
//             DataColumn(label: Text('ACTIVE')),
//           ],

//           rows: students.map((student) {
//             final String name =
//                 student['userName']?.toString().trim().isNotEmpty == true
//                 ? student['userName'].toString()
//                 : 'Unknown Student';

//             final String status = student['status']?.toString() ?? 'Absent';

//             final String? time = student['markedAtTime']?.toString();

//             final int mins = _toInt(student['totalMinutes']);

//             final Color color = _statusColor(status);

//             return DataRow(
//               cells: [
//                 DataCell(
//                   Row(
//                     children: [
//                       _studentAvatar(name, color),
//                       const SizedBox(width: 11),
//                       SizedBox(
//                         width: 210,
//                         child: Text(
//                           name,
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                           style: GoogleFonts.poppins(
//                             color: deepNavy,
//                             fontSize: 11.5,
//                             fontWeight: FontWeight.w700,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),

//                 DataCell(_statusBadge(status.toUpperCase(), color)),

//                 DataCell(
//                   Text(
//                     time ?? 'Not joined',
//                     style: GoogleFonts.poppins(
//                       color: textSecondary,
//                       fontSize: 10.5,
//                     ),
//                   ),
//                 ),

//                 DataCell(
//                   Text(
//                     '$mins mins',
//                     style: GoogleFonts.poppins(
//                       color: deepNavy,
//                       fontSize: 10.5,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                 ),
//               ],
//             );
//           }).toList(),
//         ),
//       ),
//     );
//   }

//   Widget _buildMobileStudents(List<Map<String, dynamic>> students) {
//     return Column(
//       children: students.map((student) {
//         final String name =
//             student['userName']?.toString().trim().isNotEmpty == true
//             ? student['userName'].toString()
//             : 'Unknown Student';

//         final String status = student['status']?.toString() ?? 'Absent';

//         final String? time = student['markedAtTime']?.toString();

//         final int mins = _toInt(student['totalMinutes']);

//         final Color color = _statusColor(status);

//         return Container(
//           width: double.infinity,

//           margin: const EdgeInsets.only(bottom: 11),

//           padding: const EdgeInsets.all(15),

//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(18),
//             border: Border.all(color: color.withOpacity(.18)),
//             boxShadow: [
//               BoxShadow(
//                 color: navy.withOpacity(.045),
//                 blurRadius: 12,
//                 offset: const Offset(0, 5),
//               ),
//             ],
//           ),

//           child: Row(
//             children: [
//               _studentAvatar(name, color, radius: 22),

//               const SizedBox(width: 12),

//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       name,
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: GoogleFonts.poppins(
//                         color: deepNavy,
//                         fontSize: 12.5,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),

//                     const SizedBox(height: 4),

//                     Row(
//                       children: [
//                         Icon(
//                           time != null
//                               ? Icons.login_rounded
//                               : Icons.schedule_rounded,
//                           color: textSecondary,
//                           size: 12,
//                         ),
//                         const SizedBox(width: 4),
//                         Expanded(
//                           child: Text(
//                             time != null
//                                 ? 'Joined $time • $mins mins'
//                                 : 'Not joined class yet',
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                             style: GoogleFonts.poppins(
//                               color: textSecondary,
//                               fontSize: 9.5,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),

//               const SizedBox(width: 8),

//               _statusBadge(status.toUpperCase(), color),
//             ],
//           ),
//         );
//       }).toList(),
//     );
//   }

//   Widget _studentAvatar(String name, Color color, {double radius = 19}) {
//     final String initial = name.trim().isNotEmpty
//         ? name.trim()[0].toUpperCase()
//         : 'S';

//     return CircleAvatar(
//       radius: radius,

//       backgroundColor: color.withOpacity(.12),

//       child: Text(
//         initial,

//         style: GoogleFonts.poppins(
//           color: color,
//           fontSize: radius * .62,
//           fontWeight: FontWeight.w800,
//         ),
//       ),
//     );
//   }

//   Widget _statusBadge(
//     String label,
//     Color color, {
//     bool darkBackground = false,
//   }) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),

//       decoration: BoxDecoration(
//         color: darkBackground ? color.withOpacity(.18) : color.withOpacity(.10),
//         borderRadius: BorderRadius.circular(9),
//         border: Border.all(
//           color: darkBackground
//               ? color.withOpacity(.45)
//               : color.withOpacity(.18),
//         ),
//       ),

//       child: Text(
//         label,
//         style: GoogleFonts.poppins(
//           color: darkBackground ? Colors.white : color,
//           fontSize: 8.5,
//           fontWeight: FontWeight.w800,
//           letterSpacing: .2,
//         ),
//       ),
//     );
//   }

//   Widget _smallInfoPill(String text, Color color) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),

//       decoration: BoxDecoration(
//         color: color.withOpacity(.08),
//         borderRadius: BorderRadius.circular(10),
//       ),

//       child: Text(
//         text,
//         style: GoogleFonts.poppins(
//           color: color,
//           fontSize: 9.5,
//           fontWeight: FontWeight.w700,
//         ),
//       ),
//     );
//   }

//   Widget _buildLoading() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(45),

//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//       ),

//       child: const Center(
//         child: CircularProgressIndicator(color: teal, strokeWidth: 2.5),
//       ),
//     );
//   }

//   Widget _buildEmptyState() {
//     return Container(
//       width: double.infinity,

//       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 55),

//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: navy.withOpacity(.08)),
//       ),

//       child: Column(
//         children: [
//           Container(
//             width: 70,
//             height: 70,

//             decoration: BoxDecoration(
//               color: teal.withOpacity(.10),
//               shape: BoxShape.circle,
//             ),

//             child: const Icon(Icons.groups_outlined, color: teal, size: 32),
//           ),

//           const SizedBox(height: 15),

//           Text(
//             'No students enrolled',
//             style: GoogleFonts.poppins(
//               color: deepNavy,
//               fontSize: 15,
//               fontWeight: FontWeight.w700,
//             ),
//           ),

//           const SizedBox(height: 5),

//           Text(
//             'There are no students assigned to this classroom for the selected date.',
//             textAlign: TextAlign.center,
//             style: GoogleFonts.poppins(
//               color: textSecondary,
//               fontSize: 10.5,
//               height: 1.5,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Color _statusColor(String status) {
//     switch (status.toLowerCase()) {
//       case 'present':
//         return teal;
//       case 'late':
//       case 'partial':
//         return yellow;
//       case 'absent':
//       default:
//         return red;
//     }
//   }

//   int _toInt(dynamic value) {
//     if (value is int) return value;
//     return int.tryParse(value?.toString() ?? '0') ?? 0;
//   }
// }

// class TeacherPortalScreen extends StatefulWidget {
//   final Map<String, dynamic> teacherData;

//   const TeacherPortalScreen({super.key, required this.teacherData});

//   @override
//   State<TeacherPortalScreen> createState() => _TeacherPortalScreenState();
// }

// class _TeacherPortalScreenState extends State<TeacherPortalScreen> {
//   List<dynamic> allAssignedStudents = [];
//   String activeFilter = "all";
//   bool isStartingBroadcast = false;
//   IO.Socket? _ioSocket;

//   static const Color backgroundColor = Color(0xffE8F2F8);
//   static const Color cardColor = Color(0xffFFFFFF);
//   static const Color surfaceColor = Color(0xffF5F9FC);
//   static const Color brandNavy = Color(0xff155A88);
//   static const Color brandBlue = Color(0xff2C6F9F);
//   static const Color accentBlue = Color(0xff7CA4D8);
//   static const Color accentGreen = Color(0xff28C2C2);
//   static const Color goldenYellow = Color(0xffF7DF55);
//   static const Color accentRed = Color(0xffE85D5D);
//   static const Color textPrimary = Color(0xff16324A);
//   static const Color textSecondary = Color(0xff667F95);

//   @override
//   void initState() {
//     super.initState();
//     fetchAssignedStudentsSilent();
//     _initSocket();
//   }

//   @override
//   void dispose() {
//     _ioSocket?.dispose();
//     super.dispose();
//   }

//   void _initSocket() {
//     try {
//       _ioSocket = IO.io(ApiEndpoints.baseUrl, <String, dynamic>{
//         'transports': ['websocket'],
//         'autoConnect': true,
//       });

//       _ioSocket?.onConnect((_) {
//         debugPrint("Socket connected for automatic updates");
//       });

//       _ioSocket?.on('student_update', (_) {
//         fetchAssignedStudentsSilent();
//       });
//       _ioSocket?.on('attendance_update', (_) {
//         fetchAssignedStudentsSilent();
//       });
//     } catch (e) {
//       debugPrint("Socket error: $e");
//     }
//   }

//   Future<void> fetchAssignedStudentsSilent() async {
//     try {
//       final String language =
//           widget.teacherData['language']?.toString() ?? 'English';

//       var rawStage =
//           widget.teacherData['teacherStage'] ??
//           widget.teacherData['stage'] ??
//           widget.teacherData['assignedStage'] ??
//           'stage1';
//       final String stage = rawStage.toString().toLowerCase().replaceAll(
//         RegExp(r'\s+'),
//         '',
//       );

//       var rawSection =
//           widget.teacherData['teacherSection'] ??
//           widget.teacherData['section'] ??
//           widget.teacherData['assignedSection'] ??
//           'A';
//       final String section = rawSection.toString().toUpperCase().trim();

//       final String teacherMode =
//           widget.teacherData['mode']?.toString().toLowerCase() ?? 'online';

//       final response = await http.get(
//         Uri.parse(
//           "${ApiEndpoints.baseUrl}/admin/trainer-roster?stage=$stage&language=$language&section=$section&mode=$teacherMode",
//         ),
//       );

//       if (response.statusCode == 200) {
//         final data = jsonDecode(response.body);
//         final List students = data['students'] ?? [];

//         if (mounted) {
//           setState(() {
//             allAssignedStudents = students.where((s) {
//               final role = (s['role'] ?? 'student').toString().toLowerCase();
//               return role == 'student';
//             }).toList();
//           });
//         }
//       }
//     } catch (e) {
//       debugPrint("Fetch Error: $e");
//     }
//   }

//   Future<void> _handleOfflineGeoCheckIn() async {
//     try {
//       bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (!serviceEnabled) {
//         Get.snackbar(
//           "GPS Disabled",
//           "Please enable location services.",
//           backgroundColor: accentRed,
//           colorText: Colors.white,
//         );
//         return;
//       }

//       LocationPermission permission = await Geolocator.checkPermission();
//       if (permission == LocationPermission.denied) {
//         permission = await Geolocator.requestPermission();
//         if (permission == LocationPermission.denied) {
//           Get.snackbar(
//             "Permission Denied",
//             "Location required for check-in.",
//             backgroundColor: accentRed,
//             colorText: Colors.white,
//           );
//           return;
//         }
//       }

//       Position position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//       );
//       double distance = Geolocator.distanceBetween(
//         position.latitude,
//         position.longitude,
//         instituteLat,
//         instituteLng,
//       );

//       if (distance > allowedRadius) {
//         Get.snackbar(
//           "Out of Range",
//           "You are ${distance.toInt()}m away from institute.",
//           backgroundColor: accentRed,
//           colorText: Colors.white,
//         );
//         return;
//       }

//       final teacherId =
//           (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
//               .toString();
//       final res = await http.post(
//         Uri.parse("${ApiEndpoints.baseUrl}/user/mark-attendance"),
//         headers: {"Content-Type": "application/json"},
//         body: jsonEncode({
//           "userId": teacherId,
//           "stage":
//               widget.teacherData['stage'] ??
//               widget.teacherData['teacherStage'] ??
//               "Stage 1",
//           "lat": position.latitude,
//           "lng": position.longitude,
//           "language": widget.teacherData['language']?.toString() ?? "English",
//         }),
//       );

//       if (res.statusCode == 200) {
//         Get.snackbar(
//           "Success",
//           "Attendance Marked Successfully!",
//           backgroundColor: accentGreen,
//           colorText: Colors.white,
//         );
//         fetchAssignedStudentsSilent();
//       } else {
//         final data = jsonDecode(res.body);
//         Get.snackbar(
//           "Notice",
//           data['message']?.toString() ?? "Check-in failed.",
//           backgroundColor: goldenYellow,
//           colorText: Colors.black,
//         );
//       }
//     } catch (e) {
//       Get.snackbar(
//         "Error",
//         "Check-in error: $e",
//         backgroundColor: accentRed,
//         colorText: Colors.white,
//       );
//     }
//   }

//   Future<void> _startTeacherAudioBroadcast() async {
//     setState(() => isStartingBroadcast = true);
//     final String language =
//         widget.teacherData['language']?.toString() ?? "English";
//     final String stage =
//         (widget.teacherData['stage'] ??
//                 widget.teacherData['teacherStage'] ??
//                 "stage1")
//             .toString()
//             .toLowerCase();
//     final String section =
//         (widget.teacherData['section'] ??
//                 widget.teacherData['teacherSection'] ??
//                 'A')
//             .toString()
//             .toLowerCase();
//     final String teacherId =
//         (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
//             .toString();
//     final String teacherName =
//         widget.teacherData['name']?.toString() ?? 'Teacher';

//     try {
//       await http.post(
//         Uri.parse("${ApiEndpoints.baseUrl}/user/join-online-class"),
//         headers: {"Content-Type": "application/json"},
//         body: jsonEncode({
//           "userId": teacherId,
//           "language": language,
//           "stage": stage,
//         }),
//       );

//       final tokenRes = await http.post(
//         Uri.parse("${ApiEndpoints.baseUrl}/stream/token"),
//         headers: {"Content-Type": "application/json"},
//         body: jsonEncode({
//           "userId": teacherId,
//           "name": teacherName,
//           "role": "admin",
//         }),
//       );

//       if (tokenRes.statusCode != 200)
//         throw Exception("Failed to authorize stream");
//       final tokenData = jsonDecode(tokenRes.body);
//       final token = tokenData['token']?.toString() ?? '';

//       await StreamVideo.reset(disconnect: true);
//       final client = StreamVideo(
//         'urzyyp7kctqv',
//         user: User.regular(userId: teacherId, name: teacherName),
//         userToken: token,
//       );

//       final callId = language.toLowerCase() == "english"
//           ? "${language.toLowerCase()}_${stage}_sec${section}_class"
//           : "${language.toLowerCase()}_${stage}_class";

//       final call = client.makeCall(
//         callType: StreamCallType.defaultType(),
//         id: callId,
//       );
//       await call.getOrCreate();
//       await call.join();

//       try {
//         await call.setMicrophoneEnabled(enabled: true);
//       } catch (micErr) {
//         debugPrint("Mic Error: $micErr");
//       }

//       await http.post(
//         Uri.parse(ApiEndpoints.updateLiveLink),
//         headers: {"Content-Type": "application/json"},
//         body: jsonEncode({
//           "language": language,
//           "stage": stage,
//           "section": section,
//           "type": "class",
//           "link": "stream_active_$callId",
//         }),
//       );

//       GlobalAudioOverlayController.removeOverlay();

//       Get.to(
//         () => TeacherBroadcastScreen(
//           call: call,
//           language: language,
//           stage: stage,
//           section: section,
//           enrolledStudents: allAssignedStudents,
//           teacherData: widget.teacherData,
//           onCallEnded: () => setState(() {}),
//         ),
//       );
//     } catch (e) {
//       Get.snackbar(
//         "Broadcast Error",
//         "Could not start broadcast: $e",
//         backgroundColor: accentRed,
//         colorText: Colors.white,
//       );
//     } finally {
//       if (mounted) setState(() => isStartingBroadcast = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final String stageName =
//         (widget.teacherData['teacherStage'] ??
//                 widget.teacherData['stage'] ??
//                 'Stage 1')
//             .toString();
//     final String section =
//         (widget.teacherData['teacherSection'] ??
//                 widget.teacherData['section'] ??
//                 'A')
//             .toString();
//     final String mode = (widget.teacherData['mode'] ?? 'online').toString();
//     final String language =
//         widget.teacherData['language']?.toString() ?? 'English';
//     final bool isOnline = mode.toLowerCase() == 'online';
//     final bool hasSection = isOnline && language.toLowerCase() == 'english';

//     final int totalCount = allAssignedStudents.length;
//     final int paidCount = allAssignedStudents
//         .where(
//           (s) =>
//               (s['feeStatus'] ?? 'unpaid').toString().toLowerCase() == 'paid',
//         )
//         .length;
//     final int unpaidCount = totalCount - paidCount;
//     final int presentCount = allAssignedStudents
//         .where(
//           (s) =>
//               (s['attendanceStatus'] ?? 'Absent').toString().toLowerCase() ==
//               'present',
//         )
//         .length;
//     final int absentCount = totalCount - presentCount;

//     List<dynamic> filteredStudents = List<dynamic>.from(allAssignedStudents);
//     if (activeFilter == 'paid') {
//       filteredStudents = filteredStudents
//           .where(
//             (s) =>
//                 (s['feeStatus'] ?? 'unpaid').toString().toLowerCase() == 'paid',
//           )
//           .toList();
//     } else if (activeFilter == 'unpaid') {
//       filteredStudents = filteredStudents
//           .where(
//             (s) =>
//                 (s['feeStatus'] ?? 'unpaid').toString().toLowerCase() != 'paid',
//           )
//           .toList();
//     } else if (activeFilter == 'present') {
//       filteredStudents = filteredStudents
//           .where(
//             (s) =>
//                 (s['attendanceStatus'] ?? 'Absent').toString().toLowerCase() ==
//                 'present',
//           )
//           .toList();
//     } else if (activeFilter == 'absent') {
//       filteredStudents = filteredStudents
//           .where(
//             (s) =>
//                 (s['attendanceStatus'] ?? 'Absent').toString().toLowerCase() ==
//                 'absent',
//           )
//           .toList();
//     }

//     return Scaffold(
//       backgroundColor: backgroundColor,
//       appBar: _buildPortalAppBar(
//         stageName,
//         section,
//         language,
//         mode,
//         hasSection,
//       ),
//       body: SafeArea(
//         child: LayoutBuilder(
//           builder: (context, constraints) {
//             final bool isDesktop = constraints.maxWidth >= 1000;
//             final double horizontalPadding = constraints.maxWidth >= 1300
//                 ? 32
//                 : constraints.maxWidth >= 700
//                 ? 24
//                 : 16;

//             return SingleChildScrollView(
//               padding: EdgeInsets.fromLTRB(
//                 horizontalPadding,
//                 20,
//                 horizontalPadding,
//                 32,
//               ),
//               child: Center(
//                 child: ConstrainedBox(
//                   constraints: const BoxConstraints(maxWidth: 1320),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       _buildWelcomeHeader(
//                         stageName,
//                         section,
//                         language,
//                         mode,
//                         hasSection,
//                       ),
//                       const SizedBox(height: 20),
//                       if (isDesktop)
//                         Row(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Expanded(
//                               flex: 6,
//                               child: _buildLiveClassCard(isOnline),
//                             ),
//                             const SizedBox(width: 18),
//                             Expanded(
//                               flex: 4,
//                               child: _buildOverviewCard(
//                                 totalCount,
//                                 presentCount,
//                                 absentCount,
//                                 paidCount,
//                                 unpaidCount,
//                               ),
//                             ),
//                           ],
//                         )
//                       else ...[
//                         _buildLiveClassCard(isOnline),
//                         const SizedBox(height: 16),
//                         _buildOverviewCard(
//                           totalCount,
//                           presentCount,
//                           absentCount,
//                           paidCount,
//                           unpaidCount,
//                         ),
//                       ],
//                       const SizedBox(height: 22),
//                       _buildRosterHeader(filteredStudents.length),
//                       const SizedBox(height: 12),
//                       _buildFilterBar(
//                         totalCount,
//                         paidCount,
//                         unpaidCount,
//                         presentCount,
//                         absentCount,
//                       ),
//                       const SizedBox(height: 16),
//                       if (filteredStudents.isEmpty)
//                         _buildEmptyRoster()
//                       else if (isDesktop)
//                         _buildDesktopRoster(filteredStudents)
//                       else
//                         _buildMobileRoster(filteredStudents),
//                     ],
//                   ),
//                 ),
//               ),
//             );
//           },
//         ),
//       ),
//     );
//   }

//   PreferredSizeWidget _buildPortalAppBar(
//     String stageName,
//     String section,
//     String language,
//     String mode,
//     bool hasSection,
//   ) {
//     return AppBar(
//       elevation: 0,
//       backgroundColor: const Color(0xffF4F8FB),
//       surfaceTintColor: const Color(0xffF4F8FB),
//       titleSpacing: 16,
//       title: Row(
//         children: [
//           Container(
//             width: 42,
//             height: 42,
//             decoration: BoxDecoration(
//               gradient: LinearGradient(colors: [brandNavy, accentBlue]),
//               borderRadius: BorderRadius.circular(13),
//             ),
//             child: const Icon(
//               Icons.school_rounded,
//               color: Colors.white,
//               size: 22,
//             ),
//           ),
//           const SizedBox(width: 12),
//           Flexible(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text(
//                   'Teacher Classroom',
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: GoogleFonts.poppins(
//                     color: brandNavy,
//                     fontSize: 15,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//                 Text(
//                   '$language • $stageName • ${hasSection ? 'Section $section' : mode}',
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: GoogleFonts.poppins(
//                     color: const Color(0xff71859A),
//                     fontSize: 11,
//                     fontWeight: FontWeight.w500,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//       actions: [
//         IconButton(
//           tooltip: 'Refresh students',
//           onPressed: fetchAssignedStudentsSilent,
//           icon: const Icon(Icons.refresh_rounded),
//           color: const Color(0xff294A67),
//         ),
//         const SizedBox(width: 2),
//         IconButton(
//           tooltip: 'Logout',
//           onPressed: () => Get.offAll(() => const TeacherLoginScreen()),
//           icon: const Icon(Icons.logout_rounded),
//           color: const Color(0xffC94B4B),
//         ),
//         const SizedBox(width: 8),
//       ],
//     );
//   }

//   Widget _buildWelcomeHeader(
//     String stageName,
//     String section,
//     String language,
//     String mode,
//     bool hasSection,
//   ) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(22),
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//           colors: const [Color(0xFF155A8A), Color(0xFF2C6F9F)],
//         ),
//         borderRadius: BorderRadius.circular(24),
//         boxShadow: [
//           BoxShadow(
//             color: const Color(0x33155A8A),
//             blurRadius: 24,
//             offset: const Offset(0, 10),
//           ),
//         ],
//       ),
//       child: LayoutBuilder(
//         builder: (context, constraints) {
//           final bool compact = constraints.maxWidth < 560;
//           final info = Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const Icon(Icons.class_rounded, color: Colors.white70, size: 18),
//               const SizedBox(width: 7),
//               Flexible(
//                 child: Text(
//                   '$stageName${hasSection ? ' • Section $section' : ''}',
//                   overflow: TextOverflow.ellipsis,
//                   style: GoogleFonts.poppins(
//                     color: Colors.white,
//                     fontSize: 13,
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//               ),
//             ],
//           );

//           return compact
//               ? Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     _welcomeText(language),
//                     const SizedBox(height: 16),
//                     info,
//                   ],
//                 )
//               : Row(
//                   children: [
//                     Expanded(child: _welcomeText(language)),
//                     const SizedBox(width: 20),
//                     info,
//                   ],
//                 );
//         },
//       ),
//     );
//   }

//   Widget _welcomeText(String language) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           'Welcome back 👋',
//           style: GoogleFonts.poppins(
//             color: Colors.white70,
//             fontSize: 12,
//             fontWeight: FontWeight.w500,
//           ),
//         ),
//         const SizedBox(height: 3),
//         Text(
//           'Manage your classroom with ease',
//           style: GoogleFonts.poppins(
//             color: Colors.white,
//             fontSize: 22,
//             fontWeight: FontWeight.w700,
//             height: 1.15,
//           ),
//         ),
//         const SizedBox(height: 5),
//         Text(
//           '$language classroom • Keep attendance, payments and students organized.',
//           maxLines: 2,
//           overflow: TextOverflow.ellipsis,
//           style: GoogleFonts.poppins(
//             color: Colors.white.withOpacity(.78),
//             fontSize: 11.5,
//             height: 1.4,
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildLiveClassCard(bool isOnline) {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: const Color(0xffD4E2EC)),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(.035),
//             blurRadius: 18,
//             offset: const Offset(0, 6),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Container(
//                 width: 44,
//                 height: 44,
//                 decoration: BoxDecoration(
//                   color: isOnline
//                       ? accentGreen.withOpacity(.10)
//                       : accentBlue.withOpacity(.14),
//                   borderRadius: BorderRadius.circular(13),
//                 ),
//                 child: Icon(
//                   isOnline
//                       ? Icons.graphic_eq_rounded
//                       : Icons.location_on_rounded,
//                   color: isOnline ? accentGreen : brandNavy,
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       isOnline ? 'Live Classroom' : 'Institute Attendance',
//                       style: GoogleFonts.poppins(
//                         color: brandNavy,
//                         fontSize: 15,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                     const SizedBox(height: 2),
//                     Text(
//                       isOnline
//                           ? 'Start or return to your live audio class.'
//                           : 'Verify your location and mark institute attendance.',
//                       style: GoogleFonts.poppins(
//                         color: const Color(0xff71859A),
//                         fontSize: 11.5,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               _statusPill(
//                 isOnline ? 'ONLINE MODE' : 'OFFLINE MODE',
//                 isOnline ? accentGreen : brandNavy,
//               ),
//             ],
//           ),
//           const SizedBox(height: 20),
//           Builder(
//             builder: (context) {
//               final bool isLiveActive =
//                   GlobalAudioOverlayController.currentCall != null;
//               final activeCall = GlobalAudioOverlayController.currentCall;

//               return SizedBox(
//                 width: double.infinity,
//                 height: 50,
//                 child: isOnline
//                     ? ElevatedButton.icon(
//                         onPressed: isStartingBroadcast
//                             ? null
//                             : () {
//                                 if (isLiveActive && activeCall != null) {
//                                   GlobalAudioOverlayController.removeOverlay();
//                                   Get.to(
//                                     () => TeacherBroadcastScreen(
//                                       call: activeCall,
//                                       language:
//                                           widget.teacherData['language']
//                                               ?.toString() ??
//                                           'English',
//                                       stage:
//                                           (widget.teacherData['teacherStage'] ??
//                                                   widget.teacherData['stage'] ??
//                                                   'stage1')
//                                               .toString(),
//                                       section:
//                                           (widget.teacherData['teacherSection'] ??
//                                                   widget
//                                                       .teacherData['section'] ??
//                                                   'a')
//                                               .toString(),
//                                       enrolledStudents: allAssignedStudents,
//                                       teacherData: widget.teacherData,
//                                       onCallEnded: () => setState(() {}),
//                                     ),
//                                   );
//                                 } else {
//                                   _startTeacherAudioBroadcast();
//                                 }
//                               },
//                         icon: isStartingBroadcast
//                             ? const SizedBox(
//                                 width: 19,
//                                 height: 19,
//                                 child: CircularProgressIndicator(
//                                   strokeWidth: 2,
//                                   color: Colors.white,
//                                 ),
//                               )
//                             : Icon(
//                                 isLiveActive
//                                     ? Icons.open_in_new_rounded
//                                     : Icons.mic_rounded,
//                                 size: 20,
//                               ),
//                         label: Text(
//                           isStartingBroadcast
//                               ? 'Starting live classroom...'
//                               : isLiveActive
//                               ? 'Return to live classroom'
//                               : 'Start live audio class',
//                           style: GoogleFonts.poppins(
//                             fontWeight: FontWeight.w700,
//                             fontSize: 13,
//                           ),
//                         ),
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: isLiveActive
//                               ? brandNavy
//                               : accentGreen,
//                           foregroundColor: Colors.white,
//                           disabledBackgroundColor: accentGreen.withOpacity(.55),
//                           elevation: 0,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(13),
//                           ),
//                         ),
//                       )
//                     : ElevatedButton.icon(
//                         onPressed: _handleOfflineGeoCheckIn,
//                         icon: const Icon(Icons.my_location_rounded, size: 20),
//                         label: Text(
//                           'Mark institute attendance',
//                           style: GoogleFonts.poppins(
//                             fontWeight: FontWeight.w700,
//                             fontSize: 13,
//                           ),
//                         ),
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: accentGreen,
//                           foregroundColor: Colors.white,
//                           elevation: 0,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(13),
//                           ),
//                         ),
//                       ),
//               );
//             },
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildOverviewCard(
//     int total,
//     int present,
//     int absent,
//     int paid,
//     int unpaid,
//   ) {
//     final double attendance = total == 0 ? 0 : (present / total) * 100;
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: const Color(0xffD4E2EC)),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(.035),
//             blurRadius: 18,
//             offset: const Offset(0, 6),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Text(
//                 'Class overview',
//                 style: GoogleFonts.poppins(
//                   color: brandNavy,
//                   fontSize: 15,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),
//               const Spacer(),
//               Text(
//                 '${attendance.toStringAsFixed(0)}% present',
//                 style: GoogleFonts.poppins(
//                   color: accentGreen,
//                   fontSize: 11,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           _overviewProgress('Attendance', present, total, brandNavy),
//           const SizedBox(height: 13),
//           _overviewProgress('Payments', paid, total, accentGreen),
//           const SizedBox(height: 16),
//           Row(
//             children: [
//               Expanded(
//                 child: _miniOverview('Present', '$present', accentGreen),
//               ),
//               const SizedBox(width: 8),
//               Expanded(child: _miniOverview('Absent', '$absent', accentRed)),
//               const SizedBox(width: 8),
//               Expanded(child: _miniOverview('Unpaid', '$unpaid', goldenYellow)),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _overviewProgress(String title, int value, int total, Color color) {
//     final double progress = total == 0 ? 0 : (value / total).clamp(0.0, 1.0);
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           children: [
//             Text(
//               title,
//               style: GoogleFonts.poppins(
//                 color: const Color(0xff4F6680),
//                 fontSize: 11,
//                 fontWeight: FontWeight.w600,
//               ),
//             ),
//             const Spacer(),
//             Text(
//               '$value / $total',
//               style: GoogleFonts.poppins(
//                 color: const Color(0xff294A67),
//                 fontSize: 10.5,
//                 fontWeight: FontWeight.w600,
//               ),
//             ),
//           ],
//         ),
//         const SizedBox(height: 7),
//         ClipRRect(
//           borderRadius: BorderRadius.circular(20),
//           child: LinearProgressIndicator(
//             minHeight: 7,
//             value: progress,
//             backgroundColor: const Color(0xffE7EEF5),
//             valueColor: AlwaysStoppedAnimation<Color>(color),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _miniOverview(String label, String value, Color color) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
//       decoration: BoxDecoration(
//         color: color.withOpacity(.07),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Column(
//         children: [
//           Text(
//             value,
//             style: GoogleFonts.poppins(
//               color: color,
//               fontSize: 15,
//               fontWeight: FontWeight.w700,
//             ),
//           ),
//           const SizedBox(height: 1),
//           Text(
//             label,
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//             style: GoogleFonts.poppins(
//               color: const Color(0xff71859A),
//               fontSize: 9.5,
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildRosterHeader(int count) {
//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.end,
//       children: [
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Student roster',
//                 style: GoogleFonts.poppins(
//                   color: brandNavy,
//                   fontSize: 18,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),
//               const SizedBox(height: 2),
//               Text(
//                 'View attendance and payment status at a glance.',
//                 style: GoogleFonts.poppins(
//                   color: const Color(0xff71859A),
//                   fontSize: 11.5,
//                 ),
//               ),
//             ],
//           ),
//         ),
//         Container(
//           padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
//           decoration: BoxDecoration(
//             color: const Color(0xffEEF4F8),
//             borderRadius: BorderRadius.circular(10),
//           ),
//           child: Text(
//             '$count ${count == 1 ? 'student' : 'students'}',
//             style: GoogleFonts.poppins(
//               color: const Color(0xff4F6680),
//               fontSize: 10.5,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildFilterBar(
//     int total,
//     int paid,
//     int unpaid,
//     int present,
//     int absent,
//   ) {
//     final filters = [
//       ('all', 'All', total, brandNavy),
//       ('present', 'Present', present, accentGreen),
//       ('absent', 'Absent', absent, accentRed),
//       ('paid', 'Paid', paid, accentBlue),
//       ('unpaid', 'Unpaid', unpaid, const Color(0xffD5A800)),
//     ];

//     return SizedBox(
//       height: 44,
//       child: ListView.separated(
//         scrollDirection: Axis.horizontal,
//         itemCount: filters.length,
//         separatorBuilder: (_, __) => const SizedBox(width: 8),
//         itemBuilder: (context, index) {
//           final item = filters[index];
//           final String key = item.$1;
//           final String label = item.$2;
//           final int count = item.$3;
//           final Color color = item.$4;
//           final bool selected = activeFilter == key;

//           return InkWell(
//             borderRadius: BorderRadius.circular(12),
//             onTap: () => setState(() => activeFilter = key),
//             child: AnimatedContainer(
//               duration: const Duration(milliseconds: 180),
//               padding: const EdgeInsets.symmetric(horizontal: 13),
//               decoration: BoxDecoration(
//                 color: selected ? color : Colors.white,
//                 borderRadius: BorderRadius.circular(12),
//                 border: Border.all(
//                   color: selected ? color : const Color(0xffDCE7F0),
//                 ),
//               ),
//               child: Row(
//                 children: [
//                   Text(
//                     label,
//                     style: GoogleFonts.poppins(
//                       color: selected ? Colors.white : const Color(0xff4F6680),
//                       fontSize: 11,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                   const SizedBox(width: 7),
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 6,
//                       vertical: 2,
//                     ),
//                     decoration: BoxDecoration(
//                       color: selected
//                           ? Colors.white.withOpacity(.18)
//                           : color.withOpacity(.09),
//                       borderRadius: BorderRadius.circular(7),
//                     ),
//                     child: Text(
//                       '$count',
//                       style: GoogleFonts.poppins(
//                         color: selected ? Colors.white : color,
//                         fontSize: 9.5,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildDesktopRoster(List<dynamic> students) {
//     return Container(
//       width: double.infinity,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(color: const Color(0xffDCE7F0)),
//       ),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(18),
//         child: SingleChildScrollView(
//           scrollDirection: Axis.horizontal,
//           child: ConstrainedBox(
//             constraints: const BoxConstraints(minWidth: 760),
//             child: DataTable(
//               headingRowHeight: 48,
//               dataRowMinHeight: 68,
//               dataRowMaxHeight: 76,
//               horizontalMargin: 18,
//               columnSpacing: 28,
//               headingTextStyle: GoogleFonts.poppins(
//                 color: const Color(0xff71859A),
//                 fontSize: 10.5,
//                 fontWeight: FontWeight.w700,
//               ),
//               dataTextStyle: GoogleFonts.poppins(
//                 color: const Color(0xff294A67),
//                 fontSize: 11,
//               ),
//               headingRowColor: const WidgetStatePropertyAll(Color(0xffF9FAFB)),
//               columns: const [
//                 DataColumn(label: Text('STUDENT')),
//                 DataColumn(label: Text('PHONE')),
//                 DataColumn(label: Text('ATTENDANCE')),
//                 DataColumn(label: Text('PAYMENT')),
//               ],
//               rows: students.map((student) {
//                 final String name =
//                     student['name']?.toString().trim().isNotEmpty == true
//                     ? student['name'].toString()
//                     : 'Student';
//                 final String phone = student['phone']?.toString() ?? 'No phone';
//                 final String attendance =
//                     student['attendanceStatus']?.toString() ?? 'Absent';
//                 final bool paid =
//                     (student['feeStatus'] ?? 'unpaid')
//                         .toString()
//                         .toLowerCase() ==
//                     'paid';

//                 return DataRow(
//                   cells: [
//                     DataCell(
//                       Row(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           _studentAvatar(name),
//                           const SizedBox(width: 10),
//                           SizedBox(
//                             width: 170,
//                             child: Text(
//                               name,
//                               maxLines: 1,
//                               overflow: TextOverflow.ellipsis,
//                               style: GoogleFonts.poppins(
//                                 color: brandNavy,
//                                 fontSize: 11.5,
//                                 fontWeight: FontWeight.w700,
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     DataCell(Text(phone)),
//                     DataCell(
//                       _statusBadge(
//                         attendance,
//                         attendance.toLowerCase() == 'present'
//                             ? accentGreen
//                             : accentRed,
//                       ),
//                     ),
//                     DataCell(
//                       _statusBadge(
//                         paid ? 'Paid' : 'Unpaid',
//                         paid ? accentGreen : const Color(0xffD5A800),
//                       ),
//                     ),
//                   ],
//                 );
//               }).toList(),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildMobileRoster(List<dynamic> students) {
//     return Column(
//       children: students.map((student) {
//         final String name =
//             student['name']?.toString().trim().isNotEmpty == true
//             ? student['name'].toString()
//             : 'Student';
//         final String phone = student['phone']?.toString() ?? 'No phone';
//         final String attendance =
//             student['attendanceStatus']?.toString() ?? 'Absent';
//         final bool paid =
//             (student['feeStatus'] ?? 'unpaid').toString().toLowerCase() ==
//             'paid';
//         final bool present = attendance.toLowerCase() == 'present';

//         return Container(
//           margin: const EdgeInsets.only(bottom: 10),
//           padding: const EdgeInsets.all(14),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(16),
//             border: Border.all(color: const Color(0xffDCE7F0)),
//           ),
//           child: Row(
//             children: [
//               _studentAvatar(name, radius: 22),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       name,
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: GoogleFonts.poppins(
//                         color: brandNavy,
//                         fontSize: 13,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                     const SizedBox(height: 3),
//                     Row(
//                       children: [
//                         const Icon(
//                           Icons.phone_outlined,
//                           size: 12,
//                           color: Color(0xff98A2B3),
//                         ),
//                         const SizedBox(width: 4),
//                         Expanded(
//                           child: Text(
//                             phone,
//                             maxLines: 1,
//                             overflow: TextOverflow.ellipsis,
//                             style: GoogleFonts.poppins(
//                               color: const Color(0xff71859A),
//                               fontSize: 10.5,
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 8),
//                     Wrap(
//                       spacing: 6,
//                       runSpacing: 5,
//                       children: [
//                         _statusBadge(
//                           present ? 'Present' : 'Absent',
//                           present ? accentGreen : accentRed,
//                         ),
//                         _statusBadge(
//                           paid ? 'Paid' : 'Unpaid',
//                           paid ? accentGreen : const Color(0xffD5A800),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//               const Icon(Icons.chevron_right_rounded, color: Color(0xff98A2B3)),
//             ],
//           ),
//         );
//       }).toList(),
//     );
//   }

//   Widget _studentAvatar(String name, {double radius = 19}) {
//     final String initial = name.trim().isNotEmpty
//         ? name.trim()[0].toUpperCase()
//         : 'S';
//     return CircleAvatar(
//       radius: radius,
//       backgroundColor: accentBlue.withOpacity(.14),
//       child: Text(
//         initial,
//         style: GoogleFonts.poppins(
//           color: brandNavy,
//           fontSize: radius * .62,
//           fontWeight: FontWeight.w700,
//         ),
//       ),
//     );
//   }

//   Widget _statusBadge(String label, Color color) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//       decoration: BoxDecoration(
//         color: color.withOpacity(.08),
//         borderRadius: BorderRadius.circular(8),
//       ),
//       child: Text(
//         label,
//         style: GoogleFonts.poppins(
//           color: color,
//           fontSize: 9.5,
//           fontWeight: FontWeight.w700,
//         ),
//       ),
//     );
//   }

//   Widget _statusPill(String label, Color color) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
//       decoration: BoxDecoration(
//         color: color.withOpacity(.08),
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: Text(
//         label,
//         style: GoogleFonts.poppins(
//           color: color,
//           fontSize: 8.5,
//           fontWeight: FontWeight.w800,
//         ),
//       ),
//     );
//   }

//   Widget _buildEmptyRoster() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 50),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(color: const Color(0xffDCE7F0)),
//       ),
//       child: Column(
//         children: [
//           Container(
//             width: 62,
//             height: 62,
//             decoration: const BoxDecoration(
//               color: Color(0xffF2F4F7),
//               shape: BoxShape.circle,
//             ),
//             child: const Icon(
//               Icons.people_outline_rounded,
//               color: Color(0xff98A2B3),
//               size: 29,
//             ),
//           ),
//           const SizedBox(height: 14),
//           Text(
//             'No students found',
//             style: GoogleFonts.poppins(
//               color: brandNavy,
//               fontSize: 14,
//               fontWeight: FontWeight.w700,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             activeFilter == 'all'
//                 ? 'No students are currently assigned to this classroom.'
//                 : 'Try another filter to see more students.',
//             textAlign: TextAlign.center,
//             style: GoogleFonts.poppins(
//               color: const Color(0xff71859A),
//               fontSize: 11,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class TeacherBroadcastScreen extends StatefulWidget {
//   final Call call;
//   final String language;
//   final String stage;
//   final String section;
//   final List<dynamic> enrolledStudents;
//   final VoidCallback? onCallEnded;
//   final Map<String, dynamic> teacherData;

//   const TeacherBroadcastScreen({
//     super.key,
//     required this.call,
//     required this.language,
//     required this.stage,
//     required this.section,
//     required this.enrolledStudents,
//     this.onCallEnded,
//     required this.teacherData,
//   });

//   @override
//   State<TeacherBroadcastScreen> createState() => _TeacherBroadcastScreenState();
// }

// class _TeacherBroadcastScreenState extends State<TeacherBroadcastScreen> {
//   bool isTeacherMuted = false;

//   // ============================================================
//   // LETSSPEAK BRAND COLORS
//   // ============================================================

//   static const Color navy = Color(0xFF155A88);
//   static const Color deepNavy = Color(0xFF0E466D);
//   static const Color blue = Color(0xFF2C6F9F);
//   static const Color teal = Color(0xFF28C2C2);
//   static const Color yellow = Color(0xFFF7DF55);
//   static const Color periwinkle = Color(0xFF7CA4D8);

//   static const Color background = Color(0xFFE8F2F8);
//   static const Color backgroundDark = Color(0xFFD9EAF3);

//   static const Color green = Color(0xFF20A879);
//   static const Color red = Color(0xFFE45757);
//   static const Color textSecondary = Color(0xFF6B8193);

//   @override
//   void initState() {
//     super.initState();
//     GlobalAudioOverlayController.removeOverlay();
//   }

//   Future<void> _toggleTeacherMic() async {
//     final bool newMuted = !isTeacherMuted;

//     try {
//       await widget.call.setMicrophoneEnabled(enabled: !newMuted);

//       if (mounted) {
//         setState(() => isTeacherMuted = newMuted);
//       }
//     } catch (e) {
//       debugPrint("Teacher Mic Error: $e");
//     }
//   }

//   Future<void> _endClassAndBroadcast(BuildContext context) async {
//     try {
//       await widget.call.leave();

//       final request = http.Request(
//         "DELETE",
//         Uri.parse(ApiEndpoints.deleteLiveLink),
//       );

//       request.headers.addAll({"Content-Type": "application/json"});

//       request.body = jsonEncode({
//         "language": widget.language,
//         "stage": widget.stage.toLowerCase(),
//         "section": widget.section.toLowerCase(),
//         "type": "class",
//       });

//       final streamedResponse = await request.send();

//       await http.Response.fromStream(streamedResponse);

//       GlobalAudioOverlayController.removeOverlay();

//       if (widget.onCallEnded != null) {
//         widget.onCallEnded!();
//       }

//       Get.back();

//       Get.snackbar(
//         "Class Ended",
//         "The live classroom has been closed.",
//         backgroundColor: navy,
//         colorText: Colors.white,
//         margin: const EdgeInsets.all(14),
//         borderRadius: 14,
//         icon: const Icon(Icons.check_circle_rounded, color: teal),
//       );
//     } catch (e) {
//       debugPrint("Error ending broadcast session: $e");

//       GlobalAudioOverlayController.removeOverlay();

//       if (widget.onCallEnded != null) {
//         widget.onCallEnded!();
//       }

//       Get.back();
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final String teacherId =
//         (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
//             .toString();

//     return PopScope(
//       canPop: false,

//       onPopInvokedWithResult: (didPop, result) {
//         if (didPop) return;

//         Get.until((route) => route.isFirst);

//         GlobalAudioOverlayController.showOverlay(
//           context,
//           widget.call,
//           teacherId,
//           "Live Studio",
//           widget.teacherData,
//           widget.enrolledStudents,
//         );
//       },

//       child: Scaffold(
//         backgroundColor: background,

//         appBar: _buildAppBar(context, teacherId),

//         body: SafeArea(
//           child: StreamBuilder<CallState>(
//             stream: widget.call.state.asStream(),

//             builder: (context, snapshot) {
//               final callState = snapshot.data;

//               final rawParticipants = callState?.callParticipants ?? [];

//               final seenUserIds = <String>{};

//               final participants = rawParticipants.where((p) {
//                 if (seenUserIds.contains(p.userId)) {
//                   return false;
//                 }

//                 seenUserIds.add(p.userId);

//                 return true;
//               }).toList();

//               final studentCount = participants
//                   .where((p) => !p.roles.contains('admin'))
//                   .length;

//               final speakingParticipants = participants
//                   .where((p) => p.isSpeaking)
//                   .toList();

//               final speaker = speakingParticipants.isNotEmpty
//                   ? speakingParticipants.first
//                   : null;

//               return LayoutBuilder(
//                 builder: (context, constraints) {
//                   final bool desktop = constraints.maxWidth >= 1000;

//                   final bool tablet =
//                       constraints.maxWidth >= 650 &&
//                       constraints.maxWidth < 1000;

//                   return Column(
//                     children: [
//                       // ==================================================
//                       // LIVE HEADER
//                       // ==================================================
//                       _buildLiveHeader(studentCount, speaker, desktop),

//                       // ==================================================
//                       // PARTICIPANTS
//                       // ==================================================
//                       Expanded(
//                         child: participants.isEmpty
//                             ? _buildNoStudents()
//                             : desktop
//                             ? _buildDesktopParticipants(participants)
//                             : _buildMobileParticipants(participants),
//                       ),

//                       // ==================================================
//                       // CONTROL BAR
//                       // ==================================================
//                       _buildControlBar(context, desktop, tablet),
//                     ],
//                   );
//                 },
//               );
//             },
//           ),
//         ),
//       ),
//     );
//   }

//   PreferredSizeWidget _buildAppBar(BuildContext context, String teacherId) {
//     return AppBar(
//       elevation: 0,
//       scrolledUnderElevation: 0,

//       backgroundColor: navy,
//       foregroundColor: Colors.white,

//       automaticallyImplyLeading: false,

//       toolbarHeight: 70,

//       title: Row(
//         children: [
//           Container(
//             width: 44,
//             height: 44,

//             decoration: BoxDecoration(
//               color: teal,
//               borderRadius: BorderRadius.circular(14),
//               boxShadow: [
//                 BoxShadow(
//                   color: teal.withOpacity(.25),
//                   blurRadius: 14,
//                   offset: const Offset(0, 5),
//                 ),
//               ],
//             ),

//             child: const Icon(
//               Icons.graphic_eq_rounded,
//               color: Colors.white,
//               size: 23,
//             ),
//           ),

//           const SizedBox(width: 12),

//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Text(
//                   'Live Classroom',
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: GoogleFonts.poppins(
//                     color: Colors.white,
//                     fontSize: 15,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),

//                 const SizedBox(height: 2),

//                 Text(
//                   '${widget.language} • ${widget.stage} • Section ${widget.section}',
//                   maxLines: 1,
//                   overflow: TextOverflow.ellipsis,
//                   style: GoogleFonts.poppins(
//                     color: Colors.white.withOpacity(.68),
//                     fontSize: 10,
//                     fontWeight: FontWeight.w500,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),

//       actions: [
//         // ----------------------------------------------------------
//         // MINIMIZE
//         // ----------------------------------------------------------
//         IconButton(
//           tooltip: 'Minimize classroom',
//           onPressed: () {
//             Get.until((route) => route.isFirst);

//             GlobalAudioOverlayController.showOverlay(
//               context,
//               widget.call,
//               teacherId,
//               "Live Studio",
//               widget.teacherData,
//               widget.enrolledStudents,
//             );
//           },
//           icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 21),
//         ),

//         // ----------------------------------------------------------
//         // MIC
//         // ----------------------------------------------------------
//         IconButton(
//           tooltip: isTeacherMuted ? 'Unmute microphone' : 'Mute microphone',
//           onPressed: _toggleTeacherMic,
//           icon: Icon(
//             isTeacherMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
//             color: isTeacherMuted ? yellow : teal,
//             size: 22,
//           ),
//         ),

//         // ----------------------------------------------------------
//         // END
//         // ----------------------------------------------------------
//         IconButton(
//           tooltip: 'End class',
//           onPressed: () => _showEndClassDialog(context),
//           icon: const Icon(Icons.stop_circle_rounded, color: red, size: 23),
//         ),

//         const SizedBox(width: 7),
//       ],
//     );
//   }

//   Widget _buildLiveHeader(int studentCount, dynamic speaker, bool desktop) {
//     return Container(
//       width: double.infinity,

//       margin: EdgeInsets.fromLTRB(desktop ? 30 : 14, 16, desktop ? 30 : 14, 10),

//       padding: const EdgeInsets.all(18),

//       decoration: BoxDecoration(
//         gradient: const LinearGradient(
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//           colors: [navy, blue],
//         ),

//         borderRadius: BorderRadius.circular(21),

//         boxShadow: [
//           BoxShadow(
//             color: navy.withOpacity(.16),
//             blurRadius: 22,
//             offset: const Offset(0, 8),
//           ),
//         ],
//       ),

//       child: LayoutBuilder(
//         builder: (context, constraints) {
//           final bool compact = constraints.maxWidth < 600;

//           final status = Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Container(
//                 width: 9,
//                 height: 9,
//                 decoration: const BoxDecoration(
//                   color: teal,
//                   shape: BoxShape.circle,
//                 ),
//               ),

//               const SizedBox(width: 7),

//               Text(
//                 isTeacherMuted ? 'MIC MUTED' : 'LIVE',
//                 style: GoogleFonts.poppins(
//                   color: isTeacherMuted ? yellow : teal,
//                   fontSize: 9.5,
//                   fontWeight: FontWeight.w800,
//                   letterSpacing: .5,
//                 ),
//               ),
//             ],
//           );

//           return compact
//               ? Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: [
//                         Expanded(child: _headerTitle(studentCount)),
//                         status,
//                       ],
//                     ),
//                     if (speaker != null) ...[
//                       const SizedBox(height: 12),
//                       _speakerPill(speaker.name.toString()),
//                     ],
//                   ],
//                 )
//               : Row(
//                   children: [
//                     Expanded(child: _headerTitle(studentCount)),
//                     if (speaker != null) ...[
//                       _speakerPill(speaker.name.toString()),
//                       const SizedBox(width: 18),
//                     ],
//                     status,
//                   ],
//                 );
//         },
//       ),
//     );
//   }

//   Widget _headerTitle(int studentCount) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           'Connected Students',
//           style: GoogleFonts.poppins(
//             color: Colors.white,
//             fontSize: 15,
//             fontWeight: FontWeight.w700,
//           ),
//         ),

//         const SizedBox(height: 2),

//         Text(
//           '$studentCount ${studentCount == 1 ? 'student' : 'students'} in your live classroom',
//           style: GoogleFonts.poppins(
//             color: Colors.white.withOpacity(.68),
//             fontSize: 10.5,
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _speakerPill(String name) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),

//       decoration: BoxDecoration(
//         color: Colors.white.withOpacity(.10),
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(color: teal.withOpacity(.35)),
//       ),

//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           const Icon(Icons.graphic_eq_rounded, color: teal, size: 14),

//           const SizedBox(width: 6),

//           Text(
//             '$name is speaking',
//             maxLines: 1,
//             overflow: TextOverflow.ellipsis,
//             style: GoogleFonts.poppins(
//               color: Colors.white,
//               fontSize: 9.5,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildMobileParticipants(List<dynamic> participants) {
//     return ListView.separated(
//       physics: const BouncingScrollPhysics(),

//       padding: const EdgeInsets.fromLTRB(14, 2, 14, 18),

//       itemCount: participants.length,

//       separatorBuilder: (_, __) => const SizedBox(height: 10),

//       itemBuilder: (context, index) {
//         return _participantCard(participants[index]);
//       },
//     );
//   }

//   Widget _buildDesktopParticipants(List<dynamic> participants) {
//     return SingleChildScrollView(
//       physics: const BouncingScrollPhysics(),

//       padding: const EdgeInsets.fromLTRB(30, 2, 30, 22),

//       child: Center(
//         child: ConstrainedBox(
//           constraints: const BoxConstraints(maxWidth: 1150),

//           child: GridView.builder(
//             shrinkWrap: true,

//             physics: const NeverScrollableScrollPhysics(),

//             itemCount: participants.length,

//             gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//               crossAxisCount: 2,
//               crossAxisSpacing: 14,
//               mainAxisSpacing: 14,
//               childAspectRatio: 3.5,
//             ),

//             itemBuilder: (context, index) {
//               return _participantCard(participants[index]);
//             },
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _participantCard(dynamic participant) {
//     final bool muted = !participant.isAudioEnabled;

//     final bool speaking = participant.isSpeaking;

//     final bool teacher = participant.roles.contains('admin');

//     final Color avatarColor = speaking
//         ? teal
//         : teacher
//         ? yellow
//         : navy;

//     final String name = participant.name.toString().trim().isEmpty
//         ? 'User'
//         : participant.name.toString();

//     final String initial = name[0].toUpperCase();

//     return AnimatedContainer(
//       duration: const Duration(milliseconds: 180),

//       padding: const EdgeInsets.all(14),

//       decoration: BoxDecoration(
//         color: Colors.white,

//         borderRadius: BorderRadius.circular(18),

//         border: Border.all(
//           color: speaking ? teal.withOpacity(.55) : navy.withOpacity(.09),
//           width: speaking ? 1.5 : 1,
//         ),

//         boxShadow: [
//           BoxShadow(
//             color: speaking ? teal.withOpacity(.09) : navy.withOpacity(.045),
//             blurRadius: speaking ? 18 : 11,
//             offset: const Offset(0, 5),
//           ),
//         ],
//       ),

//       child: Row(
//         children: [
//           Stack(
//             clipBehavior: Clip.none,

//             children: [
//               CircleAvatar(
//                 radius: 22,

//                 backgroundColor: avatarColor.withOpacity(.12),

//                 child: Text(
//                   initial,
//                   style: GoogleFonts.poppins(
//                     color: avatarColor,
//                     fontSize: 16,
//                     fontWeight: FontWeight.w800,
//                   ),
//                 ),
//               ),

//               if (speaking)
//                 Positioned(
//                   right: -2,
//                   bottom: -2,
//                   child: Container(
//                     width: 16,
//                     height: 16,

//                     decoration: BoxDecoration(
//                       color: teal,
//                       shape: BoxShape.circle,
//                       border: Border.all(color: Colors.white, width: 2),
//                     ),

//                     child: const Icon(
//                       Icons.graphic_eq_rounded,
//                       color: Colors.white,
//                       size: 9,
//                     ),
//                   ),
//                 ),
//             ],
//           ),

//           const SizedBox(width: 12),

//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Flexible(
//                       child: Text(
//                         name,
//                         maxLines: 1,
//                         overflow: TextOverflow.ellipsis,
//                         style: GoogleFonts.poppins(
//                           color: deepNavy,
//                           fontSize: 12.5,
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                     ),

//                     if (teacher) ...[
//                       const SizedBox(width: 7),
//                       _tinyBadge('TEACHER', yellow),
//                     ],
//                   ],
//                 ),

//                 const SizedBox(height: 3),

//                 Text(
//                   speaking
//                       ? 'Speaking now'
//                       : muted
//                       ? 'Microphone muted'
//                       : 'Connected to classroom',
//                   style: GoogleFonts.poppins(
//                     color: speaking ? teal : textSecondary,
//                     fontSize: 9.5,
//                     fontWeight: speaking ? FontWeight.w600 : FontWeight.w500,
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           const SizedBox(width: 8),

//           Container(
//             width: 37,
//             height: 37,

//             decoration: BoxDecoration(
//               color: muted ? red.withOpacity(.09) : teal.withOpacity(.10),
//               borderRadius: BorderRadius.circular(11),
//             ),

//             child: Icon(
//               muted ? Icons.mic_off_rounded : Icons.mic_rounded,
//               color: muted ? red : teal,
//               size: 18,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _tinyBadge(String label, Color color) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),

//       decoration: BoxDecoration(
//         color: color.withOpacity(.20),
//         borderRadius: BorderRadius.circular(6),
//       ),

//       child: Text(
//         label,
//         style: GoogleFonts.poppins(
//           color: deepNavy,
//           fontSize: 6.5,
//           fontWeight: FontWeight.w800,
//         ),
//       ),
//     );
//   }

//   Widget _buildNoStudents() {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(24),

//         child: Container(
//           constraints: const BoxConstraints(maxWidth: 420),

//           padding: const EdgeInsets.all(30),

//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(24),
//             border: Border.all(color: navy.withOpacity(.08)),
//           ),

//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Container(
//                 width: 72,
//                 height: 72,

//                 decoration: BoxDecoration(
//                   color: teal.withOpacity(.10),
//                   shape: BoxShape.circle,
//                 ),

//                 child: const Icon(
//                   Icons.people_outline_rounded,
//                   color: teal,
//                   size: 34,
//                 ),
//               ),

//               const SizedBox(height: 16),

//               Text(
//                 'Waiting for students',
//                 style: GoogleFonts.poppins(
//                   color: deepNavy,
//                   fontSize: 16,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),

//               const SizedBox(height: 6),

//               Text(
//                 'Your classroom is live. Students who join will appear here automatically.',
//                 textAlign: TextAlign.center,
//                 style: GoogleFonts.poppins(
//                   color: textSecondary,
//                   fontSize: 10.5,
//                   height: 1.5,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildControlBar(BuildContext context, bool desktop, bool tablet) {
//     return Container(
//       padding: EdgeInsets.fromLTRB(
//         desktop ? 30 : 14,
//         13,
//         desktop ? 30 : 14,
//         15,
//       ),

//       decoration: BoxDecoration(
//         color: Colors.white,

//         border: Border(top: BorderSide(color: navy.withOpacity(.10))),

//         boxShadow: [
//           BoxShadow(
//             color: navy.withOpacity(.08),
//             blurRadius: 18,
//             offset: const Offset(0, -5),
//           ),
//         ],
//       ),

//       child: Center(
//         child: ConstrainedBox(
//           constraints: const BoxConstraints(maxWidth: 1150),

//           child: LayoutBuilder(
//             builder: (context, constraints) {
//               final bool compact = constraints.maxWidth < 600;

//               return compact
//                   ? Column(
//                       children: [
//                         _micButton(),
//                         const SizedBox(height: 10),
//                         _endButton(context),
//                       ],
//                     )
//                   : Row(
//                       children: [
//                         Expanded(child: _micButton()),
//                         const SizedBox(width: 12),
//                         Expanded(child: _endButton(context)),
//                       ],
//                     );
//             },
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _micButton() {
//     return SizedBox(
//       height: 50,
//       width: double.infinity,

//       child: ElevatedButton.icon(
//         onPressed: _toggleTeacherMic,

//         icon: Icon(
//           isTeacherMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
//           size: 19,
//         ),

//         label: Text(
//           isTeacherMuted ? 'UNMUTE MICROPHONE' : 'MUTE MICROPHONE',
//           style: GoogleFonts.poppins(
//             fontSize: 11.5,
//             fontWeight: FontWeight.w700,
//           ),
//         ),

//         style: ElevatedButton.styleFrom(
//           backgroundColor: isTeacherMuted ? navy : teal,
//           foregroundColor: Colors.white,
//           elevation: 0,

//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(13),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _endButton(BuildContext context) {
//     return SizedBox(
//       height: 50,
//       width: double.infinity,

//       child: ElevatedButton.icon(
//         onPressed: () => _showEndClassDialog(context),

//         icon: const Icon(Icons.stop_rounded, size: 19),

//         label: Text(
//           'END CLASS',
//           style: GoogleFonts.poppins(
//             fontSize: 11.5,
//             fontWeight: FontWeight.w700,
//           ),
//         ),

//         style: ElevatedButton.styleFrom(
//           backgroundColor: red,
//           foregroundColor: Colors.white,
//           elevation: 0,

//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(13),
//           ),
//         ),
//       ),
//     );
//   }

//   void _showEndClassDialog(BuildContext context) {
//     Get.dialog(
//       Dialog(
//         backgroundColor: Colors.transparent,

//         child: Container(
//           constraints: const BoxConstraints(maxWidth: 430),

//           padding: const EdgeInsets.all(24),

//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(24),
//           ),

//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Container(
//                 width: 60,
//                 height: 60,

//                 decoration: BoxDecoration(
//                   color: red.withOpacity(.10),
//                   shape: BoxShape.circle,
//                 ),

//                 child: const Icon(
//                   Icons.stop_circle_rounded,
//                   color: red,
//                   size: 30,
//                 ),
//               ),

//               const SizedBox(height: 16),

//               Text(
//                 'End this class?',
//                 style: GoogleFonts.poppins(
//                   color: deepNavy,
//                   fontSize: 18,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),

//               const SizedBox(height: 7),

//               Text(
//                 'All connected students will be disconnected from the live classroom.',
//                 textAlign: TextAlign.center,
//                 style: GoogleFonts.poppins(
//                   color: textSecondary,
//                   fontSize: 11,
//                   height: 1.5,
//                 ),
//               ),

//               const SizedBox(height: 22),

//               Row(
//                 children: [
//                   Expanded(
//                     child: OutlinedButton(
//                       onPressed: () => Get.back(),

//                       style: OutlinedButton.styleFrom(
//                         foregroundColor: navy,
//                         side: BorderSide(color: navy.withOpacity(.18)),
//                         minimumSize: const Size(0, 46),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                       ),

//                       child: Text(
//                         'Cancel',
//                         style: GoogleFonts.poppins(
//                           fontSize: 11.5,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ),
//                   ),

//                   const SizedBox(width: 10),

//                   Expanded(
//                     child: ElevatedButton(
//                       onPressed: () {
//                         Get.back();
//                         _endClassAndBroadcast(context);
//                       },

//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: red,
//                         foregroundColor: Colors.white,
//                         elevation: 0,
//                         minimumSize: const Size(0, 46),
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                       ),

//                       child: Text(
//                         'End Class',
//                         style: GoogleFonts.poppins(
//                           fontSize: 11.5,
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }