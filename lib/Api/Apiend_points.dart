class ApiEndpoints {
  // =====================================================
  // 🔁 SWITCH SERVER: keep ONE line active, comment the other
  // =====================================================

  // 🖥️ LOCAL (laptop running `npm run dev`, phone on same Wi-Fi)
  static const String baseUrl = "http://192.168.1.3:5001/api";

  // 🚀 PRODUCTION (Render): uncomment this and comment the LOCAL line above
  // static const String baseUrl = "https://lets-talk-backend-o06t.onrender.com/api";

  // =====================================================
  // Auth Endpoints
  // =====================================================
  static const String login = "$baseUrl/login";
  static const String register = "$baseUrl/register";

  // =====================================================
  // Attendance & User Information
  // =====================================================
  static const String usersByStage = "$baseUrl/admin/users-by-stage";
  static const String adminAttendance = "$baseUrl/admin/attendance";
  static const String userAttendance = "$baseUrl/user/my-attendance";
  static const String markAttendance = "$baseUrl/user/mark-attendance";
  static const String allStudents = "$baseUrl/admin/all-students";

  // Classroom roster for trainers
  static const String trainerRoster = "$baseUrl/admin/trainer-roster";

  // =====================================================
  // Stream audio live classes
  // =====================================================
  static const String streamToken = "$baseUrl/rtc/token";
  static const String prepareCall =
      "$baseUrl/rtc/prepare-call"; // server creates today's class
  static const String updateLiveLink = "$baseUrl/live/admin/update";
  static const String deleteLiveLink = "$baseUrl/live/admin/delete";

  // =====================================================
  // 🎤 Speaking practice (live classroom)
  // =====================================================
  static const String practiceMark = "$baseUrl/practice/mark";
  static const String practiceList = "$baseUrl/practice/list";
  static const String practiceRate =
      "$baseUrl/practice/rate"; // ⭐ 1–5 after "Mark practiced"

  // =====================================================
  // ⏰ Batch timings
  // =====================================================
  // Students who joined a different timing than their own
  // (attendance counts, shown as "joined another timing")
  static const String batchVisitors = "$baseUrl/admin/batch-visitors";

  // Batch-wise summary: per timing → on time / late / absent / other timing
  static const String batchSummary = "$baseUrl/admin/batch-summary";
}
