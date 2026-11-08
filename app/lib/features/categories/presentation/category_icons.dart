import 'package:flutter/material.dart';

/// Veritabanında metin anahtar olarak saklanan kategori simgeleri.
/// İlk 16 anahtar, yeni kullanıcıya açılan varsayılan kategorilerde kullanılır.
abstract final class CategoryIcons {
  static const all = <String, IconData>{
    'shopping_cart': Icons.shopping_cart_outlined,
    'home': Icons.home_outlined,
    'receipt': Icons.receipt_outlined,
    'directions_bus': Icons.directions_bus_outlined,
    'restaurant': Icons.restaurant_outlined,
    'medical_services': Icons.medical_services_outlined,
    'school': Icons.school_outlined,
    'checkroom': Icons.checkroom_outlined,
    'celebration': Icons.celebration_outlined,
    'subscriptions': Icons.subscriptions_outlined,
    'credit_card': Icons.credit_card_outlined,
    'more_horiz': Icons.more_horiz,
    'payments': Icons.payments_outlined,
    'work': Icons.work_outline,
    'apartment': Icons.apartment_outlined,
    'handshake': Icons.handshake_outlined,
    'local_gas_station': Icons.local_gas_station_outlined,
    'local_cafe': Icons.local_cafe_outlined,
    'phone_android': Icons.phone_android_outlined,
    'wifi': Icons.wifi,
    'bolt': Icons.bolt_outlined,
    'water_drop': Icons.water_drop_outlined,
    'pets': Icons.pets_outlined,
    'child_care': Icons.child_care_outlined,
    'fitness_center': Icons.fitness_center_outlined,
    'flight': Icons.flight_outlined,
    'directions_car': Icons.directions_car_outlined,
    'sports_esports': Icons.sports_esports_outlined,
    'card_giftcard': Icons.card_giftcard_outlined,
    'savings': Icons.savings_outlined,
    'trending_up': Icons.trending_up,
    'storefront': Icons.storefront_outlined,
  };

  static const fallback = Icons.label_outline;

  static IconData of(String? key) => all[key] ?? fallback;
}
