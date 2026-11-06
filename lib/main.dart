import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'lut.dart';

const kBg = Color(0xFF0B0B0C);
const kPanel = Color(0xFF161618);
const kAccent = Color(0xFFE8412C);
const kAmber = Color(0xFFFFB02E);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: kBg,
      colorScheme: const ColorScheme.dark(primary: kAccent),
    ),
    home: const FujiVintageCamera(),
  ));
}

class FujiVintageCamera extends StatefulWidget {
  const FujiVintageCamera({super.key});
  @override
  State<FujiVintageCamera> createState() => _FujiVintageCameraState();
}

class _FujiVintageCameraState extends State<FujiVintageCamera> {
  List<CameraDescription> _cams = [];
  CameraController? _ctrl;
  int _camIdx = 0, _curLut = 0;
  final List<Lut> _luts = [];
  String _model = 'FUJIFILM X-T5';
  bool _wm = true, _isShooting = false, _flash = false;
  Uint8List? _lastThumb;
  ui.FragmentProgram? _program;
  ui.FragmentShader? _previewShader;

  final _catalog = const [
  {'name': 'ASTIA', 'code': 'AS', 'path': 'assets/luts/astia_sRGB.cube'},
  {'name': 'BLEACH BYPASS', 'code': 'BB', 'path': 'assets/luts/bleach bypass_sRGB.cube'},
  {'name': 'CLASSIC CHROME', 'code': 'CC', 'path': 'assets/luts/classic chrome_sRGB.cube'},
  {'name': 'CLASSIC NEG', 'code': 'CN', 'path': 'assets/luts/classic neg_sRGB.cube'},
  {'name': 'ETERNA', 'code': 'ET', 'path': 'assets/luts/eterna_sRGB.cube'},
  {'name': 'NOSTALGIC NEG', 'code': 'NN', 'path': 'assets/luts/nostalgic neg_sRGB.cube'},
  {'name': 'PRO NEG HI', 'code': 'PH', 'path': 'assets/luts/pro neg hi_sRGB.cube'},
  {'name': 'PRO NEG STD', 'code': 'PS', 'path': 'assets/luts/pro neg std_sRGB.cube'},
  {'name': 'PROVIA', 'code': 'PV', 'path': 'assets/luts/provia_sRGB.cube'},
  {'name': 'REAL A ACE', 'code': 'RA', 'path': 'assets/luts/reala ace_sRGB.cube'},
  {'name': 'VELVIA', 'code': 'VL', 'path': 'assets/luts/velvia_sRGB.cube'},
];
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('assets/shaders/lut.frag');
    } catch (e) {
      debugPrint('Shader load: $e');
    }
    for (final item in _catalog) {
      try {
        final text = await rootBundle.loadString(item['path']!);
        _luts.add(await Lut.parse(item['name']!, item['code']!, text));
      } catch (e) {
        debugPrint('LUT skip [${item['name']}]: $e');
      }
    }
    _rebuildPreviewShader();
    _cams = await availableCameras();
    if (_cams.isNotEmpty) await _startCamera(0);
    if (mounted) setState(() {});
  }

  // Shader dùng cho preview (ImageFilter.shader tự gán sampler 0 và 2 float đầu = size)
  void _rebuildPreviewShader() {
    _previewShader?.dispose();
    _previewShader = null;
    if (_program == null || _luts.isEmpty) return;
    final s = _program!.fragmentShader();
    final lut = _luts[_curLut];
    s.setFloat(2, lut.n.toDouble());
    s.setImageSampler(1, lut.lutTexture);
    _previewShader = s;
  }

  bool get _canShaderPreview {
    try {
      return _previewShader != null && ui.ImageFilter.isShaderFilterSupported;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startCamera(int idx) async {
    await _ctrl?.dispose();
    final c = CameraController(
      _cams[idx],
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await c.initialize();
    if (!mounted) return;
    setState(() {
      _ctrl = c;
      _camIdx = idx;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _capture() async {
    if (_isShooting || _ctrl == null || !_ctrl!.value.isInitialized || _luts.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isShooting = true;
      _flash = true;
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _flash = false);
    });

    try {
      final f = await _ctrl!.takePicture();
      final rawJpg = await f.readAsBytes();
      final lut = _luts[_curLut];

      // Giải mã, giới hạn cạnh dài nhất 2048 (không phóng to ảnh nhỏ)
      final buffer = await ui.ImmutableBuffer.fromUint8List(rawJpg);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final longest = math.max(desc.width, desc.height);
      int? tw, th;
      if (longest > 2048) {
        if (desc.width >= desc.height) {
          tw = 2048;
        } else {
          th = 2048;
        }
      }
      final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
      final src = (await codec.getNextFrame()).image;
      final w = src.width.toDouble();
      final h = src.height.toDouble();

      final barH = _wm ? (math.max(w, h) * 0.062).roundToDouble() : 0.0;
      final totalH = h + barH;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      if (_program != null) {
        final shader = _program!.fragmentShader()
          ..setFloat(0, w)
          ..setFloat(1, h)
          ..setFloat(2, lut.n.toDouble())
          ..setImageSampler(0, src)
          ..setImageSampler(1, lut.lutTexture);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = shader);
      } else {
        canvas.drawImage(src, Offset.zero,
            Paint()..colorFilter = ColorFilter.matrix(lut.previewMatrix));
      }
      if (_wm) _drawFrame(canvas, w, h, barH, lut.name);

      final outImg = await recorder.endRecording().toImage(w.toInt(), totalH.toInt());
      final data = await outImg.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw Exception('Không đọc được dữ liệu ảnh');
      final bytes = data.buffer.asUint8List();
      final iw = w.toInt(), ih = totalH.toInt();

      final jpg = await _encodeJpgIsolate(bytes, iw, ih);

      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          _toast('Chưa cấp quyền lưu ảnh');
          return;
        }
      }
      // QUAN TRỌNG: tên file phải có đuôi .jpg
      await Gal.putImageBytes(jpg, name: 'FUJI_${DateTime.now().millisecondsSinceEpoch}.jpg');
      if (mounted) setState(() => _lastThumb = jpg);
      _toast('Đã lưu vào Thư viện');
    } catch (e, st) {
      debugPrint('Shoot error: $e\n$st');
      _toast('Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isShooting = false);
    }
  }

  void _drawFrame(Canvas c, double w, double h, double bar, String lutName) {
    final u = bar / 9;
    c.drawRect(Rect.fromLTWH(0, h, w, bar), Paint()..color = const Color(0xFFF6F4ED));
    const ink = Color(0xFF1A1918), mute = Color(0xFF706B62);
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    _text(c, _model.toUpperCase(), u * 2.2, h + u * 4.2, u * 2.3, FontWeight.w800, ink, u * 0.22);
    _text(c, '${n.day}.${p(n.month)}.${n.year}  ${p(n.hour)}:${p(n.minute)}', u * 2.2, h + u * 6.8,
        u * 1.5, FontWeight.w500, mute, u * 0.1);
    _text(c, lutName.toUpperCase(), w - u * 5.6, h + u * 4.2, u * 2.1, FontWeight.w700, ink, u * 0.2,
        right: true);
    _text(c, 'FILM SIMULATION', w - u * 5.6, h + u * 6.8, u * 1.3, FontWeight.w600, mute, u * 0.12,
        right: true);
    c.drawCircle(Offset(w - u * 2.6, h + u * 4.5), u * 1.2, Paint()..color = kAccent);
  }

  void _text(Canvas c, String s, double x, double y, double sz, FontWeight w, Color col, double sp,
      {bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: sz, fontWeight: w, color: col, letterSpacing: sp)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(right ? x - tp.width : x,
        y - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
  }

  Future<void> _editModel() async {
    final tc = TextEditingController(text: _model);
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('Tên máy ảnh', style: TextStyle(fontSize: 15)),
        content: TextField(controller: tc, autofocus: true, textCapitalization: TextCapitalization.characters),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          TextButton(onPressed: () => Navigator.pop(context, tc.text), child: const Text('OK')),
        ],
      ),
    );
    if (r != null && r.trim().isNotEmpty) setState(() => _model = r.trim());
  }

  @override
  void dispose() {
    _previewShader?.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: _viewfinder()),
            _filmStrip(),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            GestureDetector(
              onTap: _editModel,
              child: Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(_model, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              ]),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _wm = !_wm);
              },
              icon: Icon(_wm ? Icons.crop_original : Icons.crop_free, size: 18, color: _wm ? kAmber : Colors.white54),
              label: Text(_wm ? 'Khung' : 'Không khung',
                  style: TextStyle(fontSize: 12, color: _wm ? kAmber : Colors.white54)),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined, size: 22),
              onPressed: _cams.length > 1 ? () => _startCamera((_camIdx + 1) % _cams.length) : null,
            ),
          ],
        ),
      );

  Widget _preview() {
    final size = _ctrl!.value.previewSize;
    Widget cam = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size?.height ?? 100,
        height: size?.width ?? 100,
        child: CameraPreview(_ctrl!),
      ),
    );
    if (_luts.isEmpty) return cam;
    if (_canShaderPreview) {
      return ImageFiltered(imageFilter: ui.ImageFilter.shader(_previewShader!), child: cam);
    }
    return ColorFiltered(colorFilter: ColorFilter.matrix(_luts[_curLut].previewMatrix), child: cam);
  }

  Widget _viewfinder() {
    final ready = _ctrl?.value.isInitialized ?? false;
    final lut = _luts.isNotEmpty ? _luts[_curLut] : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            if (ready) _preview() else const Center(child: CircularProgressIndicator(color: kAccent)),
            if (_flash) const ColoredBox(color: Colors.white),
            // Lưới 1/3 + nhãn
            IgnorePointer(child: CustomPaint(painter: _GridPainter())),
            Positioned(
              left: 14, top: 14,
              child: _chip(lut?.name ?? '', kAmber),
            ),
            Positioned(
              right: 14, top: 14,
              child: _chip('F2.8 · 1/250 · ISO 400', Colors.white70),
            ),
            if (_isShooting)
              const Positioned(
                bottom: 14, left: 0, right: 0,
                child: Center(child: Text('ĐANG XỬ LÝ…', style: TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.white70))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: c)),
      );

  Widget _filmStrip() => SizedBox(
        height: 56,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: _luts.length,
          itemBuilder: (_, i) {
            final sel = i == _curLut;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _curLut = i;
                  _rebuildPreviewShader();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? Colors.white : kPanel,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _luts[i].name,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8,
                    color: sel ? Colors.black : Colors.white60,
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _bottomBar() => Padding(
        padding: const EdgeInsets.fromLTRB(32, 6, 32, 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: _lastThumb == null
                  ? null
                  : () => showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_lastThumb!)),
                        ),
                      ),
              child: Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: kPanel,
                  borderRadius: BorderRadius.circular(12),
                  image: _lastThumb == null ? null : DecorationImage(image: MemoryImage(_lastThumb!), fit: BoxFit.cover),
                ),
                child: _lastThumb == null ? const Icon(Icons.photo_outlined, color: Colors.white24) : null,
              ),
            ),
            GestureDetector(
              onTap: _capture,
              child: AnimatedScale(
                scale: _isShooting ? 0.92 : 1,
                duration: const Duration(milliseconds: 100),
                child: Container(
                  width: 78, height: 78,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _isShooting ? Colors.white38 : Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 54, height: 54),
          ],
        ),
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.white24..strokeWidth = 0.7;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(Offset(s.width * i / 3, 0), Offset(s.width * i / 3, s.height), p);
      canvas.drawLine(Offset(0, s.height * i / 3), Offset(s.width, s.height * i / 3), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}


Future<Uint8List> _encodeJpgIsolate(Uint8List bytes, int w, int h) {
  return Isolate.run(() {
    final im = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: bytes.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(im, quality: 92));
  });
}