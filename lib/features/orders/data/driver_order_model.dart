// lib/features/orders/data/driver_order_model.dart

class DriverOrderModel {
  final int id;
  final String status;
  final double latitude;
  final double longitude;
  final String addressText;
  final String? plaque;
  final String? unit;
  final String? scheduledDate;
  final String? scheduledTimeSlot;
  final String createdAt;

  DriverOrderModel({
    required this.id,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.addressText,
    this.plaque,
    this.unit,
    this.scheduledDate,
    this.scheduledTimeSlot,
    required this.createdAt,
  });

  factory DriverOrderModel.fromJson(Map<String, dynamic> json) {
    return DriverOrderModel(
      id: json['id'] as int,
      status: json['status'] as String? ?? 'PENDING',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      addressText: json['address_text'] as String? ?? '',
      plaque: json['plaque'] as String?,
      unit: json['unit'] as String?,
      scheduledDate: json['scheduled_date'] as String?,
      scheduledTimeSlot: json['scheduled_time_slot'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}