import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'lut.dart';

// Bảng màu: đen + đỏ Fujifilm
const kRed = Color(0xFFE02A1F);
const kPanel = Color(0xFF141414);
const kPanel2 = Color(0xFF1C1C1C);
const kLine = Color(0x22FFFFFF);
const kBarRatio = 0.062; // chiều cao khung watermark / cạnh dài của ảnh

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(primary: kRed, onPrimary: Colors.white, surface: kPanel),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? kRed : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white70),
          side: WidgetStatePropertyAll(BorderSide(color: kLine)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white54),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? kRed : const Color(0xFF2A2A2A)),
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    home: const FujiVintageCamera(),
  ));
}

// ───────────────────────── Dữ liệu film ─────────────────────────

class FilmSpec {
  final String name, code, path, desc;
  final Color color;
  final String? img; // tuỳ chọn: ảnh cuộn film thật (PNG nền trong suốt)
  const FilmSpec(this.name, this.code, this.path, this.desc, this.color, {this.img});
}

class _Film {
  final FilmSpec spec;
  final Lut lut;
  _Film(this.spec, this.lut);
}

// ───────────────────────── Watermark ─────────────────────────

class WmConfig {
  final ui.Image? logo;
  final String film;
  final DateTime time;
  final bool dark, showFilm, showDate;
  const WmConfig({
    required this.logo,
    required this.film,
    required this.time,
    required this.dark,
    required this.showFilm,
    required this.showDate,
  });
}

String _fmtDate(DateTime n) {
  String p(int v) => v.toString().padLeft(2, '0');
  return '${n.day}.${p(n.month)}.${n.year}  ${p(n.hour)}:${p(n.minute)}';
}

void _wmText(Canvas c, String s, double x, double cy, double size, FontWeight fw, Color col, double sp,
    {bool right = false}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontSize: size, fontWeight: fw, color: col, letterSpacing: sp, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset(right ? x - tp.width : x, cy - tp.height / 2));
}

void paintWatermark(Canvas c, Size s, WmConfig o) {
  final w = s.width, h = s.height;
  final bg = o.dark ? const Color(0xFF0C0C0C) : const Color(0xFFF6F4EE);
  final ink = o.dark ? Colors.white : const Color(0xFF151515);
  final mute = o.dark ? const Color(0xFF9A968E) : const Color(0xFF77726A);
  final brand = o.dark ? Colors.white : kRed; // logo: đỏ Fuji trên nền sáng
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = bg);

  final pad = h * 0.5;

  final logo = o.logo;
  if (logo != null) {
    final lh = h * 0.30;
    final lw = lh * logo.width / logo.height;
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = ColorFilter.mode(brand, BlendMode.srcIn);
    c.drawImageRect(
      logo,
      Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      Rect.fromLTWH(pad, (h - lh) / 2, lw, lh),
      paint,
    );
  } else {
    _wmText(c, 'FUJIFILM', pad, h / 2, h * 0.27, FontWeight.w900, brand, h * 0.035);
  }

  final film = o.showFilm ? o.film.toUpperCase() : null;
  final date = o.showDate ? _fmtDate(o.time) : null;
  final x = w - pad;
  if (film != null && date != null) {
    _wmText(c, film, x, h * 0.40, h * 0.20, FontWeight.w800, ink, h * 0.02, right: true);
    _wmText(c, date, x, h * 0.64, h * 0.14, FontWeight.w500, mute, h * 0.01, right: true);
  } else if (film != null) {
    _wmText(c, film, x, h / 2, h * 0.22, FontWeight.w800, ink, h * 0.02, right: true);
  } else if (date != null) {
    _wmText(c, date, x, h / 2, h * 0.16, FontWeight.w500, mute, h * 0.01, right: true);
  }
}

class _BarPainter extends CustomPainter {
  final WmConfig o;
  _BarPainter(this.o);
  @override
  void paint(Canvas c, Size s) => paintWatermark(c, s, o);
  @override
  bool shouldRepaint(_BarPainter old) => true;
}

// ───────────────────────── Cuộn film 35mm ─────────────────────────

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

class _CanisterPainter extends CustomPainter {
  final Color color;
  final String code;
  const _CanisterPainter(this.color, this.code);

  // Khối trụ kim loại: tối ở mép, sáng ở khoảng 1/3
  Shader _metal(Rect r) => LinearGradient(
        colors: const [
          Color(0xFF55565B),
          Color(0xFFA9AAAF),
          Color(0xFFF1F1F4),
          Color(0xFF9C9DA2),
          Color(0xFF45464A),
        ],
        stops: const [0, .2, .38, .72, 1],
      ).createShader(r);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final bx = w * 0.04, bw = w * 0.68;

