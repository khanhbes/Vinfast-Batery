import 'package:flutter/painting.dart';

/// One approved catalog image (WebP, transparent background when the
/// backend removed the studio backdrop).
class ShowroomImage {
  const ShowroomImage({
    required this.thumbnailUrl,
    required this.mediumUrl,
    required this.heroUrl,
    this.credit,
    this.sourceUrl,
    this.backgroundRemoved = false,
  });

  final String thumbnailUrl;
  final String mediumUrl;
  final String heroUrl;
  final String? credit;
  final String? sourceUrl;
  final bool backgroundRemoved;

  static String? _https(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.startsWith('https://') ? text : null;
  }

  static ShowroomImage? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final hero = _https(raw['heroUrl']);
    final medium = _https(raw['mediumUrl']);
    final thumb = _https(raw['thumbnailUrl']);
    final best = hero ?? medium ?? thumb;
    if (best == null) return null;
    final credit = raw['credit'];
    final source = raw['sourceUrl'];
    return ShowroomImage(
      thumbnailUrl: thumb ?? medium ?? best,
      mediumUrl: medium ?? hero ?? best,
      heroUrl: hero ?? medium ?? best,
      credit: credit is String && credit.trim().isNotEmpty
          ? credit.trim()
          : null,
      sourceUrl: source is String && source.trim().isNotEmpty
          ? source.trim()
          : null,
      backgroundRemoved: raw['backgroundRemoved'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'thumbnailUrl': thumbnailUrl,
    'mediumUrl': mediumUrl,
    'heroUrl': heroUrl,
    'credit': ?credit,
    'sourceUrl': ?sourceUrl,
    'backgroundRemoved': backgroundRemoved,
  };
}

/// A paint colour of the vehicle and its ordered angle images.
class ShowroomColor {
  const ShowroomColor({
    required this.id,
    required this.name,
    required this.swatch,
    required this.angles,
  });

  final String id;
  final String name;
  final Color swatch;
  final List<ShowroomImage> angles;

  /// A full turntable needs enough evenly spaced angles to feel continuous.
  bool get canSpin => angles.length >= VehicleShowroomData.spinMinAngles;

  static Color _parseHex(Object? raw) {
    final text = raw is String ? raw.trim() : '';
    final match = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(text);
    if (match == null) return const Color(0xFFC9CDD2);
    return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }

  static ShowroomColor? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final rawAngles = raw['angles'];
    final angles = <ShowroomImage>[
      if (rawAngles is List)
        for (final item in rawAngles.take(VehicleShowroomData.maxAngles))
          ?ShowroomImage.fromMap(item),
    ];
    if (angles.isEmpty) return null;
    final name = raw['name'];
    return ShowroomColor(
      id: id.trim(),
      name: name is String && name.trim().isNotEmpty ? name.trim() : id.trim(),
      swatch: _parseHex(raw['swatchHex']),
      angles: angles,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'swatchHex':
        '#${(swatch.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
    'angles': [for (final a in angles) a.toMap()],
  };
}

/// Photos bundled with the app (Task 127), for models whose catalog has no
/// photo set yet. `asset:` URLs resolve to [AssetImage].
abstract final class BundledShowroom {
  static const String felizMintAsset = 'assets/vehicles/feliz_mint.webp';

  static const ShowroomColor felizMint = ShowroomColor(
    id: 'bundled-feliz-mint',
    name: 'Xanh bạc hà',
    swatch: Color(0xFFC3D3C6),
    angles: [
      ShowroomImage(
        thumbnailUrl: 'asset:$felizMintAsset',
        mediumUrl: 'asset:$felizMintAsset',
        heroUrl: 'asset:$felizMintAsset',
        credit: 'Ảnh render VinFast Feliz do chủ xe cung cấp',
        backgroundRemoved: true,
      ),
    ],
  );

  static bool isFeliz({String? modelId, String? name}) =>
      (modelId ?? '').toLowerCase().contains('feliz') ||
      (name ?? '').toLowerCase().contains('feliz');

  /// [catalog] plus the bundled colour; the bundled photo becomes the
  /// default when the catalog has no 360° set to show instead.
  static VehicleShowroomData? withBundled(
    VehicleShowroomData? catalog, {
    String? modelId,
    String? name,
  }) {
    if (!isFeliz(modelId: modelId, name: name)) return catalog;
    if (catalog == null) {
      return VehicleShowroomData(
        colors: const [felizMint],
        defaultColorId: felizMint.id,
      );
    }
    if (catalog.colors.any((c) => c.id == felizMint.id)) return catalog;
    final colors = [...catalog.colors, felizMint]
        .take(VehicleShowroomData.maxColors + 1)
        .toList();
    return VehicleShowroomData(
      colors: colors,
      defaultColorId: catalog.anyCanSpin ? catalog.defaultColorId : felizMint.id,
    );
  }
}

/// Catalog showroom for one vehicle model. Built from `media.showroom`, or —
/// for catalogs that only have the older single 2D/3D image — a single
/// "Ảnh chính" colour with one angle so every screen uses one code path.
class VehicleShowroomData {
  const VehicleShowroomData({
    required this.colors,
    required this.defaultColorId,
  });

  static const spinMinAngles = 12;
  static const maxAngles = 36;
  static const maxColors = 8;

  final List<ShowroomColor> colors;
  final String defaultColorId;

  ShowroomColor get defaultColor => colors.firstWhere(
    (c) => c.id == defaultColorId,
    orElse: () => colors.first,
  );

  ShowroomImage get primary => defaultColor.angles.first;

  bool get anyCanSpin => colors.any((c) => c.canSpin);

  /// Parses `media` from a catalog document or a vehicle catalog snapshot.
  /// Returns null when there is no usable HTTPS image.
  static VehicleShowroomData? fromMedia(Object? media) {
    if (media is! Map) return null;
    final showroom = media['showroom'];
    if (showroom is Map) {
      final rawColors = showroom['colors'];
      final colors = <ShowroomColor>[];
      final seen = <String>{};
      if (rawColors is List) {
        for (final raw in rawColors) {
          final color = ShowroomColor.fromMap(raw);
          if (color != null && seen.add(color.id)) colors.add(color);
          if (colors.length == maxColors) break;
        }
      }
      if (colors.isNotEmpty) {
        final wanted = showroom['defaultColorId'];
        return VehicleShowroomData(
          colors: colors,
          defaultColorId: wanted is String && seen.contains(wanted)
              ? wanted
              : colors.first.id,
        );
      }
    }
    final views = media['views'];
    final single =
        (views is Map ? ShowroomImage.fromMap(views['twoD']) : null) ??
        (views is Map ? ShowroomImage.fromMap(views['threeD']) : null) ??
        ShowroomImage.fromMap(media);
    if (single == null) return null;
    return VehicleShowroomData(
      colors: [
        ShowroomColor(
          id: 'primary',
          name: 'Ảnh chính',
          swatch: const Color(0xFFC9CDD2),
          angles: [single],
        ),
      ],
      defaultColorId: 'primary',
    );
  }

  Map<String, dynamic> toMap() => {
    'defaultColorId': defaultColorId,
    'colors': [for (final c in colors) c.toMap()],
  };
}
