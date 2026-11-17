// Dữ liệu mẫu cho test Drive (tên tệp hư cấu).
import 'dart:convert';

import 'package:flygo_chat/ui/drive/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

int _ago(Duration d) => DateTime.now().subtract(d).millisecondsSinceEpoch ~/ 1000;

List<Map<String, Object?>> driveFixture([String dir = '/']) {
  Map<String, Object?> f(String name, {bool d = false, int size = 0, String mime = '', Duration ago = const Duration(days: 3), bool fav = false, bool shared = false, int id = 0, String owner = 'u1', String ownerName = 'Tôi'}) => {
        'path': dir == '/' ? '/$name' : '$dir/$name', 'name': name, 'dir': d, 'size': size, 'mime': d ? 'httpd/unix-directory' : mime, 'mtime': _ago(ago),
        'etag': 'e$id', 'id': id, 'fav': fav, 'perms': 'RGDNVWCK', 'owner': owner, 'owner_name': ownerName, 'shared': shared, 'preview': false,
      };
  if (dir != '/') {
    return [
      f('Hợp đồng thang máy 01.pdf', size: 1240000, mime: 'application/pdf', id: 41),
      f('Phụ lục giá.xlsx', size: 88000, mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', id: 42),
    ];
  }
  return [
    f('Hợp đồng 2026', d: true, id: 11, ago: const Duration(days: 3)),
    f('Ảnh khai trương', d: true, id: 12, ago: const Duration(days: 1)),
    f('Kế toán', d: true, id: 13, shared: true, ago: const Duration(days: 12)),
    f('Báo cáo doanh thu Q3.xlsx', size: 290816, mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', id: 21, fav: true, shared: true),
    f('Pitch deck 2027.pptx', size: 4300000, mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation', id: 22, ago: const Duration(hours: 2)),
    f('Biên bản họp 14-11.docx', size: 38912, mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', id: 23, ago: const Duration(days: 1)),
    f('Hướng dẫn lắp đặt.pdf', size: 2411724, mime: 'application/pdf', id: 24, ago: const Duration(days: 13)),
    f('IMG_2051.jpg', size: 4089446, mime: 'image/jpeg', id: 25, ago: const Duration(hours: 4)),
    f('Quay phim công trình.mp4', size: 134217728, mime: 'video/mp4', id: 26, ago: const Duration(days: 1)),
  ];
}

http.Response _j(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json; charset=utf-8'});

DriveApi fakeDriveApi({void Function(http.Request req)? onRequest}) => DriveApi(
      base: 'https://chat.example/__apps/drive',
      ticketFn: (_) async => 't',
      client: MockClient((req) async {
        onRequest?.call(req);
        final p = req.url.path.replaceFirst('/__apps/drive', '');
        switch (p) {
          case '/api/me':
            return _j({'user': {'name': 'Demo'}, 'uid': 'u1', 'quota': {'used': 25125707366, 'total': 107374182400}, 'web_url': 'https://drive.example', 'chunk_size': 10485760});
          case '/api/info':
            final path = req.url.queryParameters['path'];
            final hit = driveFixture().where((x) => x['path'] == path).firstOrNull;
            return hit == null ? http.Response.bytes(utf8.encode('{"error":"không có"}'), 404) : _j({'item': hit});
          case '/api/list':
            return _j({'items': driveFixture(req.url.queryParameters['path'] ?? '/')});
          case '/api/recent':
            return _j({'items': driveFixture().where((x) => x['dir'] != true).toList()});
          case '/api/starred':
            return _j({'items': driveFixture().where((x) => x['fav'] == true).toList()});
          case '/api/shared':
            return _j({'items': [
              {...driveFixture()[2], 'owner': 'u2', 'owner_name': 'Phòng Kế toán'},
            ]});
          case '/api/trash':
            return _j({'items': [
              {...driveFixture()[6], 'trash_id': 'x.d1', 'original': '/Tài liệu cũ/Hướng dẫn lắp đặt.pdf', 'deleted': _ago(const Duration(days: 2))},
            ]});
          case '/api/shares':
            return _j({'shares': [
              {'id': '5', 'type': 'group', 'with': 'ketoan', 'with_name': 'Phòng Kế toán', 'can_edit': false},
              {'id': '6', 'type': 'link', 'url': 'https://drive.example/s/AbC123', 'can_edit': false, 'expires': '2026-11-22', 'has_password': true},
            ]});
          case '/api/activity':
            return _j({'activity': [
              {'subject': 'Bạn đã sửa Báo cáo doanh thu Q3.xlsx', 'time': _ago(const Duration(days: 3)), 'type': 'file_changed'},
              {'subject': 'Bạn đã chia sẻ với Phòng Kế toán', 'time': _ago(const Duration(days: 5)), 'type': 'shared'},
              {'subject': 'Bạn đã tạo Báo cáo doanh thu Q3.xlsx', 'time': _ago(const Duration(days: 40)), 'type': 'file_created'},
            ]});
          case '/api/sharees':
            return _j({'people': [
              {'type': 'user', 'id': 'lan', 'label': 'Lan (Kế toán)'},
              {'type': 'group', 'id': 'ketoan', 'label': 'Phòng Kế toán'},
            ]});
          case '/api/copy':
          case '/api/move':
            return _j({'items': []});
        }
        return http.Response.bytes(utf8.encode('{"error":"không có"}'), 404);
      }),
    );
