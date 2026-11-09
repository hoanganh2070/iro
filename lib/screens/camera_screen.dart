import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../lut.dart';
import '../models/film_model.dart';
import '../theme.dart';
import '../utils/date_stamp_painter.dart';
import '../widgets/camera_hud.dart';
import '../widgets/film_shelf_sheet.dart';
import '../widgets/focal_length_selector.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/vintage_shutter_bar.dart';

/// JPEG encoding runs in a background isolate.
///
/// IMPORTANT: this is a top-level function on purpose. The previous code
/// called Isolate.run() from inside the State class, so the closure captured
/// `this` (State + CameraController + ui.Image ...), which cannot be sent to
/// another isolate and made every capture fail.
Future<Uint8List> _encodeJpgInBackground(Uint8List rgba, int width, int height) {
  final packed = TransferableTypedData.fromList([rgba]);
  return Isolate.run(() {
    final bytes = packed.materialize().asUint8List();
    final im = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(im, quality: 92));
  });
}

class _Encoded {
  final Uint8List bytes;
  final String ext;
  const _Encoded(this.bytes, this.ext);
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  String? _cameraError;
  int _camIndex = 0;
  int _curFilmIndex = 3; // Default: C-NEG
  int _curFocalIndex = 1; // Default: 35mm
  int _shotsRemaining = 36;

  // LUTs keyed by film id, so one failed LUT can't shift the other indices.
  final Map<String, Lut> _lutById = {};
  bool _isShooting = false;
  bool _flashAnim = false;
  int _countdown = 0;
  FlashMode _flashMode = FlashMode.off;
  int _timerSec = 0; // 0, 3 or 10
  final double _evCompensation = 0.3;

  // Settings
  bool _watermark = true;
  bool _darkWatermark = true;
  bool _showFilmOnWm = true;
  bool _showDateOnWm = true;
  bool _grid = true;
  bool _dateStamp98 = true;

  Uint8List? _lastThumb;
  ui.FragmentProgram? _lutProgram;
  ui.FragmentShader? _previewShader;
  ui.Image? _fujiLogo;
  SharedPreferences? _prefs;