    // đuôi film thò ra phía sau
    final tongue = Rect.fromLTWH(bx + bw - w * 0.05, h * 0.60, w * 0.31, h * 0.15);
    c.drawRRect(RRect.fromRectAndRadius(tongue, Radius.circular(h * 0.012)),
        Paint()..color = const Color(0xFF1F1B19));
    c.drawLine(Offset(tongue.left, tongue.top + 1), Offset(tongue.right, tongue.top + 1),
        Paint()..color = const Color(0xFF4A4440)..strokeWidth = 1);

    // đầu trục
    final stub = Rect.fromLTWH(bx + bw / 2 - w * 0.07, 0, w * 0.14, h * 0.09);
    c.drawRRect(RRect.fromRectAndRadius(stub, Radius.circular(w * 0.02)), Paint()..shader = _metal(stub));

    // thân nhãn: màu phẳng + dải đen + vạch trắng + mã film
    final label = Rect.fromLTWH(bx, h * 0.15, bw, h * 0.70);
    c.drawRect(label, Paint()..color = color);
    final black = Paint()..color = const Color(0xFF141414);
    c.drawRect(Rect.fromLTWH(bx, label.top, bw, h * 0.075), black);
    c.drawRect(Rect.fromLTWH(bx, label.bottom - h * 0.075, bw, h * 0.075), black);
    final stripe = Paint()..color = Colors.white.withAlpha(215);
    c.drawRect(Rect.fromLTWH(bx, label.top + h * 0.075, bw, h * 0.014), stripe);
    c.drawRect(Rect.fromLTWH(bx, label.bottom - h * 0.089, bw, h * 0.014), stripe);

    final tp = TextPainter(
      text: TextSpan(
        text: code,
        style: TextStyle(
          fontSize: bw * 0.50,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1,
          letterSpacing: 1,
          shadows: const [Shadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(bx + (bw - tp.width) / 2, label.center.dy - tp.height / 2));

    // lớp bóng hình trụ phủ lên toàn bộ nhãn
    c.drawRect(
      label,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x99000000),
            Color(0x0D000000),
            Color(0x47FFFFFF),
            Color(0x1F000000),
            Color(0xA6000000),
          ],
          stops: [0, .2, .36, .7, 1],
        ).createShader(label),
    );

    // nắp trên và nắp dưới (rộng hơn thân một chút)
    for (final y in [h * 0.05, h * 0.84]) {
      final cap = Rect.fromLTWH(bx - w * 0.015, y, bw + w * 0.03, h * 0.11);
      final rr = RRect.fromRectAndRadius(cap, Radius.circular(h * 0.03));
      c.drawRRect(rr, Paint()..shader = _metal(cap));
      c.drawLine(Offset(cap.left + w * 0.04, cap.top + h * 0.02),
          Offset(cap.right - w * 0.04, cap.top + h * 0.02), Paint()..color = const Color(0x55FFFFFF)..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_CanisterPainter o) => o.color != color || o.code != code;
}

class _Canister extends StatelessWidget {
  final FilmSpec spec;
  final double h;
  const _Canister(this.spec, this.h);

  @override
  Widget build(BuildContext context) {
    final painted = CustomPaint(painter: _CanisterPainter(spec.color, spec.code));
    return SizedBox(
      width: h * 0.8,
      height: h,
      child: spec.img == null
          ? painted
          : Image.asset(spec.img!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => painted),
    );
  }
}

// ───────────────────────── Nút chụp: vòng khía kim loại + nút đỏ ─────────────────────────

class _ShutterPainter extends CustomPainter {
  final bool busy;
  const _ShutterPainter(this.busy);

