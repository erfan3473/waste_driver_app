// lib/features/mission/presentation/active_mission_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:waste_driver_app/core/constants/api_endpoints.dart';
import 'package:waste_driver_app/core/network/dio_client.dart';
import 'package:waste_driver_app/features/mission/presentation/widgets/weight_collection_sheet.dart'
    show WeightCollectionSheet;
import 'package:web_socket_channel/web_socket_channel.dart';

class ActiveMissionScreen extends ConsumerStatefulWidget {
  final int orderId;
  final LatLng citizenLocation;
  final String addressText;

  const ActiveMissionScreen({
    super.key,
    required this.orderId,
    required this.citizenLocation,
    required this.addressText,
  });

  @override
  ConsumerState<ActiveMissionScreen> createState() =>
      _ActiveMissionScreenState();
}

class _ActiveMissionScreenState extends ConsumerState<ActiveMissionScreen> {
  late final MapController _mapController;
  WebSocketChannel? _wsChannel;
  StreamSubscription<Position>? _positionStream;

  LatLng? _driverCurrentLocation;
  double _currentBearing = 0.0;
  String _missionStatus = 'ACCEPTED'; // ACCEPTED, ON_THE_WAY, ARRIVED

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _connectWebSocket();
    _startLocationStreaming();
  }

  void _connectWebSocket() {
    final wsUri = Uri.parse(ApiEndpoints.orderTrackingWs(widget.orderId));
    _wsChannel = WebSocketChannel.connect(wsUri);
  }

  void _startLocationStreaming() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // ارسال بسته در هر ۵ متر جابجایی
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) {
            final latLng = LatLng(pos.latitude, pos.longitude);

            setState(() {
              _driverCurrentLocation = latLng;
              _currentBearing = pos.heading;
            });

            // مخابره موقعیت زنده به وب‌سوکت برای اپلیکیشن شهروند
            if (_wsChannel != null) {
              final payload = {
                'type': 'driver_location',
                'latitude': pos.latitude,
                'longitude': pos.longitude,
                'bearing': pos.heading,
              };
              _wsChannel!.sink.add(jsonEncode(payload));
            }
          },
        );
  }

  Future<void> _updateStatus(String statusKey) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        'driver/requests/${widget.orderId}/update-status/',
        data: {'status': statusKey},
      );
      setState(() => _missionStatus = statusKey);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطا در تغییر وضعیت: $e')));
      }
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _wsChannel?.sink.close();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('مأموریت سفارش #${widget.orderId}'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // نقشه هدایت ناوگان
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.citizenLocation,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ariobonyantoos.waste_driver_app',
              ),
              MarkerLayer(
                markers: [
                  // مارکر مقصد (محل استقرار شهروند)
                  Marker(
                    point: widget.citizenLocation,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 44,
                    ),
                  ),

                  // مارکر موقعیت زنده راننده
                  if (_driverCurrentLocation != null)
                    Marker(
                      point: _driverCurrentLocation!,
                      width: 44,
                      height: 44,
                      child: Transform.rotate(
                        angle: _currentBearing * (3.1415926535 / 180),
                        child: const Icon(
                          Icons.local_shipping,
                          color: Color(0xFF2E7D32),
                          size: 40,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // پنل وضعیت و عملیات در پایین صفحه
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مقصد: ${widget.addressText}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const Divider(height: 18),

                    if (_missionStatus == 'ACCEPTED')
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.navigation_outlined),
                          label: const Text('شروع حرکت به سمت مقصد'),
                          onPressed: () => _updateStatus('ON_THE_WAY'),
                        ),
                      )
                    else if (_missionStatus == 'ON_THE_WAY')
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.pin_drop),
                          label: const Text('رسیدم به محل شهروند'),
                          onPressed: () => _updateStatus('ARRIVED'),
                        ),
                      )
                    else if (_missionStatus == 'ARRIVED')
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.scale_rounded),
                          label: const Text('توزین و تسویه پسماندها'),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                              ),
                              builder: (_) => WeightCollectionSheet(
                                orderId: widget.orderId,
                              ),
                            );
                          },
                        ),
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
