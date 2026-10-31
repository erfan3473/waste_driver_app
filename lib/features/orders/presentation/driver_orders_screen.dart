// lib/features/orders/presentation/driver_orders_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:waste_driver_app/core/constants/api_endpoints.dart';
import 'package:waste_driver_app/core/network/dio_client.dart';
import 'package:waste_driver_app/core/services/auth_storage.dart';
import 'package:waste_driver_app/features/auth/presentation/driver_login_screen.dart';
import 'package:waste_driver_app/features/mission/presentation/active_mission_screen.dart';
import 'package:waste_driver_app/features/orders/data/driver_order_model.dart';
import 'widgets/driver_order_card.dart';

// ════════════════════════════════════════════════════════════════
// ۱. مدیریت وضعیت واکنش‌گرا و همگام با وب‌سوکت
// ════════════════════════════════════════════════════════════════

class AvailableOrdersNotifier
    extends StateNotifier<AsyncValue<List<DriverOrderModel>>> {
  final Ref ref;

  AvailableOrdersNotifier(this.ref) : super(const AsyncValue.loading()) {
    fetchOrders();
  }

  Future<void> fetchOrders({double? driverLat, double? driverLng}) async {
    try {
      final dio = ref.read(dioProvider);

      double? lat = driverLat;
      double? lng = driverLng;

      if (lat == null || lng == null) {
        try {
          final isGpsOn = await Geolocator.isLocationServiceEnabled();
          if (isGpsOn) {
            final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium,
              timeLimit: const Duration(seconds: 4),
            );
            lat = pos.latitude;
            lng = pos.longitude;
          }
        } catch (_) {}
      }

      final queryParams = <String, dynamic>{};
      if (lat != null && lng != null) {
        queryParams['lat'] = lat;
        queryParams['lng'] = lng;
      }

      final response = await dio.get(
        'driver/requests/available/',
        queryParameters: queryParams,
      );

      final List rawList = response.data as List;
      final orders = rawList
          .map((e) => DriverOrderModel.fromJson(e as Map<String, dynamic>))
          .toList();

      state = AsyncValue.data(orders);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void addOrderRealtime(DriverOrderModel newOrder) {
    state.whenData((currentList) {
      if (!currentList.any((o) => o.id == newOrder.id)) {
        state = AsyncValue.data([newOrder, ...currentList]);
      }
    });
  }

  void removeOrderRealtime(int orderId) {
    state.whenData((currentList) {
      final updatedList = currentList.where((o) => o.id != orderId).toList();
      state = AsyncValue.data(updatedList);
    });
  }
}

final availableOrdersProvider =
    StateNotifierProvider<
      AvailableOrdersNotifier,
      AsyncValue<List<DriverOrderModel>>
    >((ref) => AvailableOrdersNotifier(ref));

// ════════════════════════════════════════════════════════════════
// ۲. صفحه اصلی یکپارچه (نقشه در پس‌زمینه + کرکره اسلایدی سفارش‌ها)
// ════════════════════════════════════════════════════════════════

class DriverOrdersScreen extends ConsumerStatefulWidget {
  const DriverOrdersScreen({super.key});

  @override
  ConsumerState<DriverOrdersScreen> createState() => _DriverOrdersScreenState();
}

class _DriverOrdersScreenState extends ConsumerState<DriverOrdersScreen> {
  final MapController _mapController = MapController();
  WebSocketChannel? _wsChannel;
  LatLng? _driverLocation;
  bool _isLoadingGps = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialPosition();
    _connectAvailableOrdersSocket();
  }

  Future<void> _fetchInitialPosition() async {
    try {
      final isGpsOn = await Geolocator.isLocationServiceEnabled();
      if (!isGpsOn) return;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

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

  /// مدیریت دکمه موقعیت من روی نقشه همراه با بررسی خطاهای GPS
  Future<void> _handleGpsTap() async {
    setState(() => _isLoadingGps = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isLoadingGps = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'مکان‌یاب (GPS) گوشی خاموش است. لطفاً آن را روشن کنید.',
              ),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'روشن کردن',
                textColor: Colors.white,
                onPressed: () => Geolocator.openLocationSettings(),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _isLoadingGps = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('دسترسی به موقعیت مکانی توسط کاربر صادر نشد.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isLoadingGps = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'دسترسی موقعیت مکانی مسدود است؛ از تنظیمات برنامه فعال فرمایید.',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'تنظیمات',
                textColor: Colors.white,
                onPressed: () => Geolocator.openAppSettings(),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final newLoc = LatLng(pos.latitude, pos.longitude);

      if (mounted) {
        setState(() {
          _driverLocation = newLoc;
          _isLoadingGps = false;
        });

        _mapController.move(newLoc, 15.0);

        // مرتب‌سازی مجدد سفارش‌ها بر اساس موقعیت جدید
        ref
            .read(availableOrdersProvider.notifier)
            .fetchOrders(
              driverLat: newLoc.latitude,
              driverLng: newLoc.longitude,
            );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingGps = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در برقراری ارتباط با ماهواره GPS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
          ref.read(availableOrdersProvider.notifier).addOrderRealtime(newOrder);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('درخواست جمع‌آوری جدید #${newOrder.id} ثبت شد.'),
                backgroundColor: const Color(0xFF2E7D32),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else if (type == 'remove_order') {
          final orderId = data['order_id'] as int;
          ref
              .read(availableOrdersProvider.notifier)
              .removeOrderRealtime(orderId);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _wsChannel?.sink.close();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _acceptOrder(DriverOrderModel order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'پذیرش سفارش',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'آیا مایل به پذیرش مأموریت جمع‌آوری شماره #${order.id} هستید؟',
        ),
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

  void _showOrderBottomSheet(DriverOrderModel order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              DriverOrderCard(
                order: order,
                onAccept: () {
                  Navigator.of(context).pop();
                  _acceptOrder(order);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(availableOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'سفارش‌های در انتظار ناوگان',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'به‌روزرسانی',
            onPressed: () =>
                ref.read(availableOrdersProvider.notifier).fetchOrders(),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: 'خروج از حساب راننده',
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
      body: ordersAsync.when(
        data: (orders) {
          final centerMap =
              _driverLocation ??
              (orders.isNotEmpty
                  ? LatLng(orders.first.latitude, orders.first.longitude)
                  : const LatLng(36.3155, 59.5385));

          return Stack(
            children: [
              // ۱. لایه تمام‌صفحه نقشه (نیمه بالایی همیشه در دسترس است)
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: centerMap,
                    initialZoom: 13.0,
                    maxZoom: 18,
                    minZoom: 5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://map.ir/shiveh/xyz/1.0.0/Shiveh:Shiveh@EPSG:3857@png/{z}/{x}/{y}.png',
                      tileProvider: NetworkTileProvider(
                        headers: {
                          'x-api-key':
                              'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImp0aSI6ImI4NzlhYmM3YzQ5MGUwOGEwMzM5MzgxZjIyZTRlNGM5ZDg4MGRkYjY0YzYwMDJmN2I1ZDNkYjBmMGVlYzhhMmYyZjU3ZTlmMWI0MDA2ZjNkIn0.eyJhdWQiOiIzODYxNyIsImp0aSI6ImI4NzlhYmM3YzQ5MGUwOGEwMzM5MzgxZjIyZTRlNGM5ZDg4MGRkYjY0YzYwMDJmN2I1ZDNkYjBmMGVlYzhhMmYyZjU3ZTlmMWI0MDA2ZjNkIiwiaWF0IjoxNzc1NzQzNDIxLCJuYmYiOjE3NzU3NDM0MjEsImV4cCI6MTc3ODMzNTQyMSwic3ViIjoiIiwic2NvcGVzIjpbImJhc2ljIl19.TfxCB8bvzvnGpmheKbNmALdGUk38fnYdojQmpaHbFm26ltPCY2AWpkruKoP1rzWrMh3jLnOl_U-QH8x2hZWO6l3ufk0u0bMJwc3IxsVgOSUycM1WNdH0mebNH92MvE0DFD6Iod4oPW6tzCwMBkMXI2LIycDzeT0sRBVTcxw7XDvaeofw2P3FhuiJBWFDqFauc3fecInOF6vK3cuI1t0yrQCPdKa2WXyb6VUG2xsexTLoW4Elayt2fVKvQdTk_ITVhkjiT6YtK_pgyYcFVAJZr2TvEzCyQZ35CRa3tDBpG6_FKcRMMNiDlMvJmeAO8P9q-ESwXXUzuvHLzjiSmijrUA',
                        },
                      ),
                    ),
                    MarkerLayer(
                      markers: [
                        // مارکر موقعیت راننده
                        if (_driverLocation != null)
                          Marker(
                            point: _driverLocation!,
                            width: 44,
                            height: 44,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.local_shipping_rounded,
                                color: Color(0xFF2E7D32),
                                size: 26,
                              ),
                            ),
                          ),

                        // مارکرهای سفارش‌ها
                        ...orders.map(
                          (order) => Marker(
                            point: LatLng(order.latitude, order.longitude),
                            width: 48,
                            height: 48,
                            child: GestureDetector(
                              onTap: () => _showOrderBottomSheet(order),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.4),
                                      blurRadius: 6,
                                    ),
                                  ],
                                  border: Border.all(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.recycling_rounded,
                                  color: Colors.red,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ۲. دکمه موقعیت من (GPS) شناور روی نقشه
              Positioned(
                top: 16,
                right: 16,
                child: FloatingActionButton.small(
                  backgroundColor: Colors.white,
                  tooltip: 'موقعیت من',
                  onPressed: _isLoadingGps ? null : _handleGpsTap,
                  child: _isLoadingGps
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF2E7D32),
                          ),
                        )
                      : Icon(
                          _driverLocation != null
                              ? Icons.my_location
                              : Icons.location_searching,
                          color: _driverLocation != null
                              ? const Color(0xFF2E7D32)
                              : Colors.red,
                        ),
                ),
              ),

              // ۳. کرکره اسلایدی سفارش‌ها (نصف صفحه پیش‌فرض با قابلیت بالا و پایین کشیدن)
              DraggableScrollableSheet(
                initialChildSize: 0.50, // پیش‌فرض ۵۰٪ ارتفاع صفحه
                minChildSize: 0.16, // حداقل ارتفاع برای دیدن بخش اعظم نقشه
                maxChildSize: 0.92, // حداکثر ارتفاع برای دیدن کامل لیست
                snap: true,
                snapSizes: const [0.16, 0.50, 0.92],
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 10,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // نوار دستگیره کرکره
                        Center(
                          child: Container(
                            width: 44,
                            height: 4.5,
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),

                        // ردیف عنوان وضعیت سفارش‌ها
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'درخواست‌های اطراف شما (${orders.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Text(
                                'کرکره را برای تغییر نما بکشید',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 14),

                        // محتوای لیست درون کرکره
                        Expanded(
                          child: orders.isEmpty
                              ? ListView(
                                  controller: scrollController,
                                  children: const [
                                    SizedBox(height: 50),
                                    Center(
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.inbox_outlined,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'در حال حاضر سفارشی در انتظار پذیرش نیست.',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  itemCount: orders.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final order = orders[index];
                                    return DriverOrderCard(
                                      order: order,
                                      onAccept: () => _acceptOrder(order),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
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
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () =>
                    ref.read(availableOrdersProvider.notifier).fetchOrders(),
                child: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
