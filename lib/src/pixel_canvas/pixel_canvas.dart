import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/drawing_controller.dart';

enum PixelCanvasLod { colors, grid, numbers }

abstract interface class PixelCanvasBoard {
  int get gridSize;
  int get totalCells;
  int get selectedNumber;
  int get paintRevision;
  Iterable<int> get lastPaintedIndexes;
  Object? get structureKey;
  bool get hasTransparentCells;
  Color get selectedColor;
  Iterable<int> get numberKeys;

  int numberAt(int index);
  bool isPaintedAt(int index);
  Color colorForNumber(int number);
  Set<int> completedNumbers();

  /// Cell indexes assigned [number]. Lets overlay passes visit only the
  /// relevant cells instead of scanning every visible cell.
  List<int> indexesForNumber(int number);
}

final class PixelCanvasMemoryBoard extends ChangeNotifier
    implements PixelCanvasBoard {
  PixelCanvasMemoryBoard({
    required this.gridSize,
    required Uint8List numbers,
    required Uint8List painted,
    required Uint32List paletteArgb,
    int selectedNumber = 1,
  }) : _numbers = numbers,
       _painted = painted,
       _paletteArgb = paletteArgb,
       _selectedNumber = selectedNumber {
    if (_numbers.length != gridSize * gridSize ||
        _painted.length != _numbers.length) {
      throw const FormatException('Pixel board has invalid dimensions');
    }
    _totalCounts = Uint32List(_paletteArgb.length);
    _paintedCounts = Uint32List(_paletteArgb.length);
    for (var index = 0; index < _numbers.length; index++) {
      final number = _numbers[index];
      if (number >= _paletteArgb.length) {
        throw const FormatException('Pixel board number exceeds palette');
      }
      _totalCounts[number]++;
      if (_painted[index] == 1) _paintedCounts[number]++;
    }
  }

  factory PixelCanvasMemoryBoard.generated({
    int gridSize = 256,
    int colorCount = 12,
  }) {
    final numbers = Uint8List(gridSize * gridSize);
    final painted = Uint8List(gridSize * gridSize);
    final palette = Uint32List(colorCount + 1);
    palette[0] = Colors.white.toARGB32();
    for (var number = 1; number <= colorCount; number++) {
      palette[number] = HSVColor.fromAHSV(
        1,
        (number * 37) % 360,
        0.48 + ((number % 4) * 0.08),
        0.72 + ((number % 3) * 0.07),
      ).toColor().toARGB32();
    }

    final center = (gridSize - 1) / 2;
    for (var y = 0; y < gridSize; y++) {
      for (var x = 0; x < gridSize; x++) {
        final dx = x - center;
        final dy = y - center;
        final radius = math.sqrt((dx * dx) + (dy * dy));
        final wave = (math.sin(x / 9) + math.cos(y / 11)) * 1.5;
        final band = ((radius / 18) + wave).floor().abs();
        numbers[y * gridSize + x] = 1 + (band % colorCount);
      }
    }

    return PixelCanvasMemoryBoard(
      gridSize: gridSize,
      numbers: numbers,
      painted: painted,
      paletteArgb: palette,
    );
  }

  @override
  final int gridSize;
  final Uint8List _numbers;
  final Uint8List _painted;
  final Uint32List _paletteArgb;
  late final Uint32List _totalCounts;
  late final Uint32List _paintedCounts;
  int _selectedNumber;
  int _paintRevision = 0;
  List<int> _lastPaintedIndexes = const <int>[];

  @override
  int get totalCells => _numbers.length;

  @override
  int get selectedNumber => _selectedNumber;

  @override
  int get paintRevision => _paintRevision;

  @override
  Iterable<int> get lastPaintedIndexes => _lastPaintedIndexes;

  @override
  Object? get structureKey => _numbers;

  @override
  bool get hasTransparentCells => _totalCounts[0] > 0;

  @override
  Color get selectedColor => colorForNumber(_selectedNumber);

  @override
  Iterable<int> get numberKeys sync* {
    for (var number = 0; number < _totalCounts.length; number++) {
      if (_totalCounts[number] > 0) yield number;
    }
  }

  double get progress {
    final total = _totalCounts[_selectedNumber];
    return total == 0 ? 1 : _paintedCounts[_selectedNumber] / total;
  }

  int totalCountForNumber(int number) =>
      number >= 0 && number < _totalCounts.length ? _totalCounts[number] : 0;

  int paintedCountForNumber(int number) =>
      number >= 0 && number < _paintedCounts.length
      ? _paintedCounts[number]
      : 0;

  void selectNumber(int number) {
    if (number <= 0 ||
        number >= _paletteArgb.length ||
        number == _selectedNumber) {
      return;
    }
    _selectedNumber = number;
    notifyListeners();
  }

  List<int> paintIndexes(Iterable<int> indexes, {int? requiredNumber}) {
    final painted = <int>[];
    final numberToPaint = requiredNumber ?? _selectedNumber;
    for (final index in indexes) {
      if (index < 0 || index >= _painted.length || _painted[index] == 1) {
        continue;
      }
      final number = _numbers[index];
      if (number == 0 || number != numberToPaint) continue;
      _painted[index] = 1;
      _paintedCounts[number]++;
      painted.add(index);
    }
    if (painted.isEmpty) return painted;
    _lastPaintedIndexes = List<int>.unmodifiable(painted);
    _paintRevision++;
    notifyListeners();
    return painted;
  }

  void reset() {
    _painted.fillRange(0, _painted.length, 0);
    _paintedCounts.fillRange(0, _paintedCounts.length, 0);
    for (var index = 0; index < _numbers.length; index++) {
      if (_numbers[index] == 0) {
        _painted[index] = 1;
        _paintedCounts[0]++;
      }
    }
    _lastPaintedIndexes = List<int>.generate(_painted.length, (index) => index);
    _paintRevision++;
    notifyListeners();
  }

  @override
  int numberAt(int index) => _numbers[index];

  @override
  bool isPaintedAt(int index) => _painted[index] == 1;

  @override
  Color colorForNumber(int number) {
    if (number < 0 || number >= _paletteArgb.length) return Colors.black;
    return Color(_paletteArgb[number]);
  }

  @override
  Set<int> completedNumbers() {
    return {
      for (var number = 1; number < _totalCounts.length; number++)
        if (_totalCounts[number] > 0 &&
            _paintedCounts[number] == _totalCounts[number])
          number,
    };
  }

  Map<int, List<int>>? _numberIndexes;

  @override
  List<int> indexesForNumber(int number) {
    // Numbers never change after construction, so build the map lazily once.
    final cache = _numberIndexes ??= _buildNumberIndexes();
    return cache[number] ?? const <int>[];
  }

  Map<int, List<int>> _buildNumberIndexes() {
    final map = <int, List<int>>{};
    for (var index = 0; index < _numbers.length; index++) {
      map.putIfAbsent(_numbers[index], () => <int>[]).add(index);
    }
    return map;
  }
}

