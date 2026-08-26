import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/lesson_whiteboard.dart';
import '../models/lesson_whiteboard_board_set.dart';
import 'lesson_material_file_image.dart';

const double lessonWhiteboardAspectRatio = 4 / 3;
const double lessonWhiteboardMaxWidth = 640;
const double lessonWhiteboardCompactMaxWidth =
    220 * lessonWhiteboardAspectRatio;

class LessonWhiteboardMaterialSource {
  const LessonWhiteboardMaterialSource.network(this.networkUrl)
    : localFilePath = null;

  const LessonWhiteboardMaterialSource.file(this.localFilePath)
    : networkUrl = null;

  final String? networkUrl;
  final String? localFilePath;

  bool get isLocalFile => localFilePath != null;
}

typedef LessonWhiteboardMaterialUrlResolver =
    Future<LessonWhiteboardMaterialSource> Function(String storagePath);

const int _maxCachedLessonMaterialUrls = 64;
final Map<String, Future<String>> _lessonMaterialUrlCache = {};

Future<LessonWhiteboardMaterialSource> resolveLessonWhiteboardMaterialUrl(
  String storagePath,
) async {
  final cached = _lessonMaterialUrlCache.remove(storagePath);
  if (cached != null) {
    _lessonMaterialUrlCache[storagePath] = cached;
    return LessonWhiteboardMaterialSource.network(await cached);
  }

  final completer = Completer<String>();
  final future = completer.future;
  _lessonMaterialUrlCache[storagePath] = future;
  while (_lessonMaterialUrlCache.length > _maxCachedLessonMaterialUrls) {
    _lessonMaterialUrlCache.remove(_lessonMaterialUrlCache.keys.first);
  }
  unawaited(
    _loadLessonWhiteboardMaterialUrl(
      storagePath: storagePath,
      cachedFuture: future,
      completer: completer,
    ),
  );
  return LessonWhiteboardMaterialSource.network(await future);
}

Future<void> _loadLessonWhiteboardMaterialUrl({
  required String storagePath,
  required Future<String> cachedFuture,
  required Completer<String> completer,
}) async {
  try {
    completer.complete(
      await FirebaseStorage.instance.ref(storagePath).getDownloadURL(),
    );
  } catch (error, stackTrace) {
    if (identical(_lessonMaterialUrlCache[storagePath], cachedFuture)) {
      _lessonMaterialUrlCache.remove(storagePath);
    }
    completer.completeError(error, stackTrace);
  }
}

enum LessonWhiteboardViewportChangePhase { start, update, end }

class LessonWhiteboardViewportChange {
  const LessonWhiteboardViewportChange({
    required this.viewport,
    required this.phase,
  });

  final LessonWhiteboardViewport viewport;
  final LessonWhiteboardViewportChangePhase phase;
}

class LessonWhiteboardCanvas extends StatefulWidget {
  const LessonWhiteboardCanvas({
    super.key,
    required this.strokes,
    this.inProgressStroke,
    this.drawingEnabled = false,
    this.onStrokeStart,
    this.onStrokeUpdate,
    this.onStrokeEnd,
    this.onStrokeCancel,
    this.viewport,
    this.onViewportChanged,
    this.viewportInteractionEnabled = true,
    this.showViewportControls = true,
    this.topLeftOverlay,
    this.bottomLeftOverlay,
    this.maxWidth = lessonWhiteboardMaxWidth,
    this.backgroundColor = Colors.white,
    this.background,
    this.aspectRatio = lessonWhiteboardAspectRatio,
    this.materialUrlResolver = resolveLessonWhiteboardMaterialUrl,
  });

  final List<WhiteboardStroke> strokes;
  final WhiteboardStroke? inProgressStroke;
  final bool drawingEnabled;
  final VoidCallback? onStrokeStart;
  final ValueChanged<WhiteboardPoint>? onStrokeUpdate;
  final ValueChanged<WhiteboardPoint>? onStrokeEnd;
  final VoidCallback? onStrokeCancel;
  final LessonWhiteboardViewport? viewport;
  final ValueChanged<LessonWhiteboardViewportChange>? onViewportChanged;
  final bool viewportInteractionEnabled;
  final bool showViewportControls;
  final Widget? topLeftOverlay;
  final Widget? bottomLeftOverlay;
  final double maxWidth;
  final Color backgroundColor;
  final LessonWhiteboardBoardBackground? background;
  final double aspectRatio;
  final LessonWhiteboardMaterialUrlResolver materialUrlResolver;

  @override
  State<LessonWhiteboardCanvas> createState() => _LessonWhiteboardCanvasState();
}

@visibleForTesting
void debugCompleteLessonWhiteboardBackgroundRaster(Element canvasElement) {
  final state =
      (canvasElement as StatefulElement).state as _LessonWhiteboardCanvasState;
  state._onBackgroundRasterReady(state._backgroundRasterScale);
}

class LessonWhiteboardBackgroundPreloader extends StatelessWidget {
  const LessonWhiteboardBackgroundPreloader({
    super.key,
    required this.backgrounds,
    this.materialUrlResolver = resolveLessonWhiteboardMaterialUrl,
  });

  final List<LessonWhiteboardBoardBackground> backgrounds;
  final LessonWhiteboardMaterialUrlResolver materialUrlResolver;