  @override
  void paint(Canvas c, Size s) {
    final ctr = s.center(Offset.zero);
    final r = s.width / 2;

    c.drawCircle(
      ctr,
      r,
      Paint()
        ..shader = const SweepGradient(colors: [
          Color(0xFF9A9A9F),
          Color(0xFFE6E6EA),
          Color(0xFF6C6C70),
          Color(0xFFD4D4D8),
          Color(0xFF8A8A8F),
          Color(0xFFE6E6EA),
          Color(0xFF9A9A9F),
        ]).createShader(Rect.fromCircle(center: ctr, radius: r)),
    );

    // vân khía
    final tick = Paint()
      ..color = const Color(0x77000000)
      ..strokeWidth = 1.2;
    const n = 64;
    for (var i = 0; i < n; i++) {
      final a = 2 * math.pi * i / n;
      final d = Offset(math.cos(a), math.sin(a));
      c.drawLine(ctr + d * (r - 5.5), ctr + d * (r - 0.5), tick);
    }

    c.drawCircle(ctr, r - 8, Paint()..color = const Color(0xFF0A0A0A));

    final br = r - 12;
    c.drawCircle(
      ctr,
      br,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 1.0,
          colors: [Color(0xFFFF5547), kRed, Color(0xFF8E1410)],
          stops: [0, .55, 1],
        ).createShader(Rect.fromCircle(center: ctr, radius: br)),
    );
    c.drawArc(
      Rect.fromCircle(center: ctr, radius: br - 3),
      math.pi * 1.1,
      math.pi * 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x66FFFFFF),
    );
    if (busy) c.drawCircle(ctr, br, Paint()..color = const Color(0x88000000));
  }

  @override
  bool shouldRepaint(_ShutterPainter o) => o.busy != busy;
}

// ───────────────────────── Khung ngắm: góc + lưới ─────────────────────────

class _FramePainter extends CustomPainter {
  final bool grid;
  const _FramePainter(this.grid);

  @override
  void paint(Canvas canvas, Size s) {
    if (grid) {
      final p = Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 0.7;
      for (var i = 1; i < 3; i++) {
        canvas.drawLine(Offset(s.width * i / 3, 0), Offset(s.width * i / 3, s.height), p);
        canvas.drawLine(Offset(0, s.height * i / 3), Offset(s.width, s.height * i / 3), p);
      }
    }
    // 4 góc ngắm
    final p = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const m = 14.0, l = 18.0;
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(m, m + l)..lineTo(m, m)..lineTo(m + l, m)
      ..moveTo(w - m - l, m)..lineTo(w - m, m)..lineTo(w - m, m + l)
      ..moveTo(m, h - m - l)..lineTo(m, h - m)..lineTo(m + l, h - m)
      ..moveTo(w - m - l, h - m)..lineTo(w - m, h - m)..lineTo(w - m, h - m - l);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_FramePainter o) => o.grid != grid;
}

// ───────────────────────── Màn hình chính ─────────────────────────

class FujiVintageCamera extends StatefulWidget {
  const FujiVintageCamera({super.key});
  @override
  State<FujiVintageCamera> createState() => _FujiVintageCameraState();
}

class _FujiVintageCameraState extends State<FujiVintageCamera> {
  List<CameraDescription> _cams = [];
  CameraController? _ctrl;
  int _camIdx = 0, _curLut = 0;
  final List<_Film> _films = [];
  bool _isShooting = false, _flash = false;

  bool _wm = true, _darkBar = false, _showFilm = true, _showDate = true, _grid = true;

  Uint8List? _lastThumb;
  ui.FragmentProgram? _program;
  ui.FragmentShader? _previewShader;
  ui.Image? _logo;
  SharedPreferences? _prefs;