final class PixelCanvasCameraController extends ChangeNotifier {
  PixelCanvasCameraController({required DrawingConfig sourceConfig})
    : _sourceController = DrawingController(config: sourceConfig) {
    _sourceController.addListener(notifyListeners);
  }

  final DrawingController _sourceController;

  double get minScale => _sourceController.config.minScale;
  double get maxScale => _sourceController.config.maxScale;
  double get scale => _sourceController.canvasScale;
  Offset get offset => _sourceController.canvasOffset;

  Offset screenToWorld(Offset screen) {
    return Offset(
      (screen.dx - offset.dx) / scale,
      (screen.dy - offset.dy) / scale,
    );
  }

  Rect visibleWorldRect(Size viewport) {
    final topLeft = screenToWorld(Offset.zero);
    return topLeft & Size(viewport.width / scale, viewport.height / scale);
  }

  void fitContent(Size viewport, double contentExtent) {
    if (viewport.isEmpty || contentExtent <= 0) return;
    final fitScale = math
        .min(viewport.width / contentExtent, viewport.height / contentExtent)
        .clamp(minScale, 1.0)
        .toDouble();
    jumpTo(scale: fitScale, offset: Offset.zero);
  }

  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    _sourceController.canvasOffset = offset + delta;
  }

  void setScaleAround(double scale, Offset focalPoint) {
    final nextScale = scale.clamp(minScale, maxScale).toDouble();
    if (nextScale == this.scale) return;
    final worldFocal = screenToWorld(focalPoint);
    jumpTo(scale: nextScale, offset: focalPoint - worldFocal * nextScale);
  }

  void jumpTo({required double scale, required Offset offset}) {
    _sourceController.canvasScale = scale;
    _sourceController.canvasOffset = offset;
  }

  @override
  void dispose() {
    _sourceController.removeListener(notifyListeners);
    _sourceController.dispose();
    super.dispose();
  }
}

final class PixelTileCache {
  static const int tileSize = 64;

  final _pictures = <int, ui.Picture>{};
  final _dirtyTiles = <int>{};
  Object? _structureKey;
  int? _gridSize;

  static int tileKey(int tileX, int tileY) => tileX | (tileY << 16);

  static int tileKeyForIndex(int index, int gridSize) {
    final x = index % gridSize;
    final y = index ~/ gridSize;
    return tileKey(x ~/ tileSize, y ~/ tileSize);
  }

