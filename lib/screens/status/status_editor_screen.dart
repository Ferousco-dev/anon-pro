import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class StatusEditorResult {
  StatusEditorResult({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

class StatusEditorScreen extends StatefulWidget {
  const StatusEditorScreen({
    super.key,
    required this.originalBytes,
    required this.fileName,
  });

  final Uint8List originalBytes;
  final String fileName;

  @override
  State<StatusEditorScreen> createState() => _StatusEditorScreenState();
}

class _StatusEditorScreenState extends State<StatusEditorScreen> {
  final GlobalKey<ExtendedImageEditorState> _editorKey =
      GlobalKey<ExtendedImageEditorState>();
  final List<Offset?> _drawPoints = [];
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _watermarkController = TextEditingController(
    text: 'AnonPro',
  );

  double _brightness = 0.0;
  double _contrast = 1.0;
  double _textScale = 1.0;
  double _watermarkScale = 0.7;
  double _watermarkOpacity = 0.35;
  Offset _textOffset = const Offset(80, 220);
  Offset _watermarkOffset = const Offset(140, 420);
  bool _drawMode = false;
  bool _showText = false;
  bool _showWatermark = true;
  bool _isSaving = false;
  double? _cropAspectRatio;
  _FilterType _filter = _FilterType.none;

  @override
  void dispose() {
    _textController.dispose();
    _watermarkController.dispose();
    super.dispose();
  }

  void _setCropRatio(double? ratio) {
    setState(() {
      _cropAspectRatio = ratio;
    });
  }

  Future<void> _rotateRight() async {
    _editorKey.currentState?.rotate(right: true);
  }

  Future<void> _saveDraft() async {
    final bytes = await _buildFinalBytes();
    if (bytes == null) return;
    await _saveToDocuments(bytes, 'draft_${DateTime.now().millisecondsSinceEpoch}.jpg');
  }

  Future<void> _saveCopy() async {
    final bytes = await _buildFinalBytes();
    if (bytes == null) return;
    await _saveToDocuments(bytes, 'copy_${DateTime.now().millisecondsSinceEpoch}.jpg');
  }

  Future<void> _saveToDocuments(Uint8List bytes, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = await File('${dir.path}/$name').create(recursive: true);
    await file.writeAsBytes(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved locally')),
    );
  }

  Future<Uint8List?> _buildFinalBytes() async {
    if (_isSaving) return null;
    setState(() => _isSaving = true);
    try {
      final baseBytes = await _cropAndRotate();
      if (baseBytes == null) return null;

      final processed = _applyAdjustments(baseBytes);
      final composed = await _composeOverlays(processed);
      final encoded = img.encodeJpg(composed, quality: 85);
      return Uint8List.fromList(encoded);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<Uint8List?> _cropAndRotate() async {
    final state = _editorKey.currentState;
    if (state == null) return widget.originalBytes;
    final rect = state.getCropRect();
    final action = state.editAction;
    final raw = state.rawImageData;
    if (raw == null) return widget.originalBytes;

    var image = img.decodeImage(raw);
    if (image == null) return widget.originalBytes;

    if (action != null) {
      if (action.hasRotateAngle) {
        image = img.copyRotate(image, angle: action.rotateAngle);
      }
      if (action.needFlip) {
        if (action.flipY) {
          image = img.flipVertical(image);
        }
        if (action.flipX) {
          image = img.flipHorizontal(image);
        }
      }
    }

    if (rect != null) {
      final left = rect.left.round().clamp(0, image.width - 1);
      final top = rect.top.round().clamp(0, image.height - 1);
      final width =
          rect.width.round().clamp(1, image.width - left);
      final height =
          rect.height.round().clamp(1, image.height - top);
      image = img.copyCrop(image, x: left, y: top, width: width, height: height);
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  img.Image _applyAdjustments(Uint8List bytes) {
    var image = img.decodeImage(bytes)!;
    if (_brightness.abs() > 0.01) {
      image = img.adjustColor(image, brightness: _brightness);
    }
    if ((_contrast - 1.0).abs() > 0.01) {
      image = img.adjustColor(image, contrast: _contrast);
    }
    if (_filter != _FilterType.none) {
      switch (_filter) {
        case _FilterType.grayscale:
          image = img.grayscale(image);
          break;
        case _FilterType.sepia:
          image = img.sepia(image);
          break;
        case _FilterType.none:
          break;
      }
    }
    return image;
  }

  Future<img.Image> _composeOverlays(img.Image base) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(base.width.toDouble(), base.height.toDouble());
    canvas.drawImage(
      await _toUiImage(base),
      Offset.zero,
      Paint(),
    );

    final scaleX = base.width / MediaQuery.of(context).size.width;
    final scaleY = base.height / MediaQuery.of(context).size.height;

    // Draw pen strokes
    if (_drawPoints.isNotEmpty) {
      final paint = Paint()
        ..color = Colors.white
        ..strokeWidth = 5 * scaleX
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < _drawPoints.length - 1; i++) {
        final p1 = _drawPoints[i];
        final p2 = _drawPoints[i + 1];
        if (p1 != null && p2 != null) {
          canvas.drawLine(
            Offset(p1.dx * scaleX, p1.dy * scaleY),
            Offset(p2.dx * scaleX, p2.dy * scaleY),
            paint,
          );
        }
      }
    }

    // Text overlay
    if (_showText && _textController.text.trim().isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: _textController.text.trim(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 24 * _textScale * scaleX,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(_textOffset.dx * scaleX, _textOffset.dy * scaleY),
      );
    }

    // Watermark overlay
    if (_showWatermark && _watermarkController.text.trim().isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: _watermarkController.text.trim(),
          style: TextStyle(
            color: Colors.white.withOpacity(_watermarkOpacity),
            fontSize: 20 * _watermarkScale * scaleX,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(_watermarkOffset.dx * scaleX, _watermarkOffset.dy * scaleY),
      );
    }

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(base.width, base.height);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    final merged = img.decodeImage(byteData!.buffer.asUint8List())!;
    return merged;
  }

  Future<ui.Image> _toUiImage(img.Image image) async {
    final bytes = Uint8List.fromList(img.encodePng(image));
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  Future<void> _onPost() async {
    final bytes = await _buildFinalBytes();
    if (bytes == null || !mounted) return;
    Navigator.pop(
      context,
      StatusEditorResult(bytes: bytes, fileName: widget.fileName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Edit Status'),
        actions: [
          IconButton(
            onPressed: _saveDraft,
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            onPressed: _saveCopy,
            icon: const Icon(Icons.download_outlined),
          ),
          TextButton(
            onPressed: _onPost,
            child: const Text('Post'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Center(
                      child: ExtendedImage.memory(
                        widget.originalBytes,
                        mode: ExtendedImageMode.editor,
                        extendedImageEditorKey: _editorKey,
                        fit: BoxFit.contain,
                        initEditorConfigHandler: (state) {
                          return EditorConfig(
                            cropAspectRatio: _cropAspectRatio,
                            maxScale: 8.0,
                          );
                        },
                      ),
                    ),
                    if (_drawMode)
                      GestureDetector(
                        onPanUpdate: (details) {
                          final box = context.findRenderObject() as RenderBox?;
                          final local = box?.globalToLocal(details.globalPosition);
                          if (local == null) return;
                          setState(() {
                            _drawPoints.add(local);
                          });
                        },
                        onPanEnd: (_) {
                          _drawPoints.add(null);
                        },
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _DrawPainter(_drawPoints),
                        ),
                      ),
                    if (_showText && _textController.text.trim().isNotEmpty)
                      Positioned(
                        left: _textOffset.dx,
                        top: _textOffset.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _textOffset += details.delta;
                            });
                          },
                          child: Text(
                            _textController.text.trim(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24 * _textScale,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (_showWatermark &&
                        _watermarkController.text.trim().isNotEmpty)
                      Positioned(
                        left: _watermarkOffset.dx,
                        top: _watermarkOffset.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _watermarkOffset += details.delta;
                            });
                          },
                          child: Opacity(
                            opacity: _watermarkOpacity,
                            child: Text(
                              _watermarkController.text.trim(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20 * _watermarkScale,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_isSaving)
                      const Center(
                        child: CircularProgressIndicator(),
                      ),
                  ],
                );
              },
            ),
          ),
          _buildToolsPanel(),
        ],
      ),
    );
  }

  Widget _buildToolsPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.black,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolButton('Crop 1:1', () => _setCropRatio(1)),
            _toolButton('Crop 4:5', () => _setCropRatio(4 / 5)),
            _toolButton('Crop 9:16', () => _setCropRatio(9 / 16)),
            _toolButton('Free', () => _setCropRatio(null)),
            _toolButton('Rotate', _rotateRight),
            _toolButton('Draw', () {
              setState(() => _drawMode = !_drawMode);
            }),
            _toolButton('Text', () {
              setState(() => _showText = !_showText);
            }),
            _toolButton('Watermark', () {
              setState(() => _showWatermark = !_showWatermark);
            }),
            _toolButton('Filters', _showFilterSheet),
            _toolButton('Adjust', _showAdjustSheet),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: OutlinedButton(
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<_FilterType>(
              value: _FilterType.none,
              groupValue: _filter,
              title: const Text('None', style: TextStyle(color: Colors.white)),
              onChanged: (v) => setState(() => _filter = v!),
            ),
            RadioListTile<_FilterType>(
              value: _FilterType.grayscale,
              groupValue: _filter,
              title:
                  const Text('Grayscale', style: TextStyle(color: Colors.white)),
              onChanged: (v) => setState(() => _filter = v!),
            ),
            RadioListTile<_FilterType>(
              value: _FilterType.sepia,
              groupValue: _filter,
              title: const Text('Sepia', style: TextStyle(color: Colors.white)),
              onChanged: (v) => setState(() => _filter = v!),
            ),
          ],
        );
      },
    );
  }

  void _showAdjustSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Brightness', style: TextStyle(color: Colors.white)),
              Slider(
                value: _brightness,
                min: -0.5,
                max: 0.5,
                onChanged: (v) => setState(() => _brightness = v),
              ),
              const Text('Contrast', style: TextStyle(color: Colors.white)),
              Slider(
                value: _contrast,
                min: 0.7,
                max: 1.5,
                onChanged: (v) => setState(() => _contrast = v),
              ),
              const Text('Text Size', style: TextStyle(color: Colors.white)),
              Slider(
                value: _textScale,
                min: 0.5,
                max: 2.0,
                onChanged: (v) => setState(() => _textScale = v),
              ),
              const Text('Watermark Size',
                  style: TextStyle(color: Colors.white)),
              Slider(
                value: _watermarkScale,
                min: 0.5,
                max: 2.0,
                onChanged: (v) => setState(() => _watermarkScale = v),
              ),
              const Text('Watermark Opacity',
                  style: TextStyle(color: Colors.white)),
              Slider(
                value: _watermarkOpacity,
                min: 0.1,
                max: 0.8,
                onChanged: (v) => setState(() => _watermarkOpacity = v),
              ),
              TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Text overlay',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _watermarkController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Watermark text',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DrawPainter extends CustomPainter {
  _DrawPainter(this.points);

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      if (p1 != null && p2 != null) {
        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPainter oldDelegate) => true;
}

enum _FilterType { none, grayscale, sepia }