  @override
  Widget build(BuildContext context) {
    final uniqueBackgrounds = <LessonWhiteboardBoardBackground>[];
    final storagePaths = <String>{};
    for (final background in backgrounds) {
      if (storagePaths.add(background.storagePath)) {
        uniqueBackgrounds.add(background);
      }
    }
    if (uniqueBackgrounds.isEmpty) {
      return const SizedBox.shrink();
    }
    return Offstage(
      offstage: true,
      child: SizedBox(
        width: 1,
        height: 1,
        child: Stack(
          children: [
            for (final background in uniqueBackgrounds)
              _LessonWhiteboardBackgroundPreload(
                key: ValueKey(
                  'whiteboard-background-preload-${background.storagePath}',
                ),
                background: background,
                urlResolver: materialUrlResolver,
              ),
          ],
        ),
      ),
    );
  }
}

class _LessonWhiteboardBackgroundPreload extends StatefulWidget {
  const _LessonWhiteboardBackgroundPreload({
    super.key,
    required this.background,
    required this.urlResolver,
  });

  final LessonWhiteboardBoardBackground background;
  final LessonWhiteboardMaterialUrlResolver urlResolver;

  @override
  State<_LessonWhiteboardBackgroundPreload> createState() =>
      _LessonWhiteboardBackgroundPreloadState();
}

class _LessonWhiteboardBackgroundPreloadState
    extends State<_LessonWhiteboardBackgroundPreload> {
  late Future<LessonWhiteboardMaterialSource> _sourceFuture;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  @override
  void didUpdateWidget(covariant _LessonWhiteboardBackgroundPreload oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.background.storagePath != widget.background.storagePath ||
        oldWidget.urlResolver != widget.urlResolver) {
      _resolveUrl();
    }
  }

  void _resolveUrl() {
    _sourceFuture = Future<LessonWhiteboardMaterialSource>.sync(
      () => widget.urlResolver(widget.background.storagePath),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LessonWhiteboardMaterialSource>(
      future: _sourceFuture,
      builder: (context, snapshot) {
        final source = snapshot.data;
        if (source == null) {
          return const SizedBox.shrink();
        }
        if (widget.background.isImage) {
          if (source.isLocalFile) {
            final provider = lessonMaterialFileImageProvider(
              source.localFilePath!,
            );
            return provider == null
                ? const SizedBox.shrink()
                : Image(
                    image: provider,
                    width: 1,
                    height: 1,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  );
          }
          final url = source.networkUrl;
          if (url == null || url.isEmpty) {
            return const SizedBox.shrink();
          }
          return Image.network(
            url,
            width: 1,
            height: 1,
            cacheWidth: 1024,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          );
        }
        final localPath = source.localFilePath;
        if (localPath != null) {
          return PdfDocumentViewBuilder.file(
            localPath,
            useProgressiveLoading: true,
            builder: (context, document) => const SizedBox.shrink(),
            loadingBuilder: (context) => const SizedBox.shrink(),
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          );
        }
        final url = source.networkUrl;
        return url == null || url.isEmpty
            ? const SizedBox.shrink()
            : PdfDocumentViewBuilder.uri(
                Uri.parse(url),
                useProgressiveLoading: true,
                builder: (context, document) => const SizedBox.shrink(),
                loadingBuilder: (context) => const SizedBox.shrink(),
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              );
      },
    );
  }
}

class _LessonWhiteboardBackgroundView extends StatefulWidget {
  const _LessonWhiteboardBackgroundView({
    super.key,
    required this.background,
    required this.urlResolver,
    required this.maximumDpi,
    required this.canvasSize,
    required this.visual,
    required this.visibleRasterScale,
    this.pendingRasterScale,
    required this.visibleLayoutKey,
    required this.pendingLayoutKey,
    required this.slotKeyPrefix,
    this.onRasterReady,
  });

  final LessonWhiteboardBoardBackground background;
  final LessonWhiteboardMaterialUrlResolver urlResolver;
  final double maximumDpi;
  final Size canvasSize;
  final LessonWhiteboardViewport visual;
  final double visibleRasterScale;
  final double? pendingRasterScale;
  final String visibleLayoutKey;
  final String pendingLayoutKey;
  final String slotKeyPrefix;
  final ValueChanged<double>? onRasterReady;

  @override
  State<_LessonWhiteboardBackgroundView> createState() =>
      _LessonWhiteboardBackgroundViewState();
}

