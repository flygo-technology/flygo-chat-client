// Kiểm thử điều khiển máy tính từ xa: giao thức thao tác, đổi toạ độ, kiểm tra giới hạn, xin phép / hết giờ.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/remote/rc_call.dart';
import 'package:flygo_chat/remote/rc_call_buttons.dart';
import 'package:flygo_chat/remote/rc_consent.dart';
import 'package:flygo_chat/remote/rc_native.dart';
import 'package:flygo_chat/remote/rc_protocol.dart';
import 'package:flygo_chat/remote/rc_service.dart';
import 'package:flygo_chat/remote/rc_ui.dart';
import 'package:flygo_chat/ui/theme.dart';

void main() {
  group('mã hoá / giải mã', () {
    test('đi một vòng giữ nguyên', () {
      final all = <RcInput>[
        const RcMove(0, 65535),
        const RcButton(1, true, 100, 200),
        const RcButton(0, false, 65535, 0),
        const RcWheel(-120, 240),
        const RcKey(0x04, true),
        const RcKey(0xE3, false),
        const RcText('Xin chào Việt Nam \u{1F600}\n'),
        const RcQuality('low'),
        const RcRelease(),
        const RcSelectScreen('69733382'),
      ];
      for (final i in all) {
        final back = RcInput.decode(i.encode());
        expect(back, isNotNull, reason: i.encode());
        expect(back!.toWire(), i.toWire());
      }
      expect(const RcMove(5, 6).encode(), '["m",5,6]');
    });

    test('bỏ tin sai dạng / vượt giới hạn', () {
      for (final raw in [
        '',
        'xyz',
        '{}',
        '[]',
        '[1,2]',
        '["m",1]',
        '["m",1,2,3]',
        '["m",-1,2]',
        '["m",1,65536]',
        '["m",1.5,2]',
        '["m","1",2]',
        '["b",3,1,0,0]',
        '["b",0,2,0,0]',
        '["w",0,2401]',
        '["k",4,1,0]',
        '["k",999,1]', // không phải phím trong bảng
        '["k",4,3]',
        '["t",""]',
        '["t",5]',
        '["t","\\u0000\\u0007"]', // toàn ký tự điều khiển
        '["q","ultra"]',
        '["r",1]',
        '["x"]',
        '["d"]',
        '["d",""]',
        '["d",5]',
        '["d","a","b"]',
        '["d","${'a' * 200}"]',
        '["t","${'a' * 5000}"]',
      ]) {
        expect(RcInput.decode(raw), isNull, reason: raw);
      }
    });

    test('chữ: bỏ ký tự điều khiển, cắt độ dài, chia khúc', () {
      final t = RcInput.decode('["t","a\\u0000b\\u001bc\\r\\nd\\te"]') as RcText;
      expect(t.text, 'abc\nd\te');
      expect(sanitizeRcText('x' * 1500).length, kRcMaxText);
      final parts = chunkRcText('y' * 2500);
      expect(parts.map((p) => p.length), [1000, 1000, 500]);
      // Emoji không bị cắt đôi.
      final emoji = chunkRcText('\u{1F600}' * 1001);
      expect(emoji.length, 2);
      expect(emoji.last, '\u{1F600}');
    });
  });

  group('giới hạn tần suất', () {
    test('thùng token', () {
      final l = RcRateLimiter(ratePerSecond: 10, burst: 5);
      var ok = 0;
      for (var i = 0; i < 20; i++) {
        if (l.allow(1000)) ok++;
      }
      expect(ok, 5, reason: 'dồn tối đa 5');
      expect(l.allow(1050), isFalse, reason: '50 ms mới được 0,5 token');
      expect(l.allow(1100), isTrue, reason: '100 ms = 1 token');
      var later = 0;
      for (var i = 0; i < 20; i++) {
        if (l.allow(10000)) later++;
      }
      expect(later, 5, reason: 'nghỉ lâu cũng chỉ dồn tới burst');
    });
  });

  group('toạ độ', () {
    test('khung hình vừa ô (viền đen)', () {
      // Video 16:9 trong ô vuông: viền trên dưới.
      final r = rcFitRect(const Size(1000, 1000), const Size(1920, 1080));
      expect(r.left, closeTo(0, 1e-9));
      expect(r.width, closeTo(1000, 1e-9));
      expect(r.height, closeTo(562.5, .01));
      expect(r.top, closeTo(218.75, .01));
    });

    test('điểm trong ô → toạ độ chuẩn hoá', () {
      const box = Size(1000, 1000), video = Size(1920, 1080);
      expect(rcToWire(const Offset(0, 218.75), box, video), (0, 0));
      expect(rcToWire(const Offset(1000, 781.25), box, video), (65535, 65535));
      expect(rcToWire(const Offset(500, 500), box, video), (32768, 32768));
      expect(rcToWire(const Offset(500, 100), box, video), isNull, reason: 'viền đen');
      expect(rcToWire(const Offset(500, 100), box, video, clamp: true), (32768, 0));
      expect(rcToWire(const Offset(5, 5), box, Size.zero), (328, 328), reason: 'chưa biết cỡ video: cả ô');
    });

    test('toạ độ chuẩn hoá → màn hình (Windows: màn hình phụ bên trái, điểm ảnh âm)', () {
      const s = RcScreen(id: '1', x: -1920, y: 0, width: 1920, height: 1080);
      expect(rcWireToScreen(0, 0, s), const Offset(-1920, 0));
      expect(rcWireToScreen(65535, 65535, s), const Offset(-1, 1079));
      final virt = const Rect.fromLTWH(-1920, 0, 1920 + 2560, 1440);
      expect(rcWinAbsolute(const Offset(-1920, 0), virt), (0, 0));
      expect(rcWinAbsolute(Offset(virt.right - 1, virt.bottom - 1), virt), (65535, 65535));
      final (x, y) = rcWinAbsolute(const Offset(0, 720), virt);
      expect(x, closeTo(1920 * 65535 / (4480 - 1), 1));
      expect(y, closeTo(720 * 65535 / 1439, 1));
    });

    test('chọn màn hình theo nguồn chụp', () {
      const a = RcScreen(id: '69733382', x: 0, y: 0, width: 1512, height: 982, primary: true);
      const b = RcScreen(id: '2', x: 1512, y: 0, width: 1920, height: 1080);
      expect(rcMatchScreen([a, b], '2', 0), b, reason: 'khớp id');
      expect(rcMatchScreen([a, b], 'zz', 1), b, reason: 'theo thứ tự');
      expect(rcMatchScreen([b, a], 'zz', 7), a, reason: 'màn hình chính');
      expect(rcMatchScreen([], '1', 0), isNull);
    });

    test('phóng to trên điện thoại', () {
      expect(rcUnzoom(const Offset(300, 300), 2, const Offset(-100, -100)), const Offset(200, 200));
      const box = Size(400, 800);
      expect(rcClampPan(const Offset(50, 50), 2, box), Offset.zero);
      expect(rcClampPan(const Offset(-900, -900), 2, box), const Offset(-400, -800));
      expect(rcClampPan(const Offset(-10, -10), 1, box), Offset.zero);
    });

    test('cuộn', () {
      expect(rcWinWheel(50), -120);
      expect(rcWinWheel(-100), 240);
      expect(rcMacWheel(30), -30);
    });
  });

  group('bàn phím', () {
    test('bảng phím', () {
      expect(rcHidFromUsage(0x00070004), 0x04); // A
      expect(rcHidFromUsage(0x000c00e9), isNull); // trang khác
      expect(rcWinScan(0x04), 0x1E);
      expect(rcMacKey(0x04), 0x00);
      expect(rcWinScan(0x4F), 0xE04D, reason: '→ là phím mở rộng');
      expect(rcMacKey(0x46), isNull, reason: 'PrintScreen không có trên Mac');
      expect(rcIsModifier(0xE0), isTrue);
      expect(rcIsModifier(0x04), isFalse);
    });

    test('đổi Cmd ↔ Ctrl', () {
      expect(rcSwapMeta(0xE3), 0xE0);
      expect(rcSwapMeta(0xE0), 0xE3);
      expect(rcSwapMeta(0xE7), 0xE4);
      expect(rcSwapMeta(0x04), 0x04);
    });

    test('Ctrl+Alt+Del: gửi thứ làm được', () {
      final win = rcSecureAttention(macTarget: false).map((k) => k.toWire()).toList();
      expect(win, [
        ['k', 0xE0, 1],
        ['k', 0xE1, 1],
        ['k', 0x29, 1],
        ['k', 0x29, 0],
        ['k', 0xE1, 0],
        ['k', 0xE0, 0],
      ]);
      expect(rcSecureAttention(macTarget: true).first.hid, 0xE3);
    });

    test('bàn phím ảo: so chữ', () {
      expect(rcTextDiff(kRcSentinel, '${kRcSentinel}a'), (0, 'a'));
      expect(rcTextDiff('${kRcSentinel}ab', '${kRcSentinel}a'), (1, ''));
      expect(rcTextDiff(kRcSentinel, '​'), (1, ''), reason: 'xoá khi ô "trống"');
      expect(rcTextDiff('${kRcSentinel}viet', '${kRcSentinel}việt'), (2, 'ệt'));
      expect(rcTextDiff('${kRcSentinel}a\u{1F600}', '${kRcSentinel}a\u{1F603}'), (1, '\u{1F603}'), reason: 'không cắt đôi emoji');
    });
  });

  group('đổi sang sự kiện nền tảng', () {
    const screen = RcScreen(id: '0', x: 0, y: 0, width: 1001, height: 501);
    test('Windows: toạ độ 0..65535 trên màn hình ảo, phím theo mã quét', () {
      final inj = RcInjector(mac: false, screen: screen, virtualDesk: const Rect.fromLTWH(0, 0, 1001, 501));
      expect(inj.map(const RcMove(65535, 0)).single, {'op': 'move', 'x': 65535, 'y': 0, 'buttons': 0});
      expect(inj.map(const RcKey(0x04, true)).single, {'op': 'key', 'code': 0x1E, 'down': true, 'hid': 0x04});
      expect(inj.map(const RcKey(0x05, false)), isEmpty, reason: 'nhả phím chưa bấm');
      expect(inj.map(const RcButton(0, true, 0, 0)).single['clicks'], 1);
      expect(inj.map(const RcMove(10, 10)).single['buttons'], 1, reason: 'đang giữ nút trái');
      // Kết thúc phiên: nhả hết.
      final rel = inj.map(const RcRelease());
      expect(rel, [
        {'op': 'key', 'code': 0x1E, 'down': false, 'hid': 0x04},
        {'op': 'button', 'b': 0, 'down': false, 'clicks': 1},
      ]);
      expect(inj.releaseAll(), isEmpty);
      expect(inj.map(const RcQuality('high')), isEmpty);
      expect(inj.map(const RcSelectScreen('1')), isEmpty, reason: 'chọn màn hình không bơm thao tác');
    });

    test('macOS: điểm toàn cục, đếm nháy đúp', () {
      final inj = RcInjector(mac: true, screen: const RcScreen(id: '1', x: 100, y: 0, width: 1001, height: 501), virtualDesk: Rect.zero);
      expect(inj.map(const RcMove(65535, 65535)).single, {'op': 'move', 'x': 1100.0, 'y': 500.0, 'buttons': 0});
      expect(inj.map(const RcKey(0x04, true)).single['code'], 0x00);
      expect(inj.map(const RcKey(0x46, true)), isEmpty, reason: 'PrintScreen không có trên Mac');
      expect(inj.map(const RcWheel(0, 30)).single, {'op': 'wheel', 'dx': 0, 'dy': -30});
    });

    test('Linux X11: điểm ảnh trên cửa sổ gốc, mã phím X = evdev + 8, cuộn theo nấc', () {
      final inj = RcInjector(
          mac: false, linux: true, screen: const RcScreen(id: '355', x: 1920, y: 0, width: 1001, height: 501), virtualDesk: Rect.zero);
      expect(inj.map(const RcMove(65535, 65535)).single, {'op': 'move', 'x': 2920, 'y': 500, 'buttons': 0});
      expect(inj.map(const RcKey(0x04, true)).single, {'op': 'key', 'code': 38, 'down': true, 'hid': 0x04}, reason: 'A');
      expect(inj.map(const RcKey(0xE0, true)).single['code'], 37, reason: 'Ctrl trái');
      expect(inj.map(const RcKey(0x52, true)).single['code'], 111, reason: 'mũi tên lên');
      // Cuộn: dồn điểm ảnh, đủ 50 mới thành một nấc; phần dư giữ lại.
      expect(inj.map(const RcWheel(0, 30)), isEmpty);
      expect(inj.map(const RcWheel(0, 30)).single, {'op': 'wheel', 'dx': 0, 'dy': 1});
      expect(inj.map(const RcWheel(-120, -10)).single, {'op': 'wheel', 'dx': -2, 'dy': 0});
      expect(inj.releaseAll().map((e) => e['code']), [111, 37, 38]);
    });

    test('Linux: bảng phím đủ mọi phím của giao thức, không trùng mã', () {
      final codes = <int>{};
      for (final hid in rcKnownKeys) {
        final c = rcLinuxKey(hid);
        expect(c, isNotNull, reason: 'HID 0x${hid.toRadixString(16)}');
        expect(c! >= 8 && c <= 255, isTrue);
        expect(codes.add(c), isTrue, reason: 'trùng mã X $c');
      }
      expect(rcLinuxKey(0x29), 9, reason: 'Esc');
      expect(rcLinuxKey(0x28), 36, reason: 'Enter');
      expect(rcLinuxKey(0x45), 96, reason: 'F12');
      expect(rcLinuxKey(0xE3), 133, reason: 'Super trái');
      expect(rcLinuxKey(0x48), isNull, reason: 'không có trong giao thức');
    });

    test('Linux: nhận ra Wayland', () {
      expect(rcLinuxIsWayland({'DISPLAY': ':0', 'XDG_SESSION_TYPE': 'x11'}), isFalse);
      expect(rcLinuxIsWayland({'DISPLAY': ':0', 'XDG_SESSION_TYPE': 'wayland', 'WAYLAND_DISPLAY': 'wayland-0'}), isTrue);
      expect(rcLinuxIsWayland({'DISPLAY': ':0', 'WAYLAND_DISPLAY': 'wayland-0'}), isTrue, reason: 'XWayland');
      expect(rcLinuxIsWayland({}), isTrue, reason: 'không có màn hình X');
      expect(rcLinuxWheel(-49), (0, -49));
      expect(rcLinuxWheel(101), (2, 1));
    });

    test('đếm số lần bấm', () {
      final c = RcClickCounter();
      expect(c.down(0, 100, 100, 1000), 1);
      expect(c.down(0, 110, 100, 1300), 2);
      expect(c.down(0, 110, 100, 1600), 3);
      expect(c.down(0, 110, 100, 2500), 1, reason: 'quá lâu');
      expect(c.down(1, 110, 100, 2600), 1, reason: 'nút khác');
      expect(c.down(1, 5000, 100, 2700), 1, reason: 'xa quá');
    });
  });

  group('xin phép / hết giờ', () {
    test('cho phép một lần, sau đó không đổi được', () {
      final done = <RcConsentState>[];
      final c = RcConsent(sid: 's', fromUserId: 'u', fromName: 'An', channelId: 'c', onDone: (c) => done.add(c.state));
      expect(c.pending, isTrue);
      expect(c.accept(), isTrue);
      expect(c.decline(), isFalse);
      expect(c.cancel(), isFalse);
      expect(c.state, RcConsentState.accepted);
      expect(done, [RcConsentState.accepted]);
    });

    test('60 giây không trả lời thì tự từ chối', () {
      fakeAsyncRun((advance) {
        final done = <RcConsentState>[];
        final c = RcConsent(sid: 's', fromUserId: 'u', fromName: 'An', channelId: 'c', onDone: (c) => done.add(c.state));
        advance(const Duration(seconds: 59));
        expect(c.pending, isTrue);
        advance(const Duration(seconds: 2));
        expect(c.state, RcConsentState.timedOut);
        expect(c.accept(), isFalse, reason: 'bấm Cho phép sau khi hết giờ không có tác dụng');
        expect(done, [RcConsentState.timedOut]);
      });
    });

    test('từ chối / bên kia huỷ huỷ luôn hẹn giờ', () {
      fakeAsyncRun((advance) {
        final done = <RcConsentState>[];
        final a = RcConsent(sid: '1', fromUserId: 'u', fromName: 'An', channelId: 'c', onDone: (c) => done.add(c.state));
        final b = RcConsent(sid: '2', fromUserId: 'u', fromName: 'An', channelId: 'c', onDone: (c) => done.add(c.state));
        a.decline();
        b.cancel();
        advance(const Duration(minutes: 2));
        expect(done, [RcConsentState.declined, RcConsentState.cancelled]);
      });
    });

    test('số giây còn lại', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final c = RcConsent(sid: 's', fromUserId: 'u', fromName: 'An', channelId: 'c', onDone: (_) {}, now: t0, timer: (d, f) => Timer(d, f));
      expect(c.secondsLeft(t0), 60);
      expect(c.secondsLeft(t0.add(const Duration(milliseconds: 30500))), 30);
      expect(c.secondsLeft(t0.add(const Duration(seconds: 90))), 0);
      c.cancel();
    });

    test('kết quả lời xin từ tin của trạm', () {
      expect(rcOutcomeOf({'t': 'accepted'}), RcRequestOutcome.accepted);
      expect(rcOutcomeOf({'t': 'declined'}), RcRequestOutcome.declined);
      expect(rcOutcomeOf({'t': 'declined', 'reason': 'permission'}), RcRequestOutcome.permission);
      expect(rcOutcomeOf({'t': 'declined', 'reason': 'timeout'}), RcRequestOutcome.timeout);
      expect(rcOutcomeOf({'t': 'unsupported'}), RcRequestOutcome.unsupported);
      expect(rcOutcomeOf({'t': 'busy'}), RcRequestOutcome.busy);
      expect(rcOutcomeOf({'t': 'error', 'code': 'busy_self'}), RcRequestOutcome.busy);
      expect(rcOutcomeOf({'t': 'error', 'code': 'forbidden'}), RcRequestOutcome.error);
      expect(rcOutcomeOf({'t': 'sig'}), isNull);
      expect(rcOutcomeOf({'t': 'ringing'}), isNull);
    });

    test('số phút của phiên', () {
      final s = DateTime(2026, 1, 1, 10);
      expect(rcSessionMinutes(s, s.add(const Duration(seconds: 20))), 1);
      expect(rcSessionMinutes(s, s.add(const Duration(minutes: 14, seconds: 40))), 15);
      expect(rcSessionMinutes(s, s), 0);
    });
  });

  group('chọn màn hình (máy điều khiển chọn)', () {
    const a = RcDisplay(id: '69733382', name: 'Built-in Retina Display', width: 1512, height: 982, primary: true);
    const b = RcDisplay(id: '2', name: 'DELL U2720Q', width: 1920, height: 1080);

    test('danh sách màn hình đi một vòng', () {
      final m = RcHostMessage('2', const [a, b]);
      final back = RcHostMessage.decode(m.encode());
      expect(back, isNotNull);
      expect(back!.current, '2');
      expect(back.screens, [a, b]);
      expect(m.encode(), '["s","2",[["69733382","Built-in Retina Display",1512,982,1],["2","DELL U2720Q",1920,1080,0]]]');
    });

    test('bỏ danh sách sai dạng', () {
      for (final raw in [
        '',
        '[]',
        '["s"]',
        '["s","1",[]]', // rỗng
        '["s","9",[["1","",10,10,1]]]', // màn hình đang chia sẻ không có trong danh sách
        '["s","1",[["1","",10,10,1],["1","",10,10,0]]]', // trùng id
        '["s","1",[["1","",-1,10,1]]]',
        '["s","1",[["1","",10,10,2]]]',
        '["s","1",[["1",5,10,10,1]]]',
        '["s","1",[["1","",10.5,10,1]]]',
        '["s","1",[["1","",10,10]]]',
        '["s","",[["","",10,10,1]]]',
        '["x","1",[["1","",10,10,1]]]',
        '["s","1",[${List.generate(17, (i) => '["$i","",1,1,0]').join(',')}]]', // quá nhiều màn hình
      ]) {
        expect(RcHostMessage.decode(raw), isNull, reason: raw);
      }
      // Tên có ký tự điều khiển / quá dài: làm sạch, không bỏ cả tin.
      final m = RcHostMessage.decode(r'["s","1",[["1","A\u0007\nB' '${'x' * 100}' r'",10,10,1]]]');
      expect(m!.screens.single.name, startsWith('A B'));
      expect(m.screens.single.name.length, lessThanOrEqualTo(kRcMaxScreenName));
    });

    test('bắt đầu với màn hình chính, không hỏi', () {
      expect(rcDefaultDisplay(const [b, a]), a);
      expect(rcDefaultDisplay(const [b]), b, reason: 'không có màn hình chính thì lấy màn hình đầu');
      expect(rcDefaultDisplay(const []), isNull);
    });

    test('ghép nguồn chụp với màn hình gốc', () {
      const main = RcScreen(id: '69733382', name: 'Built-in', x: 0, y: 0, width: 1512, height: 982, primary: true);
      const ext = RcScreen(id: '2', name: 'DELL', x: 1512, y: 0, width: 1920, height: 1080);
      final list = rcDisplaysOf(['2', '69733382', '2', ''], [main, ext]);
      expect(list.map((e) => e.display.id), ['2', '69733382'], reason: 'bỏ id trùng / rỗng, giữ thứ tự');
      expect(list.first.screen, ext);
      expect(list.first.display, const RcDisplay(id: '2', name: 'DELL', width: 1920, height: 1080));
      expect(list.last.display.primary, isTrue);
      // Windows: id nguồn chụp không khớp id màn hình, ghép theo thứ tự; chỉ một màn hình chính.
      const w0 = RcScreen(id: 'a', x: 0, y: 0, width: 1920, height: 1080, primary: true);
      const w1 = RcScreen(id: 'b', x: -1280, y: 0, width: 1280, height: 1024);
      final win = rcDisplaysOf(['0', '1', '2'], [w0, w1]);
      expect(win.map((e) => e.screen), [w0, w1, w0]);
      expect(win.where((e) => e.display.primary).length, 1);
      expect(rcDisplaysOf(['0'], const []), isEmpty);
    });

    test('đổi màn hình: toạ độ theo màn hình mới', () {
      final inj = RcInjector(
          mac: false, linux: true, screen: const RcScreen(id: '1', x: 0, y: 0, width: 1001, height: 501), virtualDesk: Rect.zero);
      expect(inj.map(const RcMove(65535, 0)).single['x'], 1000);
      inj.screen = const RcScreen(id: '2', x: 1920, y: 0, width: 1001, height: 501);
      expect(inj.map(const RcMove(65535, 0)).single['x'], 2920);
    });
  });

  group('lời mời điều khiển (máy được mời điều khiển máy người mời)', () {
    test('đồng ý một lần, không từ chối / huỷ được sau đó', () {
      final done = <RcConsentState>[];
      final c = RcConsent(sid: 's1', fromUserId: 'u1', fromName: 'An', channelId: 'c1', invite: true, onDone: (x) => done.add(x.state));
      expect(c.invite, isTrue);
      expect(c.pending, isTrue);
      expect(c.accept(), isTrue);
      expect(c.decline(), isFalse);
      expect(c.cancel(), isFalse);
      expect(done, [RcConsentState.accepted]);
      expect(RcConsent(sid: 's2', fromUserId: 'u1', fromName: 'An', channelId: 'c1', onDone: (_) {}).invite, isFalse);
    });

    test('hết giờ thì tự từ chối; bên mời huỷ thì đóng', () {
      fakeAsyncRun((advance) {
        final done = <RcConsentState>[];
        final c = RcConsent(sid: 's1', fromUserId: 'u1', fromName: 'An', channelId: 'c1', invite: true, onDone: (x) => done.add(x.state));
        advance(const Duration(seconds: 59));
        expect(c.pending, isTrue);
        advance(const Duration(seconds: 2));
        expect(done, [RcConsentState.timedOut]);
        expect(c.accept(), isFalse);
        final d = RcConsent(sid: 's2', fromUserId: 'u1', fromName: 'An', channelId: 'c1', invite: true, onDone: (x) => done.add(x.state));
        expect(d.cancel(), isTrue);
        expect(done.last, RcConsentState.cancelled);
      });
    });

    test('máy tính (cửa sổ chính) giao cho cửa sổ điều khiển; điện thoại / cửa sổ điều khiển điều khiển ngay', () {
      expect(rcInviteAcceptPlan(desktop: true, controllerWindow: false), RcInviteAccept.handoff);
      expect(rcInviteAcceptPlan(desktop: true, controllerWindow: true), RcInviteAccept.inline);
      expect(rcInviteAcceptPlan(desktop: false, controllerWindow: false), RcInviteAccept.inline);
    });

    test('kết quả từ trạm: claimed / accepted / declined', () {
      expect(rcOutcomeOf({'t': 'accepted'}), RcRequestOutcome.accepted);
      expect(rcOutcomeOf({'t': 'declined', 'reason': 'busy'}), RcRequestOutcome.busy);
      expect(rcOutcomeOf({'t': 'unsupported'}), RcRequestOutcome.unsupported);
      expect(rcOutcomeOf({'t': 'error', 'code': 'no_session'}), RcRequestOutcome.error);
      expect(rcOutcomeOf({'t': 'claimed'}), isNull); // không kết thúc lời xin
    });

    test('tham số cửa sổ điều khiển đi một vòng', () {
      final ch = 'c' * 26, u = 'u' * 26, sid = 'a1' * 16, cid = 'f0' * 16;
      var j = rcWindowArgsParse(rcWindowArgs(RcWindowJob(channelId: ch, userId: u, sid: sid, via: 'call', name: 'Bình'), server: 'https://x'))!;
      expect([j.channelId, j.userId, j.sid, j.via, j.name, j.device], [ch, u, sid, 'call', 'Bình', null]);
      j = rcWindowArgsParse(rcWindowArgs(RcWindowJob(channelId: ch, userId: u)))!;
      expect([j.sid, j.via], [null, null]);
      j = rcWindowArgsParse(rcWindowArgs(RcWindowJob(device: cid, name: 'Mac mini')))!;
      expect([j.device, j.name, j.channelId], [cid, 'Mac mini', '']);
      expect(rcWindowArgsParse(['--chat=$ch']), isNull);
      expect(rcWindowArgsParse(['--rc=$ch', '--rc-user=xyz']), isNull);
      expect(rcWindowArgsParse(['--rc=', '--rc-device=nothex']), isNull);
      expect(rcWindowArgsParse(['--rc=$ch', '--rc-user=$u', '--rc-sid=bad', '--rc-via=other'])!.sid, isNull);
    });
  });

  group('chọn người trong cuộc gọi', () {
    test('bỏ mình, bot, tài khoản khoá, trùng; xếp theo tên', () {
      final names = {'me': 'Tôi', 'u1': 'Bình', 'u2': 'an', 'bot': 'Trợ lý', 'gone': 'Cũ', 'u3': ''};
      final l = rcPickList(['u1', 'me', 'u2', '', 'bot', 'u1', 'gone', 'u3'],
          myId: 'me', nameOf: (id) => names[id], isBot: (id) => id == 'bot', isDeleted: (id) => id == 'gone', fallbackName: 'Người dùng');
      expect(l, const [RcPick('u2', 'an'), RcPick('u1', 'Bình'), RcPick('u3', 'Người dùng')]);
      expect(rcPickList(['me'], myId: 'me', nameOf: (_) => 'x'), isEmpty);
    });

    testWidgets('bảng chọn: hiện người, bấm trả về người đó; danh sách trống', (t) async {
      RcPick? picked;
      var people = const [RcPick('u1', 'Bình'), RcPick('u2', 'Cường')];
      final change = ValueNotifier(0);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => picked = await showRcPeoplePicker(ctx, title: 'Chọn', people: () => people, listenable: change),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('mở'));
      await t.pumpAndSettle();
      expect(find.text('Chọn'), findsOneWidget);
      expect(find.text('Bình'), findsOneWidget);
      expect(find.text('Cường'), findsOneWidget);
      // Người rời cuộc gọi: danh sách tự cập nhật.
      people = const [RcPick('u2', 'Cường')];
      change.value++;
      await t.pump();
      expect(find.text('Bình'), findsNothing);
      await t.tap(find.text('Cường'));
      await t.pumpAndSettle();
      expect(picked, const RcPick('u2', 'Cường'));
      people = const [];
      await t.tap(find.text('mở'));
      await t.pumpAndSettle();
      expect(find.text('Chưa có ai khác trong cuộc gọi'), findsOneWidget);
    });
  });

  group('Máy tính của chính mình', () {
    final now = DateTime(2026, 11, 4, 10, 30).millisecondsSinceEpoch;
    final raw = [
      {'cid': 'c' * 32, 'device_id': 'win', 'name': 'PC-KT', 'platform': 'windows', 'version': '1.0 (281)', 'online': true, 'busy': false, 'self': false},
      {'cid': '', 'device_id': 'old', 'name': 'Old-PC', 'platform': 'linux', 'online': false, 'last_seen': now - 86400000},
      {'cid': 'd' * 32, 'device_id': 'mac', 'name': 'Mac-mini', 'platform': 'macos', 'online': true, 'self': false},
      {'cid': '', 'device_id': 'lap', 'name': 'Laptop', 'platform': 'macos', 'online': false, 'last_seen': now - 60000},
      {'cid': '', 'device_id': 'win', 'name': 'PC-KT', 'platform': 'windows', 'online': false, 'last_seen': now - 5}, // trùng: giữ dòng online
      'rác',
      {'cid': '', 'device_id': ''},
    ];

    test('online trước (máy này đầu), ngoại tuyến theo lần cuối online; đánh dấu Máy này; bỏ trùng', () {
      final l = rcDeviceRows(raw, myDeviceId: 'mac');
      expect(l.map((d) => d.name), ['Mac-mini', 'PC-KT', 'Laptop', 'Old-PC']);
      expect(l.first.self, isTrue);
      expect(l.first.canControl, isFalse); // chính máy này
      expect(l[1].canControl, isTrue);
      expect(l[2].online, isFalse);
      expect(l[2].canControl, isFalse);
      expect(l[3].lastSeen, DateTime.fromMillisecondsSinceEpoch(now - 86400000));
      expect(rcDeviceRows(null), isEmpty);
      expect(rcLastSeenText(DateTime(2026, 11, 4, 9, 5), DateTime(2026, 11, 4, 12)), '09:05');
      expect(rcLastSeenText(DateTime(2026, 11, 3, 23, 59), DateTime(2026, 11, 4, 12)), '23:59 03/11/2026');
    });

    testWidgets('trang Máy tính: bấm máy online để điều khiển, máy ngoại tuyến mờ, xoá khỏi danh sách', (t) async {
      final opened = <String>[];
      final forgot = <String>[];
      var list = rcDeviceRows(raw, myDeviceId: 'mac');
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: RcDevicesPage(
            load: () async => list,
            forget: (id) async {
              forgot.add(id);
              list = list.where((d) => d.deviceId != id).toList();
              return list;
            },
            onOpen: (d) => opened.add(d.name),
            refresh: const Duration(hours: 1),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Mac-mini'), findsOneWidget);
      expect(find.text('Máy này'), findsWidgets);
      expect(find.textContaining('Ngoại tuyến'), findsNWidgets(2));
      expect(find.textContaining('lần cuối online'), findsNWidgets(2));
      await t.tap(find.text('PC-KT'));
      await t.tap(find.text('Mac-mini')); // máy này: không làm gì
      await t.pump();
      expect(opened, ['PC-KT']);
      await t.tap(find.text('Laptop'));
      await t.pump();
      expect(find.text('Máy đang ngoại tuyến'), findsOneWidget);
      expect(opened, ['PC-KT']);
      await t.longPress(find.text('Old-PC'));
      await t.pumpAndSettle();
      await t.tap(find.text('Xoá khỏi danh sách'));
      await t.pumpAndSettle();
      expect(forgot, ['old']);
      expect(find.text('Old-PC'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('trang Máy tính: chưa có máy nào / không tải được', (t) async {
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: RcDevicesPage(load: () async => const [], refresh: const Duration(hours: 1)))));
      await t.pumpAndSettle();
      expect(find.textContaining('Chưa có máy tính nào của bạn'), findsOneWidget);
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: RcDevicesPage(key: const ValueKey('x'), load: () async => null, refresh: const Duration(hours: 1)))));
      await t.pumpAndSettle();
      expect(find.textContaining('Không tải được danh sách máy tính'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });
}

/// Hẹn giờ giả: chạy [body] với đồng hồ tự điều khiển (không chờ thật).
void fakeAsyncRun(void Function(void Function(Duration) advance) body) {
  final timers = <_FakeTimer>[];
  var now = Duration.zero;
  void advance(Duration d) {
    now += d;
    for (final t in [...timers]) {
      if (!t.cancelled && t.due <= now) {
        t.cancelled = true;
        t.fn();
      }
    }
  }
  runZoned(() => body(advance), zoneSpecification: ZoneSpecification(createTimer: (self, parent, zone, d, f) {
    final t = _FakeTimer(now + d, f);
    timers.add(t);
    return t;
  }));
}

class _FakeTimer implements Timer {
  final Duration due;
  final void Function() fn;
  bool cancelled = false;
  _FakeTimer(this.due, this.fn);
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}
