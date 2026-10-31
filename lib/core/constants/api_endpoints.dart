// lib/core/constants/api_endpoints.dart

class ApiEndpoints {
  static const String baseUrl = 'https://eco.ariobonyantoos.com/api/';
  static const String wsBaseUrl =
      'wss://eco.ariobonyantoos.com/ws'; // 👈 بدون اسلش انتهایی

  // آدرس خروجی: wss://eco.ariobonyantoos.com/ws/driver/available-orders/
  static String get driverAvailableOrdersWs =>
      '$wsBaseUrl/driver/available-orders/';

  // آدرس خروجی: wss://eco.ariobonyantoos.com/ws/orders/12/track/
  static String orderTrackingWs(int orderId) =>
      '$wsBaseUrl/orders/$orderId/track/';
}