  static Set<int> affectedTileKeys(Iterable<int> indexes, int gridSize) {
    return {
      for (final index in indexes)
        if (index >= 0 && index < gridSize * gridSize)
          tileKeyForIndex(index, gridSize),
    };
  }

  void syncBoard(PixelCanvasBoard board) {
    if (_gridSize == board.gridSize &&
        identical(_structureKey, board.structureKey)) {
      return;
    }
    clear();
    _gridSize = board.gridSize;
    _structureKey = board.structureKey;
  }

  void markDirtyIndexes(Iterable<int> indexes, int gridSize) {
    _dirtyTiles.addAll(affectedTileKeys(indexes, gridSize));
  }

  void clear() {
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
    _dirtyTiles.clear();
  }

  ui.Picture pictureFor(
    PixelCanvasBoard board,
    int tileKey,
    double cellExtent, {
    required bool hasPreview,
  }) {
    final cached = _pictures[tileKey];
    if (cached != null && !_dirtyTiles.contains(tileKey)) return cached;

    cached?.dispose();
    final picture = _buildTilePicture(
      board,
      tileKey,
      cellExtent,
      hasPreview: hasPreview,
    );
    _pictures[tileKey] = picture;
    _dirtyTiles.remove(tileKey);
    return picture;
  }

  ui.Picture _buildTilePicture(
    PixelCanvasBoard board,
    int tileKey,
    double cellExtent, {
    required bool hasPreview,
  }) {
    final tileX = tileKey & 0xffff;
    final tileY = tileKey >> 16;
    final startX = tileX * tileSize;
    final startY = tileY * tileSize;
    final endX = math.min(startX + tileSize, board.gridSize);
    final endY = math.min(startY + tileSize, board.gridSize);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final fill = Paint()..style = PaintingStyle.fill;
    final maxNum = _maxNumber(board);
    final range = maxNum > 1 ? maxNum - 1 : 1;

    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        final index = y * board.gridSize + x;
        final number = board.numberAt(index);
        if (number == 0) continue;

        if (board.isPaintedAt(index)) {
          fill.color = board.colorForNumber(number).withAlpha(255);
        } else if (hasPreview) {
          continue;
        } else {
          final shade = 120 + (((number - 1) / range) * 120).round();
          fill.color = Color.fromARGB(255, shade, shade, shade);
        }

        canvas.drawRect(
          Rect.fromLTWH(
            (x - startX) * cellExtent,
            (y - startY) * cellExtent,
            cellExtent,
            cellExtent,
          ),
          fill,
        );
      }
    }

    return recorder.endRecording();
  }
}

final class PixelCanvasPainter extends CustomPainter {
  const PixelCanvasPainter({
    required this.board,
    required this.camera,
    required this.tileCache,
    required this.previewImage,
    required this.sparklePhase,
    this.optimisticPaintedIndexes = const <int>{},
    this.optimisticPaintRevision = 0,
    this.cellExtent = 20,
  }) : super(repaint: camera);

  final PixelCanvasBoard board;
  final PixelCanvasCameraController camera;
  final PixelTileCache tileCache;
  final ui.Image? previewImage;
  final double sparklePhase;
  final Set<int> optimisticPaintedIndexes;
  final int optimisticPaintRevision;
  final double cellExtent;

  PixelCanvasLod get lod {
    final screenCell = cellExtent * camera.scale;
    if (screenCell >= 16) return PixelCanvasLod.numbers;
    if (screenCell >= 8) return PixelCanvasLod.grid;
    return PixelCanvasLod.colors;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final boardExtent = board.gridSize * cellExtent;
    final boardRect = Rect.fromLTWH(0, 0, boardExtent, boardExtent);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );

    final visible = camera.visibleWorldRect(size).intersect(boardRect);
    if (visible.isEmpty) return;

    canvas.save();
    canvas.translate(camera.offset.dx, camera.offset.dy);
    canvas.scale(camera.scale);
    canvas.clipRect(boardRect);

    canvas.drawRect(boardRect, Paint()..color = Colors.white);
    final preview = previewImage;
    if (preview != null) {
      canvas.drawImageRect(
        preview,
        Rect.fromLTWH(
          0,
          0,
          preview.width.toDouble(),
          preview.height.toDouble(),
        ),
        boardRect,
        Paint()..filterQuality = FilterQuality.none,
      );
    }