  // Tap-to-focus
  Offset? _focusPoint;
  int _focusTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _previewShader?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      if (c != null && c.value.isInitialized && !_isShooting) {
        setState(() => _controller = null);
        c.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _cameras.isNotEmpty) {
        _initCamera(_cameras[_camIndex]);
      }
    }
  }

  // ───────────────────────── Setup ─────────────────────────

  Future<void> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    _watermark = _prefs?.getBool('wm') ?? true;
    _darkWatermark = _prefs?.getBool('wmDark') ?? true;
    _showFilmOnWm = _prefs?.getBool('wmFilm') ?? true;
    _showDateOnWm = _prefs?.getBool('wmDate') ?? true;
    _dateStamp98 = _prefs?.getBool('dateStamp98') ?? true;
    _grid = _prefs?.getBool('grid') ?? true;
    final saved = _prefs?.getInt('filmIndex') ?? 3;
    _curFilmIndex = (saved >= 0 && saved < FilmModel.fujiCatalog.length) ? saved : 3;

    // Start the camera first so the preview shows up quickly,
    // load the heavy LUT assets in parallel.
    final assetsFuture = _loadAssets();
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera found on this device');
      } else {
        await _initCamera(_cameras[_camIndex]);
      }
    } on CameraException catch (e) {
      if (mounted) setState(() => _cameraError = e.description ?? e.code);
    } catch (e) {
      if (mounted) setState(() => _cameraError = '$e');
    }
    await assetsFuture;
  }

  Future<void> _loadAssets() async {
    try {
      final logoBytes = await rootBundle.load('assets/images/fujifilm_logo.png');
      final codec = await ui.instantiateImageCodec(logoBytes.buffer.asUint8List());
      _fujiLogo = (await codec.getNextFrame()).image;
    } catch (_) {}

    try {
      _lutProgram = await ui.FragmentProgram.fromAsset('assets/shaders/lut.frag');
    } catch (e) {
      debugPrint('Shader error: $e');
    }

    for (final film in FilmModel.fujiCatalog) {
      try {
        final text = await rootBundle.loadString(film.lutPath);
        _lutById[film.id] = await Lut.parse(film.fullName, film.id, text);
      } catch (e) {
        debugPrint('LUT parse failed: ${film.fullName} ($e)');
      }
    }
    _rebuildShader();
    if (mounted) setState(() {});
  }

  void _rebuildShader() {
    _previewShader?.dispose();
    _previewShader = null;
    final lut = _lutById[FilmModel.fujiCatalog[_curFilmIndex].id];
    if (_lutProgram == null || lut == null) return;
    final s = _lutProgram!.fragmentShader();
    s.setFloat(2, lut.n.toDouble());
    s.setImageSampler(1, lut.lutTexture);
    _previewShader = s;
  }

  Future<void> _initCamera(CameraDescription description) async {
    final old = _controller;
    if (mounted) setState(() => _controller = null);
    await old?.dispose();

    final ctrl = CameraController(
      description,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      try {
        await ctrl.setFlashMode(_flashMode);
      } catch (_) {}
      try {
        final minE = await ctrl.getMinExposureOffset();
        final maxE = await ctrl.getMaxExposureOffset();
        await ctrl.setExposureOffset(_evCompensation.clamp(minE, maxE).toDouble());
      } catch (_) {}
      try {
        final minZ = await ctrl.getMinZoomLevel();
        final maxZ = await ctrl.getMaxZoomLevel();
        final z = FocalLengthSelector.options[_curFocalIndex].zoomRatio;
        await ctrl.setZoomLevel(z.clamp(minZ, maxZ).toDouble());
      } catch (_) {}

      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      await ctrl.dispose();
      if (mounted) setState(() => _cameraError = e.description ?? e.code);
    }
  }

  Future<void> _onSelectFocal(int index, double zoom) async {
    setState(() => _curFocalIndex = index);
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      final maxZ = await c.getMaxZoomLevel();
      final minZ = await c.getMinZoomLevel();
      await c.setZoomLevel(zoom.clamp(minZ, maxZ).toDouble());
    } catch (_) {}
  }

  Future<void> _onTapFocus(TapDownDetails d, BoxConstraints box) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final p = d.localPosition;
    final tick = ++_focusTick;
    setState(() => _focusPoint = p);
    try {
      final pt = Offset(p.dx / box.maxWidth, p.dy / box.maxHeight);
      await c.setFocusPoint(pt);
      await c.setExposurePoint(pt);
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted && tick == _focusTick) setState(() => _focusPoint = null);
    });
  }

  // ───────────────────────── Capture ─────────────────────────

  Future<void> _takePhoto() async {
    final ctrl = _controller;
    if (_isShooting || ctrl == null || !ctrl.value.isInitialized || ctrl.value.isTakingPicture) {
      return;
    }
    setState(() => _isShooting = true);

    try {
      for (var t = _timerSec; t > 0; t--) {
        if (!mounted) return;
        setState(() => _countdown = t);
        HapticFeedback.selectionClick();
        await Future.delayed(const Duration(seconds: 1));
      }
      if (mounted) setState(() => _countdown = 0);

      HapticFeedback.heavyImpact();
      setState(() => _flashAnim = true);
      Future.delayed(const Duration(milliseconds: 70), () {
        if (mounted) setState(() => _flashAnim = false);
      });

      final file = await ctrl.takePicture();
      final bytes = await file.readAsBytes();

      final result = await _processPhoto(bytes);

      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) throw 'Photo library permission was denied';
      }
      await Gal.putImageBytes(
        result.bytes,
        name: 'FUJI_${DateTime.now().millisecondsSinceEpoch}.${result.ext}',
      );

      if (!mounted) return;
      setState(() {
        _lastThumb = result.bytes;
        if (_shotsRemaining > 1) _shotsRemaining--;
      });
      _showToast('Saved to your photo library');
    } catch (e, st) {
      debugPrint('Capture failed: $e\n$st');
      _showToast('Capture failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isShooting = false;
          _countdown = 0;
        });
      }
    }
  }

  /// Applies LUT, date stamp and frame, then encodes the result.
  Future<_Encoded> _processPhoto(Uint8List bytes) async {
    final film = FilmModel.fujiCatalog[_curFilmIndex];
    final lut = _lutById[film.id];

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    int? tw, th;
    if (math.max(desc.width, desc.height) > 2048) {
      if (desc.width >= desc.height) {
        tw = 2048;
      } else {
        th = 2048;
      }
    }
    final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
    final rawImage = (await codec.getNextFrame()).image;
    codec.dispose();
    desc.dispose();
    buffer.dispose();

    final w = rawImage.width.toDouble();
    final h = rawImage.height.toDouble();
    final barH = _watermark ? (math.max(w, h) * 0.062).roundToDouble() : 0.0;
    final totalH = h + barH;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, w, h);

    // 1. Film colour (LUT). Shader first, colour-matrix fallback, then raw.
    ui.FragmentShader? shader;
    if (_lutProgram != null && lut != null) {
      try {
        shader = _lutProgram!.fragmentShader()
          ..setFloat(0, w)
          ..setFloat(1, h)
          ..setFloat(2, lut.n.toDouble())
          ..setImageSampler(0, rawImage)
          ..setImageSampler(1, lut.lutTexture);
      } catch (e) {
        debugPrint('Shader setup failed: $e');
        shader = null;
      }
    }
    if (shader != null) {
      canvas.drawRect(rect, Paint()..shader = shader);
    } else if (lut != null) {
      canvas.drawImage(
        rawImage,
        Offset.zero,
        Paint()..colorFilter = ColorFilter.matrix(lut.previewMatrix),
      );
    } else {
      canvas.drawImage(rawImage, Offset.zero, Paint());
    }

    // 2. Date stamp '98
    if (_dateStamp98) {
      DateStampPainter.drawStamp(canvas, Size(w, h), DateTime.now());
    }

    // 3. Watermark frame
    if (barH > 0) {
      canvas.save();
      canvas.translate(0, h);
      _drawWatermarkBar(canvas, Size(w, barH), film.fullName);
      canvas.restore();
    }

    final outImg = await recorder.endRecording().toImage(w.toInt(), totalH.toInt());
    final byteData = await outImg.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw 'Could not read rendered image';
    final rgba = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);

    _Encoded result;
    try {
      final jpg = await _encodeJpgInBackground(rgba, outImg.width, outImg.height);
      result = _Encoded(jpg, 'jpg');
    } catch (e) {
      // Fallback: let the engine encode a PNG so the shot is never lost.
      debugPrint('JPEG isolate failed ($e), falling back to PNG');
      final png = await outImg.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw 'Could not encode image';
      result = _Encoded(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes), 'png');
    }

    shader?.dispose();
    rawImage.dispose();
    outImg.dispose();
    return result;
  }

  String _wmDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}.${two(d.month)}.${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  void _drawWatermarkBar(Canvas c, Size s, String filmName) {
    final bg = _darkWatermark ? const Color(0xFF0C0C0C) : const Color(0xFFF7F5F0);
    final ink = _darkWatermark ? Colors.white : Colors.black87;
    c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), Paint()..color = bg);

    final pad = s.height * 0.5;
    final logo = _fujiLogo;
    if (logo != null) {
      final lh = s.height * 0.30;
      final lw = lh * logo.width / logo.height;
      c.drawImageRect(
        logo,
        Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
        Rect.fromLTWH(pad, (s.height - lh) / 2, lw, lh),
        Paint()
          ..colorFilter = ColorFilter.mode(
            _darkWatermark ? Colors.white : AppColors.red,
            BlendMode.srcIn,
          ),
      );
    } else {
      final tp = TextPainter(
        text: TextSpan(
          text: 'FUJIFILM',
          style: TextStyle(
            color: _darkWatermark ? Colors.white : AppColors.red,
            fontSize: s.height * 0.26,
            fontWeight: FontWeight.w900,
            letterSpacing: s.height * 0.02,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(pad, (s.height - tp.height) / 2));
    }

    final lines = <TextPainter>[];
    if (_showFilmOnWm) {
      lines.add(TextPainter(
        text: TextSpan(
          text: filmName.toUpperCase(),
          style: TextStyle(
            color: ink,
            fontSize: s.height * 0.22,
            fontWeight: FontWeight.w800,
            letterSpacing: s.height * 0.01,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout());
    }
    if (_showDateOnWm) {
      lines.add(TextPainter(
        text: TextSpan(
          text: _wmDate(DateTime.now()),
          style: TextStyle(
            color: ink.withAlpha(150),
            fontSize: s.height * 0.16,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout());
    }
    if (lines.isNotEmpty) {
      final gap = s.height * 0.05;
      final total = lines.fold<double>(0, (a, l) => a + l.height) + gap * (lines.length - 1);
      var y = (s.height - total) / 2;
      for (final l in lines) {
        l.paint(c, Offset(s.width - pad - l.width, y));
        y += l.height + gap;
      }
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ───────────────────────── Settings persistence ─────────────────────────

  void _setWatermark(bool v) {
    setState(() => _watermark = v);
    _prefs?.setBool('wm', v);
  }

  void _setGrid(bool v) {
    setState(() => _grid = v);
    _prefs?.setBool('grid', v);
  }

  void _cycleTimer() {
    HapticFeedback.selectionClick();
    setState(() => _timerSec = _timerSec == 0 ? 3 : (_timerSec == 3 ? 10 : 0));
  }

  void _toggleFlash() {
    HapticFeedback.selectionClick();
    final next = _flashMode == FlashMode.off ? FlashMode.always : FlashMode.off;
    setState(() => _flashMode = next);
    _controller?.setFlashMode(next).catchError((_) {});
  }

  void _flipCamera() {
    if (_cameras.length < 2) return;
    HapticFeedback.selectionClick();
    _camIndex = (_camIndex + 1) % _cameras.length;
    _initCamera(_cameras[_camIndex]);
  }

  Future<void> _openGallery() async {
    try {
      await Gal.open();
    } catch (_) {
      _showToast('Could not open the photo library');
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentFilm = FilmModel.fujiCatalog[_curFilmIndex];
    final currentFocal = FocalLengthSelector.options[_curFocalIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _GlassButton(icon: Icons.tune_rounded, onTap: _openSettingsSheet),
                  GestureDetector(
                    onTap: _openShelfSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.stroke),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RedDot(size: 8),
                          const SizedBox(width: 8),
                          Text(
                            currentFilm.fullName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 16, color: Colors.white54),
                        ],
                      ),
                    ),
                  ),
                  _GlassButton(
                    icon: Icons.grid_3x3_rounded,
                    active: _grid,
                    onTap: () => _setGrid(!_grid),
                  ),
                ],
              ),
            ),

            // 2. Viewfinder
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2E2E2E), Color(0xFF151515)],
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black, blurRadius: 18, spreadRadius: 2),
                        ],
                      ),
                      padding: const EdgeInsets.all(3.5),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22.5),
                        child: LayoutBuilder(builder: (context, box) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) => _onTapFocus(d, box),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const ColoredBox(color: Color(0xFF0A0A0A)),
                                _buildViewfinderContent(),

                                if (_focusPoint != null)
                                  Positioned(
                                    left: _focusPoint!.dx - 34,
                                    top: _focusPoint!.dy - 34,
                                    child: _FocusRing(key: ValueKey(_focusTick)),
                                  ),

                                if (_flashAnim) const ColoredBox(color: Colors.white),

                                CameraHud(
                                  filmCode: '${currentFilm.shortLabel} ${currentFilm.subLabel}',
                                  focalMm: '${currentFocal.mm}MM',
                                  evValue: _evCompensation,
                                  shotsRemaining: _shotsRemaining,
                                  showGrid: _grid,
                                ),

                                if (_countdown > 0)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: ColoredBox(
                                        color: Colors.black38,
                                        child: Center(
                                          child: Text(
                                            '$_countdown',
                                            style: const TextStyle(
                                              fontSize: 96,
                                              fontWeight: FontWeight.w200,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // 3. Focal length
            FocalLengthSelector(selectedIndex: _curFocalIndex, onSelected: _onSelectFocal),

            const SizedBox(height: 10),

            // 4. Tools
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ToolButton(
                    icon: _watermark ? Icons.crop_portrait_rounded : Icons.crop_square_rounded,
                    label: 'Frame',
                    active: _watermark,
                    onTap: () => _setWatermark(!_watermark),
                  ),
                  _ToolButton(
                    icon: _timerSec == 0
                        ? Icons.timer_outlined
                        : (_timerSec == 3 ? Icons.timer_3_outlined : Icons.timer_10_outlined),
                    label: _timerSec == 0 ? 'Timer' : '${_timerSec}s',
                    active: _timerSec > 0,
                    onTap: _cycleTimer,
                  ),
                  _ToolButton(
                    icon: _flashMode == FlashMode.off
                        ? Icons.flash_off_rounded
                        : Icons.flash_on_rounded,
                    label: _flashMode == FlashMode.off ? 'Flash off' : 'Flash on',
                    active: _flashMode != FlashMode.off,
                    onTap: _toggleFlash,
                  ),
                  _ToolButton(
                    icon: Icons.cameraswitch_outlined,
                    label: 'Flip',
                    enabled: _cameras.length > 1,
                    onTap: _flipCamera,
                  ),
                ],
              ),
            ),

            // 5. Shutter
            VintageShutterBar(
              lastThumb: _lastThumb,
              isShooting: _isShooting,
              currentFilm: currentFilm,
              onCapture: _takePhoto,
              onOpenShelf: _openShelfSheet,
              onOpenGallery: _openGallery,
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildViewfinderContent() {
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      return _buildCameraPreview(ctrl);
    }
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 40, color: Colors.white38),
              const SizedBox(height: 12),
              const Text('Camera unavailable',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(_cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () {
                  setState(() => _cameraError = null);
                  _bootstrap();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator(color: AppColors.red));
  }

  Widget _buildCameraPreview(CameraController ctrl) {
    // Cover-fit the preview in the 3:4 frame without stretching it.
    final ps = ctrl.value.previewSize ?? const Size(1440, 1080);
    Widget cam = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: ps.height, height: ps.width, child: CameraPreview(ctrl)),
    );

    final lut = _lutById[FilmModel.fujiCatalog[_curFilmIndex].id];
    if (lut == null) return cam;
    if (_previewShader != null && ui.ImageFilter.isShaderFilterSupported) {
      return ImageFiltered(imageFilter: ui.ImageFilter.shader(_previewShader!), child: cam);
    }
    return ColorFiltered(colorFilter: ColorFilter.matrix(lut.previewMatrix), child: cam);
  }

  void _openShelfSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilmShelfSheet(
        selectedIndex: _curFilmIndex,
        enableDateStamp: _dateStamp98,
        onSelectFilm: (idx) {
          setState(() {
            _curFilmIndex = idx;
            _rebuildShader();
          });
          _prefs?.setInt('filmIndex', idx);
        },
        onToggleDateStamp: (enabled) {
          setState(() => _dateStamp98 = enabled);
          _prefs?.setBool('dateStamp98', enabled);
        },
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SettingsSheet(
        enableWatermark: _watermark,
        darkWatermark: _darkWatermark,
        showFilmName: _showFilmOnWm,
        showDateOnWatermark: _showDateOnWm,
        showGrid: _grid,
        onToggleWatermark: _setWatermark,
        onToggleDarkWatermark: (v) {
          setState(() => _darkWatermark = v);
          _prefs?.setBool('wmDark', v);
        },
        onToggleFilmName: (v) {
          setState(() => _showFilmOnWm = v);
          _prefs?.setBool('wmFilm', v);
        },
        onToggleDate: (v) {
          setState(() => _showDateOnWm = v);
          _prefs?.setBool('wmDate', v);
        },
        onToggleGrid: _setGrid,
      ),
    );
  }
}

// ───────────────────────── Small UI pieces ─────────────────────────

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _GlassButton({required this.icon, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.panel,
          border: Border.all(color: active ? AppColors.red : AppColors.stroke),
        ),
        child: Icon(icon, size: 20, color: active ? Colors.white : Colors.white70),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Colors.white24
        : (active ? AppColors.redBright : Colors.white70);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusRing extends StatelessWidget {
  const _FocusRing({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.4, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFFD60A), width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}