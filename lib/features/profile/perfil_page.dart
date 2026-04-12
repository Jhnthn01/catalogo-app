import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await Supabase.instance.client
          .from('perfiles')
          .select()
          .eq('id', user.id)
          .maybeSingle(); // <--- Cambiado para evitar error si no hay datos

      if (data != null && mounted) {
        setState(() {
          _nombreController.text = data['nombre'] ?? '';
          _telefonoController.text = data['telefono'] ?? '';
        });
      }
    } catch (e) {
      debugPrint("Error cargando perfil: $e");
    }
  }

  Future<void> _actualizarPerfil() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Validación simple
    if (_nombreController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("El nombre no puede estar vacío")),
      );
      return;
    }

    setState(() => _cargando = true);
    try {
      // Intentamos actualizar con upsert por si la fila no existe
      await Supabase.instance.client.from('perfiles').upsert({
        'id': user.id,
        'nombre': _nombreController.text.trim(),
        'telefono': _telefonoController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("¡Datos actualizados correctamente!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al guardar: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ... Tu diseño actual de build se mantiene igual ...
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text("Mi Cuenta")),
      body: SingleChildScrollView( // Añadido para evitar error de overflow con teclado
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: "Nombre Completo"),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _telefonoController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Teléfono Celular",
                prefixIcon: Icon(Icons.phone, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cargando ? null : _actualizarPerfil,
                child: Text(_cargando ? "Guardando..." : "GUARDAR CAMBIOS"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}