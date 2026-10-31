// lib/core/constants/api_endpoints.dart

class ApiEndpoints {
  static const String baseUrl = 'https://eco.ariobonyantoos.com/api/';
  static const String wsBaseUrl = 'wss://eco.ariobonyantoos.com/ws/';

  static String orderTrackingWs(int orderId) =>
      '${wsBaseUrl}orders/$orderId/track/';
}
