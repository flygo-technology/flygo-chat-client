import '../i18n/i18n.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Chặn từ khoá nhạy cảm giữa agent (Sếp 2026-11-19), mục Cài đặt trợ lý của trang Trợ lý. Cài đặt lưu ở máy chủ A2A
/// (relay/dlp.mjs) theo từng người: máy chủ kiểm mọi tin đi vào trợ lý của mình (giữa các trợ lý của mình, agent của
/// người khác, agent ngoài qua "Kết nối agent từ xa"). Tin bị chặn thì không chuyển, agent không được báo lý do; chủ
/// nhận tin báo riêng kèm nội dung.
class DlpApi {
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String method, String path, Map<String, dynamic>? body)? debugCall;

  static Future<Map<String, dynamic>> _call(AppState app, String method, String path, [Map<String, dynamic>? body]) async {
    if (debugCall != null) return debugCall!(method, path, body);
    final uri = Uri.parse('$kPushUrl/a2a/dlp/$path');
    final headers = {
      'Authorization': 'Bearer ${app.api.token}',
      'X-MM-Server': kServerUrl,
      'Content-Type': 'application/json',
      'User-Agent': kUserAgent,
    };
    final r = await (method == 'GET'
            ? http.get(uri, headers: headers)
            : method == 'PUT'
                ? http.put(uri, headers: headers, body: jsonEncode(body ?? {}))
                : http.post(uri, headers: headers, body: jsonEncode(body ?? {})))
        .timeout(const Duration(seconds: 20));
    final m = r.body.isEmpty ? <String, dynamic>{} : (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
    if (r.statusCode != 200) throw Exception(m['error'] ?? 'HTTP ${r.statusCode}');
    return m;
  }

  static Future<Map<String, dynamic>> load(AppState app) => _call(app, 'GET', 'settings');
  static Future<Map<String, dynamic>> save(AppState app, Map<String, dynamic> s) => _call(app, 'PUT', 'settings', s);
  static Future<Map<String, dynamic>> test(AppState app, String text, Map<String, dynamic> s) => _call(app, 'POST', 'test', {'text': text, 'settings': s});
}

class AgentDlpPage extends StatefulWidget {
  const AgentDlpPage({super.key});
  @override
  State<AgentDlpPage> createState() => _AgentDlpPageState();
}