    final opacity = preview == null ? 1.0 : _templateOpacityForScale();
    if (opacity >= 1) {
      // Full opacity needs no offscreen layer; saveLayer is expensive per frame.
      _paintVisibleTiles(canvas, visible, hasPreview: preview != null);
    } else if (opacity > 0) {
      canvas.saveLayer(
        visible,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      _paintVisibleTiles(canvas, visible, hasPreview: preview != null);
      canvas.restore();
    }

    final lod = this.lod;
    _paintOptimisticPainted(canvas, visible);
    _paintSelection(canvas, visible);
    // Completed overlays are sub-pixel below the grid LOD; skip the full-board
    // walks they would cost when zoomed far out.
    if (lod != PixelCanvasLod.colors) {
      final completed = board.completedNumbers();
      _paintCompletedFilter(canvas, visible, completed);
      _paintCompletedSparkles(canvas, visible, completed);
    }
    if (lod.index >= PixelCanvasLod.grid.index) _paintGrid(canvas, visible);
    if (lod == PixelCanvasLod.numbers) _paintNumbers(canvas, visible);

    canvas.restore();
  }

  void _paintOptimisticPainted(Canvas canvas, Rect visible) {
    if (optimisticPaintedIndexes.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final index in optimisticPaintedIndexes) {
      if (index < 0 || index >= board.totalCells) continue;
      final x = index % board.gridSize;
      final y = index ~/ board.gridSize;
      final rect = _cellRect(x, y);
      if (!visible.overlaps(rect)) continue;
      final number = board.numberAt(index);
      if (number == 0) continue;
      paint.color = board.colorForNumber(number).withAlpha(255);
      canvas.drawRect(rect, paint);
    }
  }

  double _templateOpacityForScale() {
    return ((camera.scale - 0.04) / 0.16).clamp(0.0, 1.0).toDouble();
  }

  void _paintVisibleTiles(
    Canvas canvas,
    Rect visible, {
    required bool hasPreview,
  }) {
    final tileWorld = PixelTileCache.tileSize * cellExtent;
    final minTileX = (visible.left / tileWorld).floor().clamp(0, 1 << 20);
    final minTileY = (visible.top / tileWorld).floor().clamp(0, 1 << 20);
    final maxTileX = (visible.right / tileWorld).floor().clamp(0, 1 << 20);
    final maxTileY = (visible.bottom / tileWorld).floor().clamp(0, 1 << 20);

    for (var ty = minTileY; ty <= maxTileY; ty++) {
      for (var tx = minTileX; tx <= maxTileX; tx++) {
        final key = PixelTileCache.tileKey(tx, ty);
        final picture = tileCache.pictureFor(
          board,
          key,
          cellExtent,
          hasPreview: hasPreview,
        );
        canvas.save();
        canvas.translate(tx * tileWorld, ty * tileWorld);
        canvas.drawPicture(picture);
        canvas.restore();
      }
    }
  }

