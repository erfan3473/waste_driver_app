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
import '../../orders/presentation/driver_orders_screen.dart';
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
  bool _isLoadingGps = false;
  bool _isLoadingRoute = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _connectWebSocket();
    _initGpsAndStartRouting();
  }

  void _connectWebSocket() {
    final wsUri = Uri.parse(ApiEndpoints.orderTrackingWs(widget.orderId));
    _wsChannel = WebSocketChannel.connect(wsUri);
  }

  /// مدیریت کلیک روی دکمه اختصاصی GPS و خطایابی خودکار
  Future<void> _handleGpsButtonTap() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'مکان‌یاب (GPS) گوشی خاموش است. لطفاً آن را روشن فرمایید.',
          ),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'تنظیمات GPS',
            textColor: Colors.white,
            onPressed: () => Geolocator.openLocationSettings(),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('دسترسی به موقعیت مکانی داده نشد.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'دسترسی لوکیشن مسدود است؛ از تنظیمات برنامه فعال کنید.',
          ),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'مجوزها',
            textColor: Colors.white,
            onPressed: () => Geolocator.openAppSettings(),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    // اگر قبلاً لوکیشن داشتیم، فقط دوربین نقشه را به موقعیت راننده می‌بریم و روت را تازه می‌کنیم
    if (_driverCurrentLocation != null) {
      _mapController.move(_driverCurrentLocation!, 16.5);
      _requestRouteFromNeshan(_driverCurrentLocation!, _currentBearing);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('موقعیت راننده در مرکز نقشه قرار گرفت.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // در غیر این صورت، دریافت مجدد موقعیت از ماهواره
    await _initGpsAndStartRouting();
  }

  /// دریافت قطعی موقعیت راننده و تنها پس از آن، شروع مسیریابی
  Future<void> _initGpsAndStartRouting() async {
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
              action: SnackBarAction(
                label: 'تنظیمات',
                textColor: Colors.white,
                onPressed: () => Geolocator.openLocationSettings(),
              ),
              backgroundColor: Colors.orange,
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
              const SnackBar(content: Text('دسترسی به موقعیت مکانی داده نشد.')),
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
                'دسترسی لوکیشن مسدود است؛ از تنظیمات برنامه دسترسی را فعال کنید.',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'تنظیمات',
                textColor: Colors.white,
                onPressed: () => Geolocator.openAppSettings(),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      // دریافت امن موقعیت بدون رها کردن اکسپشن کنترل‌نشده
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final driverLoc = LatLng(pos.latitude, pos.longitude);

      if (mounted) {
        setState(() {
          _driverCurrentLocation = driverLoc;
          _currentBearing = pos.heading;
          _isLoadingGps = false;
        });

        _requestRouteFromNeshan(driverLoc, pos.heading);
      }

      _startLiveTrackingStream();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingGps = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در دریافت مختصات GPS راننده: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// استعلام مسیر ترافیکی نشان
  Future<void> _requestRouteFromNeshan(LatLng driverPos, double bearing) async {
    if (_isLoadingRoute) return;
    setState(() => _isLoadingRoute = true);

    final result = await NeshanRoutingService.getTrafficRoute(
      origin: driverPos,
      destination: widget.citizenLocation,
      bearing: bearing,
    );

    if (mounted) {
      if (result != null && result.polylinePoints.isNotEmpty) {
        setState(() {
          _routePoints = result.polylinePoints;
          _remainingDistance = result.distanceText;
          _remainingDuration = result.durationText;
          _currentStepInstruction = result.nextInstruction;
        });

        try {
          final bounds = LatLngBounds(driverPos, widget.citizenLocation);
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.symmetric(
                horizontal: 50,
                vertical: 130,
              ),
            ),
          );
        } catch (_) {}
      }
      setState(() => _isLoadingRoute = false);
    }
  }

  void _startLiveTrackingStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 6,
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (pos) {
            final latLng = LatLng(pos.latitude, pos.longitude);

            if (mounted) {
              setState(() {
                _driverCurrentLocation = latLng;
                _currentBearing = pos.heading;
              });
            }

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
      if (mounted) setState(() => _missionStatus = statusKey);
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
          // ۱. لایه نقشه
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.citizenLocation,
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ariobonyantoos.waste_driver_app',
              ),

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

          // ۲. نوار وضعیت راهنمای مسیر یا وضعیت اتصال ماهواره در بالای صفحه
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
                child: _isLoadingGps
                    ? Row(
                        children: const [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'در حال دریافت موقعیت دقیق خودرو از ماهواره GPS...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      )
                    : _isLoadingRoute
                    ? Row(
                        children: const [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.lightGreenAccent,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'موقعیت دریافت شد؛ در حال محاسبه بهترین مسیر نشان...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
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
                                  _currentStepInstruction.isNotEmpty
                                      ? _currentStepInstruction
                                      : (_driverCurrentLocation == null
                                            ? 'سیگنال GPS نامشخص (دکمه پایین را لمس کنید)'
                                            : 'حرکت به سمت مبدأ پسماند'),
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
                                  _remainingDuration.isNotEmpty
                                      ? 'مدت سفر: $_remainingDuration | مسافت: $_remainingDistance'
                                      : 'نقشه آماده راهبری است',
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

          // ۳. 🎯 دکمه اختصاصی بررسی وضعیت و تمرکز روی GPS راننده روی نقشه
          Positioned(
            right: 16,
            bottom: 175,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white,
              tooltip: 'موقعیت GPS راننده',
              onPressed: _isLoadingGps ? null : _handleGpsButtonTap,
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
                      _driverCurrentLocation != null
                          ? Icons.my_location
                          : Icons.location_disabled,
                      color: _driverCurrentLocation != null
                          ? const Color(0xFF2E7D32)
                          : Colors.red,
                    ),
            ),
          ),

          // ۴. پنل مأموریت و دکمه‌های وضعیت در پایین صفحه
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
                          onPressed: () async {
                            final total = await showModalBottomSheet<int>(
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

                            if (total != null && context.mounted) {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  title: const Text(
                                    'تسویه نهایی با موفقیت انجام شد',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  content: Text(
                                    'مبلغ $total تومان به کیف پول شهروند و دستمزد راننده واریز گردید.',
                                  ),
                                  actions: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF2E7D32,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        Navigator.of(
                                          context,
                                        ).pushAndRemoveUntil(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const DriverOrdersScreen(),
                                          ),
                                          (route) => false,
                                        );
                                      },
                                      child: const Text(
                                        'بازگشت به لیست سفارش‌ها',
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
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
