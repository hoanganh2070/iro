import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

class Lut {
  final String name;
  final String code;
  final int n;
  final Float32List data;
  final List<double> previewMatrix;
  final ui.Image lutTexture;

  Lut({
    required this.name,
    required this.code,
    required this.n,
    required this.data,
    required this.previewMatrix,
    required this.lutTexture,
  });


   static List<double> _fitMatrix(int n, Float32List d) {
  final step = math.max(1, n ~/ 9);
  final a = List.generate(4, (_) => List<double>.filled(7, 0)); // 4x4 | 3 vế phải
  final m = (n - 1).toDouble();
  for (var b = 0; b < n; b += step) {
    for (var g = 0; g < n; g += step) {
      for (var r = 0; r < n; r += step) {
        final x = [r / m, g / m, b / m, 1.0];
        final i = (b * n * n + g * n + r) * 3;
        for (var p = 0; p < 4; p++) {
          for (var q = 0; q < 4; q++) {
            a[p][q] += x[p] * x[q];
          }
          for (var q = 0; q < 3; q++) {
            a[p][4 + q] += x[p] * d[i + q];
          }
        }
      }
    }
  }
  // Gauss-Jordan
  for (var c = 0; c < 4; c++) {
    var piv = c;
    for (var r = c + 1; r < 4; r++) {
      if (a[r][c].abs() > a[piv][c].abs()) piv = r;
    }
    final t = a[c]; a[c] = a[piv]; a[piv] = t;
    final div = a[c][c];
    for (var k = 0; k < 7; k++) { a[c][k] /= div; }
    for (var r = 0; r < 4; r++) {
      if (r == c) continue;
      final f = a[r][c];
      for (var k = 0; k < 7; k++) { a[r][k] -= f * a[c][k]; }
    }
  }
  // a[p][4+ch] = hệ số của đầu vào p cho kênh ch
  List<double> row(int ch) =>
      [a[0][4 + ch], a[1][4 + ch], a[2][4 + ch], 0.0, a[3][4 + ch] * 255.0];
  return [...row(0), ...row(1), ...row(2), 0, 0, 0, 1, 0];
}
  /// Parse dữ liệu .cube thành đối tượng Lut
  static Future<Lut> parse(String name, String code, String text) async {
    var n = 0;
    final v = <double>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final s = raw.trim();
      if (s.isEmpty || s.startsWith('#')) continue;
      if (s.startsWith('LUT_3D_SIZE')) {
        n = int.parse(s.split(RegExp(r'\s+')).last);
      } else if (RegExp(r'^[-\d.]').hasMatch(s)) {
        final p = s.split(RegExp(r'\s+'));
        if (p.length >= 3) v.addAll(p.take(3).map(double.parse));
      }
    }
    if (n == 0 || v.length < n * n * n * 3) {
      throw const FormatException('File .cube không hợp lệ');
    }

    final data = Float32List.fromList(v.sublist(0, n * n * n * 3));
    final matrix = _fitMatrix(n, data);
    final texture = await _createTexture(n, data);

    return Lut(
      name: name,
      code: code,
      n: n,
      data: data,
      previewMatrix: matrix,
      lutTexture: texture,
    );
  }

  /// Đưa dữ liệu 3D .cube thành 2D Texture trên VRAM GPU
  static Future<ui.Image> _createTexture(int n, Float32List d) async {
    final count = n * n * n;
    final px = Uint8List(count * 4);
    var src = 0, dst = 0;
    for (var i = 0; i < count; i++) {
      px[dst] = (d[src] * 255).clamp(0, 255).toInt();
      px[dst + 1] = (d[src + 1] * 255).clamp(0, 255).toInt();
      px[dst + 2] = (d[src + 2] * 255).clamp(0, 255).toInt();
      px[dst + 3] = 255;
      src += 3;
      dst += 4;
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, n, n * n, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

}