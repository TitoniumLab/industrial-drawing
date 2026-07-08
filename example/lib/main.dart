import 'package:flutter/material.dart';
import 'package:industrial_drawing_flutter/industrial_drawing_flutter.dart';

void main() {
  runApp(const IndustrialDrawingApp());
}

class IndustrialDrawingApp extends StatelessWidget {
  const IndustrialDrawingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Industrial Pixel Canvas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
      ),
      home: const PixelPaintExampleScreen(),
    );
  }
}

class PixelPaintExampleScreen extends StatefulWidget {
  const PixelPaintExampleScreen({super.key});

  @override
  State<PixelPaintExampleScreen> createState() =>
      _PixelPaintExampleScreenState();
}

class _PixelPaintExampleScreenState extends State<PixelPaintExampleScreen> {
  static const double _cellExtent = 20;

  late final PixelCanvasMemoryBoard _board;
  late final PixelCanvasCameraController _camera;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _board = PixelCanvasMemoryBoard.generated(gridSize: 256, colorCount: 12);
    _camera = PixelCanvasCameraController(
      sourceConfig: const DrawingConfig(minScale: 0.02, maxScale: 8),
    );
  }

  @override
  void dispose() {
    _camera.dispose();
    _board.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('256 x 256 Pixel Canvas'),
        actions: [
          IconButton(
            tooltip: 'Fit',
            onPressed: _fitCanvas,
            icon: const Icon(Icons.fit_screen),
          ),
          IconButton(
            tooltip: 'Reset',
            onPressed: _board.reset,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStats(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                return PixelCanvasSurface(
                  board: _board,
                  camera: _camera,
                  onPaintIndexes: _board.paintIndexes,
                  cellExtent: _cellExtent,
                );
              },
            ),
          ),
          _buildPalette(),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return ListenableBuilder(
      listenable: _board,
      builder: (context, _) {
        final total = _board.totalCountForNumber(_board.selectedNumber);
        final painted = _board.paintedCountForNumber(_board.selectedNumber);
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Number ${_board.selectedNumber}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text('$painted / $total'),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _board.progress),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPalette() {
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SizedBox(
          height: 88,
          child: ListenableBuilder(
            listenable: _board,
            builder: (context, _) {
              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final number = index + 1;
                  final selected = number == _board.selectedNumber;
                  return Tooltip(
                    message: 'Paint number $number',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _board.selectNumber(number),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _board.colorForNumber(number),
                          border: Border.all(
                            color: selected
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: Text(
                          '$number',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemCount: 12,
              );
            },
          ),
        ),
      ),
    );
  }

  void _fitCanvas() {
    if (_canvasSize.isEmpty) return;
    _camera.fitContent(_canvasSize, _board.gridSize * _cellExtent);
  }
}
