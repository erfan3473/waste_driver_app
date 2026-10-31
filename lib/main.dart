// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/auth_storage.dart';
import 'features/auth/presentation/driver_login_screen.dart';
import 'features/orders/presentation/driver_orders_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loggedIn = await AuthStorage.isLoggedIn();

  runApp(ProviderScope(child: WasteDriverApp(isLoggedIn: loggedIn)));
}

class WasteDriverApp extends StatelessWidget {
  final bool isLoggedIn;
  const WasteDriverApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سامانه ناوگان جمع‌آوری',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'IRANSans',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: isLoggedIn ? const DriverOrdersScreen() : const DriverLoginScreen(),
    );
  }
}
