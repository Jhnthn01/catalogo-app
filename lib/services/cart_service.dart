import 'package:flutter/material.dart';

class CartItem {
  final String id;
  final String nombre;
  final double precio;
  int cantidad;

  CartItem({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.cantidad,
  });
}

class CartService {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  final List<CartItem> _items = [];

  final ValueNotifier<int> itemsCountNotifier = ValueNotifier<int>(0);

  List<CartItem> get items => _items;

  double get total =>
      _items.fold(0, (sum, item) => sum + (item.precio * item.cantidad));

  void agregarProducto(Map<String, dynamic> producto, int cantidad) {
    final index = _items.indexWhere((item) => item.id == producto['id']);
    if (index >= 0) {
      _items[index].cantidad += cantidad;
    } else {
      _items.add(CartItem(
        id: producto['id'],
        nombre: producto['descripcion_1'],
        precio: (producto['precio_venta'] as num).toDouble(),
        cantidad: cantidad,
      ));
    }
    itemsCountNotifier.value = _items.length;
  }

  void actualizarCantidad(String id, int nuevaCantidad) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      if (nuevaCantidad > 0) {
        _items[index].cantidad = nuevaCantidad;
      } else {
        eliminarProducto(id);
      }
      itemsCountNotifier.value = _items.length;
    }
  }

  void eliminarProducto(String id) {
    _items.removeWhere((item) => item.id == id);
    itemsCountNotifier.value = _items.length;
  }

  void limpiar() {
    _items.clear();
    itemsCountNotifier.value = 0;
  }
}
