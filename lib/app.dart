import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/features/auth/auth_page.dart';
import 'package:catalogo_digital_app/features/catalog/catalogo_page.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      navigatorObservers: [routeObserver],
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final session = snapshot.data?.session;

          if (session != null) {
            // Load stores at startup so tienda_id is available globally
            TiendaService().cargarTiendas();
            return const CatalogoPage();
          } else {
            return const AuthPage();
          }
        },
      ),
      routes: {
        '/login': (context) => const AuthPage(),
        '/catalogo': (context) => const CatalogoPage(),
      },
    );
  }
}
