import '../models/ticket.dart';

/// Area search that works without the server: the named areas Drishti
/// covers, and every PIN code in the four live cities (by the first three
/// digits, which India Post assigns by sorting district). Used when the
/// server's `area_lookup` is unreachable or finds nothing, and by demo mode.

/// A named area: id, name, Hindi name, PIN, lat, lng, city.
typedef KnownArea = (String, String, String, String, double, double, PinCity);

class PinCity {
  const PinCity(this.id, this.name, this.nameHi, this.lat, this.lng, this.prefixes);
  final String id;
  final String name;
  final String nameHi;
  final double lat;
  final double lng;
  final List<String> prefixes;
}

const pune = PinCity('11111111-1111-1111-1111-111111111111', 'Pune', 'पुणे', 18.5204, 73.8567, ['411', '412']);
const delhi = PinCity('22222222-2222-2222-2222-222222222222', 'Delhi', 'दिल्ली', 28.6139, 77.2090, ['110']);
const indore = PinCity('indore', 'Indore', 'इंदौर', 22.7196, 75.8577, ['452', '453']);
const bhopal = PinCity('bhopal', 'Bhopal', 'भोपाल', 23.2599, 77.4126, ['462']);
const pinCities = [pune, delhi, indore, bhopal];

const knownAreas = <KnownArea>[
  ('loc-pune-shivajinagar', 'Shivajinagar', 'शिवाजीनगर', '411005', 18.5308, 73.8475, pune),
  ('loc-pune-deccan', 'Deccan Gymkhana', 'डेक्कन जिमखाना', '411004', 18.5167, 73.8411, pune),
  ('loc-pune-kothrud', 'Kothrud', 'कोथरुड', '411038', 18.5074, 73.8077, pune),
  ('loc-pune-aundh', 'Aundh', 'औंध', '411007', 18.5590, 73.8070, pune),
  ('loc-ind-rau', 'Rau', 'राऊ', '453331', 22.6360, 75.8110, indore),
  ('loc-ind-sudama', 'Sudama Nagar', 'सुदामा नगर', '452009', 22.6900, 75.8300, indore),
  ('loc-bho-kolar', 'Kolar Road', 'कोलार रोड', '462042', 23.1800, 77.4100, bhopal),
  ('loc-del-okhla', 'Okhla', 'ओखला', '110020', 28.5300, 77.2700, delhi),
];

/// What a search box query means.
sealed class AreaQuery {
  const AreaQuery();
}

/// Too short to search.
class TooShort extends AreaQuery {
  const TooShort();
}

/// Digits, but not a valid Indian PIN code (six digits, not starting with 0).
class BadPin extends AreaQuery {
  const BadPin();
}

class PinQuery extends AreaQuery {
  const PinQuery(this.pin);
  final String pin;
}

class NameQuery extends AreaQuery {
  const NameQuery(this.text);
  final String text;
}

/// Reads "411 005", "411-005", " 411005 " as a PIN; anything with letters as a name.
AreaQuery parseAreaQuery(String raw) {
  final t = raw.trim();
  final digits = t.replaceAll(RegExp(r'[\s-]'), '');
  if (digits.isNotEmpty && RegExp(r'^\d+$').hasMatch(digits)) {
    return RegExp(r'^[1-9]\d{5}$').hasMatch(digits) ? PinQuery(digits) : const BadPin();
  }
  return t.length < 2 ? const TooShort() : NameQuery(t);
}

/// The city a PIN code belongs to, if Drishti covers it.
PinCity? cityForPin(String pin) {
  for (final c in pinCities) {
    if (c.prefixes.any(pin.startsWith)) return c;
  }
  return null;
}

/// Sentinel-2 passes every five days: the last pass before today and the next.
(DateTime, DateTime) passesAround(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final epoch = DateTime(2026, 1, 1);
  final days = today.difference(epoch).inDays;
  final last = epoch.add(Duration(days: days - days % 5));
  return (last, last.add(const Duration(days: 5)));
}

AreaHit knownAreaHit(KnownArea a, {int? openSites, DateTime? now}) {
  final (last, next) = passesAround(now ?? DateTime.now());
  return AreaHit(
    id: a.$1,
    name: a.$2,
    nameHi: a.$3,
    pincode: a.$4,
    lat: a.$5,
    lng: a.$6,
    cityId: a.$7.id,
    cityName: a.$7.name,
    openSites: openSites,
    lastPass: last,
    nextPass: next,
  );
}

/// A PIN code Drishti covers but has no named area for: the city, centred.
AreaHit pinAreaHit(String pin, PinCity c, {DateTime? now}) {
  final (last, next) = passesAround(now ?? DateTime.now());
  return AreaHit(
    id: 'pin-$pin',
    name: c.name,
    nameHi: c.nameHi,
    pincode: pin,
    lat: c.lat,
    lng: c.lng,
    cityId: c.id,
    cityName: c.name,
    lastPass: last,
    nextPass: next,
  );
}

/// Searches without the server. Open-site counts are unknown here (null).
List<AreaHit> localAreaLookup(String raw, {DateTime? now}) {
  switch (parseAreaQuery(raw)) {
    case PinQuery(:final pin):
      for (final a in knownAreas) {
        if (a.$4 == pin) return [knownAreaHit(a, now: now)];
      }
      final c = cityForPin(pin);
      return c == null ? const [] : [pinAreaHit(pin, c, now: now)];
    case NameQuery(:final text):
      final lower = text.toLowerCase();
      return [
        for (final a in knownAreas)
          if (a.$2.toLowerCase().startsWith(lower) || a.$3.startsWith(text)) knownAreaHit(a, now: now),
        for (final c in pinCities)
          if (c.name.toLowerCase().startsWith(lower) || c.nameHi.startsWith(text))
            AreaHit(
              id: 'city-${c.id}',
              name: c.name,
              nameHi: c.nameHi,
              lat: c.lat,
              lng: c.lng,
              cityId: c.id,
              cityName: c.name,
            ),
      ].take(5).toList();
    case TooShort():
    case BadPin():
      return const [];
  }
}
