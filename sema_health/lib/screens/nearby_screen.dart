import 'dart:async';
import 'dart:math' show sin, cos, atan2, max;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/health_center.dart';
import '../theme/tokens.dart';
import '../widgets/mini_map.dart';
import '../widgets/press_scale.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

enum _NavState { browse, preview, active }

class _NearbyScreenState extends State<NearbyScreen> {
  int _index = 0;
  _NavState _state = _NavState.browse;
  int _modeIndex = 0;

  bool _loading = true;
  String? _error;
  bool _permissionDenied = false;

  LatLng? _userLatLng;
  List<HealthCenter> _nearestCenters = const [];

  static const _modes = <_TravelMode>[
    _TravelMode('Walk',    PhosphorIconsRegular.personSimpleWalk),
    _TravelMode('Drive',   PhosphorIconsRegular.car),
    _TravelMode('Transit', PhosphorIconsRegular.bus),
  ];

  List<_Provider> _providers = const [];
  List<List<_RouteOption>> _routes = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
      _permissionDenied = false;
      _index = 0;
      _state = _NavState.browse;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _loading = false;
          });
        }
        return;
      }

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      ).timeout(const Duration(seconds: 30));

      final centers = await loadHealthCenters();

      final sorted = centers
          .map((c) => (c: c, d: haversineKm(pos.latitude, pos.longitude, c.latitude, c.longitude)))
          .toList()
        ..sort((a, b) => a.d.compareTo(b.d));

      final nearest = sorted.take(15).toList();

      final providers = [
        for (final (i, item) in nearest.indexed)
          _providerFromCenter(item.c, item.d, i),
      ];
      final routes = [
        for (final item in nearest)
          _routesForCenter(item.c, item.d, pos.latitude, pos.longitude),
      ];

      if (mounted) {
        setState(() {
          _userLatLng = LatLng(pos.latitude, pos.longitude);
          _nearestCenters = nearest.map((x) => x.c).toList();
          _providers = providers;
          _routes = routes;
          _loading = false;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'GPS timed out. Check signal and try again.';
          _loading = false;
        });
      }
    } on LocationServiceDisabledException {
      if (mounted) {
        setState(() {
          _error = 'Location services are off.\nEnable GPS in settings.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load nearby centers.\n${e.runtimeType}: $e';
          _loading = false;
        });
      }
    }
  }

  // ─── Type helpers ────────────────────────────────────────────────────────────

  static IconData _iconForType(String type) => switch (type) {
    'hospital' || 'general_hospital'                => PhosphorIconsRegular.hospital,
    'pharmacy' || 'drugstore'                        => PhosphorIconsRegular.pill,
    'doctor' || 'medical_center' || 'medical_clinic' => PhosphorIconsRegular.stethoscope,
    'physiotherapist'                                => PhosphorIconsRegular.personSimpleWalk,
    'child_care_agency'                              => PhosphorIconsRegular.babyCarriage,
    _                                                => PhosphorIconsRegular.heartbeat,
  };

  static String _roleForType(String type) => switch (type) {
    'hospital' || 'general_hospital' => 'Hospital',
    'pharmacy' || 'drugstore'        => 'Pharmacy',
    'doctor'                         => 'Doctor',
    'medical_center'                 => 'Medical center',
    'medical_clinic'                 => 'Medical clinic',
    'physiotherapist'                => 'Physiotherapy',
    'dentist' || 'dental_clinic'     => 'Dental clinic',
    'child_care_agency'              => 'Child care',
    'health'                         => 'Health center',
    _                                => type.isEmpty ? 'Health center' : type.replaceAll('_', ' '),
  };

  static SemaAccent _accentForType(String type, int index) => switch (type) {
    'hospital' || 'general_hospital'                 => SemaAccent.butter,
    'pharmacy' || 'drugstore'                         => SemaAccent.lilac,
    'doctor' || 'medical_center' || 'medical_clinic'  => SemaAccent.blush,
    'dentist' || 'dental_clinic'                      => SemaAccent.mint,
    'physiotherapist'                                 => SemaAccent.sand,
    _                                                 => SemaAccent.cycle[index % SemaAccent.cycle.length],
  };

  // ─── Distance / time formatters ──────────────────────────────────────────────

  static String _fmtDist(double km) {
    if (km < 1.0) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1)} km';
  }

  static String _fmtWalk(double km) {
    final min = max(1, (km / 5.0 * 60).round());
    return '$min min walk';
  }

  static String _fmtDrive(double km) {
    final min = max(1, (km / 30.0 * 60).round());
    return '$min min drive';
  }

  static String _fmtTransit(double km) {
    final min = max(3, (km / 15.0 * 60 + 5).round());
    return '$min min transit';
  }

  // ─── Bearing / direction ─────────────────────────────────────────────────────

  static String _cardinalDir(double fromLat, double fromLon, double toLat, double toLon) {
    final dLon = (toLon - fromLon) * pi / 180;
    final lat1 = fromLat * pi / 180;
    final lat2 = toLat * pi / 180;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final bearing = (atan2(y, x) * 180 / pi + 360) % 360;
    const dirs = ['north', 'northeast', 'east', 'southeast', 'south', 'southwest', 'west', 'northwest'];
    return dirs[((bearing + 22.5) / 45).floor() % 8];
  }

  // ─── Center → Provider / Route conversion ────────────────────────────────────

  static _Provider _providerFromCenter(HealthCenter c, double distKm, int index) {
    final tags = <String>[];
    if (c.rating != null && c.rating! > 0) {
      tags.add('★ ${c.rating!.toStringAsFixed(1)}');
    }
    if (c.phoneNational != null && c.phoneNational!.isNotEmpty) {
      tags.add('Has phone');
    }
    if (tags.isEmpty) tags.add(_roleForType(c.primaryType));

    return _Provider(
      name: c.name,
      role: _roleForType(c.primaryType),
      distance: _fmtDist(distKm),
      walk: _fmtWalk(distKm),
      icon: _iconForType(c.primaryType),
      open: c.isOperational,
      tags: tags,
      accent: _accentForType(c.primaryType, index),
      phone: (c.phoneNational != null && c.phoneNational!.isNotEmpty) ? c.phoneNational : null,
    );
  }

  static List<_RouteOption> _routesForCenter(
    HealthCenter c, double distKm, double userLat, double userLon,
  ) {
    final dist = _fmtDist(distKm);
    final dir  = _cardinalDir(userLat, userLon, c.latitude, c.longitude);
    final name = c.name.length > 24 ? '${c.name.substring(0, 22)}…' : c.name;
    return [
      _RouteOption(
        eta: _fmtWalk(distKm),
        distance: dist,
        steps: [
          _Step(PhosphorIconsBold.arrowUp, 'Head $dir toward $name', dist),
          _Step(PhosphorIconsBold.flag, 'Arrive at $name', '0 m'),
        ],
      ),
      _RouteOption(
        eta: _fmtDrive(distKm),
        distance: dist,
        steps: [
          _Step(PhosphorIconsRegular.car, 'Drive $dir to $name', dist),
          _Step(PhosphorIconsBold.flag, 'Arrive at $name', '0 m'),
        ],
      ),
      _RouteOption(
        eta: _fmtTransit(distKm),
        distance: dist,
        steps: [
          _Step(PhosphorIconsBold.bus, 'Take transit $dir to $name', dist),
          _Step(PhosphorIconsBold.flag, 'Arrive at $name', '0 m'),
        ],
      ),
    ];
  }

  // ─── Navigation callbacks ────────────────────────────────────────────────────

  _Provider get _selected => _providers[_index];
  _RouteOption get _route => _routes[_index][_modeIndex];

  void _previewDirections() {
    setState(() {
      _state = _NavState.preview;
      _modeIndex = 0;
    });
  }

  void _startActive() => setState(() => _state = _NavState.active);
  void _endDirections() => setState(() => _state = _NavState.browse);

  void _selectProvider(int i) {
    setState(() {
      _index = i;
      if (_state == _NavState.active) _state = _NavState.preview;
      _modeIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxHeight;
          final hasData  = !_loading && _error == null && !_permissionDenied && _providers.isNotEmpty;
          final isActive = hasData && _state == _NavState.active;
          final mapHeight = isActive ? available * 0.62 : available * 0.32;

          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                height: mapHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: MiniMap(
                        userPosition: _userLatLng,
                        centers: _nearestCenters,
                        selectedCenter: hasData && _nearestCenters.isNotEmpty
                            ? LatLng(_nearestCenters[_index].latitude, _nearestCenters[_index].longitude)
                            : null,
                        showRoute: hasData && _state != _NavState.browse,
                      ),
                    ),
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: const BoxDecoration(
                                  color: SemaColors.bg,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'A',
                                  style: TextStyle(
                                    fontFamily: 'Plus Jakarta Sans',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: SemaColors.forest,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              _CircleIcon(
                                icon: PhosphorIconsRegular.bell,
                                onTap: () {},
                              ),
                              const SizedBox(width: 8),
                              _CircleIcon(icon: PhosphorIconsRegular.slidersHorizontal, onTap: () {}),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (hasData && !isActive)
                      Positioned(
                        left: 20, bottom: 38,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: SemaColors.ink,
                            borderRadius: BorderRadius.circular(SemaRadii.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsRegular.mapPin, size: 12, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                '${_providers.length} nearby',
                                style: const TextStyle(
                                  fontFamily: 'Plus Jakarta Sans',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -28),
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: SemaColors.bg,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _loading
                          ? const _LoadingSheet(key: ValueKey('loading'))
                          : (_permissionDenied || _error != null || _providers.isEmpty)
                              ? _StatusSheet(
                                  key: const ValueKey('status'),
                                  permissionDenied: _permissionDenied,
                                  error: _error ?? (_providers.isEmpty ? 'No health centers found nearby.' : null),
                                  onRetry: _loadData,
                                )
                              : isActive
                                  ? _ActiveNavStrip(
                                      key: const ValueKey('active'),
                                      provider: _selected,
                                      route: _route,
                                      modeIcon: _modes[_modeIndex].icon,
                                      onEnd: _endDirections,
                                    )
                                  : _BrowseSheet(
                                      key: const ValueKey('browse'),
                                      providers: _providers,
                                      index: _index,
                                      modes: _modes,
                                      modeIndex: _modeIndex,
                                      navigating: _state == _NavState.preview,
                                      selected: _selected,
                                      route: _route,
                                      onProviderTap: _selectProvider,
                                      onGetDirections: _previewDirections,
                                      onModeChanged: (i) => setState(() => _modeIndex = i),
                                      onCloseDirections: _endDirections,
                                      onStart: _startActive,
                                    ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Loading sheet ────────────────────────────────────────────────────────────

class _LoadingSheet extends StatelessWidget {
  const _LoadingSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: SemaColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Spacer(),
          const CircularProgressIndicator(strokeWidth: 2, color: SemaColors.forest),
          const SizedBox(height: 20),
          const Text(
            'Finding health centers near you…',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SemaColors.inkMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// ─── Status sheet (permission denied / error) ─────────────────────────────────

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({
    super.key,
    required this.permissionDenied,
    required this.error,
    required this.onRetry,
  });

  final bool permissionDenied;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = permissionDenied
        ? 'Location permission is needed to find nearby health centers.'
        : error ?? 'Something went wrong.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: SemaColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            permissionDenied ? 'Location needed' : 'Could not load',
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: SemaColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: SemaColors.inkMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          PressScale(
            onTap: permissionDenied ? () => Geolocator.openAppSettings() : onRetry,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: SemaColors.ink,
                borderRadius: BorderRadius.circular(SemaRadii.pill),
              ),
              alignment: Alignment.center,
              child: Text(
                permissionDenied ? 'Open Settings' : 'Try again',
                style: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.05,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet for browse + preview states
// ─────────────────────────────────────────────────────────────────────────────

class _BrowseSheet extends StatelessWidget {
  const _BrowseSheet({
    super.key,
    required this.providers,
    required this.index,
    required this.modes,
    required this.modeIndex,
    required this.navigating,
    required this.selected,
    required this.route,
    required this.onProviderTap,
    required this.onGetDirections,
    required this.onModeChanged,
    required this.onCloseDirections,
    required this.onStart,
  });

  final List<_Provider> providers;
  final int index;
  final List<_TravelMode> modes;
  final int modeIndex;
  final bool navigating;
  final _Provider selected;
  final _RouteOption route;
  final ValueChanged<int> onProviderTap;
  final VoidCallback onGetDirections;
  final ValueChanged<int> onModeChanged;
  final VoidCallback onCloseDirections;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      children: [
        Center(
          child: Container(
            width: 38, height: 4,
            decoration: BoxDecoration(
              color: SemaColors.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Around you', style: t.labelMedium),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  style: t.displayMedium!.copyWith(
                    fontSize: 28, height: 1.15, letterSpacing: -0.9,
                  ),
                  children: const [
                    TextSpan(text: 'Trusted '),
                    TextSpan(
                      text: 'care',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: ', minutes away.'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
              child: navigating
                  ? _NavigationCard(
                      key: ValueKey('nav_${selected.name}'),
                      provider: selected,
                      modes: modes,
                      modeIndex: modeIndex,
                      route: route,
                      onModeChanged: onModeChanged,
                      onClose: onCloseDirections,
                      onStart: onStart,
                    )
                  : _ProviderHero(
                      key: ValueKey('hero_${selected.name}'),
                      provider: selected,
                      onGetDirections: onGetDirections,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            navigating ? 'Switch destination' : 'All nearby',
            style: t.labelMedium,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: providers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _ProviderChip(
              provider: providers[i],
              selected: i == index,
              onTap: () => onProviderTap(i),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active navigation strip
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveNavStrip extends StatelessWidget {
  const _ActiveNavStrip({
    super.key,
    required this.provider,
    required this.route,
    required this.modeIcon,
    required this.onEnd,
  });
  final _Provider provider;
  final _RouteOption route;
  final IconData modeIcon;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ink = provider.accent.ink;
    final next = route.steps.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: SemaColors.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: provider.accent.surface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(next.icon, size: 18, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Now',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: SemaColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      next.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                        height: 1.3,
                        color: SemaColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                next.distance,
                style: const TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: SemaColors.inkMid,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: SemaColors.card,
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  child: Row(
                    children: [
                      Icon(modeIcon, size: 14, color: SemaColors.ink),
                      const SizedBox(width: 8),
                      Text(
                        route.eta,
                        style: t.titleMedium?.copyWith(
                          fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 3, height: 3,
                        decoration: const BoxDecoration(
                          color: SemaColors.inkSoft, shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        route.distance,
                        style: const TextStyle(
                          fontFamily: 'Plus Jakarta Sans',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: SemaColors.inkMid,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Flexible (not Spacer + Text) so the destination
                      // name shrinks-with-ellipsis on long provider
                      // labels — "Pharmacie de la Croix Rouge" etc.
                      // Right-aligned to keep the strip's "ETA on left,
                      // destination on right" reading order.
                      Expanded(
                        child: Text(
                          'to ${provider.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: SemaColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PressScale(
                onTap: onEnd,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: SemaColors.danger,
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'End',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.05,
                      color: Colors.white,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _Provider {
  _Provider({
    required this.name,
    required this.role,
    required this.distance,
    required this.walk,
    required this.icon,
    required this.open,
    required this.tags,
    required this.accent,
    this.phone,
  });
  final String name;
  final String role;
  final String distance;
  final String walk;
  final IconData icon;
  final bool open;
  final List<String> tags;
  final SemaAccent accent;
  final String? phone;
}

class _TravelMode {
  const _TravelMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _RouteOption {
  const _RouteOption({required this.eta, required this.distance, required this.steps});
  final String eta;
  final String distance;
  final List<_Step> steps;
}

class _Step {
  const _Step(this.icon, this.text, this.distance);
  final IconData icon;
  final String text;
  final String distance;
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider hero card
// ─────────────────────────────────────────────────────────────────────────────

class _ProviderHero extends StatelessWidget {
  const _ProviderHero({super.key, required this.provider, required this.onGetDirections});
  final _Provider provider;
  final VoidCallback onGetDirections;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ink = provider.accent.ink;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(20, 18, 18, 18),
      decoration: BoxDecoration(
        color: provider.accent.surface,
        borderRadius: BorderRadius.circular(SemaRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(SemaRadii.s),
                ),
                alignment: Alignment.center,
                child: Icon(provider.icon, size: 22, color: ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    provider.role,
                    key: ValueKey('${provider.name}_role'),
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      color: ink.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
              _StatusDot(open: provider.open, ink: ink),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.18), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              provider.name,
              key: ValueKey(provider.name),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.displayMedium!.copyWith(
                fontSize: 26, height: 1.1, letterSpacing: -0.7,
                fontWeight: FontWeight.w800, color: ink,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Pill(icon: PhosphorIconsRegular.personSimpleWalk, label: provider.walk, ink: ink),
              const SizedBox(width: 8),
              _Pill(icon: PhosphorIconsRegular.mapPin, label: provider.distance, ink: ink),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: [
              for (final tag in provider.tags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(SemaRadii.pill),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                      color: ink,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  onTap: onGetDirections,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(SemaRadii.pill),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(PhosphorIconsBold.navigationArrow, size: 14, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Get directions',
                          style: TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (provider.phone != null)
                PressScale(
                  onTap: () => launchUrl(Uri(scheme: 'tel', path: provider.phone)),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(PhosphorIconsRegular.phone, size: 18, color: ink),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.ink});
  final IconData icon;
  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ink),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: ink,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.open, required this.ink});
  final bool open;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: open ? SemaColors.online : SemaColors.inkSoft,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            open ? 'Open' : 'Closed',
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({required this.provider, required this.selected, required this.onTap});
  final _Provider provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 156,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: selected ? SemaColors.ink : SemaColors.bg,
          borderRadius: BorderRadius.circular(SemaRadii.l),
          border: Border.all(
            color: selected ? SemaColors.ink : SemaColors.hairline,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: provider.accent.surface, shape: BoxShape.circle,
                  ),
                ),
                const Spacer(),
                Icon(
                  provider.icon,
                  size: 16,
                  color: selected ? Colors.white.withValues(alpha: 0.8) : SemaColors.inkMuted,
                ),
              ],
            ),
            const Spacer(),
            Text(
              provider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: selected ? Colors.white : SemaColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${provider.role} · ${provider.distance}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white.withValues(alpha: 0.6) : SemaColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: const BoxDecoration(color: SemaColors.bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: SemaColors.ink),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Directions card
// ─────────────────────────────────────────────────────────────────────────────

class _NavigationCard extends StatelessWidget {
  const _NavigationCard({
    super.key,
    required this.provider,
    required this.modes,
    required this.modeIndex,
    required this.route,
    required this.onModeChanged,
    required this.onClose,
    required this.onStart,
  });
  final _Provider provider;
  final List<_TravelMode> modes;
  final int modeIndex;
  final _RouteOption route;
  final ValueChanged<int> onModeChanged;
  final VoidCallback onClose;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ink = provider.accent.ink;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
      decoration: BoxDecoration(
        color: provider.accent.surface,
        borderRadius: BorderRadius.circular(SemaRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(SemaRadii.s),
                ),
                alignment: Alignment.center,
                child: Icon(provider.icon, size: 16, color: ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'En route to',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: ink.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      provider.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
              PressScale(
                onTap: onClose,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(PhosphorIconsBold.x, size: 14, color: ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ModeSegmentedControl(modes: modes, index: modeIndex, ink: ink, onChanged: onModeChanged),
          const SizedBox(height: 16),
          // FittedBox scales the whole "ETA · distance" line down on the
          // long-route case (e.g. French provider names + "1 hr 24 min ·
          // 1 350 km") rather than overflowing the card. Bottom-left
          // alignment keeps the baseline pinned to the column's left
          // edge so it still reads as a headline.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  route.eta,
                  style: t.displayLarge!.copyWith(
                    fontSize: 36, height: 1.0, letterSpacing: -1.4,
                    fontWeight: FontWeight.w800, color: ink,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '· ${route.distance}',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(SemaRadii.l),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (int i = 0; i < route.steps.length; i++)
                  _StepRow(
                    step: route.steps[i],
                    ink: ink,
                    first: i == 0,
                    last: i == route.steps.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PressScale(
            onTap: onStart,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: ink,
                borderRadius: BorderRadius.circular(SemaRadii.pill),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(PhosphorIconsBold.navigationArrow, size: 14, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Start',
                    style: TextStyle(
                      fontFamily: 'Plus Jakarta Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSegmentedControl extends StatelessWidget {
  const _ModeSegmentedControl({
    required this.modes,
    required this.index,
    required this.ink,
    required this.onChanged,
  });
  final List<_TravelMode> modes;
  final int index;
  final Color ink;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(SemaRadii.pill),
      ),
      child: Row(
        children: List.generate(modes.length, (i) {
          final selected = i == index;
          final m = modes[i];
          return Expanded(
            child: PressScale(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected ? ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(SemaRadii.pill),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      m.icon,
                      size: 14,
                      color: selected ? Colors.white : ink.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      m.label,
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.05,
                        color: selected ? Colors.white : ink.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.ink,
    required this.first,
    required this.last,
  });
  final _Step step;
  final Color ink;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                if (!first) Container(width: 2, height: 6, color: ink.withValues(alpha: 0.18)),
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: first ? ink : Colors.white, shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(step.icon, size: 13, color: first ? Colors.white : ink),
                ),
                if (!last) Container(width: 2, height: 6, color: ink.withValues(alpha: 0.18)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              step.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontSize: 13,
                fontWeight: first ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.05,
                height: 1.3,
                color: ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            step.distance,
            style: TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: ink.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
