// lib/features/orders/presentation/widgets/driver_order_card.dart

import 'package:flutter/material.dart';
import 'package:waste_driver_app/core/utils/jalali_helper.dart';
import 'package:waste_driver_app/features/orders/data/driver_order_model.dart';

class DriverOrderCard extends StatelessWidget {
  final DriverOrderModel order;
  final VoidCallback onAccept;

  const DriverOrderCard({
    super.key,
    required this.order,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final shamsiDate = JalaliHelper.formatToShamsi(order.scheduledDate);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'درخواست #${order.id}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'در انتظار پذیرش',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.addressText,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
              ],
            ),
            if (order.plaque != null || order.unit != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 28),
                child: Text(
                  'پلاک: ${order.plaque ?? "-"} | واحد: ${order.unit ?? "-"}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  '$shamsiDate (${order.scheduledTimeSlot ?? "بازه عادی"})',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[800]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.check, size: 19),
                label: const Text(
                  'پذیرش مأموریت',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: onAccept,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