class _LessonWhiteboardBackgroundViewState
    extends State<_LessonWhiteboardBackgroundView> {
  late Future<LessonWhiteboardMaterialSource> _sourceFuture;
  final Set<String> _notifiedSignatures = <String>{};

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  @override
  void didUpdateWidget(covariant _LessonWhiteboardBackgroundView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.background.storagePath != widget.background.storagePath ||
        oldWidget.urlResolver != widget.urlResolver) {
      _resolveUrl();
      _notifiedSignatures.clear();
    }
    _pruneNotifiedSignatures();
  }

  void _pruneNotifiedSignatures() {
    final keep = <String>{
      widget.visibleRasterScale.toStringAsFixed(3),
      if (widget.pendingRasterScale != null)
        widget.pendingRasterScale!.toStringAsFixed(3),
    };
    _notifiedSignatures.removeWhere((signature) => !keep.contains(signature));
  }

  void _scheduleRasterReady(double scale) {
    final signature = scale.toStringAsFixed(3);
    if (_notifiedSignatures.contains(signature)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _notifiedSignatures.contains(signature)) {
        return;
      }
      _notifiedSignatures.add(signature);
      widget.onRasterReady?.call(scale);
    });
  }

  void _resolveUrl() {
    _sourceFuture = Future<LessonWhiteboardMaterialSource>.sync(
      () => widget.urlResolver(widget.background.storagePath),
    );
  }

  String _slotKey(double rasterScale) {
    if (widget.slotKeyPrefix.endsWith('-minimap')) {
      return widget.slotKeyPrefix;
    }
    return '${widget.slotKeyPrefix}-${rasterScale.toStringAsFixed(3)}';
  }

  Widget _statusPage({required bool isError, required bool labeled}) {
    if (isError) {
      return ColoredBox(
        color: const Color(0xfff5f5f5),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            key: labeled ? const ValueKey('whiteboard-background-error') : null,
          ),
        ),
      );
    }
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: CircularProgressIndicator(
          key: labeled ? const ValueKey('whiteboard-background-loading') : null,
        ),
      ),
    );
  }

  Widget _buildRasterStack({required Widget Function(double scale) pageChild}) {
    final visibleScale = widget.visibleRasterScale;
    final pendingScale = widget.pendingRasterScale;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        _buildRasterLayer(
          rasterScale: visibleScale,
          hidden: false,
          layoutKey: widget.visibleLayoutKey,
          pageChild: pageChild(visibleScale),
        ),
        if (pendingScale != null)
          _buildRasterLayer(
            rasterScale: pendingScale,
            hidden: true,
            layoutKey: widget.pendingLayoutKey,
            pageChild: pageChild(pendingScale),
          ),
      ],
    );
  }

  Widget _buildRasterLayer({
    required double rasterScale,
    required bool hidden,
    required String layoutKey,
    required Widget pageChild,
  }) {
    final visual = widget.visual;
    final size = widget.canvasSize;
    final extraScale = visual.scale / rasterScale;
    final rasterWidth = size.width * rasterScale;
    final rasterHeight = size.height * rasterScale;
    Widget layer = SizedBox(
      width: rasterWidth,
      height: rasterHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          pageChild,
          IgnorePointer(child: SizedBox.expand(key: ValueKey(layoutKey))),
        ],
      ),
    );
    if ((extraScale - 1).abs() > 0.0001) {
      layer = Transform.scale(
        alignment: Alignment.topLeft,
        scale: extraScale,
        child: layer,
      );
    }
    return Positioned(
      key: ValueKey(_slotKey(rasterScale)),
      left: -visual.left * size.width * visual.scale,
      top: -visual.top * size.height * visual.scale,
      width: rasterWidth,
      height: rasterHeight,
      child: IgnorePointer(
        child: Offstage(offstage: hidden, child: layer),
      ),
    );
  }

  Widget _buildPdfPages(PdfDocument document) {
    return _buildRasterStack(
      pageChild: (scale) {
        final signature = scale.toStringAsFixed(3);
        return PdfPageView(
          key: ValueKey(
            'whiteboard-pdf-page-${widget.background.pageNumber}-'
            '$signature',
          ),
          document: document,
          pageNumber: widget.background.pageNumber,
          maximumDpi: widget.maximumDpi,
          backgroundColor: Colors.white,
          decorationBuilder: (context, pageSize, page, pageImage) {
            if (pageImage != null) {
              _scheduleRasterReady(scale);
            }
            return ColoredBox(
              color: Colors.white,
              child: pageImage ?? const SizedBox.expand(),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LessonWhiteboardMaterialSource>(
      future: _sourceFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildRasterStack(
            pageChild: (scale) => _statusPage(
              isError: true,
              labeled: _sameWhiteboardRasterScale(
                scale,
                widget.visibleRasterScale,
              ),
            ),
          );
        }
        final source = snapshot.data;
        if (source == null) {
          return _buildRasterStack(
            pageChild: (scale) => _statusPage(
              isError: false,
              labeled: _sameWhiteboardRasterScale(
                scale,
                widget.visibleRasterScale,
              ),
            ),
          );
        }
        if (widget.background.isImage) {
          if (source.isLocalFile) {
            final provider = lessonMaterialFileImageProvider(
              source.localFilePath!,
            );
            if (provider == null) {
              return _buildRasterStack(
                pageChild: (scale) => _statusPage(
                  isError: true,
                  labeled: _sameWhiteboardRasterScale(
                    scale,
                    widget.visibleRasterScale,
                  ),
                ),
              );
            }
            return _buildRasterStack(
              pageChild: (scale) => _sizedImageBackground(
                image: provider,
                rasterSignature: scale.toStringAsFixed(3),
                onFrame: () => _scheduleRasterReady(scale),
              ),
            );
          }
          final url = source.networkUrl;
          if (url == null || url.isEmpty) {
            return _buildRasterStack(
              pageChild: (_) => const ColoredBox(color: Colors.white),
            );
          }
          return _buildRasterStack(
            pageChild: (scale) => _sizedNetworkImageBackground(
              url: url,
              rasterSignature: scale.toStringAsFixed(3),
              onFrame: () => _scheduleRasterReady(scale),
            ),
          );
        }
        Widget loadingBuilder(BuildContext context) => _buildRasterStack(
          pageChild: (scale) => _statusPage(
            isError: false,
            labeled: _sameWhiteboardRasterScale(
              scale,
              widget.visibleRasterScale,
            ),
          ),
        );
        Widget builder(BuildContext context, PdfDocument? document) =>
            document == null
            ? loadingBuilder(context)
            : _buildPdfPages(document);
        Widget errorBuilder(
          BuildContext context,
          Object error,
          StackTrace? stackTrace,
        ) => _buildRasterStack(
          pageChild: (scale) => _statusPage(
            isError: true,
            labeled: _sameWhiteboardRasterScale(
              scale,
              widget.visibleRasterScale,
            ),
          ),
        );
        final localPath = source.localFilePath;
        if (localPath != null) {
          return PdfDocumentViewBuilder.file(
            localPath,
            key: ValueKey('whiteboard-pdf-${widget.background.assetId}'),
            useProgressiveLoading: true,
            builder: builder,
            loadingBuilder: loadingBuilder,
            errorBuilder: errorBuilder,
          );
        }
        final url = source.networkUrl;
        return url == null || url.isEmpty
            ? _buildRasterStack(
                pageChild: (_) => const ColoredBox(color: Colors.white),
              )
            : PdfDocumentViewBuilder.uri(
                Uri.parse(url),
                key: ValueKey('whiteboard-pdf-${widget.background.assetId}'),
                useProgressiveLoading: true,
                builder: builder,
                loadingBuilder: loadingBuilder,
                errorBuilder: errorBuilder,
              );
      },
    );
  }
}

Widget _sizedImageBackground({
  required ImageProvider image,
  required String rasterSignature,
  VoidCallback? onFrame,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final cacheSize = _imageCacheSizeFor(context, constraints);
      return Image(
        image: ResizeImage(image, width: cacheSize.$1, height: cacheSize.$2),
        key: ValueKey('whiteboard-image-background-$rasterSignature'),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null || wasSynchronouslyLoaded) {
            onFrame?.call();
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: Color(0xfff5f5f5),
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    },
  );
}

Widget _sizedNetworkImageBackground({
  required String url,
  required String rasterSignature,
  VoidCallback? onFrame,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final cacheSize = _imageCacheSizeFor(context, constraints);
      return Image.network(
        url,
        key: ValueKey('whiteboard-image-background-$rasterSignature'),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
        cacheWidth: cacheSize.$1,
        cacheHeight: cacheSize.$2,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null || wasSynchronouslyLoaded) {
            onFrame?.call();
          }
          return child;
        },
        errorBuilder: (context, error, stackTrace) => const ColoredBox(
          color: Color(0xfff5f5f5),
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    },
  );
}

(int, int) _imageCacheSizeFor(
  BuildContext context,
  BoxConstraints constraints,
) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final layoutWidth = constraints.maxWidth.isFinite
      ? constraints.maxWidth
      : 1.0;
  final layoutHeight = constraints.maxHeight.isFinite
      ? constraints.maxHeight
      : 1.0;
  final width = (layoutWidth * dpr).round().clamp(1, 4096);
  final height = (layoutHeight * dpr).round().clamp(1, 4096);
  return (width, height);
}

