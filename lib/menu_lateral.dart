import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

class MenuLateral extends StatelessWidget {
  const MenuLateral({super.key});

  // Función para obtener el rol del usuario actual
  Future<String?> _getUsuarioRol() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    final data = await Supabase.instance.client
        .from('perfiles')
        .select('rol')
        .eq('id', user.id)
        .single();
    
    return data['rol'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: FutureBuilder<String?>(
        future: _getUsuarioRol(),
        builder: (context, snapshot) {
          // Mientras carga el rol, mostramos un indicador o solo el fondo
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rol = snapshot.data;
          // Definimos si tiene permiso (admin o trabajador/empleado)
          final bool tieneAccesoInventario = rol == 'admin' || rol == 'empleado';

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  image: DecorationImage(
                    image: const NetworkImage('https://via.placeholder.com/350x150'),
                    fit: BoxFit.cover,
                    opacity: 0.3,
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'FERRETERÍA PRO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Gestión de Inventario',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              
              // OPCIÓN: CATÁLOGO (Visible para todos)
              ListTile(
                leading: const Icon(Icons.list, color: Colors.white),
                title: const Text('Catálogo', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false),
              ),

              // OPCIÓN: INVENTARIO (Condicional)
              if (tieneAccesoInventario)
                ListTile(
                  leading: const Icon(Icons.inventory, color: Colors.white),
                  title: const Text('Inventario', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false),
                ),

              const Divider(color: Colors.grey),

              // CERRAR SESIÓN
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.redAccent)),
                onTap: () => _mostrarDialogoCerrarSesion(context),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mostrarDialogoCerrarSesion(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text("Cerrar Sesión", style: TextStyle(color: Colors.white)),
          content: const Text("¿Estás seguro de que deseas salir?", style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar", style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                }
              },
              child: const Text("Salir", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}