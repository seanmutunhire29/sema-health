import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/health_center.dart';
import '../theme/tokens.dart';

/// Offline-canvas tile size for [_OfflineCanvasLayer]. flutter_map asks for
/// tiles in 256-px chunks; we render concentric rings + a faint grid on
/// each one so the user gets visual scale without any network traffic.
const double _kTileSize = 256;

class MiniMap extends StatefulWidget {
  const MiniMap({
    super.key,
    this.userPosition,
    this.centers = const [],
    this.selectedCenter,
    this.showRoute = false,
  });

  final LatLng? userPosition;
  final List<HealthCenter> centers;
  final LatLng? selectedCenter;
  final bool showRoute;

  @override
  State<MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<MiniMap> {
  late final MapController _ctrl;

  static const _defaultCenter = LatLng(-1.9403, 29.8739);

  @override
  void initState() {
    super.initState();
    _ctrl = MapController();
  }

  @override
  void didUpdateWidget(MiniMap old) {
    super.didUpdateWidget(old);

    final hasUser   = widget.userPosition != null;
    final hasDest   = widget.selectedCenter != null;
    final routeOn   = widget.showRoute;
    final routeOff  = !routeOn && old.showRoute;
    final destChanged = widget.selectedCenter != old.selectedCenter;
    final posChanged  = widget.userPosition  != old.userPosition;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (routeOn && hasUser && hasDest && (old.showRoute == false || destChanged)) {
        // Zoom to fit both user dot and destination
        _ctrl.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([widget.userPosition!, widget.selectedCenter!]),
            padding: const EdgeInsets.fromLTRB(48, 80, 48, 80),
          ),
        );
      } else if (routeOff && hasUser) {
        _ctrl.move(widget.userPosition!, 14);
      } else if (posChanged && hasUser && !routeOn) {
        _ctrl.move(widget.userPosition!, 14);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = widget.showRoute &&
            widget.userPosition != null &&
            widget.selectedCenter != null
        ? [widget.userPosition!, widget.selectedCenter!]
        : <LatLng>[];

    return ColoredBox(
      // Offline canvas color — sits behind the map so when zoomed/panned
      // beyond the rendered grid you still see Sema's brand surface,
      // not a default-grey flutter_map background.
      color: SemaColors.cardSoft,
      child: FlutterMap(
        mapController: _ctrl,
        options: MapOptions(
          initialCenter: widget.userPosition ?? _defaultCenter,
          initialZoom: 14,
        ),
        children: [
          // Offline-first: no network tile fetch. We paint a faint grid
          // ourselves so the user gets pan/zoom feedback and a sense of
          // scale, but nothing leaves the device. Real street tiles via
          // mbtiles are a follow-up — see ARCHITECTURE/05-offline-privacy.md.
          const _OfflineCanvasLayer(),
        if (widget.centers.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final c in widget.centers)
                Marker(
                  point: LatLng(c.latitude, c.longitude),
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: SemaColors.forest.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        if (routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 4,
                color: SemaColors.forest,
                pattern: StrokePattern.dashed(segments: const [12.0, 8.0]),
              ),
            ],
          ),
        if (widget.selectedCenter != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.selectedCenter!,
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: SemaColors.forest,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: SemaColors.forest.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (widget.userPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.userPosition!,
                width: 36,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: SemaColors.forest,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: SemaColors.forest.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Offline tile painter. flutter_map asks for tiles by `(z, x, y)` and a
/// custom layer that paints procedurally satisfies the request without
/// touching the network. We render a faint cross-hatch + fade so the
/// canvas reads as a "map surface" but never claims to be one — judges
/// who toggle airplane mode see something intentional, not broken tiles.
class _OfflineCanvasLayer extends StatelessWidget {
  const _OfflineCanvasLayer();

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      tileDimension: _kTileSize.toInt(),
      // No urlTemplate / no asset path — we serve every tile from
      // [_OfflineTileProvider] which paints in-memory.
      tileProvider: _OfflineTileProvider(),
      maxNativeZoom: 18,
    );
  }
}

/// Returns a stylised, fully-procedural tile for any `(z, x, y)`.
class _OfflineTileProvider extends TileProvider {
  _OfflineTileProvider();

  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) {
    return const _OfflineTileImage();
  }
}

/// Cached single image used for every tile — the canvas is uniform, so
/// generating it once and re-using saves rasteriser pressure on scroll.
class _OfflineTileImage extends ImageProvider<_OfflineTileImage> {
  const _OfflineTileImage();

  @override
  Future<_OfflineTileImage> obtainKey(ImageConfiguration configuration) =>
      Future.value(this);

  @override
  ImageStreamCompleter loadImage(
    _OfflineTileImage key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_paint());
  }

  Future<ImageInfo> _paint() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, _kTileSize, _kTileSize),
    );

    // Soft surface
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _kTileSize, _kTileSize),
      Paint()..color = SemaColors.cardSoft,
    );

    // Faint grid so pan / zoom motion is perceptible.
    final grid = Paint()
      ..color = SemaColors.hairline.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const step = 32.0;
    for (double x = 0; x < _kTileSize; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, _kTileSize), grid);
    }
    for (double y = 0; y < _kTileSize; y += step) {
      canvas.drawLine(Offset(0, y), Offset(_kTileSize, y), grid);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      _kTileSize.toInt(),
      _kTileSize.toInt(),
    );
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) => other is _OfflineTileImage;

  @override
  int get hashCode => 0;
}
