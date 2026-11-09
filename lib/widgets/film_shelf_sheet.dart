import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/film_model.dart';
import '../theme.dart';
import '../utils/date_stamp_painter.dart';

class FilmShelfSheet extends StatefulWidget {
  final int selectedIndex;
  final bool enableDateStamp;
  final Function(int index) onSelectFilm;
  final Function(bool enabled) onToggleDateStamp;

  const FilmShelfSheet({
    super.key,
    required this.selectedIndex,
    required this.enableDateStamp,
    required this.onSelectFilm,
    required this.onToggleDateStamp,
  });

  @override
  State<FilmShelfSheet> createState() => _FilmShelfSheetState();
}

class _FilmShelfSheetState extends State<FilmShelfSheet> {
  late bool _stampEnabled;

  @override
  void initState() {
    super.initState();
    _stampEnabled = widget.enableDateStamp;
  }

  @override
  Widget build(BuildContext context) {
    final catalog = FilmModel.fujiCatalog;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E0E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  const Text('Film Simulations',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Row(
                children: [
                  Container(width: 4, height: 14, color: AppColors.red),
                  const SizedBox(width: 8),
                  Text(
                    'FUJIFILM COLOR SIMULATIONS · ${catalog.length} ROLLS',
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                itemCount: catalog.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.74,
                ),
                itemBuilder: (context, i) {
                  final film = catalog[i];
                  final sel = i == widget.selectedIndex;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onSelectFilm(i);
                      Navigator.pop(context);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF1E1412) : AppColors.panel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel ? AppColors.red : AppColors.stroke,
                          width: sel ? 1.6 : 1,
                        ),
                        boxShadow: sel
                            ? [BoxShadow(color: AppColors.red.withAlpha(70), blurRadius: 14)]
                            : null,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Image.asset(
                              film.imagePath,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                decoration: BoxDecoration(
                                  color: film.themeColor.withAlpha(50),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(film.id,
                                      style: const TextStyle(fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (sel)
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const RedDot(size: 7),
                                  const SizedBox(width: 5),
                                  Text(film.id,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black)),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(film.id,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white70,
                                    letterSpacing: 1,
                                  )),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Date stamp option
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                color: Color(0xFF161616),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF241512),
                          border: Border.all(color: AppColors.redBright.withAlpha(100)),
                        ),
                        alignment: Alignment.center,
                        child: const Text("'98",
                            style: TextStyle(
                                color: Color(0xFFFF6500),
                                fontWeight: FontWeight.w900,
                                fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Date Stamp '98",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(
                              DateStampPainter.getFormattedDate(DateTime.now()),
                              style: const TextStyle(
                                fontFamily: 'Courier',
                                color: AppColors.orangeLcd,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _stampEnabled,
                        activeColor: Colors.white,
                        activeTrackColor: AppColors.red,
                        inactiveTrackColor: Colors.white12,
                        onChanged: (val) {
                          HapticFeedback.lightImpact();
                          setState(() => _stampEnabled = val);
                          widget.onToggleDateStamp(val);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('Format & position',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                      Text('Bottom right (Orange LCD)',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}