import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  static String get baseUrl => (dotenv.isInitialized ? dotenv.env['API_BASE_URL'] : null) ?? 'http://localhost:8000';
  static const String v1 = '/api/v1';
  static const String auth = '$v1/auth';
}
