// lib/features/orders/presentation/widgets/driver_orders_list_tab.dart

import 'package:flutter/material.dart';
import 'package:waste_driver_app/features/orders/data/driver_order_model.dart';
import 'driver_order_card.dart';

class DriverOrdersListTab extends StatelessWidget {
  final List<DriverOrderModel> orders;
  final Future<void> Function() onRefresh;
  final void Function(DriverOrderModel order) onAcceptOrder;

  const DriverOrdersListTab({
    super.key,
    required this.orders,
    required this.onRefresh,
    required this.onAcceptOrder,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            Center(
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'در حال حاضر سفارشی در انتظار پذیرش وجود ندارد.',
                    style: TextStyle(color: Colors.grey, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final order = orders[index];
          return DriverOrderCard(
            order: order,
            onAccept: () => onAcceptOrder(order),
          );
        },
      ),
    );
  }
}
