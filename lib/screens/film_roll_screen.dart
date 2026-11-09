import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/film_model.dart';
import '../services/photo_store.dart';
import '../theme.dart';

String _filmName(String id) {
  for (final f in FilmModel.fujiCatalog) {
    if (PhotoStore.sanitize(f.id) == id) return f.fullName.toUpperCase();
  }
  return id;
}

String _fmt(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}.${two(d.month)}.${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
}

/// Photos taken with the app, laid out as a vertical strip of film.
class FilmRollScreen extends StatefulWidget {
  const FilmRollScreen({super.key});

  @override
  State<FilmRollScreen> createState() => _FilmRollScreenState();
}

class _FilmRollScreenState extends State<FilmRollScreen> {
  static const double _pitch = 30; // distance between sprocket holes
  static const double _side = 32; // sprocket column width

  final ScrollController _scroll = ScrollController();
  List<RollEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load(toEnd: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool toEnd}) async {
    final list = await PhotoStore.load();
    if (!mounted) return;
    setState(() => _entries = list);
    if (toEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  Future<void> _open(int index) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoViewer(entries: List.of(_entries!), initialIndex: index),
    ));
    _load(toEnd: false);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const RedDot(size: 8),
                  const SizedBox(width: 8),
                  const Text('FILM ROLL',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 2.2)),
                  const Spacer(),
                  if (entries != null)
                    Text('${entries.length} EXP.',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.orangeLcd,
                          letterSpacing: 1.2,
                        )),
                ],
              ),
            ),
            Expanded(child: _body(entries)),
          ],
        ),
      ),
    );
  }

  Widget _body(List<RollEntry>? entries) {
    if (entries == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.red));
    }
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.camera_roll_outlined, size: 44, color: Colors.white24),
            SizedBox(height: 12),
            Text('The roll is empty',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Shots you take will appear here as frames',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final stripW = box.maxWidth - 28;
      final frameW = stripW - _side * 2;
      final frameH = frameW * 4 / 3;
      final extent = ((frameH + 44) / _pitch).ceil() * _pitch;
      final gap = (extent - frameH) / 2;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF16100B),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ListView.builder(
            controller: _scroll,
            itemExtent: extent,
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final n = i + 1;
              const edge = TextStyle(
                fontFamily: 'Courier',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Color(0xFFE8892B),
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _SprocketPainter(_pitch, _side)),
                  ),
                  // Edge print above the frame
                  Positioned(
                    top: 0,
                    left: _side,
                    right: _side,
                    height: gap,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text('FUJIFILM  ${_fmt(e.time)}',
                            style: edge.copyWith(color: Colors.white24)),
                      ),
                    ),
                  ),
                  // Frame
                  Positioned(
                    top: gap,
                    left: _side,
                    right: _side,
                    height: frameH,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _open(i);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: Colors.white12, width: 0.8),
                        ),
                        child: Image.file(
                          e.file,
                          cacheWidth: math.min(900, (frameW * 2).round()),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined, color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Edge print below the frame: ▶ 12   VELVIA 50   12A
                  Positioned(
                    bottom: 0,
                    left: _side,
                    right: _side,
                    height: gap,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('▶ $n', style: edge),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _filmName(e.filmId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: edge.copyWith(color: Colors.white38),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${n}A', style: edge),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    });
  }
}

class _SprocketPainter extends CustomPainter {
  final double pitch;
  final double side;
  const _SprocketPainter(this.pitch, this.side);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.black;
    const hw = 13.0, hh = 18.0;
    final lx = (side - hw) / 2;
    final rx = s.width - side + (side - hw) / 2;
    for (var y = (pitch - hh) / 2; y < s.height; y += pitch) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(lx, y, hw, hh), const Radius.circular(3)), p);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(rx, y, hw, hh), const Radius.circular(3)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SprocketPainter old) => old.pitch != pitch || old.side != side;
}

class _PhotoViewer extends StatefulWidget {
  final List<RollEntry> entries;
  final int initialIndex;
  const _PhotoViewer({required this.entries, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  late final List<RollEntry> _list = widget.entries;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panelHigh,
        title: const Text('Delete this frame?'),
        content: const Text(
          'It will be removed from the film roll. The copy saved in your '
          'DCIM folder is not deleted.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.redBright)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PhotoStore.delete(_list[_index]);
    if (!mounted) return;
    setState(() {
      _list.removeAt(_index);
      if (_list.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (_index >= _list.length) _index = _list.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_list.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final e = _list[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(_filmName(e.filmId),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                        const SizedBox(height: 2),
                        Text(_fmt(e.time),
                            style: const TextStyle(
                                fontFamily: 'Courier', fontSize: 11, color: AppColors.orangeLcd)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _delete,
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _list.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.file(_list[i].file, fit: BoxFit.contain),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'FRAME ${_index + 1} / ${_list.length}',
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 11,
                    color: Colors.white38,
                    letterSpacing: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}