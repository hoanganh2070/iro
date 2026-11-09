import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

class FocalLengthOption {
  final String mm;
  final String zoomLabel;
  final double zoomRatio;
  const FocalLengthOption(this.mm, this.zoomLabel, this.zoomRatio);
}

class FocalLengthSelector extends StatelessWidget {
  final int selectedIndex;
  final Function(int index, double zoom) onSelected;

  const FocalLengthSelector({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const options = [
    FocalLengthOption('24', '1×', 1.0),
    FocalLengthOption('35', '1.5×', 1.5),
    FocalLengthOption('50', '2×', 2.0),
    FocalLengthOption('90', '4×', 4.0),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(options.length, (i) {
            final opt = options[i];
            final sel = i == selectedIndex;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(i, opt.zoomRatio);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 58,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  color: sel ? Colors.white : Colors.transparent,
                  boxShadow: sel
                      ? [BoxShadow(color: Colors.white.withAlpha(50), blurRadius: 10)]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${opt.mm}mm',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        color: sel ? Colors.black : Colors.white,
                      ),
                    ),
                    Text(
                      opt.zoomLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: sel ? Colors.black54 : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}