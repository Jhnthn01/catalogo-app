import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'catalogo_page.dart';
import 'auth_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://aesmdplpcxybjzmwnjbw.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFlc21kcGxwY3h5Ymp6bXduamJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU5MzQwNDIsImV4cCI6MjA5MTUxMDA0Mn0.Ixxuql-Mrem6zdOSLoWyWQ2YPithJCK3MWCwhF72_fQ',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      // Usamos un StreamBuilder para reaccionar a cambios de sesión en tiempo real
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          // Mientras se establece la conexión inicial
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final session = snapshot.data?.session;

          // Si hay sesión activa, vamos al Catálogo; si no, al Login
          if (session != null) {
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