bool _sameWhiteboardRasterScale(double a, double b) => (a - b).abs() < 0.001;

bool _sameWhiteboardBackground(
  LessonWhiteboardBoardBackground? a,
  LessonWhiteboardBoardBackground? b,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null) {
    return false;
  }
  return a.assetId == b.assetId &&
      a.pageNumber == b.pageNumber &&
      a.storagePath == b.storagePath &&
      a.mediaType == b.mediaType;
}

class _LessonWhiteboardCanvasState extends State<LessonWhiteboardCanvas> {
  final Map<int, Offset> _pointerPositions = {};
  late LessonWhiteboardViewport _viewport;
  late double _backgroundRasterScale;
  late double _visibleRasterScale;
  bool _visibleRasterReady = false;
  double? _queuedRasterScale;
  Timer? _minimapHideTimer;
  Timer? _scrollInteractionEndTimer;
  bool _minimapVisible = false;
  bool _viewInteractionActive = false;
  bool _suppressUntilAllPointersUp = false;
  int? _drawingPointer;
  int? _panPointer;
  Offset? _lastFocalPoint;
  double? _lastPointerSpan;

  @override
  void initState() {
    super.initState();
    _viewport = widget.viewport ?? LessonWhiteboardViewport.full;
    _backgroundRasterScale = _viewport.scale;
    _visibleRasterScale = _backgroundRasterScale;
    _visibleRasterReady = false;
    _queuedRasterScale = null;
  }

  bool get _isPendingRasterInFlight =>
      _visibleRasterReady &&
      !_sameWhiteboardRasterScale(_visibleRasterScale, _backgroundRasterScale);

  double get _hysteresisRasterScale =>
      _queuedRasterScale ?? _backgroundRasterScale;

  /// Starts a new PDF/image raster only when none is already in flight.
  /// While one is rendering, keep showing the old image and remember the
  /// latest desired scale for afterwards.
  void _requestBackgroundRasterScale(double desiredScale) {
    if (_sameWhiteboardRasterScale(desiredScale, _backgroundRasterScale)) {
      _queuedRasterScale = null;
      return;
    }
    if (_isPendingRasterInFlight) {
      _queuedRasterScale = desiredScale;
      return;
    }
    _backgroundRasterScale = desiredScale;
    _queuedRasterScale = null;
  }

