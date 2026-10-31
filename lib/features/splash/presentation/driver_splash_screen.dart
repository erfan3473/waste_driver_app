// lib/features/splash/presentation/driver_splash_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:dio/dio.dart';

import 'package:waste_driver_app/core/network/dio_client.dart';
import 'package:waste_driver_app/core/services/auth_storage.dart';
import 'package:waste_driver_app/features/auth/presentation/driver_login_screen.dart';
import 'package:waste_driver_app/features/mission/presentation/active_mission_screen.dart';
import 'package:waste_driver_app/features/orders/presentation/driver_orders_screen.dart';

class DriverSplashScreen extends ConsumerStatefulWidget {
  const DriverSplashScreen({super.key});

  @override
  ConsumerState<DriverSplashScreen> createState() => _DriverSplashScreenState();
}

class _DriverSplashScreenState extends ConsumerState<DriverSplashScreen> {
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkStatusAndNavigate();
  }

  Future<void> _checkStatusAndNavigate() async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    final token = await AuthStorage.getToken();
    if (token == null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
        );
      }
      return;
    }

    try {
      final dio = ref.read(dioProvider);

      // ۱. استعلام مأموریت فعال راننده
      final response = await dio.get('driver/requests/current-mission/');

      if (!mounted) return;

      Map<String, dynamic>? missionData;

      // بررسی دقیق نوع دیتا برای جلوگیری از کرش رشته‌های متنی یا بدنه خالی
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is Map) {
          missionData = Map<String, dynamic>.from(response.data as Map);
        } else if (response.data is String &&
            (response.data as String).trim().startsWith('{')) {
          try {
            missionData =
                jsonDecode(response.data as String) as Map<String, dynamic>;
          } catch (_) {}
        }
      }

      // ۲. تصمیم‌گیری بر اساس وجود یا عدم وجود مأموریت ناتمام
      if (missionData != null && missionData['id'] != null) {
        final orderId = missionData['id'] as int;
        final lat = (missionData['latitude'] as num?)?.toDouble() ?? 0.0;
        final lng = (missionData['longitude'] as num?)?.toDouble() ?? 0.0;
        final address = missionData['address_text'] as String? ?? '';

        // در صورت وجود مأموریت در حال انجام، مستقیم به نقشه سفر می‌رود
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ActiveMissionScreen(
              orderId: orderId,
              citizenLocation: LatLng(lat, lng),
              addressText: address,
            ),
          ),
        );
      } else {
        // در صورت نبود مأموریت فعال، هدایت به صفحه یکپارچه سفارش‌ها (نقشه + کرکره لیست)
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverOrdersScreen()),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;

      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await AuthStorage.logout();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
        );
        return;
      }

      setState(() {
        _hasError = true;
        _errorMessage =
            'عدم برقراری ارتباط با سرور. لطفاً اتصال اینترنت را بررسی کنید.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'خطای غیرمنتظره در بارگذاری اطلاعات: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  size: 54,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'سامانه مدیریت ناوگان آریو بنیان توس (اکو)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'دوست‌دار محیط زیست',
                style: TextStyle(fontSize: 14, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(height: 10),
              const Text(
                'در حال همگام‌سازی مأموریت‌ها...',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 36),

              if (!_hasError)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF2E7D32),
                  ),
                )
              else ...[
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('تلاش مجدد'),
                  onPressed: _checkStatusAndNavigate,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
