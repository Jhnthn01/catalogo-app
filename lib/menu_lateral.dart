import 'package:catalogo_digital_app/mis_pedidos_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'perfil_page.dart'; // Asegúrate de crear este archivo

class MenuLateral extends StatelessWidget {
  const MenuLateral({super.key});

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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final rol = snapshot.data;
          final bool tieneAccesoInventario =
              rol == 'admin' || rol == 'empleado';

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.8),
                  image: const DecorationImage(
                    image: NetworkImage('https://via.placeholder.com/350x150'),
                    fit: BoxFit.cover,
                    opacity: 0.2,
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
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Panel de Control',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // 1. MI CUENTA / PERFIL (En primer lugar)
              ListTile(
                leading: const Icon(
                  Icons.manage_accounts,
                  color: Colors.blueAccent,
                ),
                title: const Text(
                  'Mi Cuenta',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: const Text(
                  'Editar mis datos',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(context); // Cierra el drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const PerfilPage()),
                  );
                },
              ),

              // LÍNEA DIVISORIA DE SECCIÓN
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 15.0),
                child: Divider(color: Colors.white24, thickness: 1),
              ),

              // 2. CATÁLOGO
              ListTile(
                leading: const Icon(Icons.storefront, color: Colors.white70),
                title: const Text(
                  'Catálogo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/',
                  (route) => false,
                ),
              ),

              // 3. NUEVA OPCIÓN: MIS PEDIDOS
              ListTile(
                leading: const Icon(
                  Icons.shopping_bag_outlined,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Mis Pedidos',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context); // Cerrar drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MisPedidosPage(),
                    ),
                  );
                },
              ),

              // 4. INVENTARIO (Solo para Admin/Empleado)
              if (tieneAccesoInventario)
                ListTile(
                  leading: const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Inventario',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/',
                    (route) => false,
                  ),
                ),

              const Divider(color: Colors.white10),

              // CERRAR SESIÓN
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(color: Colors.redAccent),
                ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            "Cerrar Sesión",
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            "¿Estás seguro de que deseas salir de la aplicación?",
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Cancelar",
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  );
                }
              },
              child: const Text(
                "Salir ahora",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
