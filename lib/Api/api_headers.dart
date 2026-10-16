import 'package:get_storage/get_storage.dart';

/// Adds the login token to every request.
/// Usage:
///   http.get(uri, headers: ApiHeaders.auth())
///   http.post(uri, headers: ApiHeaders.json(), body: jsonEncode(data))
///   multipartRequest.headers.addAll(ApiHeaders.auth())
class ApiHeaders {
  ApiHeaders._();

  static String? get token => GetStorage().read('token');

  static Map<String, String> auth() {
    final t = token;
    return {if (t != null && t.isNotEmpty) 'Authorization': 'Bearer $t'};
  }

  static Map<String, String> json() => {
        'Content-Type': 'application/json',
        ...auth(),
      };
}
