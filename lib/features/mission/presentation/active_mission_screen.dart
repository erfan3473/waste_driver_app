// lib/features/mission/presentation/active_mission_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../data/neshan_routing_service.dart';
import 'widgets/weight_collection_sheet.dart';

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
  String _missionStatus = 'ACCEPTED';

  // متغیرهای مسیریابی نشان
  List<LatLng> _routePoints = [];
  String _remainingDistance = '';
  String _remainingDuration = '';
  String _currentStepInstruction = '';
  bool _isLoadingRoute = false;

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

  /// دریافت مسیر بهینه نشان و رسم خط روی نقشه
  Future<void> _fetchNeshanRoute(LatLng currentPos, double bearing) async {
    if (_isLoadingRoute) return;
    _isLoadingRoute = true;

    final result = await NeshanRoutingService.getTrafficRoute(
      origin: currentPos,
      destination: widget.citizenLocation,
      bearing: bearing,
    );

    if (result != null && mounted) {
      setState(() {
        _routePoints = result.polylinePoints;
        _remainingDistance = result.distanceText;
        _remainingDuration = result.durationText;
        _currentStepInstruction = result.nextInstruction;
      });
    }
    _isLoadingRoute = false;
  }

  void _startLocationStreaming() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 6,
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) {
            final latLng = LatLng(pos.latitude, pos.longitude);

            // استعلام اولیه یا به‌روزرسانی مسیر در صورت خالی بودن
            if (_routePoints.isEmpty) {
              _fetchNeshanRoute(latLng, pos.heading);
            }

            setState(() {
              _driverCurrentLocation = latLng;
              _currentBearing = pos.heading;
            });

            // ارسال زنده موقعیت به وب‌سوکت برای رهگیری توسط شهروند
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
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      appBar: AppBar(
        title: Text('مأموریت سفارش #${widget.orderId}'),
        centerTitle: true,
        actions: [
          // دکمه بازخوانی دستی مسیر
          IconButton(
            icon: const Icon(Icons.alt_route_rounded),
            tooltip: 'مسیریابی مجدد',
            onPressed: () {
              if (_driverCurrentLocation != null) {
                _fetchNeshanRoute(_driverCurrentLocation!, _currentBearing);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ۱. لایه نقشه و ترسیم خط مسیر نشان
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

              // رسم خط چندضلعی مسیر ترافیکی نشان
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.5,
                      color: const Color(0xFF1976D2),
                    ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  // مارکر موقعیت شهروند (مقصد)
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

                  // مارکر موقعیت لحظه‌ای خودروی راننده با زاویه چرخش
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

          // ۲. نوار شناور راهنمای مسیر و زمان تخمینی سفر (ETA) در بالای نقشه
          if (_remainingDuration.isNotEmpty ||
              _currentStepInstruction.isNotEmpty)
            Positioned(
              top: 12,
              left: 14,
              right: 14,
              child: Card(
                elevation: 6,
                color: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.navigation_rounded,
                        color: Colors.lightGreenAccent,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentStepInstruction,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'زمان تقریبی: $_remainingDuration | مسافت: $_remainingDistance',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ۳. پنل کنترل وضعیت مأموریت در پایین صفحه
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
