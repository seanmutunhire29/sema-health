import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

class HealthCenter {
  const HealthCenter({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.primaryType,
    required this.businessStatus,
    this.phoneNational,
    this.rating,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String primaryType;
  final String businessStatus;
  final String? phoneNational;
  final double? rating;

  bool get isOperational => businessStatus == 'OPERATIONAL';

  factory HealthCenter.fromJson(Map<String, dynamic> j) => HealthCenter(
        name: (j['name'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        primaryType: (j['primary_type'] as String?) ?? 'health',
        businessStatus: (j['business_status'] as String?) ?? '',
        phoneNational: j['phone_national'] as String?,
        rating: j['rating'] is num ? (j['rating'] as num).toDouble() : null,
      );
}

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

Future<List<HealthCenter>> loadHealthCenters() async {
  final raw = await rootBundle.loadString('assets/data/health_centers.json');
  final list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((e) => HealthCenter.fromJson(e as Map<String, dynamic>))
      .toList();
}
