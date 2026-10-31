// lib/features/mission/data/neshan_routing_service.dart

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/utils/polyline_decoder.dart';

class RouteResult {
  final List<LatLng> polylinePoints;
  final String distanceText;
  final String durationText;
  final String nextInstruction;

  RouteResult({
    required this.polylinePoints,
    required this.distanceText,
    required this.durationText,
    required this.nextInstruction,
  });
}

class NeshanRoutingService {
  // 👈 کلید دریافتی از پنل نشان را اینجا جایگزین کنید
  static const String neshanApiKey = 'service.ff7d913b22494981b426505c23d74204';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  /// دریافت مسیر بهینه با احتساب ترافیک آنلاین
  static Future<RouteResult?> getTrafficRoute({
    required LatLng origin,
    required LatLng destination,
    double? bearing,
  }) async {
    try {
      final originStr = '${origin.latitude},${origin.longitude}';
      final destStr = '${destination.latitude},${destination.longitude}';

      final queryParams = <String, dynamic>{
        'type': 'car',
        'origin': originStr,
        'destination': destStr,
        'avoidTrafficZone': 'false',
        'avoidOddEvenZone': 'false',
        'alternative': 'false',
      };

      if (bearing != null && bearing >= 0) {
        queryParams['bearing'] = bearing.toInt().toString();
      }

      final response = await _dio.get(
        'https://api.neshan.org/v4/direction',
        queryParameters: queryParams,
        options: Options(headers: {'Api-Key': neshanApiKey}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final routes = response.data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0];
          final encodedPoints =
              firstRoute['overview_polyline']?['points'] ?? '';
          final legs = firstRoute['legs'] as List?;

          String distance = '';
          String duration = '';
          String instruction = 'به سمت مقصد حرکت کنید';

          if (legs != null && legs.isNotEmpty) {
            final firstLeg = legs[0];
            distance = firstLeg['distance']?['text'] ?? '';
            duration = firstLeg['duration']?['text'] ?? '';

            final steps = firstLeg['steps'] as List?;
            if (steps != null && steps.isNotEmpty) {
              instruction = steps[0]['instruction'] ?? instruction;
            }
          }

          final decodedList = PolylineDecoder.decode(encodedPoints);

          return RouteResult(
            polylinePoints: decodedList,
            distanceText: distance,
            durationText: duration,
            nextInstruction: instruction,
          );
        }
      }
    } catch (_) {
      // در صورت بروز خطای کلید یا قطعی اینترنت، جریان مأموریت متوقف نمی‌شود
    }
    return null;
  }
}
