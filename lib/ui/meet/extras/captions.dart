import 'dart:async';

import 'package:flutter/material.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';
import 'fx_api.dart';

// Phụ đề trực tiếp: câu Thư ký Họp phiên âm xong được relay phát cho cả phòng (fx_caption, lang 'src'); ai chọn ngôn ngữ
// khác nhận thêm bản dịch riêng. Chỉ có khi cuộc họp đang được phiên âm (chủ trì bật). Bật / tắt và ngôn ngữ: mỗi máy tự chọn.

/// Máy này đang hiện phụ đề không.
final meetCaptionsOn = ValueNotifier<bool>(false);

/// Ngôn ngữ phụ đề của máy này: 'src' (gốc) | 'vi' | 'en' | 'zh'.
final meetCaptionsLang = ValueNotifier<String>('src');

const _langs = {'src': 'Gốc (theo người nói)', 'vi': 'Tiếng Việt', 'en': 'English', 'zh': '中文'};

class _Line {
  final String key, name;
  String text, orig;
  bool translated;
  DateTime at;
  _Line(this.key, this.name, this.text, this.orig, this.translated) : at = DateTime.now();
}

/// Lớp phụ đề đặt trong Stack của màn hình họp (phía trên thanh điều khiển).
class MeetCaptionsOverlay extends StatefulWidget {
  final CallService call;
  final double bottom;
  const MeetCaptionsOverlay({super.key, required this.call, this.bottom = 96});
  @override
  State<MeetCaptionsOverlay> createState() => _MeetCaptionsOverlayState();
}

class _MeetCaptionsOverlayState extends State<MeetCaptionsOverlay> {
  final _lines = <_Line>[];
  StreamSubscription? _sub;
  Timer? _sweep;

  @override
  void initState() {
    super.initState();
    _sub = widget.call.fxEvents.stream.listen(_on);
    _sweep = Timer.periodic(const Duration(seconds: 1), (_) {
      final n = _lines.length;
      _lines.removeWhere((l) => DateTime.now().difference(l.at) > const Duration(seconds: 8));
      if (n != _lines.length && mounted) setState(() {});
    });
    meetCaptionsOn.addListener(_changed);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sweep?.cancel();
    meetCaptionsOn.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _on(Map<String, dynamic> m) {
    if (m['t'] != 'fx_caption' || !meetCaptionsOn.value) return;
    final lang = '${m['lang'] ?? 'src'}';
    final key = '${m['speaker']}|${m['at']}';
    final want = meetCaptionsLang.value;
    final text = '${m['text'] ?? ''}';
    final i = _lines.indexWhere((l) => l.key == key);
    if (lang == 'src') {
      if (i >= 0) return; // bản dịch đã đến trước
      _lines.add(_Line(key, '${m['name'] ?? ''}', text, text, false));
    } else {
      if (lang != want) return;
      if (i >= 0) {
        _lines[i]
          ..text = text
          ..translated = true
          ..at = DateTime.now();
      } else {
        _lines.add(_Line(key, '${m['name'] ?? ''}', text, '${m['orig'] ?? ''}', true));
      }
    }
    while (_lines.length > 2) {
      _lines.removeAt(0);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Luôn trả Positioned: một con không định vị trong Stack làm Stack co về cỡ của nó (vỡ bố cục màn hình họp).
    if (!meetCaptionsOn.value || _lines.isEmpty) return const Positioned(left: 0, bottom: 0, child: SizedBox.shrink());
    final want = meetCaptionsLang.value;
    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.bottom,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 640),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in _lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${l.name}  ', style: const TextStyle(color: Color(0xFF8AB4F8), fontWeight: FontWeight.w600)),
                      TextSpan(
                        text: l.text,
                        // Đang chờ bản dịch: hiện bản gốc mờ.
                        style: TextStyle(color: want != 'src' && !l.translated ? Colors.white60 : Colors.white),
                      ),
                    ]),
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bảng phụ đề: bật / tắt, chọn ngôn ngữ.
Future<void> showCaptions(BuildContext context, CallService call) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CaptionsSheet(call: call),
    );

class _CaptionsSheet extends StatefulWidget {
  final CallService call;
  const _CaptionsSheet({required this.call});
  @override
  State<_CaptionsSheet> createState() => _CaptionsSheetState();
}

class _CaptionsSheetState extends State<_CaptionsSheet> {
  bool _busy = false;

  Future<void> _setLang(String lang) async {
    setState(() => _busy = true);
    try {
      await fxRequest(widget.call, 'POST', '/captions', {'lang': lang});
      meetCaptionsLang.value = lang;
      meetCaptionsOn.value = true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.call.transcribing;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Phụ đề'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          if (!on)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('Phụ đề cần Thư ký Họp. Chỉ chủ trì bật phiên âm được, và mọi người sẽ được báo.'),
                  style: const TextStyle(color: Colors.white70)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hiện phụ đề'), style: const TextStyle(color: Colors.white)),
            value: meetCaptionsOn.value,
            onChanged: (v) => setState(() => meetCaptionsOn.value = v),
          ),
          Text(tr('Ngôn ngữ của bạn'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
          RadioGroup<String>(
            groupValue: meetCaptionsLang.value,
            onChanged: (v) {
              if (v != null && !_busy) _setLang(v);
            },
            child: Column(children: [
              for (final e in _langs.entries)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: e.key,
                  title: Text(tr(e.value), style: const TextStyle(color: Colors.white)),
                ),
            ]),
          ),
          Text(tr('Bản dịch do AI công ty làm, chậm hơn bản gốc 1–2 giây.'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
      ),
    );
  }
}
