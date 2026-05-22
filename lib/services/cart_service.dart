import 'package:flutter/material.dart';

class CartItem {
  final String id;
  final String nombre;
  final double precio;
  int cantidad;
  int stockActual;

  CartItem({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.cantidad,
    this.stockActual = 0,
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

  void agregarProducto(Map<String, dynamic> producto, int cantidad, {int stockActual = 0}) {
    final index = _items.indexWhere((item) => item.id == producto['id']);
    if (index >= 0) {
      _items[index].cantidad += cantidad;
      _items[index].stockActual = stockActual;
    } else {
      _items.add(CartItem(
        id: producto['id'],
        nombre: producto['descripcion_1'],
        precio: (producto['precio_venta'] as num).toDouble(),
        cantidad: cantidad,
        stockActual: stockActual,
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