  static const _catalog = [
    FilmSpec('ASTIA', 'AS', 'assets/luts/astia_sRGB.cube', 'Mềm, màu da tự nhiên', Color(0xFFC94F7C)),
    FilmSpec('BLEACH BYPASS', 'BB', 'assets/luts/bleach bypass_sRGB.cube', 'Giảm bão hoà, tương phản cao', Color(0xFF6F757B)),
    FilmSpec('CLASSIC CHROME', 'CC', 'assets/luts/classic chrome_sRGB.cube', 'Màu trầm, tương phản cứng', Color(0xFF3F7078)),
    FilmSpec('CLASSIC NEG', 'CN', 'assets/luts/classic neg_sRGB.cube', 'Hoài cổ, bóng tối ngả xanh', Color(0xFF2F7D6B)),
    FilmSpec('ETERNA', 'ET', 'assets/luts/eterna_sRGB.cube', 'Tông điện ảnh, màu dịu', Color(0xFF7D5E42)),
    FilmSpec('NOSTALGIC NEG', 'NN', 'assets/luts/nostalgic neg_sRGB.cube', 'Ấm, highlight mềm', Color(0xFFB87530)),
    FilmSpec('PRO NEG HI', 'PH', 'assets/luts/pro neg hi_sRGB.cube', 'Chân dung, tương phản cao', Color(0xFFA9483A)),
    FilmSpec('PRO NEG STD', 'PS', 'assets/luts/pro neg std_sRGB.cube', 'Chân dung, mềm, da đẹp', Color(0xFFB98563)),
    FilmSpec('PROVIA', 'PV', 'assets/luts/provia_sRGB.cube', 'Trung thực, đa dụng', Color(0xFF2860B8)),
    FilmSpec('REALA ACE', 'RA', 'assets/luts/reala ace_sRGB.cube', 'Chân thực, trung tính', Color(0xFF6B4FAE)),
    FilmSpec('VELVIA', 'VL', 'assets/luts/velvia_sRGB.cube', 'Rực rỡ, bão hoà cao', Color(0xFF248A44)),
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<ui.Image?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/images/fujifilm_logo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null; // chưa có logo -> vẽ chữ FUJIFILM
    }
  }

  Future<void> _init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs!;
      _wm = p.getBool('wm') ?? true;
      _darkBar = p.getBool('dark') ?? false;
      _showFilm = p.getBool('showFilm') ?? true;
      _showDate = p.getBool('showDate') ?? true;
      _grid = p.getBool('grid') ?? true;
      _curLut = p.getInt('film') ?? 0;
    } catch (e) {
      debugPrint('Prefs: $e');
    }
    _logo = await _loadLogo();
    try {
      _program = await ui.FragmentProgram.fromAsset('assets/shaders/lut.frag');
    } catch (e) {
      debugPrint('Shader load: $e');
    }
    for (final s in _catalog) {
      try {
        final text = await rootBundle.loadString(s.path);
        _films.add(_Film(s, await Lut.parse(s.name, s.code, text)));
      } catch (e) {
        debugPrint('LUT skip [${s.name}]: $e');
      }
    }
    if (_curLut >= _films.length) _curLut = 0;
    _rebuildPreviewShader();
    _cams = await availableCameras();
    if (_cams.isNotEmpty) await _startCamera(0);
    if (mounted) setState(() {});
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setBool('wm', _wm);
    p.setBool('dark', _darkBar);
    p.setBool('showFilm', _showFilm);
    p.setBool('showDate', _showDate);
    p.setBool('grid', _grid);
    p.setInt('film', _curLut);
  }

  void _rebuildPreviewShader() {
    _previewShader?.dispose();
    _previewShader = null;
    if (_program == null || _films.isEmpty) return;
    final s = _program!.fragmentShader();
    final lut = _films[_curLut].lut;
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
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: kPanel2,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 130),
        duration: const Duration(seconds: 2),
      ));
  }

  void _selectFilm(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _curLut = i;
      _rebuildPreviewShader();
    });
    _save();
  }

  WmConfig _wmConfig(String film) => WmConfig(
        logo: _logo,
        film: film,
        time: DateTime.now(),
        dark: _darkBar,
        showFilm: _showFilm,
        showDate: _showDate,
      );

  // ───────────────────────── Chụp ─────────────────────────

  Future<void> _capture() async {
    if (_isShooting || _ctrl == null || !_ctrl!.value.isInitialized || _films.isEmpty) return;
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
      final film = _films[_curLut];
      final lut = film.lut;

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

      final barH = _wm ? (math.max(w, h) * kBarRatio).roundToDouble() : 0.0;
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
        canvas.drawImage(src, Offset.zero, Paint()..colorFilter = ColorFilter.matrix(lut.previewMatrix));
      }

      if (barH > 0) {
        canvas.save();
        canvas.translate(0, h);
        paintWatermark(canvas, Size(w, barH), _wmConfig(film.spec.name));
        canvas.restore();
      }

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

  @override
  void dispose() {
    _previewShader?.dispose();
    _ctrl?.dispose();
    _logo?.dispose();
    super.dispose();
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: Center(child: _viewfinder())),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: Colors.white70),
              onPressed: _openSettings,
            ),
            Expanded(child: Center(child: _filmPill())),
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white70),
              onPressed: _cams.length > 1 ? () => _startCamera((_camIdx + 1) % _cams.length) : null,
            ),
          ],
        ),
      );

  Widget _filmPill() {
    if (_films.isEmpty) return const SizedBox(height: 44);
    final f = _films[_curLut];
    return GestureDetector(
      onTap: _openFilmPicker,
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 12, right: 10),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Canister(f.spec, 28),
            const SizedBox(width: 10),
            Text(f.spec.name,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: kRed),
          ],
        ),
      ),
    );
  }

  // Bảng chọn film: lưới 3 cột, mỗi film một cuộn riêng
  void _openFilmPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kPanel,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('FILM SIMULATION',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2, color: kRed)),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: _films.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.66,
                  ),
                  itemBuilder: (_, i) => _filmTile(i, ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filmTile(int i, BuildContext ctx) {
    final f = _films[i];
    final sel = i == _curLut;
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        _selectFilm(i);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF261312) : kPanel2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? kRed : kLine, width: sel ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: _Canister(f.spec, 74))),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(f.spec.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: sel ? Colors.white : Colors.white70,
                  )),
            ),
            const SizedBox(height: 3),
            Text(
              f.spec.desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9.5, height: 1.25, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final size = _ctrl!.value.previewSize;
    final Widget cam = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size?.height ?? 100,
        height: size?.width ?? 100,
        child: CameraPreview(_ctrl!),
      ),
    );
    if (_films.isEmpty) return cam;
    if (_canShaderPreview) {
      return ImageFiltered(imageFilter: ui.ImageFilter.shader(_previewShader!), child: cam);
    }
    return ColorFiltered(colorFilter: ColorFilter.matrix(_films[_curLut].lut.previewMatrix), child: cam);
  }

  Widget _viewfinder() {
    final ready = _ctrl?.value.isInitialized ?? false;
    final ar = ready ? 1 / _ctrl!.value.aspectRatio : 3 / 4;
    final k = _wm ? kBarRatio : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AspectRatio(
        aspectRatio: ar / (1 + k),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kLine),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: LayoutBuilder(builder: (context, box) {
              final barH = box.maxHeight * k / (1 + k);
              final film = _films.isNotEmpty ? _films[_curLut] : null;
              return Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Colors.black),
                        if (ready)
                          _preview()
                        else
                          const Center(child: CircularProgressIndicator(color: kRed)),
                        if (_flash) const ColoredBox(color: Colors.white),
                        IgnorePointer(child: CustomPaint(painter: _FramePainter(_grid))),
                        if (film != null)
                          Positioned(
                            left: 14,
                            top: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(4)),
                              child: Text(film.spec.code,
                                  style: const TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_wm && film != null)
                    SizedBox(
                      height: barH,
                      width: double.infinity,
                      child: CustomPaint(painter: _BarPainter(_wmConfig(film.spec.name))),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() => Padding(
        padding: const EdgeInsets.fromLTRB(28, 14, 28, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [_thumb(), _shutter(), _frameToggle()],
        ),
      );

  Widget _thumb() => GestureDetector(
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
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kLine),
            image: _lastThumb == null
                ? null
                : DecorationImage(image: MemoryImage(_lastThumb!), fit: BoxFit.cover),
          ),
          child: _lastThumb == null ? const Icon(Icons.photo_outlined, color: Colors.white24) : null,
        ),
      );

  Widget _shutter() => GestureDetector(
        onTap: _capture,
        child: AnimatedScale(
          scale: _isShooting ? 0.94 : 1,
          duration: const Duration(milliseconds: 100),
          child: SizedBox(
            width: 84,
            height: 84,
            child: CustomPaint(painter: _ShutterPainter(_isShooting)),
          ),
        ),
      );

  Widget _frameToggle() => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _wm = !_wm);
          _save();
        },
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _wm ? kRed : kPanel,
            border: Border.all(color: _wm ? kRed : kLine),
          ),
          child: Icon(Icons.branding_watermark_outlined, size: 22, color: _wm ? Colors.white : Colors.white54),
        ),
      );

  // ───────────────────────── Cài đặt ─────────────────────────

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kPanel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) {
        void upd(VoidCallback f) {
          setState(f);
          setSheet(() {});
          _save();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('CÀI ĐẶT',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 2, color: kRed)),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Khung watermark'),
                  subtitle: const Text('Thanh logo Fujifilm dưới ảnh'),
                  value: _wm,
                  onChanged: (v) => upd(() => _wm = v),
                ),
                if (_wm) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Màu khung'),
                    trailing: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('Sáng')),
                        ButtonSegment(value: true, label: Text('Tối')),
                      ],
                      selected: {_darkBar},
                      onSelectionChanged: (s) => upd(() => _darkBar = s.first),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hiện tên film'),
                    value: _showFilm,
                    onChanged: (v) => upd(() => _showFilm = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hiện ngày giờ'),
                    value: _showDate,
                    onChanged: (v) => upd(() => _showDate = v),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lưới 1/3'),
                  value: _grid,
                  onChanged: (v) => upd(() => _grid = v),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
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