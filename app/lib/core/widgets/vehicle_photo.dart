import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/vehicle_model.dart';
import '../../data/models/vehicle_showroom.dart';
import '../../data/models/vinfast_model_spec.dart';

/// One photo per vehicle, the same on every screen (QA 131: the 360° viewer
/// was removed). A Feliz always shows the owner's photo bundled with the
/// app; other models show their catalog photo, else the line art.
abstract final class VehicleImages {
  static const String felizAsset = 'assets/vehicles/feliz_mint.webp';
  static const String felizUrl = 'asset:$felizAsset';

  static bool isFeliz(String? text) =>
      (text ?? '').toLowerCase().contains('feliz');

  /// `asset:` or `https://` URL, or null when the model has no photo.
  static String? resolve({
    String? modelId,
    String? name,
    Object? catalogSnapshot,
    String? imageUrl,
  }) {
    if (isFeliz(modelId) || isFeliz(name)) return felizUrl;
    if (catalogSnapshot is Map) {
      final catalog =
          VehicleShowroomData.fromMedia(catalogSnapshot['media']) ??
          VehicleShowroomData.fromMedia({
            'heroUrl': catalogSnapshot['imageUrl'],
          });
      if (catalog != null) return catalog.primary.mediumUrl;
    }
    final direct = imageUrl?.trim() ?? '';
    return direct.startsWith('https://') ? direct : null;
  }

  static String? forVehicle(VehicleModel? v) => v == null
      ? null
      : resolve(
          modelId: v.vinfastModelId,
          name: '${v.modelName} ${v.vehicleName}',
          catalogSnapshot: v.catalogSnapshot,
        );

  /// A raw `Vehicles` document (garage list, spec screen).
  static String? forVehicleMap(Map<String, dynamic> v) => resolve(
    modelId: v['vinfastModelId'] as String?,
    name: [
      v['vinfastModelName'],
      v['model'],
      v['vehicleName'],
    ].whereType<String>().join(' '),
    catalogSnapshot: v['catalogSnapshot'],
  );

  static String? forSpec(VinFastModelSpec spec) => resolve(
    modelId: spec.modelId,
    name: spec.modelName,
    imageUrl: spec.showroom?.primary.mediumUrl ?? spec.imageUrl,
  );
}

/// Resolves a vehicle photo URL. Disk-cached in the app (photos stay
/// available offline); tests swap it for an in-memory provider.
ImageProvider Function(String url) vehicleImageProvider = (url) =>
    url.startsWith('asset:')
    ? AssetImage(url.substring(6))
    : CachedNetworkImageProvider(url);

/// The vehicle photo, faded in once decoded; [fallback] while there is no
/// photo or it fails to load. [reflection] mirrors it onto the floor.
class VehiclePhoto extends StatelessWidget {
  const VehiclePhoto({
    super.key,
    required this.url,
    required this.fallback,
    this.reflection = false,
    this.semanticLabel,
  });

  final String? url;
  final Widget fallback;
  final bool reflection;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) return fallback;
    Widget photo() => Image(
      image: vehicleImageProvider(source),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: sync || frame != null ? 1 : 0,
        duration: const Duration(milliseconds: 320),
        child: child,
      ),
      errorBuilder: (_, _, _) => fallback,
    );
    if (!reflection) return photo();
    return LayoutBuilder(
      builder: (context, box) {
        final mainHeight = box.maxHeight * 6 / 7;
        return Column(
          children: [
            SizedBox(height: mainHeight, child: photo()),
            Expanded(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (b) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
                    ).createShader(b),
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topCenter,
                        minHeight: mainHeight,
                        maxHeight: mainHeight,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(1, -1, 1),
                          child: photo(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
