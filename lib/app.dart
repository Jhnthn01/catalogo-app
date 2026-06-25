import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/features/auth/auth_page.dart';
import 'package:catalogo_digital_app/features/catalog/catalogo_page.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

class MyApp extends StatefulWidget {
  final bool initialPasswordRecovery;
  const MyApp({super.key, this.initialPasswordRecovery = false});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late StreamSubscription<AuthState> _authSub;
  bool _dialogoMostrado = false;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        // Schedule the dialog for after the current frame so the navigator is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mostrarCambioContrasena();
        });
      }
    });

    if (widget.initialPasswordRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mostrarCambioContrasena();
      });
    }
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  void _mostrarCambioContrasena() {
    if (_dialogoMostrado) return;
    _dialogoMostrado = true;

    final ctx = _navigatorKey.currentContext;
    if (ctx == null) {
      _dialogoMostrado = false;
      return;
    }

    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (sbCtx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock_reset, color: Colors.blue, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nueva Contraseña',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ingresa tu nueva contraseña (mínimo 6 caracteres):',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure1,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nueva contraseña',
                  labelStyle: const TextStyle(color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure1 ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () => setDialogState(() => obscure1 = !obscure1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.blue),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Confirmar contraseña',
                  labelStyle: const TextStyle(color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure2 ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () => setDialogState(() => obscure2 = !obscure2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.grey),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.blue),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _dialogoMostrado = false;
                passwordCtrl.dispose();
                confirmCtrl.dispose();
                Navigator.pop(dialogCtx);
              },
              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                final pass = passwordCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();

                if (pass.length < 6) {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    const SnackBar(
                      content: Text('La contraseña debe tener al menos 6 caracteres'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                if (pass != confirm) {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    const SnackBar(
                      content: Text('Las contraseñas no coinciden'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                try {
                  await Supabase.instance.client.auth.updateUser(
                    UserAttributes(password: pass),
                  );
                  _dialogoMostrado = false;
                  passwordCtrl.dispose();
                  confirmCtrl.dispose();
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  if (_navigatorKey.currentContext != null) {
                    ScaffoldMessenger.of(_navigatorKey.currentContext!).showSnackBar(
                      const SnackBar(
                        content: Text('Contraseña actualizada correctamente'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
              child: const Text('GUARDAR', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      navigatorKey: _navigatorKey,
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