  void _paintSelection(Canvas canvas, Rect visible) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = board.selectedColor.withValues(alpha: 0.25);
    final indexes = board.indexesForNumber(board.selectedNumber);
    if (indexes.length < _visibleCellCount(visible)) {
      // Fewer selected cells than visible cells (e.g. zoomed out over a large
      // board): walk only the selected number's indexes.
      for (final index in indexes) {
        if (board.isPaintedAt(index)) continue;
        final rect = _cellRect(index % board.gridSize, index ~/ board.gridSize);
        if (!visible.overlaps(rect)) continue;
        canvas.drawRect(rect, paint);
      }
      return;
    }
    _forVisibleCells(visible, (index, x, y) {
      if (board.numberAt(index) != board.selectedNumber ||
          board.isPaintedAt(index)) {
        return;
      }
      canvas.drawRect(_cellRect(x, y), paint);
    });
  }

  int _visibleCellCount(Rect visible) {
    final cols = (visible.width / cellExtent).ceil().clamp(0, board.gridSize);
    final rows = (visible.height / cellExtent).ceil().clamp(0, board.gridSize);
    return cols * rows;
  }

  void _paintCompletedFilter(Canvas canvas, Rect visible, Set<int> completed) {
    if (completed.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;
    _forVisibleCells(visible, (index, x, y) {
      final number = board.numberAt(index);
      if (!completed.contains(number)) return;
      paint.color = Color.lerp(
        board.colorForNumber(number),
        Colors.white,
        0.38,
      )!.withAlpha(46);
      canvas.drawRect(_cellRect(x, y), paint);
    });
  }

  void _paintCompletedSparkles(
    Canvas canvas,
    Rect visible,
    Set<int> completed,
  ) {
    if (completed.isEmpty) return;
    final glowPaint = Paint()..style = PaintingStyle.fill;
    final corePaint = Paint()..style = PaintingStyle.fill;
    final phase = sparklePhase % 1;

    _forVisibleCells(visible, (index, x, y) {
      final number = board.numberAt(index);
      if (!completed.contains(number)) return;
      final seed = _hashCell(x, y, number);
      if (seed % 11 != 0) return;

      final pulseOffset = ((seed >> 24) & 0xff) / 255.0;
      final pulse = 0.5 + (0.5 * math.sin((phase + pulseOffset) * math.pi * 2));
      final alpha = (46 + (pulse * 150)).round();
      if (alpha < 70) return;

      final xJitter = ((seed >> 8) & 0xff) / 255.0;
      final yJitter = ((seed >> 16) & 0xff) / 255.0;
      final center = Offset(
        (x + 0.18 + (xJitter * 0.64)) * cellExtent,
        (y + 0.18 + (yJitter * 0.64)) * cellExtent,
      );
      final radius = cellExtent * (0.055 + (((seed >> 4) & 0x7) * 0.008));

      glowPaint.color = const Color(0xFFFFF3B0).withAlpha(alpha ~/ 2);
      corePaint.color = Colors.white.withAlpha(alpha);
      canvas.drawCircle(center, radius * 1.8, glowPaint);
      canvas.drawCircle(center, radius, corePaint);
    });
  }

  void _paintGrid(Canvas canvas, Rect visible) {
    final gridPaint = Paint()
      ..color = Colors.black.withAlpha(45)
      ..strokeWidth = 0.5 / camera.scale;

    if (board.hasTransparentCells) {
      gridPaint.style = PaintingStyle.stroke;
      _forVisibleCells(visible, (index, x, y) {
        if (board.numberAt(index) != 0) {
          canvas.drawRect(_cellRect(x, y), gridPaint);
        }
      });
      return;
    }

    final startX = (visible.left / cellExtent).floor().clamp(0, board.gridSize);
    final endX = (visible.right / cellExtent).ceil().clamp(0, board.gridSize);
    final startY = (visible.top / cellExtent).floor().clamp(0, board.gridSize);
    final endY = (visible.bottom / cellExtent).ceil().clamp(0, board.gridSize);
    final boardExtent = board.gridSize * cellExtent;

    for (var x = startX; x <= endX; x++) {
      final offset = x * cellExtent;
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset, boardExtent),
        gridPaint,
      );
    }
    for (var y = startY; y <= endY; y++) {
      final offset = y * cellExtent;
      canvas.drawLine(
        Offset(0, offset),
        Offset(boardExtent, offset),
        gridPaint,
      );
    }
  }

  void _paintNumbers(Canvas canvas, Rect visible) {
    final maxNum = _maxNumber(board);
    final threshold = maxNum / 3.0;
    final painters = <int, TextPainter>{};

    _forVisibleCells(visible, (index, x, y) {
      final number = board.numberAt(index);
      if (number == 0 || board.isPaintedAt(index)) return;
      final tp = painters.putIfAbsent(number, () {
        final textColor = number <= threshold
            ? Colors.white.withAlpha(210)
            : Colors.black54;
        return TextPainter(
          text: TextSpan(
            text: '$number',
            style: TextStyle(
              color: textColor,
              fontSize: cellExtent * 0.46,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: cellExtent);
      });
      tp.paint(
        canvas,
        Offset(
          (x * cellExtent) + (cellExtent - tp.width) / 2,
          (y * cellExtent) + (cellExtent - tp.height) / 2,
        ),
      );
    });

    for (final tp in painters.values) {
      tp.dispose();
    }
  }

  void _forVisibleCells(
    Rect visible,
    void Function(int index, int x, int y) visit,
  ) {
    final startX = (visible.left / cellExtent).floor().clamp(
      0,
      board.gridSize - 1,
    );
    final endX = (visible.right / cellExtent).ceil().clamp(0, board.gridSize);
    final startY = (visible.top / cellExtent).floor().clamp(
      0,
      board.gridSize - 1,
    );
    final endY = (visible.bottom / cellExtent).ceil().clamp(0, board.gridSize);

    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        visit(y * board.gridSize + x, x, y);
      }
    }
  }

  Rect _cellRect(int x, int y) {
    return Rect.fromLTWH(
      x * cellExtent,
      y * cellExtent,
      cellExtent,
      cellExtent,
    );
  }

  static int _hashCell(int x, int y, int number) {
    var hash = 0x811c9dc5;
    hash = _hashInt(hash, x);
    hash = _hashInt(hash, y);
    hash = _hashInt(hash, number);
    return hash & 0x7fffffff;
  }

  static int _hashInt(int hash, int value) {
    hash ^= value;
    hash = (hash * 0x01000193) & 0xffffffff;
    return hash;
  }

  @override
  bool shouldRepaint(PixelCanvasPainter oldDelegate) {
    return oldDelegate.board.paintRevision != board.paintRevision ||
        oldDelegate.board.selectedNumber != board.selectedNumber ||
        oldDelegate.camera.scale != camera.scale ||
        oldDelegate.camera.offset != camera.offset ||
        oldDelegate.previewImage != previewImage ||
        // Sparkles are not drawn at colors LOD, so phase changes alone must
        // not force a full-board repaint when zoomed far out.
        (oldDelegate.sparklePhase != sparklePhase &&
            lod != PixelCanvasLod.colors) ||
        oldDelegate.optimisticPaintRevision != optimisticPaintRevision;
  }
}

