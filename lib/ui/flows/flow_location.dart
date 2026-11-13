import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../i18n/i18n.dart';
import '../location.dart' show mapsUrl;
import '../theme.dart';

/// Trường Vị trí (chấm công): bản đồ nhỏ có ghim + vòng độ chính xác, toạ độ, độ chính xác, giờ lấy; trạng thái
/// đang lấy / đã lấy / lỗi. Chỉ để xem — app tự lấy, người dùng không sửa được. Bấm bản đồ mở Google Maps.
class FlowLocationView extends StatelessWidget {
  final String label;
  /// `{lat, lon, accuracy, at}` hoặc null (chưa có).
  final Object? value;
  final bool busy;
  final String? error;
  /// Lấy lại (biểu mẫu); null = trang chi tiết, không có nút.
  final VoidCallback? onRetry;
  final double mapHeight;
  const FlowLocationView({super.key, required this.label, required this.value, this.busy = false, this.error, this.onRetry, this.mapHeight = 140});

  static (double, double)? point(Object? v) =>
      v is Map && v['lat'] is num && v['lon'] is num ? ((v['lat'] as num).toDouble(), (v['lon'] as num).toDouble()) : null;

  static String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}:${two(d.second)} ${two(d.day)}/${two(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = point(value);
    final v = value is Map ? value as Map : const {};
    final acc = (v['accuracy'] as num?)?.toDouble();
    final at = (v['at'] as num?)?.toInt();
    final (Color tone, IconData icon, String state) = busy
        ? (pal.accentText, Icons.gps_not_fixed_rounded, tr('Đang lấy vị trí…'))
        : p != null
            ? (Colors.green, Icons.gps_fixed_rounded, tr('Đã lấy vị trí'))
            : (error != null ? Colors.redAccent : pal.sub, Icons.gps_off_rounded, error ?? tr('Chưa có vị trí'));
    return Container(
      decoration: BoxDecoration(border: Border.all(color: p != null ? tone.withValues(alpha: .5) : pal.divider), borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => launchUrl(Uri.parse(mapsUrl(p.$1, p.$2)), mode: LaunchMode.externalApplication),
            child: SizedBox(
              height: mapHeight,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(initialCenter: LatLng(p.$1, p.$2), initialZoom: 16.5, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'vn.flygo.chat',
                      tileProvider: NetworkTileProvider(headers: {'User-Agent': kUserAgent}),
                    ),
                    if (acc != null && acc > 0)
                      CircleLayer(circles: [
                        CircleMarker(point: LatLng(p.$1, p.$2), radius: acc, useRadiusInMeter: true, color: pal.accent.withValues(alpha: .15), borderColor: pal.accent, borderStrokeWidth: 1),
                      ]),
                    MarkerLayer(markers: [Marker(point: LatLng(p.$1, p.$2), width: 40, height: 40, child: Icon(Icons.location_on, color: pal.accent, size: 36))]),
                  ],
                ),
              ),
            ),
          )
        else
          Container(
            height: 72,
            color: pal.surface2,
            alignment: Alignment.center,
            child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.map_outlined, size: 30, color: pal.sub),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                Text(state, style: TextStyle(fontSize: 12.5, color: tone)),
                if (p != null) ...[
                  const SizedBox(height: 2),
                  SelectableText('${p.$1.toStringAsFixed(6)}, ${p.$2.toStringAsFixed(6)}', style: TextStyle(fontSize: 12.5, color: pal.sub)),
                  Text(
                    [
                      if (acc != null) tr('độ chính xác ±{0} m', ['${acc.round()}']),
                      if (at != null) tr('lúc {0}', [_time(at)]),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12.5, color: pal.sub),
                  ),
                ],
              ]),
            ),
            if (onRetry != null && !busy) TextButton(onPressed: onRetry, child: Text(p == null ? tr('Thử lại') : tr('Lấy lại'))),
          ]),
        ),
      ]),
    );
  }
}