class _AgentDlpPageState extends State<AgentDlpPage> {
  Map<String, dynamic>? _s; // {enabled, notify, builtins, keywords}
  List<Map<String, dynamic>> _catalog = const [];
  String? _error;
  bool _saving = false;
  bool _regex = false;
  final _kw = TextEditingController();
  final _probe = TextEditingController();
  Map<String, dynamic>? _probeResult;
  String _probeText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kw.dispose();
    _probe.dispose();
    super.dispose();
  }

  void _take(Map<String, dynamic> m) {
    _catalog = [for (final c in (m['catalog'] as List? ?? const [])) (c as Map).cast<String, dynamic>()];
    _s = {
      'enabled': m['enabled'] != false,
      'notify': m['notify'] != false,
      'builtins': Map<String, dynamic>.from(m['builtins'] as Map? ?? const {}),
      'keywords': [for (final k in (m['keywords'] as List? ?? const [])) Map<String, dynamic>.from(k as Map)],
    };
  }

  Future<void> _load() async {
    try {
      final m = await DlpApi.load(context.read<AppState>());
      if (mounted) setState(() { _take(m); _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  /// Lưu ngay mỗi thay đổi; lỗi thì báo và tải lại bản trên máy chủ.
  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() => _saving = true);
    try {
      final m = await DlpApi.save(app, _s!);
      if (mounted) setState(() => _take(m));
      if (_probeText.isNotEmpty) _runProbe();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Chưa lưu được: {0}', ['$e'.replaceFirst('Exception: ', '')]))));
        _load();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addKeyword() {
    final t = _kw.text.trim();
    if (t.isEmpty) return;
    setState(() {
      (_s!['keywords'] as List).add({'text': t, 'regex': _regex});
      _kw.clear();
    });
    _save();
  }

  Future<void> _runProbe() async {
    final text = _probe.text;
    if (text.trim().isEmpty) return setState(() { _probeResult = null; _probeText = ''; });
    try {
      final r = await DlpApi.test(context.read<AppState>(), text, _s!);
      if (mounted) setState(() { _probeResult = r; _probeText = text; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final s = _s;
    return EscToPop(
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bg,
          surfaceTintColor: Colors.transparent,
          title: Text(tr('Chặn từ khoá nhạy cảm giữa agent'), style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
          actions: [
            if (_saving) Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent))),
          ],
        ),
        body: _error != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: TextStyle(color: pal.sub), textAlign: TextAlign.center)))
            : s == null
                ? Center(child: CircularProgressIndicator(color: pal.accent))
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: _content(pal, s)),
                    ),
                  ),
      ),
    );
  }

  Widget _section(Pal pal, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 13, color: pal.sub, letterSpacing: .3)),
      );

  // Material (không phải Container tô nền) để ListTile / công tắc có hiệu ứng chạm.
  Widget _card(Pal pal, List<Widget> rows) => Material(
        color: pal.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, r) in rows.indexed) ...[if (i > 0) Divider(height: 1, indent: 16, color: pal.divider), r],
        ]),
      );

  List<Widget> _content(Pal pal, Map<String, dynamic> s) {
    final on = s['enabled'] == true;
    final keywords = s['keywords'] as List;
    final builtins = s['builtins'] as Map<String, dynamic>;
    final sub = TextStyle(color: pal.sub, fontSize: 12.5);
    return [
      _card(pal, [
        SwitchListTile(
          value: on,
          activeTrackColor: pal.accent,
          title: Text(tr('Bật chặn từ khoá'), style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
          subtitle: Text(tr('Kiểm mọi tin giữa các trợ lý của bạn và tin agent khác gửi vào trợ lý của bạn. Tin có từ khoá cấm bị chặn: không chuyển đi, agent không được báo lý do.'), style: sub),
          onChanged: (v) { setState(() => s['enabled'] = v); _save(); },
        ),
        SwitchListTile(
          value: s['notify'] == true,
          activeTrackColor: pal.accent,
          title: Text(tr('Báo cho tôi khi chặn'), style: TextStyle(color: pal.text)),
          subtitle: Text(tr('Tin báo riêng gửi bạn kèm nội dung tin bị chặn. Trợ lý không đọc được tin báo này.'), style: sub),
          onChanged: on ? (v) { setState(() => s['notify'] = v); _save(); } : null,
        ),
      ]),
      _section(pal, tr('Phát hiện có sẵn')),
      _card(pal, [
        for (final c in _catalog)
          CheckboxListTile(
            value: builtins[c['id']] != false,
            enabled: on,
            activeColor: pal.accent,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(tr('${c['name']}'), style: TextStyle(color: on ? pal.text : pal.sub)),
            subtitle: Text('${c['description']}', style: sub),
            onChanged: (v) { setState(() => builtins['${c['id']}'] = v == true); _save(); },
          ),
      ]),
      _section(pal, tr('Từ khoá của tôi')),
      _card(pal, [
        for (final (i, k) in keywords.indexed)
          ListTile(
            dense: true,
            title: Text('${k['text']}',
                style: TextStyle(color: on ? pal.text : pal.sub, fontSize: 15, fontFamily: k['regex'] == true ? 'JetBrains Mono' : null)),
            subtitle: k['regex'] == true ? Text(tr('Biểu thức'), style: sub) : null,
            trailing: IconButton(
              tooltip: tr('Xoá'),
              icon: Icon(Icons.close_rounded, color: pal.sub, size: 20),
              onPressed: () { setState(() => keywords.removeAt(i)); _save(); },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _kw,
                enabled: on,
                style: TextStyle(color: pal.text, fontFamily: _regex ? 'JetBrains Mono' : null),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: _regex ? r'HD-\d{6}' : tr('Thêm từ khoá hoặc cụm từ, vd. dự án Kiara'),
                  hintStyle: TextStyle(color: pal.sub),
                ),
                onSubmitted: (_) => _addKeyword(),
              ),
            ),
            FilterChip(
              label: Text(tr('Biểu thức')),
              selected: _regex,
              onSelected: on ? (v) => setState(() => _regex = v) : null,
              showCheckmark: false,
              selectedColor: pal.chipSelBg,
              labelStyle: TextStyle(color: _regex ? pal.chipSelFg : pal.sub, fontSize: 13),
              side: BorderSide.none,
              backgroundColor: pal.surface2,
            ),
            IconButton(tooltip: tr('Thêm'), icon: Icon(Icons.add_circle_rounded, color: on ? pal.accent : pal.sub), onPressed: on ? _addKeyword : null),
          ]),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(tr('Không phân biệt hoa thường và dấu: "mật khẩu" khớp cả "MAT KHAU". Từ khoá khớp nguyên từ.'), style: sub),
      ),
      _section(pal, tr('Thử một câu')),
      _card(pal, [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _probe,
                minLines: 1,
                maxLines: 5,
                style: TextStyle(color: pal.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: tr('Gõ một câu agent có thể gửi để xem có bị chặn không'),
                  hintStyle: TextStyle(color: pal.sub),
                ),
                onSubmitted: (_) => _runProbe(),
              ),
            ),
            TextButton(onPressed: _runProbe, child: Text(tr('Thử'))),
          ]),
        ),
        if (_probeResult case final r?) _probeView(pal, r),
      ]),
    ];
  }

  Widget _probeView(Pal pal, Map<String, dynamic> r) {
    final hits = [for (final h in (r['hits'] as List? ?? const [])) (h as Map).cast<String, dynamic>()];
    final text = _probeText;
    const block = Color(0xFFE5484D), ok = Color(0xFF30A46C);
    final spans = <TextSpan>[];
    var at = 0;
    for (final h in hits) {
      final s = (h['start'] as num).toInt(), e = (h['end'] as num).toInt();
      if (s < at || e > text.length) continue;
      spans.add(TextSpan(text: text.substring(at, s)));
      spans.add(TextSpan(text: text.substring(s, e), style: TextStyle(backgroundColor: block.withValues(alpha: .25), fontWeight: FontWeight.w700)));
      at = e;
    }
    spans.add(TextSpan(text: text.substring(at)));
    final names = {for (final h in hits) tr('${h['name']}')}.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(12)),
          child: Text.rich(TextSpan(style: TextStyle(color: pal.text, fontSize: 14.5, height: 1.4), children: spans)),
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(hits.isEmpty ? Icons.check_circle_outline : Icons.block, size: 18, color: hits.isEmpty ? ok : block),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hits.isEmpty ? tr('Không có từ khoá cấm: tin này được gửi.') : tr('Tin này sẽ bị chặn ({0}).', [names.join(', ')]),
              style: TextStyle(color: pal.text, fontSize: 13.5),
            ),
          ),
        ]),
      ]),
    );
  }
}