final class PixelCanvasSurface extends StatefulWidget {
  const PixelCanvasSurface({
    required this.board,
    required this.camera,
    required this.onPaintIndexes,
    super.key,
    this.previewImage,
    this.sparklePhase = 0,
    this.cellExtent = 20,
    this.paintEnabled = true,
    this.interactionDisabled = false,
    this.zoomOnTap = false,
    this.tapZoomScale = 1.4,
    this.onCellTap,
    this.canPaintIndex,
  });

  final PixelCanvasBoard board;
  final PixelCanvasCameraController camera;
  final void Function(List<int> indexes) onPaintIndexes;
  final ui.Image? previewImage;
  final double sparklePhase;
  final double cellExtent;
  final bool paintEnabled;
  final bool interactionDisabled;
  final bool zoomOnTap;
  final double tapZoomScale;
  final void Function(int index)? onCellTap;
  final bool Function(int index)? canPaintIndex;

  @override
  State<PixelCanvasSurface> createState() => _PixelCanvasSurfaceState();
}

final class _PixelCanvasSurfaceState extends State<PixelCanvasSurface> {
  final PixelTileCache _tileCache = PixelTileCache();
  final Set<int> _paintedStrokeIndexes = <int>{};
  final Set<int> _pendingPaintedIndexes = <int>{};
  final Set<int> _optimisticPaintedIndexes = <int>{};
  final Map<int, Offset> _pointerPositions = <int, Offset>{};

  Size _viewportSize = Size.zero;
  bool _needsInitialFit = true;
  bool _paintFlushScheduled = false;
  int _optimisticPaintRevision = 0;
  int? _lastStrokeIndex;
  int? _paintingPointer;
  int? _tapCandidateIndex;
  Offset? _tapStartPosition;
  Offset? _lastPanPosition;
  Offset? _lastGestureCentroid;
  double? _lastGestureDistance;
  bool _longPressPainting = false;

  @override
  void initState() {
    super.initState();
    _tileCache.syncBoard(widget.board);
  }

