class ApiEndpoints {
  // static const String baseUrl =
  // "http://192.168.1.4:5001/api";

  static const String baseUrl =
      "https://lets-talk-backend-o06t.onrender.com/api";

  // Auth Endpoints
  static const String login = "$baseUrl/login";
  static const String register = "$baseUrl/register";

  // Attendance & User Information
  static const String usersByStage = "$baseUrl/admin/users-by-stage";
  static const String adminAttendance = "$baseUrl/admin/attendance";
  static const String userAttendance = "$baseUrl/user/my-attendance";
  static const String markAttendance = "$baseUrl/user/mark-attendance";
  static const String allStudents = "$baseUrl/admin/all-students";

  // 🚀 Added dedicated classroom roster endpoint for trainers
  static const String trainerRoster = "$baseUrl/admin/trainer-roster";

  // Stream Audio Live Broadcasting Endpoints
  static const String streamToken = "$baseUrl/stream/token";
  static const String updateLiveLink = "$baseUrl/live/admin/update";
  static const String deleteLiveLink = "$baseUrl/live/admin/delete";
}
