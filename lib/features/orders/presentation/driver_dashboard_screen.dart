// lib/features/orders/presentation/driver_dashboard_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:waste_driver_app/core/constants/api_endpoints.dart';
import 'package:waste_driver_app/core/network/dio_client.dart';
import 'package:waste_driver_app/core/services/auth_storage.dart';
import 'package:waste_driver_app/features/auth/presentation/driver_login_screen.dart';
import 'package:waste_driver_app/features/mission/presentation/active_mission_screen.dart';
import 'package:waste_driver_app/features/orders/data/driver_order_model.dart';
import 'providers/available_orders_provider.dart';
import 'widgets/driver_orders_list_tab.dart';
import 'widgets/driver_orders_map_tab.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() =>
      _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends ConsumerState<DriverDashboardScreen> {
  late final PageController _pageController;
  int _currentViewIndex = 0; // ۰: لیست ، ۱: نقشه
  WebSocketChannel? _wsChannel;
  LatLng? _driverLocation;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fetchDriverPosition();
    _connectAvailableOrdersSocket();
  }

  /// دریافت موقعیت جهت مرکز نقشه
  Future<void> _fetchDriverPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 4),
      );
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(pos.latitude, pos.longitude);
        });
      }
    } catch (_) {}
  }

  /// اتصال به روم وب‌سوکت کاردکس زنده
  void _connectAvailableOrdersSocket() {
    try {
      final wsUri = Uri.parse(ApiEndpoints.driverAvailableOrdersWs);
      _wsChannel = WebSocketChannel.connect(wsUri);

      _wsChannel!.stream.listen((message) {
        final data = jsonDecode(message);
        final type = data['type'];

        if (type == 'new_order') {
          final orderJson = data['order'] as Map<String, dynamic>;
          final newOrder = DriverOrderModel.fromJson(orderJson);
          ref
              .read(availableOrdersNotifierProvider.notifier)
              .addOrderRealtime(newOrder);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('سفارش جدید #${newOrder.id} اضافه شد.'),
                backgroundColor: const Color(0xFF2E7D32),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else if (type == 'remove_order') {
          final orderId = data['order_id'] as int;
          ref
              .read(availableOrdersNotifierProvider.notifier)
              .removeOrderRealtime(orderId);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _wsChannel?.sink.close();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleAcceptOrder(DriverOrderModel order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'پذیرش سفارش',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('آیا مایل به پذیرش مأموریت شماره #${order.id} هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تأیید و شروع مأموریت'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.post('driver/requests/${order.id}/accept/');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ActiveMissionScreen(
              orderId: order.id,
              citizenLocation: LatLng(order.latitude, order.longitude),
              addressText: order.addressText,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در پذیرش سفارش: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(availableOrdersNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ناوگان جمع‌آوری اکو',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'به‌روزرسانی',
            onPressed: () => ref
                .read(availableOrdersNotifierProvider.notifier)
                .fetchOrders(),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: 'خروج',
            onPressed: () async {
              await AuthStorage.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // تب‌بار اسلایدری (لیست / نقشه)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _currentViewIndex == 0
                            ? const Color(0xFF2E7D32)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.format_list_bulleted_rounded,
                            size: 18,
                            color: _currentViewIndex == 0
                                ? Colors.white
                                : Colors.black87,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'لیست درخواست‌ها',
                            style: TextStyle(
                              color: _currentViewIndex == 0
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _currentViewIndex == 1
                            ? const Color(0xFF2E7D32)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.map_outlined,
                            size: 18,
                            color: _currentViewIndex == 1
                                ? Colors.white
                                : Colors.black87,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'نقشه سفارش‌ها',
                            style: TextStyle(
                              color: _currentViewIndex == 1
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // بدنه دو تب با قابلیت سوایپ
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                return PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentViewIndex = index);
                  },
                  children: [
                    DriverOrdersListTab(
                      orders: orders,
                      onRefresh: () async {
                        await ref
                            .read(availableOrdersNotifierProvider.notifier)
                            .fetchOrders();
                      },
                      onAcceptOrder: _handleAcceptOrder,
                    ),
                    DriverOrdersMapTab(
                      orders: orders,
                      driverPosition: _driverLocation,
                      onAcceptOrder: _handleAcceptOrder,
                    ),
                  ],
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
              ),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('خطا در دریافت سفارش‌ها: $err'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref
                          .read(availableOrdersNotifierProvider.notifier)
                          .fetchOrders(),
                      child: const Text('تلاش مجدد'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