  @override
  void didUpdateWidget(covariant LessonWhiteboardCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameWhiteboardBackground(oldWidget.background, widget.background)) {
      _visibleRasterReady = false;
      _visibleRasterScale = _backgroundRasterScale;
      _queuedRasterScale = null;
    }
    final controlledViewport = widget.viewport;
    if (controlledViewport != null && !_viewInteractionActive) {
      if (controlledViewport != _viewport) {
        _viewport = controlledViewport;
        _showMinimap(scheduleHide: true);
      }
      _requestBackgroundRasterScale(
        commitLessonWhiteboardBackgroundRasterScale(
          visualScale: controlledViewport.scale,
          currentRasterScale: _hysteresisRasterScale,
        ),
      );
    }
  }

  void _onBackgroundRasterReady(double scale) {
    if (!mounted) {
      return;
    }
    if (!_sameWhiteboardRasterScale(scale, _backgroundRasterScale)) {
      return;
    }
    if (_visibleRasterReady &&
        _sameWhiteboardRasterScale(scale, _visibleRasterScale)) {
      return;
    }
    setState(() {
      _visibleRasterScale = scale;
      _visibleRasterReady = true;
      final queued = _queuedRasterScale;
      _queuedRasterScale = null;
      if (queued != null && !_sameWhiteboardRasterScale(queued, scale)) {
        _backgroundRasterScale = queued;
      }
    });
  }

  @override
  void dispose() {
    _minimapHideTimer?.cancel();
    _scrollInteractionEndTimer?.cancel();
    super.dispose();
  }

  void _showMinimap({required bool scheduleHide}) {
    _minimapHideTimer?.cancel();
    if (!_minimapVisible && mounted) {
      setState(() => _minimapVisible = true);
    } else {
      _minimapVisible = true;
    }
    if (scheduleHide) {
      _minimapHideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _minimapVisible = false);
        }
      });
    }
  }

  void _beginViewInteraction() {
    if (_viewInteractionActive) {
      return;
    }
    _viewInteractionActive = true;
    _showMinimap(scheduleHide: false);
    widget.onViewportChanged?.call(
      LessonWhiteboardViewportChange(
        viewport: _viewport,
        phase: LessonWhiteboardViewportChangePhase.start,
      ),
    );
  }

  void _setViewport(LessonWhiteboardViewport viewport) {
    if (viewport == _viewport) {
      return;
    }
    setState(() {
      _viewport = viewport;
      _requestBackgroundRasterScale(
        commitLessonWhiteboardBackgroundRasterScale(
          visualScale: viewport.scale,
          currentRasterScale: _hysteresisRasterScale,
        ),
      );
    });
    _showMinimap(scheduleHide: false);
    widget.onViewportChanged?.call(
      LessonWhiteboardViewportChange(
        viewport: viewport,
        phase: LessonWhiteboardViewportChangePhase.update,
      ),
    );
  }

  void _endViewInteraction() {
    if (!_viewInteractionActive) {
      return;
    }
    _viewInteractionActive = false;
    _scrollInteractionEndTimer = null;
    final snapped = _viewport.scale
        .clamp(
          minLessonWhiteboardViewportScale,
          maxLessonWhiteboardViewportScale,
        )
        .toDouble();
    if (!_sameWhiteboardRasterScale(snapped, _backgroundRasterScale) ||
        (_queuedRasterScale != null &&
            !_sameWhiteboardRasterScale(snapped, _queuedRasterScale!))) {
      setState(() => _requestBackgroundRasterScale(snapped));
    }
    widget.onViewportChanged?.call(
      LessonWhiteboardViewportChange(
        viewport: _viewport,
        phase: LessonWhiteboardViewportChangePhase.end,
      ),
    );
    _showMinimap(scheduleHide: true);
  }

  void _applySingleViewportChange(LessonWhiteboardViewport viewport) {
    _beginViewInteraction();
    _setViewport(viewport);
    _endViewInteraction();
  }

  WhiteboardPoint _boardPoint(Offset position, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return const WhiteboardPoint(x: 0, y: 0);
    }
    return WhiteboardPoint(
      x:
          (_viewport.centerX +
                  (((position.dx / size.width) - 0.5) / _viewport.scale))
              .clamp(0.0, 1.0),
      y:
          (_viewport.centerY +
                  (((position.dy / size.height) - 0.5) / _viewport.scale))
              .clamp(0.0, 1.0),
    );
  }

  Offset _currentFocalPoint() {
    final positions = _pointerPositions.values.take(2).toList();
    if (positions.length < 2) {
      return positions.isEmpty ? Offset.zero : positions.single;
    }
    return Offset(
      (positions[0].dx + positions[1].dx) / 2,
      (positions[0].dy + positions[1].dy) / 2,
    );
  }

  double _currentPointerSpan() {
    final positions = _pointerPositions.values.take(2).toList();
    if (positions.length < 2) {
      return 0;
    }
    return (positions[0] - positions[1]).distance;
  }

  void _startMultiPointerInteraction() {
    if (_drawingPointer != null) {
      widget.onStrokeCancel?.call();
    }
    _drawingPointer = null;
    _panPointer = null;
    _beginViewInteraction();
    _lastFocalPoint = _currentFocalPoint();
    _lastPointerSpan = _currentPointerSpan();
  }

  void _updateMultiPointerInteraction(Size size) {
    final previousFocal = _lastFocalPoint;
    final previousSpan = _lastPointerSpan;
    final focal = _currentFocalPoint();
    final span = _currentPointerSpan();
    if (previousFocal == null ||
        previousSpan == null ||
        previousSpan <= 0 ||
        span <= 0) {
      _lastFocalPoint = focal;
      _lastPointerSpan = span;
      return;
    }
    final boardPointAtPreviousFocal = _boardPoint(previousFocal, size);
    final nextScale = (_viewport.scale * (span / previousSpan))
        .clamp(
          minLessonWhiteboardViewportScale,
          maxLessonWhiteboardViewportScale,
        )
        .toDouble();
    final nextViewport = LessonWhiteboardViewport.normalized(
      centerX:
          boardPointAtPreviousFocal.x -
          (((focal.dx / size.width) - 0.5) / nextScale),
      centerY:
          boardPointAtPreviousFocal.y -
          (((focal.dy / size.height) - 0.5) / nextScale),
      scale: nextScale,
    );
    _setViewport(nextViewport);
    _lastFocalPoint = focal;
    _lastPointerSpan = span;
  }

  void _updateSinglePointerPan(Offset position, Size size) {
    final previous = _lastFocalPoint;
    if (previous == null) {
      _lastFocalPoint = position;
      return;
    }
    final dragDelta = position - previous;
    if (!_viewInteractionActive && dragDelta.distance < kTouchSlop) {
      return;
    }
    _beginViewInteraction();
    final nextViewport = LessonWhiteboardViewport.normalized(
      centerX:
          _viewport.centerX - (dragDelta.dx / (size.width * _viewport.scale)),
      centerY:
          _viewport.centerY - (dragDelta.dy / (size.height * _viewport.scale)),
      scale: _viewport.scale,
    );
    _setViewport(nextViewport);
    _lastFocalPoint = position;
  }

  void _handlePointerDown(PointerDownEvent event, Size size) {
    if (_scrollInteractionEndTimer != null) {
      _scrollInteractionEndTimer?.cancel();
      _scrollInteractionEndTimer = null;
      _endViewInteraction();
    }
    _pointerPositions[event.pointer] = event.localPosition;
    if (!widget.viewportInteractionEnabled) {
      if (widget.drawingEnabled && _pointerPositions.length == 1) {
        _drawingPointer = event.pointer;
        widget.onStrokeStart?.call();
        widget.onStrokeUpdate?.call(_boardPoint(event.localPosition, size));
      }
      return;
    }
    if (_pointerPositions.length >= 2) {
      _startMultiPointerInteraction();
      return;
    }
    if (_suppressUntilAllPointersUp) {
      return;
    }
    if (widget.drawingEnabled) {
      _drawingPointer = event.pointer;
      widget.onStrokeStart?.call();
      widget.onStrokeUpdate?.call(_boardPoint(event.localPosition, size));
    } else if (_viewport.scale > minLessonWhiteboardViewportScale) {
      _panPointer = event.pointer;
      _lastFocalPoint = event.localPosition;
    }
  }

  void _handlePointerMove(PointerMoveEvent event, Size size) {
    if (!_pointerPositions.containsKey(event.pointer)) {
      return;
    }
    _pointerPositions[event.pointer] = event.localPosition;
    if (widget.viewportInteractionEnabled && _pointerPositions.length >= 2) {
      _updateMultiPointerInteraction(size);
      return;
    }
    if (_suppressUntilAllPointersUp) {
      return;
    }
    if (_drawingPointer == event.pointer && widget.drawingEnabled) {
      widget.onStrokeUpdate?.call(_boardPoint(event.localPosition, size));
    } else if (_panPointer == event.pointer &&
        widget.viewportInteractionEnabled) {
      _updateSinglePointerPan(event.localPosition, size);
    }
  }

  void _handlePointerEnd(
    PointerEvent event,
    Size size, {
    required bool cancelled,
  }) {
    final hadMultiplePointers = _pointerPositions.length >= 2;
    if (_drawingPointer == event.pointer) {
      if (cancelled) {
        widget.onStrokeCancel?.call();
      } else {
        widget.onStrokeEnd?.call(_boardPoint(event.localPosition, size));
      }
      _drawingPointer = null;
    }
    if (_panPointer == event.pointer) {
      _panPointer = null;
      _endViewInteraction();
    }
    _pointerPositions.remove(event.pointer);
    if (hadMultiplePointers && _pointerPositions.length < 2) {
      _endViewInteraction();
      _suppressUntilAllPointersUp = true;
    }
    if (_pointerPositions.isEmpty) {
      _suppressUntilAllPointersUp = false;
      _lastFocalPoint = null;
      _lastPointerSpan = null;
    }
  }

  double _nextZoomLevel({required bool zoomIn}) {
    const levels = <double>[1, 2, 4, 8];
    if (zoomIn) {
      return levels.firstWhere(
        (level) => level > _viewport.scale + 0.001,
        orElse: () => maxLessonWhiteboardViewportScale,
      );
    }
    return levels.reversed.firstWhere(
      (level) => level < _viewport.scale - 0.001,
      orElse: () => minLessonWhiteboardViewportScale,
    );
  }

  void _zoomAt(Offset focalPoint, Size size, double nextScale) {
    final boardPointAtFocal = _boardPoint(focalPoint, size);
    _applySingleViewportChange(
      LessonWhiteboardViewport.normalized(
        centerX:
            boardPointAtFocal.x -
            (((focalPoint.dx / size.width) - 0.5) / nextScale),
        centerY:
            boardPointAtFocal.y -
            (((focalPoint.dy / size.height) - 0.5) / nextScale),
        scale: nextScale,
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event, Size size) {
    if (!widget.viewportInteractionEnabled || event is! PointerScrollEvent) {
      return;
    }
    final zoomIn = event.scrollDelta.dy < 0;
    final factor = zoomIn ? 1.2 : 1 / 1.2;
    final nextScale = (_viewport.scale * factor)
        .clamp(
          minLessonWhiteboardViewportScale,
          maxLessonWhiteboardViewportScale,
        )
        .toDouble();
    if (nextScale != _viewport.scale) {
      final boardPointAtFocal = _boardPoint(event.localPosition, size);
      _beginViewInteraction();
      _setViewport(
        LessonWhiteboardViewport.normalized(
          centerX:
              boardPointAtFocal.x -
              (((event.localPosition.dx / size.width) - 0.5) / nextScale),
          centerY:
              boardPointAtFocal.y -
              (((event.localPosition.dy / size.height) - 0.5) / nextScale),
          scale: nextScale,
        ),
      );
      _scrollInteractionEndTimer?.cancel();
      _scrollInteractionEndTimer = Timer(
        const Duration(milliseconds: 160),
        _endViewInteraction,
      );
    }
  }

  Widget _buildControls(Size size) {
    final canZoomOut =
        _viewport.scale > minLessonWhiteboardViewportScale + 0.001;
    final canZoomIn =
        _viewport.scale < maxLessonWhiteboardViewportScale - 0.001;
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('whiteboard-zoom-out'),
              tooltip: '縮小',
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: canZoomOut
                  ? () => _zoomAt(
                      size.center(Offset.zero),
                      size,
                      _nextZoomLevel(zoomIn: false),
                    )
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text(
              '${_viewport.scale.toStringAsFixed(_viewport.scale % 1 == 0 ? 0 : 1)}x',
              key: const ValueKey('whiteboard-zoom-label'),
              style: const TextStyle(color: Colors.white),
            ),
            IconButton(
              key: const ValueKey('whiteboard-zoom-in'),
              tooltip: '拡大',
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: canZoomIn
                  ? () => _zoomAt(
                      size.center(Offset.zero),
                      size,
                      _nextZoomLevel(zoomIn: true),
                    )
                  : null,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              key: const ValueKey('whiteboard-zoom-reset'),
              tooltip: '元の大きさに戻す',
              visualDensity: VisualDensity.compact,
              color: Colors.white,
              onPressed: canZoomOut
                  ? () => _applySingleViewportChange(
                      LessonWhiteboardViewport.full,
                    )
                  : null,
              icon: const Icon(Icons.center_focus_strong),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(Size size, {bool minimap = false}) {
    final background = widget.background;
    if (background == null) {
      return const SizedBox.shrink();
    }
    if (minimap) {
      return _LessonWhiteboardBackgroundView(
        key: ValueKey(
          'whiteboard-background-${background.assetId}-'
          '${background.pageNumber}-minimap',
        ),
        background: background,
        urlResolver: widget.materialUrlResolver,
        maximumDpi: 96,
        canvasSize: size,
        visual: LessonWhiteboardViewport.full,
        visibleRasterScale: 1,
        visibleLayoutKey: 'whiteboard-background-raster-layout-minimap',
        pendingLayoutKey: 'whiteboard-background-raster-layout-minimap-pending',
        slotKeyPrefix: 'whiteboard-background-raster-slot-minimap',
      );
    }
    final pendingScale = _backgroundRasterScale;
    final visibleScale = _visibleRasterReady
        ? _visibleRasterScale
        : pendingScale;
    final hasPending =
        _visibleRasterReady &&
        !_sameWhiteboardRasterScale(visibleScale, pendingScale);
    return _LessonWhiteboardBackgroundView(
      key: ValueKey(
        'whiteboard-background-${background.assetId}-'
        '${background.pageNumber}',
      ),
      background: background,
      urlResolver: widget.materialUrlResolver,
      maximumDpi: 300,
      canvasSize: size,
      visual: _viewport,
      visibleRasterScale: visibleScale,
      pendingRasterScale: hasPending ? pendingScale : null,
      visibleLayoutKey: 'whiteboard-background-raster-layout',
      pendingLayoutKey: 'whiteboard-background-raster-layout-pending',
      slotKeyPrefix: 'whiteboard-background-raster-slot',
      onRasterReady: _onBackgroundRasterReady,
    );
  }

  @override
  Widget build(BuildContext context) {
    final allStrokes = [
      ...widget.strokes,
      if (widget.inProgressStroke != null) widget.inProgressStroke!,
    ];
    final aspectRatio = widget.aspectRatio.isFinite && widget.aspectRatio > 0
        ? widget.aspectRatio
        : lessonWhiteboardAspectRatio;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: AspectRatio(
          key: const ValueKey('whiteboard-aspect-ratio'),
          aspectRatio: aspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final minimapWidth = math.min(120.0, size.width * 0.32);
              final minimapSize = Size(
                minimapWidth,
                minimapWidth / aspectRatio,
              );
              return Semantics(
                label: 'ホワイトボード',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: widget.backgroundColor,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RawGestureDetector(
                          gestures: {
                            _WhiteboardGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  _WhiteboardGestureRecognizer
                                >(_WhiteboardGestureRecognizer.new, (
                                  recognizer,
                                ) {
                                  recognizer.acceptSinglePointer =
                                      widget.drawingEnabled ||
                                      (widget.viewportInteractionEnabled &&
                                          _viewport.scale >
                                              minLessonWhiteboardViewportScale);
                                }),
                          },
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) =>
                                _handlePointerDown(event, size),
                            onPointerMove: (event) =>
                                _handlePointerMove(event, size),
                            onPointerUp: (event) => _handlePointerEnd(
                              event,
                              size,
                              cancelled: false,
                            ),
                            onPointerCancel: (event) =>
                                _handlePointerEnd(event, size, cancelled: true),
                            onPointerSignal: (event) =>
                                _handlePointerSignal(event, size),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (widget.background != null)
                                  _buildBackground(size),
                                CustomPaint(
                                  size: size,
                                  painter: _LessonWhiteboardPainter(
                                    strokes: allStrokes,
                                    viewport: _viewport,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.viewportInteractionEnabled &&
                            widget.showViewportControls)
                          _buildControls(size),
                        if (widget.topLeftOverlay case final overlay?)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: IgnorePointer(child: overlay),
                          ),
                        if (widget.bottomLeftOverlay case final overlay?)
                          Positioned(left: 8, bottom: 8, child: overlay),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              key: const ValueKey('whiteboard-minimap'),
                              opacity: _minimapVisible ? 1 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: widget.backgroundColor.withValues(
                                    alpha: 0.92,
                                  ),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: const [
                                    BoxShadow(
                                      blurRadius: 4,
                                      color: Color(0x33000000),
                                    ),
                                  ],
                                ),
                                child: SizedBox.fromSize(
                                  size: minimapSize,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (widget.background != null)
                                        _buildBackground(
                                          minimapSize,
                                          minimap: true,
                                        ),
                                      CustomPaint(
                                        painter:
                                            _LessonWhiteboardMinimapPainter(
                                              strokes: allStrokes,
                                              viewport: _viewport,
                                              viewportColor: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WhiteboardGestureRecognizer extends OneSequenceGestureRecognizer {
  bool acceptSinglePointer = false;
  final Set<int> _trackedPointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    _trackedPointers.add(event.pointer);
    if (acceptSinglePointer || _trackedPointers.length >= 2) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
      _trackedPointers.remove(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _trackedPointers.clear();
  }

  @override
  String get debugDescription => 'whiteboard';
}

class _LessonWhiteboardPainter extends CustomPainter {
  const _LessonWhiteboardPainter({
    required this.strokes,
    required this.viewport,
  });

  final List<WhiteboardStroke> strokes;
  final LessonWhiteboardViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWhiteboardStrokes(
      canvas: canvas,
      size: size,
      strokes: strokes,
      viewport: viewport,
      scaleStrokeWidth: true,
    );
  }

  @override
  bool shouldRepaint(covariant _LessonWhiteboardPainter oldDelegate) {
    return oldDelegate.viewport != viewport ||
        _strokeListVisualsChanged(oldDelegate.strokes, strokes);
  }
}

class _LessonWhiteboardMinimapPainter extends CustomPainter {
  const _LessonWhiteboardMinimapPainter({
    required this.strokes,
    required this.viewport,
    required this.viewportColor,
  });

  final List<WhiteboardStroke> strokes;
  final LessonWhiteboardViewport viewport;
  final Color viewportColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintWhiteboardStrokes(
      canvas: canvas,
      size: size,
      strokes: strokes,
      viewport: LessonWhiteboardViewport.full,
      scaleStrokeWidth: false,
    );
    final viewportRect = Rect.fromLTWH(
      viewport.left * size.width,
      viewport.top * size.height,
      viewport.width * size.width,
      viewport.height * size.height,
    );
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = viewportColor.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      viewportRect,
      Paint()
        ..color = viewportColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _LessonWhiteboardMinimapPainter oldDelegate) {
    return oldDelegate.viewport != viewport ||
        oldDelegate.viewportColor != viewportColor ||
        _strokeListVisualsChanged(oldDelegate.strokes, strokes);
  }
}

void _paintWhiteboardStrokes({
  required Canvas canvas,
  required Size size,
  required List<WhiteboardStroke> strokes,
  required LessonWhiteboardViewport viewport,
  required bool scaleStrokeWidth,
}) {
  for (final stroke in strokes) {
    if (stroke.points.length < 2) {
      continue;
    }
    final paint = Paint()
      ..color = Color(stroke.colorArgb)
      ..strokeWidth = scaleStrokeWidth
          ? stroke.strokeWidth * viewport.scale
          : math.max(0.7, stroke.strokeWidth * 0.35)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final first = _viewportPosition(stroke.points.first, size, viewport);
    path.moveTo(first.dx, first.dy);
    for (var index = 1; index < stroke.points.length; index++) {
      final point = _viewportPosition(stroke.points[index], size, viewport);
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
}

Offset _viewportPosition(
  WhiteboardPoint point,
  Size size,
  LessonWhiteboardViewport viewport,
) {
  return Offset(
    (point.x.clamp(0.0, 1.0) - viewport.left) * size.width * viewport.scale,
    (point.y.clamp(0.0, 1.0) - viewport.top) * size.height * viewport.scale,
  );
}

bool _strokeListVisualsChanged(
  List<WhiteboardStroke> previous,
  List<WhiteboardStroke> next,
) {
  if (identical(previous, next)) {
    return false;
  }
  if (previous.length != next.length) {
    return true;
  }
  for (var index = 0; index < next.length; index++) {
    if (_strokeVisualsChanged(previous[index], next[index])) {
      return true;
    }
  }
  return false;
}

bool _strokeVisualsChanged(WhiteboardStroke previous, WhiteboardStroke next) {
  if (previous.id != next.id ||
      previous.colorArgb != next.colorArgb ||
      previous.strokeWidth != next.strokeWidth ||
      previous.points.length != next.points.length) {
    return true;
  }
  if (previous.points.isEmpty) {
    return false;
  }
  final previousLast = previous.points.last;
  final nextLast = next.points.last;
  return previousLast.x != nextLast.x || previousLast.y != nextLast.y;
}

double whiteboardStrokeWidthForSize(Size size) {
  return math.max(2, math.min(size.width, size.height) * 0.008);
}
