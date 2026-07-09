import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GestionProveedoresPage extends StatefulWidget {
  const GestionProveedoresPage({super.key});

  @override
  State<GestionProveedoresPage> createState() => _GestionProveedoresPageState();
}

class _GestionProveedoresPageState extends State<GestionProveedoresPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _proveedores = [];
  bool _isLoading = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProveedores();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProveedores() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      var query = _supabase.from('proveedores').select('*');

      if (_searchQuery.isNotEmpty) {
        query = query.or(
            'razon_social.ilike.%$_searchQuery%,ruc.ilike.%$_searchQuery%,contacto.ilike.%$_searchQuery%');
      }

      final data = await query.order('razon_social', ascending: true);

      if (mounted) {
        setState(() {
          _proveedores = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error cargando proveedores: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _guardarProveedor({
    String? id,
    required String razonSocial,
    String? ruc,
    String? contacto,
    String? telefono,
    String? email,
    String? direccion,
  }) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final body = {
        'razon_social': razonSocial,
        'ruc': ruc,
        'contacto': contacto,
        'telefono': telefono,
        'email': email,
        'direccion': direccion,
      };

      if (id == null) {
        // Nuevo
        await _supabase.from('proveedores').insert(body);
      } else {
        // Editar
        await _supabase.from('proveedores').update(body).eq('id', id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(id == null
                ? "Proveedor creado con éxito"
                : "Proveedor actualizado con éxito"),
            backgroundColor: Colors.green,
          ),
        );
        _fetchProveedores();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al guardar proveedor: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _eliminarProveedor(String id, String razonSocial) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Eliminar Proveedor", style: TextStyle(color: Colors.white)),
        content: Text(
          "¿Estás seguro de que deseas eliminar a '$razonSocial'? Esta acción no se puede deshacer si tiene registros asociados.",
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCELAR", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("ELIMINAR", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    if (mounted) setState(() => _isLoading = true);
    try {
      await _supabase.from('proveedores').delete().eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Proveedor eliminado con éxito"),
            backgroundColor: Colors.green,
          ),
        );
        _fetchProveedores();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No se pudo eliminar el proveedor (puede estar en uso por órdenes de compra). Error: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _mostrarFormulario({Map<String, dynamic>? proveedor}) {
    final formKey = GlobalKey<FormState>();
    final razonSocialCtrl =
        TextEditingController(text: proveedor?['razon_social'] ?? '');
    final rucCtrl = TextEditingController(text: proveedor?['ruc'] ?? '');
    final contactoCtrl =
        TextEditingController(text: proveedor?['contacto'] ?? '');
    final telefonoCtrl =
        TextEditingController(text: proveedor?['telefono'] ?? '');
    final emailCtrl = TextEditingController(text: proveedor?['email'] ?? '');
    final direccionCtrl =
        TextEditingController(text: proveedor?['direccion'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text(
            proveedor == null ? "Nuevo Proveedor" : "Editar Proveedor",
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildField(
                    controller: razonSocialCtrl,
                    label: "Razón Social *",
                    hint: "Nombre de la empresa",
                    validator: (v) => v == null || v.trim().isEmpty
                        ? "Campo requerido"
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: rucCtrl,
                    label: "RUC / Identificación",
                    hint: "ej. 20123456789",
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: contactoCtrl,
                    label: "Persona de Contacto",
                    hint: "Nombre del representante",
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: telefonoCtrl,
                    label: "Teléfono",
                    hint: "ej. +51 987654321",
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: emailCtrl,
                    label: "Email",
                    hint: "ej. contacto@proveedor.com",
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: direccionCtrl,
                    label: "Dirección",
                    hint: "Dirección física de despacho",
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCELAR",
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade400,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                _guardarProveedor(
                  id: proveedor?['id']?.toString(),
                  razonSocial: razonSocialCtrl.text.trim(),
                  ruc: rucCtrl.text.trim().isEmpty
                      ? null
                      : rucCtrl.text.trim(),
                  contacto: contactoCtrl.text.trim().isEmpty
                      ? null
                      : contactoCtrl.text.trim(),
                  telefono: telefonoCtrl.text.trim().isEmpty
                      ? null
                      : telefonoCtrl.text.trim(),
                  email: emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim(),
                  direccion: direccionCtrl.text.trim().isEmpty
                      ? null
                      : direccionCtrl.text.trim(),
                );
              },
              child: const Text("GUARDAR"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.tealAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          "Gestión de Proveedores",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.tealAccent.shade400,
        foregroundColor: Colors.black,
        tooltip: "Nuevo Proveedor",
        onPressed: () => _mostrarFormulario(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Buscador
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
                _fetchProveedores();
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Buscar por razón social, RUC o contacto...",
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.tealAccent),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = "";
                          });
                          _fetchProveedores();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: Colors.tealAccent, width: 1.5),
                ),
              ),
            ),
          ),

          // Contenido
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                : _proveedores.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.business,
                                size: 64, color: Colors.tealAccent.withOpacity(0.3)),
                            const SizedBox(height: 12),
                            const Text(
                              "No se encontraron proveedores",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _proveedores.length,
                        itemBuilder: (context, index) {
                          final prov = _proveedores[index];
                          final razonSocial = prov['razon_social'] ?? '—';
                          final ruc = prov['ruc'];
                          final contacto = prov['contacto'];
                          final telefono = prov['telefono'];
                          final email = prov['email'];
                          final direccion = prov['direccion'];

                          return Card(
                            color: const Color(0xFF1E1E1E),
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                  color: Colors.white.withOpacity(0.06)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          razonSocial,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit,
                                                color: Colors.tealAccent,
                                                size: 20),
                                            tooltip: "Editar",
                                            onPressed: () =>
                                                _mostrarFormulario(
                                                    proveedor: prov),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.redAccent,
                                                size: 20),
                                            tooltip: "Eliminar",
                                            onPressed: () =>
                                                _eliminarProveedor(
                                                    prov['id'].toString(),
                                                    razonSocial),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (ruc != null && ruc.toString().isNotEmpty) ...[
                                    Text(
                                      "RUC: $ruc",
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                  if (contacto != null &&
                                      contacto.toString().isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.person_outline,
                                            size: 14, color: Colors.white38),
                                        const SizedBox(width: 6),
                                        Text(
                                          contacto,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  if (telefono != null &&
                                      telefono.toString().isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.phone_outlined,
                                            size: 14, color: Colors.white38),
                                        const SizedBox(width: 6),
                                        Text(
                                          telefono,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  if (email != null &&
                                      email.toString().isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.email_outlined,
                                            size: 14, color: Colors.white38),
                                        const SizedBox(width: 6),
                                        Text(
                                          email,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  if (direccion != null &&
                                      direccion.toString().isNotEmpty) ...[
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.location_on_outlined,
                                            size: 14, color: Colors.white38),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            direccion,
                                            style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
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
