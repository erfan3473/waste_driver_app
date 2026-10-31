// lib/features/mission/presentation/active_mission_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:waste_driver_app/core/constants/api_endpoints.dart';
import 'package:waste_driver_app/core/network/dio_client.dart';
import 'package:waste_driver_app/core/services/auth_storage.dart';
import 'package:waste_driver_app/features/mission/data/neshan_routing_service.dart';
import 'package:waste_driver_app/features/mission/presentation/widgets/weight_collection_sheet.dart';
import 'package:waste_driver_app/features/orders/presentation/driver_orders_screen.dart';
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

class _ActiveMissionScreenState extends ConsumerState<ActiveMissionScreen>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  WebSocketChannel? _wsChannel;
  StreamSubscription<Position>? _positionStream;

  LatLng? _driverCurrentLocation;
  double _currentBearing = 0.0;
  int _currentSpeedKmh = 0;
  String _missionStatus = 'ACCEPTED';

  List<LatLng> _routePoints = [];
  String _remainingDistance = '';
  String _remainingDuration = '';
  String _currentStepInstruction = '';
  bool _isLoadingGps = false;
  bool _isLoadingRoute = false;

  double _mapRotation = 0.0;
  AnimationController? _cameraAnimController;
  late final AnimationController _pulseAnimController;
  final Distance _distanceCalc = const Distance();

  bool _isNavigating = false;
  int _offRouteCounter = 0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _connectWebSocket();
    _initGpsAndFetchLocation();

    _mapController.mapEventStream.listen((event) {
      if (mounted) {
        setState(() {
          _mapRotation = _mapController.camera.rotation;
        });
      }
    });
  }

  void _resetRotation() {
    _animateCamera(
      targetCenter: _mapController.camera.center,
      targetZoom: _mapController.camera.zoom,
      targetRotation: 0.0,
    );
  }

  Future<void> _connectWebSocket() async {
    try {
      final token = await AuthStorage.getToken();
      final url =
          '${ApiEndpoints.orderTrackingWs(widget.orderId)}?role=driver&token=${token ?? ""}';
      final wsUri = Uri.parse(url);
      _wsChannel = WebSocketChannel.connect(wsUri);
    } catch (_) {}
  }

  void _animateCamera({
    required LatLng targetCenter,
    required double targetZoom,
    required double targetRotation,
    Duration duration = const Duration(milliseconds: 950),
  }) {
    _cameraAnimController?.stop();
    _cameraAnimController?.dispose();

    _cameraAnimController = AnimationController(
      vsync: this,
      duration: duration,
    );

    final startCenter = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;
    final startRotation = _mapController.camera.rotation;

    double diffRotation = (targetRotation - startRotation) % 360.0;
    if (diffRotation > 180.0) diffRotation -= 360.0;
    if (diffRotation < -180.0) diffRotation += 360.0;

    final animation = CurvedAnimation(
      parent: _cameraAnimController!,
      curve: Curves.fastOutSlowIn,
    );

    _cameraAnimController!.addListener(() {
      final double t = animation.value;
      final double lat =
          startCenter.latitude +
          (targetCenter.latitude - startCenter.latitude) * t;
      final double lng =
          startCenter.longitude +
          (targetCenter.longitude - startCenter.longitude) * t;
      final double zoom = startZoom + (targetZoom - startZoom) * t;
      final double rot = (startRotation + diffRotation * t) % 360.0;

      _mapController.move(LatLng(lat, lng), zoom);
      _mapController.rotate(rot);
    });

    _cameraAnimController!.forward();
  }

  void _trimPassedRoutePoints(LatLng currentPos) {
    if (_routePoints.length < 2) return;

    int closestIndex = -1;
    double minDistance = double.infinity;

    final int checkLimit = math.min(_routePoints.length, 12);
    for (int i = 0; i < checkLimit; i++) {
      final d = _distanceCalc.as(LengthUnit.Meter, currentPos, _routePoints[i]);
      if (d < minDistance) {
        minDistance = d;
        closestIndex = i;
      }
    }

    if (closestIndex > 0 && minDistance < 32.0) {
      setState(() {
        _routePoints.removeRange(0, closestIndex);
      });
      _offRouteCounter = 0;
    } else if (minDistance > 60.0) {
      _offRouteCounter++;
      if (_offRouteCounter >= 3 && !_isLoadingRoute) {
        _fetchNeshanRoute(currentPos, _currentBearing);
        _offRouteCounter = 0;
      }
    }
  }

  Future<void> _initGpsAndFetchLocation() async {
    setState(() => _isLoadingGps = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isLoadingGps = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'مکان‌یاب (GPS) گوشی خاموش است. لطفاً آن را روشن فرمایید.',
              ),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'تنظیمات',
                textColor: Colors.white,
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isLoadingGps = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLoadingGps = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );

      final driverLoc = LatLng(pos.latitude, pos.longitude);

      if (mounted) {
        setState(() {
          _driverCurrentLocation = driverLoc;
          _currentBearing = pos.heading;
          _currentSpeedKmh = (pos.speed > 0) ? (pos.speed * 3.6).round() : 0;
          _isLoadingGps = false;
        });

        _mapController.move(driverLoc, 15.5);
        _fetchNeshanRoute(driverLoc, pos.heading);
      }

      _startLiveStream();
    } catch (e) {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  Future<void> _fetchNeshanRoute(LatLng driverPos, double bearing) async {
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
          _routePoints = List.from(result.polylinePoints);
          _remainingDistance = result.distanceText;
          _remainingDuration = result.durationText;
          _currentStepInstruction = result.nextInstruction;
        });

        if (!_isNavigating) {
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
      }
      setState(() => _isLoadingRoute = false);
    }
  }

  void _startLiveStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 4,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) {
          final loc = LatLng(pos.latitude, pos.longitude);
          final speedKmh = (pos.speed > 0) ? (pos.speed * 3.6).round() : 0;

          if (mounted) {
            setState(() {
              _driverCurrentLocation = loc;
              _currentBearing = pos.heading;
              _currentSpeedKmh = speedKmh;
            });

            _trimPassedRoutePoints(loc);

            if (_isNavigating) {
              _animateCamera(
                targetCenter: loc,
                targetZoom: 17.8,
                targetRotation: pos.heading,
                duration: const Duration(milliseconds: 650),
              );
            }
          }

          if (_wsChannel != null) {
            final payload = {
              'action': 'location_update',
              'type': 'driver_location',
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              'bearing': pos.heading,
              'speed': speedKmh,
            };
            _wsChannel!.sink.add(jsonEncode(payload));
          }
        });
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

  void _startDrivingNavigation() {
    setState(() {
      _isNavigating = true;
    });

    _updateStatus('ON_THE_WAY');

    if (_driverCurrentLocation != null) {
      _animateCamera(
        targetCenter: _driverCurrentLocation!,
        targetZoom: 17.8,
        targetRotation: _currentBearing,
        duration: const Duration(milliseconds: 1100),
      );
    } else {
      _initGpsAndFetchLocation();
    }
  }

  IconData _getManeuverIcon(String instruction) {
    if (instruction.contains('چپ')) return Icons.turn_left_rounded;
    if (instruction.contains('راست')) return Icons.turn_right_rounded;
    if (instruction.contains('میدان')) return Icons.roundabout_right_rounded;
    if (instruction.contains('دور') || instruction.contains('برگردان')) {
      return Icons.u_turn_left_rounded;
    }
    return Icons.straight_rounded;
  }

  @override
  void dispose() {
    _pulseAnimController.dispose();
    _cameraAnimController?.dispose();
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
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.citizenLocation,
              initialZoom: 15.0,
              maxZoom: 18,
              minZoom: 5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _isNavigating) {
                  setState(() => _isNavigating = false);
                }
              },
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

              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: _isNavigating ? 7.0 : 5.5,
                      color: const Color(0xFF1976D2),
                    ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.citizenLocation,
                    width: 50,
                    height: 50,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),

                  if (_driverCurrentLocation != null)
                    Marker(
                      point: _driverCurrentLocation!,
                      width: 72,
                      height: 72,
                      child: AnimatedBuilder(
                        animation: _pulseAnimController,
                        builder: (context, child) {
                          final pulseScale =
                              1.0 + (_pulseAnimController.value * 0.28);
                          final pulseOpacity =
                              (1.0 - _pulseAnimController.value).clamp(
                                0.15,
                                0.5,
                              );

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_isNavigating)
                                Transform.scale(
                                  scale: pulseScale,
                                  child: Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(
                                        0xFF00E676,
                                      ).withOpacity(pulseOpacity),
                                    ),
                                  ),
                                ),

                              Transform.rotate(
                                angle: _currentBearing * (math.pi / 180),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (_isNavigating)
                                      CustomPaint(
                                        size: const Size(64, 64),
                                        painter: _HeadingConePainter(),
                                      ),
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                        boxShadow: [
                                          BoxShadow(
                                            color: _isNavigating
                                                ? const Color(
                                                    0xFF2E7D32,
                                                  ).withOpacity(0.45)
                                                : Colors.black.withOpacity(
                                                    0.25,
                                                  ),
                                            blurRadius: _isNavigating ? 10 : 6,
                                            spreadRadius: _isNavigating ? 2 : 0,
                                          ),
                                        ],
                                        border: Border.all(
                                          color: _isNavigating
                                              ? const Color(0xFF2E7D32)
                                              : Colors.white,
                                          width: 2.2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.navigation_rounded,
                                        color: Color(0xFF2E7D32),
                                        size: 26,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),

          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                color: _isNavigating ? const Color(0xFF1B1D21) : Colors.black87,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isNavigating
                      ? const Color(0xFF00E676)
                      : Colors.white24,
                  width: _isNavigating ? 1.6 : 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isNavigating
                        ? const Color(0xFF00E676).withOpacity(0.22)
                        : Colors.black.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _isNavigating
                            ? const Color(0xFF00E676)
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getManeuverIcon(_currentStepInstruction),
                        color: _isNavigating
                            ? Colors.black
                            : Colors.lightGreenAccent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isNavigating)
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00E676),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'ناوبری فعال به سمت شهروند',
                                  style: TextStyle(
                                    color: Color(0xFF00E676),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          Text(
                            _currentStepInstruction.isNotEmpty
                                ? _currentStepInstruction
                                : 'در حال هدایت به سمت مقصد...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _remainingDuration.isNotEmpty
                                ? 'زمان: $_remainingDuration | مسافت: $_remainingDistance'
                                : 'نقشه آماده راهبری است',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_currentSpeedKmh',
                            style: TextStyle(
                              color: _isNavigating
                                  ? const Color(0xFF00E676)
                                  : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'km/h',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 8.5,
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

          Positioned(
            left: 16,
            bottom: 175,
            child: GestureDetector(
              onTap: _resetRotation,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Transform.rotate(
                  angle: -(_mapRotation * math.pi / 180),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 3,
                            height: 13,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(2),
                                topRight: Radius.circular(2),
                              ),
                            ),
                          ),
                          Container(
                            width: 3,
                            height: 13,
                            decoration: const BoxDecoration(
                              color: Colors.grey,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(2),
                                bottomRight: Radius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Positioned(
                        top: 2,
                        child: Text(
                          'N',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 2,
                        child: Text(
                          'S',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            right: 16,
            bottom: 175,
            child: FloatingActionButton.small(
              backgroundColor: _isNavigating
                  ? const Color(0xFF2E7D32)
                  : Colors.white,
              tooltip: 'قفل دوربین روی من',
              onPressed: () {
                if (_driverCurrentLocation != null) {
                  setState(() => _isNavigating = true);
                  _animateCamera(
                    targetCenter: _driverCurrentLocation!,
                    targetZoom: 17.8,
                    targetRotation: _currentBearing,
                  );
                } else {
                  _initGpsAndFetchLocation();
                }
              },
              child: Icon(
                _isNavigating ? Icons.navigation : Icons.my_location,
                color: _isNavigating ? Colors.white : const Color(0xFF2E7D32),
              ),
            ),
          ),

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
                          onPressed: _startDrivingNavigation,
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
                          onPressed: () {
                            setState(() => _isNavigating = false);
                            _updateStatus('ARRIVED');
                          },
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

class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF00E676).withOpacity(0.42),
              const Color(0xFF00E676).withOpacity(0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width / 2, size.height / 2),
              radius: size.width / 2,
            ),
          );

    final path = Path()
      ..moveTo(size.width / 2, size.height / 2)
      ..lineTo(size.width * 0.15, 0)
      ..arcToPoint(
        Offset(size.width * 0.85, 0),
        radius: Radius.circular(size.width / 2),
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
