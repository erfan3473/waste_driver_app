// lib/features/orders/presentation/providers/available_orders_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:waste_driver_app/core/network/dio_client.dart';
import 'package:waste_driver_app/features/orders/data/driver_order_model.dart';

class AvailableOrdersNotifier
    extends StateNotifier<AsyncValue<List<DriverOrderModel>>> {
  final Ref ref;

  AvailableOrdersNotifier(this.ref) : super(const AsyncValue.loading()) {
    fetchOrders();
  }

  /// دریافت لیست از REST API (پشتیبانی از موقعیت راننده جهت مرتب‌سازی فاصله‌ای)
  Future<void> fetchOrders() async {
    try {
      final dio = ref.read(dioProvider);

      double? lat;
      double? lng;

      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 4),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}

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

  /// اضافه شدن آنی سفارش جدید دریافتی از وب‌سوکت
  void addOrderRealtime(DriverOrderModel newOrder) {
    state.whenData((currentList) {
      // جلوگیری از اضافه شدن رکورد تکراری
      if (!currentList.any((o) => o.id == newOrder.id)) {
        state = AsyncValue.data([newOrder, ...currentList]);
      }
    });
  }

  /// حذف آنی سفارش برداشته‌شده یا لغو‌شده از وب‌سوکت
  void removeOrderRealtime(int orderId) {
    state.whenData((currentList) {
      final updatedList = currentList.where((o) => o.id != orderId).toList();
      state = AsyncValue.data(updatedList);
    });
  }
}

final availableOrdersNotifierProvider =
    StateNotifierProvider<
      AvailableOrdersNotifier,
      AsyncValue<List<DriverOrderModel>>
    >((ref) => AvailableOrdersNotifier(ref));
