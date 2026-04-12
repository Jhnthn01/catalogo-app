import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nombreController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  // 1. Mejoramos la sincronización para que sea más insistente
  Future<void> _syncPerfilTrasRegistro({
    required String nombre,
    required String telefono,
  }) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    // Intentamos actualizar. Si falla (porque el trigger aún no termina),
    // esperamos un segundo y reintentamos una vez.
    try {
      final updateData = <String, dynamic>{
        'id': uid,
        'nombre': nombre,
        'telefono': telefono,
      };

      // Si el trigger de la BD falló, upsert creará el registro. Si ya existe, lo actualiza.
      await Supabase.instance.client
          .from('perfiles')
          .upsert(updateData);

    } catch (e) {
      debugPrint('Error en sincronización: $e');
    }
  }

  // 2. Ajustamos el flujo de autenticación
  Future<void> _handleAuth() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      if (_isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        final nombre = _nombreController.text.trim();
        final telefono = _telefonoController.text.trim();

        if (nombre.isEmpty) {
          throw Exception('El nombre es obligatorio');
        }

        // Registro
        final response = await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {'nombre': nombre, 'telefono': telefono},
        );

        // Si el login es automático tras el registro (o forzamos uno)
        if (response.session != null || response.user != null) {
          // Si no hay sesión, logueamos manualmente (sucede en algunos configs)
          if (response.session == null) {
            await Supabase.instance.client.auth.signInWithPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );
          }

          // Sincronizamos los datos adicionales en la tabla 'perfiles'
          await _syncPerfilTrasRegistro(nombre: nombre, telefono: telefono);
        }
      }

      if (!mounted) return;

      // Éxito: Navegamos a la pantalla principal
      Navigator.pushReplacementNamed(context, '/');
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person, size: 80, color: Colors.blue),
              const SizedBox(height: 20),
              Text(
                _isLogin ? 'BIENVENIDO' : 'CREAR CUENTA',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              _buildField('Correo Electrónico', _emailController, false),
              const SizedBox(height: 15),
              _buildPasswordField(),
              if (!_isLogin) ...[
                const SizedBox(height: 15),
                _buildField(
                  'Nombre completo',
                  _nombreController,
                  false,
                  hint: 'Cómo te llamamos en la tienda',
                ),
                const SizedBox(height: 15),
                _buildField(
                  'Teléfono (opcional)',
                  _telefonoController,
                  false,
                  keyboardType: TextInputType.phone,
                  hint: 'Para avisos sobre tu pedido',
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d+\s\-().]')),
                  ],
                ),
              ],
              const SizedBox(height: 30),
              _loading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onPressed: _handleAuth,
                        child: Text(_isLogin ? 'INGRESAR' : 'REGISTRARME'),
                      ),
                    ),
              TextButton(
                onPressed: () => setState(() {
                  _isLogin = !_isLogin;
                  if (_isLogin) {
                    _nombreController.clear();
                    _telefonoController.clear();
                  }
                }),
                child: Text(
                  _isLogin
                      ? '¿No tienes cuenta? Regístrate'
                      : '¿Ya tienes cuenta? Ingresa',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Contraseña',
        labelStyle: const TextStyle(color: Colors.grey),
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? 'Mostrar' : 'Ocultar',
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.grey,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    bool isPassword, {
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        labelStyle: const TextStyle(color: Colors.grey),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.grey),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.blue),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
