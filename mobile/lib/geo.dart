// Point-in-polygon and area resolution (sector › zone › building).

List<List<double>> parsePolygon(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<List>()
      .where((p) => p.length >= 2)
      .map((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
      .toList();
}

/// Ray casting. Points are [lat, lng].
bool insidePolygon(double lat, double lng, List<List<double>> poly) {
  if (poly.length < 3) return false;
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final yi = poly[i][0], xi = poly[i][1], yj = poly[j][0], xj = poly[j][1];
    final intersect = ((yi > lat) != (yj > lat)) &&
        (lng < (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

class Areas {
  final List<Map<String, dynamic>> sectors, zones, buildings;
  Areas(this.sectors, this.zones, this.buildings);

  Map<String, dynamic>? _byId(List<Map<String, dynamic>> list, String? id) {
    if (id == null) return null;
    for (final x in list) {
      if (x['id'] == id) return x;
    }
    return null;
  }

  Map<String, dynamic>? sector(String? id) => _byId(sectors, id);
  Map<String, dynamic>? zone(String? id) => _byId(zones, id);
  Map<String, dynamic>? building(String? id) => _byId(buildings, id);

  /// Returns the ids of the building, zone and sector containing the point.
  Position3 locate(double lat, double lng) {
    String? b, z, s;
    for (final x in buildings) {
      if (insidePolygon(lat, lng, parsePolygon(x['boundary']))) {
        b = x['id'];
        z = x['zone_id'];
        break;
      }
    }
    if (z == null) {
      for (final x in zones) {
        if (insidePolygon(lat, lng, parsePolygon(x['boundary']))) {
          z = x['id'];
          break;
        }
      }
    }
    if (z != null) s = zone(z)?['sector_id'];
    if (s == null) {
      for (final x in sectors) {
        if (insidePolygon(lat, lng, parsePolygon(x['boundary']))) {
          s = x['id'];
          break;
        }
      }
    }
    return Position3(s, z, b);
  }
}

class Position3 {
  final String? sectorId, zoneId, buildingId;
  const Position3(this.sectorId, this.zoneId, this.buildingId);
  bool get insideAny => sectorId != null || zoneId != null || buildingId != null;
}
