import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:catalogo_digital_app/services/tienda_service.dart';

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
    _cargarTiendas();
  }

  Future<void> _cargarTiendas() async {
    if (TiendaService().tiendas.isEmpty) {
      await TiendaService().cargarTiendas();
      if (mounted) setState(() {});
    }
  }

  Future<void> _fetchUsuarios() async {
    setState(() => _isLoading = true);
    try {
      var query = _supabase.from('perfiles').select('id, nombre, email, rol, tienda_id');

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

  Future<void> _actualizarUsuario(String userId, String nuevoRol, int? nuevaTiendaId) async {
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

    setState(() => _isLoading = true);
    try {
      await _supabase.from('perfiles').update({
        'rol': nuevoRol,
        'tienda_id': nuevaTiendaId,
      }).eq('id', userId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Usuario actualizado con éxito"),
            backgroundColor: Colors.green,
          ),
        );
        _fetchUsuarios(); // Recargar la lista
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error actualizando usuario: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _mostrarDialogoEdicion(Map<String, dynamic> user) {
    String selectedRol = user['rol'] ?? 'cliente';
    int? selectedTiendaId = user['tienda_id'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Text(
                "Editar Usuario: ${user['nombre'] ?? 'Sin Nombre'}",
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Rol del Usuario", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2C2C2C),
                        value: selectedRol,
                        style: const TextStyle(color: Colors.white),
                        items: _rolesDisponibles.map((String rol) {
                          return DropdownMenuItem<String>(
                            value: rol,
                            child: Text(rol.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (String? val) {
                          if (val != null) {
                            setDialogState(() => selectedRol = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("Sucursal Asignada (Tienda)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        isExpanded: true,
                        dropdownColor: const Color(0xFF2C2C2C),
                        value: selectedTiendaId,
                        hint: const Text("Ninguna/Sin sucursal", style: TextStyle(color: Colors.grey, fontSize: 13)),
                        style: const TextStyle(color: Colors.white),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text("Ninguna/Sin sucursal"),
                          ),
                          ...TiendaService().tiendas.map((Map<String, dynamic> t) {
                            return DropdownMenuItem<int?>(
                              value: t['id'] as int,
                              child: Text(t['nombre'] as String),
                            );
                          }),
                        ],
                        onChanged: (int? val) {
                          setDialogState(() => selectedTiendaId = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () {
                    Navigator.pop(context);
                    _actualizarUsuario(user['id'], selectedRol, selectedTiendaId);
                  },
                  child: const Text("GUARDAR"),
                ),
              ],
            );
          },
        );
      },
    );
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
                          
                          final int? tiendaId = user['tienda_id'];
                          final tiendaName = TiendaService().tiendas.firstWhere(
                                (t) => t['id'] == tiendaId,
                                orElse: () => <String, dynamic>{},
                              )['nombre'] ?? 'Sin asignar';

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              onTap: () => _mostrarDialogoEdicion(user),
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
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
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
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.blueAccent),
                                        ),
                                        child: Text(
                                          tiendaName.toString().toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.blueAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                tooltip: "Editar Usuario",
                                onPressed: () => _mostrarDialogoEdicion(user),
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
