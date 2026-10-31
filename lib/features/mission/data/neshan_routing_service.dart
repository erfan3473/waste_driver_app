// lib/features/mission/data/neshan_routing_service.dart

import 'package:flutter/foundation.dart';
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
  static const String neshanApiKey = 'service.ff7d913b22494981b426505c23d74204';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Api-Key': neshanApiKey},
    ),
  );

  /// دریافت مسیر بهینه با تلاش اولیه روی ترافیک‌دار و فال‌بک خودکار روی بدون ترافیک
  static Future<RouteResult?> getTrafficRoute({
    required LatLng origin,
    required LatLng destination,
    double? bearing,
  }) async {
    // ۱. بررسی معتبر بودن مختصات (جلوگیری از ارسال نقاط خالی 0,0)
    if (origin.latitude == 0.0 || destination.latitude == 0.0) {
      debugPrint(
        '❌ [Neshan] مختصات مبدأ یا مقصد نامعتبر است: Origin($origin), Dest($destination)',
      );
      return null;
    }

    final originStr = '${origin.latitude},${origin.longitude}';
    final destStr = '${destination.latitude},${destination.longitude}';

    debugPrint(
      '🚀 [Neshan] ارسال درخواست مسیریابی: مبدأ $originStr -> مقصد $destStr',
    );

    // تلاش اول: سرویس با ترافیک لحظه‌ای
    RouteResult? result = await _callNeshanApi(
      url: 'https://api.neshan.org/v4/direction',
      originStr: originStr,
      destStr: destStr,
      bearing: bearing,
    );

    // تلاش دوم (فال‌بک): سرویس بدون ترافیک در صورت خطا
    if (result == null) {
      debugPrint('⚠️ [Neshan] تلاش مجدد با سرویس بدون ترافیک (no-traffic)...');
      result = await _callNeshanApi(
        url: 'https://api.neshan.org/v4/direction/no-traffic',
        originStr: originStr,
        destStr: destStr,
        bearing: bearing,
      );
    }

    return result;
  }

  static Future<RouteResult?> _callNeshanApi({
    required String url,
    required String originStr,
    required String destStr,
    double? bearing,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'type': 'car',
        'origin': originStr,
        'destination': destStr,
        'avoidTrafficZone': false,
        'avoidOddEvenZone': false,
        'alternative': false,
      };

      if (bearing != null && bearing >= 0) {
        queryParams['bearing'] = bearing.toInt().toString();
      }

      final response = await _dio.get(url, queryParameters: queryParams);

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
          debugPrint(
            '✅ [Neshan] مسیر با موفقیت دریافت شد. تعداد نقاط پلی‌لاین: ${decodedList.length}',
          );

          return RouteResult(
            polylinePoints: decodedList,
            distanceText: distance,
            durationText: duration,
            nextInstruction: instruction,
          );
        } else {
          debugPrint(
            '⚠️ [Neshan] هیچ مسیری بین این دو نقطه یافت نشد (لیست routes خالی است).',
          );
        }
      }
    } on DioException catch (e) {
      debugPrint('❌ [Neshan Dio Error] کد وضعیت: ${e.response?.statusCode}');
      debugPrint('❌ [Neshan Data] جزئیات پاسخ نشان: ${e.response?.data}');
      debugPrint('❌ [Neshan Message] پیام خطا: ${e.message}');
    } catch (e) {
      debugPrint('❌ [Neshan Exception] خطای پیش‌بینی‌نشده: $e');
    }
    return null;
  }
}
