import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GestionRolesPage extends StatefulWidget {
  const GestionRolesPage({super.key});

  @override
  State<GestionRolesPage> createState() => _GestionRolesPageState();
}

class _GestionRolesPageState extends State<GestionRolesPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _usuarios = [];
  bool _isLoading = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  final List<String> _rolesDisponibles = [
    'admin',
    'gerente',
    'almacenista',
    'despachador',
    'vendedor',
    'cajero',
    'cliente'
  ];

  @override
  void initState() {
    super.initState();
    _fetchUsuarios();
  }

  Future<void> _fetchUsuarios() async {
    setState(() => _isLoading = true);
    try {
      var query = _supabase.from('perfiles').select('id, nombre, email, rol');

      if (_searchQuery.isNotEmpty) {
        query = query.or(
            'nombre.ilike.%$_searchQuery%,email.ilike.%$_searchQuery%');
      }

      final data = await query.order('nombre', ascending: true);

      if (mounted) {
        setState(() {
          _usuarios = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error cargando usuarios: $e")),
        );
      }
    }
  }

  Future<void> _cambiarRol(String userId, String nuevoRol) async {
    // Evitar que el administrador se quite su propio rol (seguridad básica frontal)
    if (userId == _supabase.auth.currentUser?.id && nuevoRol != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No puedes quitarte el rol de admin a ti mismo."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      await _supabase.from('perfiles').update({'rol': nuevoRol}).eq('id', userId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Rol actualizado con éxito a '$nuevoRol'"),
            backgroundColor: Colors.green,
          ),
        );
        _fetchUsuarios(); // Recargar la lista
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error actualizando rol: $e (Asegúrate de haber corrido las políticas SQL en Supabase)"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Color _getColorParaRol(String rol) {
    switch (rol) {
      case 'admin':
        return Colors.redAccent;
      case 'gerente':
        return Colors.purpleAccent;
      case 'almacenista':
        return Colors.orangeAccent;
      case 'despachador':
        return Colors.amberAccent;
      case 'vendedor':
        return Colors.blueAccent;
      case 'cajero':
        return Colors.tealAccent;
      default:
        return Colors.grey; // cliente
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Gestión de Usuarios y Roles"),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(15),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  _searchQuery = val;
                  _fetchUsuarios();
                },
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Buscar por nombre o correo...",
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.search, color: Colors.blue),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _usuarios.isEmpty
                    ? const Center(
                        child: Text("No se encontraron usuarios",
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _usuarios.length,
                        itemBuilder: (context, index) {
                          final user = _usuarios[index];
                          final rolActual = user['rol'] ?? 'cliente';
                          
                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              title: Text(
                                user['nombre'] ?? 'Sin Nombre',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    user['email'] ?? 'Sin correo',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getColorParaRol(rolActual).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: _getColorParaRol(rolActual)),
                                    ),
                                    child: Text(
                                      rolActual.toString().toUpperCase(),
                                      style: TextStyle(
                                        color: _getColorParaRol(rolActual),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  dropdownColor: const Color(0xFF2C2C2C),
                                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                                  items: _rolesDisponibles.map((String rol) {
                                    return DropdownMenuItem<String>(
                                      value: rol,
                                      child: Text(
                                        rol.toUpperCase(),
                                        style: TextStyle(
                                          color: _getColorParaRol(rol),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    if (newValue != null && newValue != rolActual) {
                                      _cambiarRol(user['id'], newValue);
                                    }
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
