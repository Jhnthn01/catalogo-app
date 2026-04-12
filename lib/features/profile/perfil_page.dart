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
    if (user != null) {
      try {
        final data = await Supabase.instance.client
            .from('perfiles')
            .select()
            .eq('id', user.id)
            .single();

        setState(() {
          _nombreController.text = data['nombre'] ?? '';
          _telefonoController.text = data['telefono'] ?? '';
        });
      } catch (e) {
        debugPrint("Error cargando perfil: $e");
      }
    }
  }

  Future<void> _actualizarPerfil() async {
    setState(() => _cargando = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      await Supabase.instance.client.from('perfiles').update({
        'nombre': _nombreController.text,
        'telefono': _telefonoController.text,
      }).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Datos actualizados correctamente")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al guardar: $e")),
      );
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Mi Cuenta"),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _nombreController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Nombre Completo",
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _telefonoController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Teléfono Celular",
                prefixIcon: const Icon(Icons.phone, color: Colors.blue),
                labelStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