  @override
  void didUpdateWidget(PixelCanvasSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.board.gridSize != widget.board.gridSize ||
        !identical(oldWidget.board.structureKey, widget.board.structureKey)) {
      _needsInitialFit = true;
      _pendingPaintedIndexes.clear();
      _optimisticPaintedIndexes.clear();
      _optimisticPaintRevision++;
      _paintFlushScheduled = false;
      _tileCache.syncBoard(widget.board);
      return;
    }
    if (oldWidget.board.paintRevision != widget.board.paintRevision) {
      _tileCache.markDirtyIndexes(
        widget.board.lastPaintedIndexes,
        widget.board.gridSize,
      );
      if (widget.board.lastPaintedIndexes.isNotEmpty) {
        _optimisticPaintedIndexes.removeAll(widget.board.lastPaintedIndexes);
        _optimisticPaintRevision++;
      }
    }
  }

  @override
  void dispose() {
    _tileCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[widget.camera];
    final Object board = widget.board;
    if (board is Listenable) listenables.add(board);

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleInitialFit();

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: _handleLongPressStart,
            onLongPressMoveUpdate: _handleLongPressMoveUpdate,
            onLongPressEnd: (_) => _endLongPressPainting(),
            onLongPressCancel: _endLongPressPainting,
            onTapUp: _handleTapUp,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge(listenables),
                builder: (context, _) {
                  return CustomPaint(
                    key: const ValueKey('pixel-canvas-surface'),
                    painter: PixelCanvasPainter(
                      board: widget.board,
                      camera: widget.camera,
                      tileCache: _tileCache,
                      previewImage: widget.previewImage,
                      sparklePhase: widget.sparklePhase,
                      optimisticPaintedIndexes: _optimisticPaintedIndexes,
                      optimisticPaintRevision: _optimisticPaintRevision,
                      cellExtent: widget.cellExtent,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.interactionDisabled) return;
    _pointerPositions[event.pointer] = event.localPosition;

    if (_pointerPositions.length != 1) {
      _cancelDirectPainting();
      _endLongPressPainting();
      _clearTapCandidate();
      _setCurrentTransformGesture();
      return;
    }

    final index = _cellIndexAtPosition(event.localPosition);
    _tapCandidateIndex = index;
    _tapStartPosition = event.localPosition;
    _lastPanPosition = event.localPosition;
    if (widget.paintEnabled && index != null && _isPaintable(index)) {
      _paintingPointer = event.pointer;
      _resetStroke();
      _lastStrokeIndex = index;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (widget.interactionDisabled ||
        !_pointerPositions.containsKey(event.pointer)) {
      return;
    }
    _pointerPositions[event.pointer] = event.localPosition;

    final tapStart = _tapStartPosition;
    if (tapStart != null && (event.localPosition - tapStart).distance > 8) {
      _tapCandidateIndex = null;
    }

    if (_pointerPositions.length > 1) {
      _handleTransformGesture();
      return;
    }

    if (widget.paintEnabled && _paintingPointer == event.pointer) {
      _paintAtPosition(event.localPosition, withHaptic: true);
      return;
    }

    final lastPanPosition = _lastPanPosition;
    if (lastPanPosition != null) {
      widget.camera.panBy(event.localPosition - lastPanPosition);
    }
    _lastPanPosition = event.localPosition;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (widget.interactionDisabled) return;
    final isPaintingPointer = _paintingPointer == event.pointer;
    final tapStart = _tapStartPosition;
    if (isPaintingPointer &&
        _pointerPositions.length == 1 &&
        widget.paintEnabled &&
        _tapCandidateIndex != null &&
        tapStart != null) {
      _paintAtPosition(tapStart, withHaptic: true);
    }
    final zoomIndex = _pointerPositions.length == 1 && widget.zoomOnTap
        ? _tapCandidateIndex
        : null;
    if (isPaintingPointer) _cancelDirectPainting();
    _pointerPositions.remove(event.pointer);
    _resetPointerGestureState();
    if (_pointerPositions.isEmpty) _clearTapCandidate();
    if (zoomIndex != null) zoomToCellIndex(zoomIndex);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_paintingPointer == event.pointer) _cancelDirectPainting();
    _pointerPositions.remove(event.pointer);
    _resetPointerGestureState();
    if (_pointerPositions.isEmpty) _clearTapCandidate();
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.interactionDisabled) return;
    if (widget.paintEnabled) return;
    final index = _cellIndexAtPosition(details.localPosition);
    if (index != null) widget.onCellTap?.call(index);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (widget.interactionDisabled ||
        !widget.paintEnabled ||
        _paintingPointer != null) {
      return;
    }
    HapticFeedback.mediumImpact();
    _longPressPainting = true;
    _resetStroke();
    _lastStrokeIndex = _cellIndexAtPosition(details.localPosition);
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_longPressPainting ||
        widget.interactionDisabled ||
        !widget.paintEnabled) {
      return;
    }
    _paintAtPosition(details.localPosition, withHaptic: true);
  }

  void _endLongPressPainting() {
    if (!_longPressPainting) return;
    _longPressPainting = false;
    _resetStroke();
  }

  void _cancelDirectPainting() {
    if (_paintingPointer == null) return;
    _paintingPointer = null;
    _resetStroke();
  }

  void _handleTransformGesture() {
    _cancelDirectPainting();
    _endLongPressPainting();
    _clearTapCandidate();

    final snapshot = _transformSnapshot();
    if (snapshot == null) return;
    final (centroid, distance) = snapshot;

    final lastCentroid = _lastGestureCentroid;
    if (lastCentroid != null) {
      widget.camera.panBy(centroid - lastCentroid);
    }

    final lastDistance = _lastGestureDistance;
    if (lastDistance != null && lastDistance > 0 && distance > 0) {
      widget.camera.setScaleAround(
        widget.camera.scale * (distance / lastDistance),
        centroid,
      );
    }

    _lastGestureCentroid = centroid;
    _lastGestureDistance = distance;
  }

  void _setCurrentTransformGesture() {
    final snapshot = _transformSnapshot();
    if (snapshot == null) {
      _lastGestureCentroid = null;
      _lastGestureDistance = null;
      return;
    }
    _lastGestureCentroid = snapshot.$1;
    _lastGestureDistance = snapshot.$2;
  }

  (Offset centroid, double distance)? _transformSnapshot() {
    if (_pointerPositions.length < 2) return null;
    final positions = _pointerPositions.values.take(2).toList();
    final first = positions[0];
    final second = positions[1];
    return ((first + second) / 2, (first - second).distance);
  }

  void _resetPointerGestureState() {
    if (_pointerPositions.length >= 2) {
      _setCurrentTransformGesture();
      _lastPanPosition = null;
      return;
    }
    _lastGestureCentroid = null;
    _lastGestureDistance = null;
    _lastPanPosition = _pointerPositions.isEmpty
        ? null
        : _pointerPositions.values.first;
  }

  bool _paintAtPosition(Offset position, {bool withHaptic = false}) {
    final index = _cellIndexAtPosition(position);
    if (index == null) {
      _lastStrokeIndex = null;
      return false;
    }

    final previousIndex = _lastStrokeIndex;
    final indexes = previousIndex == null
        ? [index]
        : _indexesBetween(previousIndex, index);
    final toPaint = <int>[];
    var didHaptic = false;

    for (final paintIndex in indexes) {
      final cx = paintIndex % widget.board.gridSize;
      final cy = paintIndex ~/ widget.board.gridSize;
      var stepPainted = false;

      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          if (dx.abs() + dy.abs() > 2) continue;
          final x = cx + dx;
          final y = cy + dy;
          if (x < 0 ||
              x >= widget.board.gridSize ||
              y < 0 ||
              y >= widget.board.gridSize) {
            continue;
          }
          final targetIndex = y * widget.board.gridSize + x;
          if (_isPaintable(targetIndex) &&
              _paintedStrokeIndexes.add(targetIndex)) {
            toPaint.add(targetIndex);
            stepPainted = true;
          }
        }
      }

      if (stepPainted && withHaptic && !didHaptic) {
        didHaptic = true;
        HapticFeedback.selectionClick();
      }
    }

    if (toPaint.isNotEmpty) _emitPaintedCells(toPaint);
    _lastStrokeIndex = index;
    return toPaint.isNotEmpty;
  }

  int? _cellIndexAtPosition(Offset position) {
    final world = widget.camera.screenToWorld(position);
    final x = world.dx ~/ widget.cellExtent;
    final y = world.dy ~/ widget.cellExtent;
    if (x < 0 ||
        y < 0 ||
        x >= widget.board.gridSize ||
        y >= widget.board.gridSize) {
      return null;
    }
    return y * widget.board.gridSize + x;
  }

  bool _isPaintable(int index) {
    final canPaintIndex = widget.canPaintIndex;
    if (canPaintIndex != null && !canPaintIndex(index)) return false;
    return widget.board.numberAt(index) == widget.board.selectedNumber &&
        !widget.board.isPaintedAt(index) &&
        !_optimisticPaintedIndexes.contains(index);
  }

  List<int> _indexesBetween(int startIndex, int endIndex) {
    final gridSize = widget.board.gridSize;
    final startX = startIndex % gridSize;
    final startY = startIndex ~/ gridSize;
    final endX = endIndex % gridSize;
    final endY = endIndex ~/ gridSize;
    final steps = math.max((endX - startX).abs(), (endY - startY).abs());
    if (steps == 0) return [endIndex];

    return [
      for (var step = 0; step <= steps; step++)
        ((startY + ((endY - startY) * step / steps)).round() * gridSize) +
            (startX + ((endX - startX) * step / steps)).round(),
    ];
  }

  void _emitPaintedCells(List<int> indexes) {
    if (indexes.isEmpty) return;
    _pendingPaintedIndexes.addAll(indexes);
    _optimisticPaintedIndexes.addAll(indexes);
    _optimisticPaintRevision++;
    if (_paintFlushScheduled) return;

    _paintFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _pendingPaintedIndexes.clear();
        _paintFlushScheduled = false;
        return;
      }
      _flushPendingPaintedCells();
    });
    setState(() {});
  }

  void _flushPendingPaintedCells() {
    if (_pendingPaintedIndexes.isEmpty) {
      _paintFlushScheduled = false;
      return;
    }

    final indexes = List<int>.of(_pendingPaintedIndexes);
    _pendingPaintedIndexes.clear();
    _paintFlushScheduled = false;
    _tileCache.markDirtyIndexes(indexes, widget.board.gridSize);
    widget.onPaintIndexes(indexes);
    _optimisticPaintedIndexes.removeAll(indexes);
    _optimisticPaintRevision++;
  }

  void _resetStroke() {
    _flushPendingPaintedCells();
    _lastStrokeIndex = null;
    _paintedStrokeIndexes.clear();
  }

  void _clearTapCandidate() {
    _tapCandidateIndex = null;
    _tapStartPosition = null;
  }

  void _scheduleInitialFit() {
    if (!_needsInitialFit || _viewportSize.isEmpty) return;
    _needsInitialFit = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.camera.fitContent(
        _viewportSize,
        widget.board.gridSize * widget.cellExtent,
      );
    });
  }

  void zoomToCellIndex(int index) {
    final x = index % widget.board.gridSize;
    final y = index ~/ widget.board.gridSize;
    final tx = (x + 0.5) * widget.cellExtent;
    final ty = (y + 0.5) * widget.cellExtent;
    final zoomScale = widget.tapZoomScale;
    widget.camera.jumpTo(
      scale: zoomScale,
      offset: Offset(
        _viewportSize.width / 2 - tx * zoomScale,
        _viewportSize.height / 2 - ty * zoomScale,
      ),
    );
  }
}

int _maxNumber(PixelCanvasBoard board) {
  var maxNumber = 9;
  for (final number in board.numberKeys) {
    if (number > maxNumber) maxNumber = number;
  }
  return maxNumber;
}
