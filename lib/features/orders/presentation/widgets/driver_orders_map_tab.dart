// lib/features/orders/presentation/widgets/driver_orders_map_tab.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:waste_driver_app/features/orders/data/driver_order_model.dart';
import 'driver_order_card.dart';

class DriverOrdersMapTab extends StatelessWidget {
  final List<DriverOrderModel> orders;
  final LatLng? driverPosition;
  final void Function(DriverOrderModel order) onAcceptOrder;

  const DriverOrdersMapTab({
    super.key,
    required this.orders,
    required this.driverPosition,
    required this.onAcceptOrder,
  });

  void _showOrderBottomSheet(BuildContext context, DriverOrderModel order) {
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
                  onAcceptOrder(order);
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
    final initialCenter =
        driverPosition ??
        (orders.isNotEmpty
            ? LatLng(orders.first.latitude, orders.first.longitude)
            : const LatLng(36.3155, 59.5385));

    return FlutterMap(
      options: MapOptions(initialCenter: initialCenter, initialZoom: 13.0),
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
            // ۱. مارکر سبز راننده
            if (driverPosition != null)
              Marker(
                point: driverPosition!,
                width: 46,
                height: 46,
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

            // ۲. مارکرهای زنده کلیه سفارش‌های در انتظار با امکان کلیک
            ...orders.map(
              (order) => Marker(
                point: LatLng(order.latitude, order.longitude),
                width: 48,
                height: 48,
                child: GestureDetector(
                  onTap: () => _showOrderBottomSheet(context, order),
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
                      border: Border.all(color: Colors.red, width: 2),
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
    );
  }
}
