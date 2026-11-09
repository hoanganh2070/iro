import 'package:flutter/material.dart';
import '../theme.dart';

/// Stateful so the switches update immediately while the sheet is open
/// (the old stateless version never rebuilt after the parent's setState).
class SettingsSheet extends StatefulWidget {
  final bool enableWatermark;
  final bool darkWatermark;
  final bool showFilmName;
  final bool showDateOnWatermark;
  final bool showGrid;
  final Function(bool) onToggleWatermark;
  final Function(bool) onToggleDarkWatermark;
  final Function(bool) onToggleFilmName;
  final Function(bool) onToggleDate;
  final Function(bool) onToggleGrid;

  const SettingsSheet({
    super.key,
    required this.enableWatermark,
    required this.darkWatermark,
    required this.showFilmName,
    required this.showDateOnWatermark,
    required this.showGrid,
    required this.onToggleWatermark,
    required this.onToggleDarkWatermark,
    required this.onToggleFilmName,
    required this.onToggleDate,
    required this.onToggleGrid,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late bool _wm = widget.enableWatermark;
  late bool _dark = widget.darkWatermark;
  late bool _name = widget.showFilmName;
  late bool _date = widget.showDateOnWatermark;
  late bool _grid = widget.showGrid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: const [
                RedDot(size: 9),
                SizedBox(width: 8),
                Text('CAMERA SETTINGS',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 2,
                    )),
              ]),
              const SizedBox(height: 16),

              _label('WATERMARK FRAME'),
              _card([
                _switch(
                  icon: Icons.photo_size_select_actual_outlined,
                  title: 'Fujifilm frame',
                  subtitle: 'Adds a border with the Fujifilm logo',
                  value: _wm,
                  onChanged: (v) {
                    setState(() => _wm = v);
                    widget.onToggleWatermark(v);
                  },
                ),
                if (_wm) ...[
                  _divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.contrast_rounded, size: 20, color: Colors.white54),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Frame color',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            selectedBackgroundColor: Colors.white,
                            selectedForegroundColor: Colors.black,
                          ),
                          segments: const [
                            ButtonSegment(value: false, label: Text('Light')),
                            ButtonSegment(value: true, label: Text('Dark')),
                          ],
                          selected: {_dark},
                          onSelectionChanged: (s) {
                            setState(() => _dark = s.first);
                            widget.onToggleDarkWatermark(s.first);
                          },
                        ),
                      ],
                    ),
                  ),
                  _divider(),
                  _switch(
                    icon: Icons.label_outline_rounded,
                    title: 'Film name on frame',
                    value: _name,
                    onChanged: (v) {
                      setState(() => _name = v);
                      widget.onToggleFilmName(v);
                    },
                  ),
                  _divider(),
                  _switch(
                    icon: Icons.schedule_rounded,
                    title: 'Date & time on frame',
                    value: _date,
                    onChanged: (v) {
                      setState(() => _date = v);
                      widget.onToggleDate(v);
                    },
                  ),
                ],
              ]),

              const SizedBox(height: 16),
              _label('VIEWFINDER'),
              _card([
                _switch(
                  icon: Icons.grid_3x3_rounded,
                  title: 'Rule-of-thirds grid',
                  value: _grid,
                  onChanged: (v) {
                    setState(() => _grid = v);
                    widget.onToggleGrid(v);
                  },
                ),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Column(children: children),
      );

  Widget _divider() => const Divider(height: 1, thickness: 1, color: Color(0x14FFFFFF));

  Widget _switch({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      secondary: Icon(icon, size: 20, color: Colors.white54),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
      value: value,
      activeColor: Colors.white,
      activeTrackColor: AppColors.red,
      inactiveTrackColor: Colors.white12,
      onChanged: onChanged,
    );
  }
}