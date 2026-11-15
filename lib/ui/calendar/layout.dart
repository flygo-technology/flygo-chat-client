// Lịch: xếp chỗ sự kiện (thuần tính toán, không vẽ) — sự kiện chồng giờ chia cột trong một ngày, và thanh nhiều ngày ở
// hàng "cả ngày" / lịch tháng.

/// Vị trí một sự kiện trong cột ngày: cột [col] trên [cols] cột của cụm chồng nhau, chiếm [span] cột (giãn sang phải
/// khi các cột bên cạnh trống).
class Placed<T> {
  Placed(this.item, this.start, this.end, this.col, this.cols, [this.span = 1]);
  final T item;
  /// Phút từ đầu ngày.
  final int start, end;
  int col, cols, span;
}

/// Xếp các khoảng [start, end) (phút) trong một ngày. Sự kiện ngắn hơn [minLen] phút được coi như dài [minLen] để
/// chữ không đè lên nhau.
List<Placed<T>> layoutDay<T>(List<(T, int, int)> items, {int minLen = 20}) {
  final sorted = [...items]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : b.$3.compareTo(a.$3));
  final out = <Placed<T>>[];
  var cluster = <Placed<T>>[];
  final colEnds = <int>[];
  var clusterEnd = -1;

  void close() {
    final n = colEnds.length;
    for (final p in cluster) {
      p.cols = n;
      // Giãn sang các cột bên phải không có ai chồng giờ.
      var span = 1;
      for (var c = p.col + 1; c < n; c++) {
        final busy = cluster.any((q) => q.col == c && q.start < _vis(p, minLen) && _vis(q, minLen) > p.start);
        if (busy) break;
        span++;
      }
      p.span = span;
    }
    out.addAll(cluster);
    cluster = [];
    colEnds.clear();
    clusterEnd = -1;
  }

  for (final (item, s, e) in sorted) {
    final end = e - s < minLen ? s + minLen : e;
    if (cluster.isNotEmpty && s >= clusterEnd) close();
    var col = colEnds.indexWhere((x) => x <= s);
    if (col < 0) {
      col = colEnds.length;
      colEnds.add(end);
    } else {
      colEnds[col] = end;
    }
    cluster.add(Placed(item, s, e, col, 0));
    if (end > clusterEnd) clusterEnd = end;
  }
  if (cluster.isNotEmpty) close();
  return out;
}

int _vis<T>(Placed<T> p, int minLen) => p.end - p.start < minLen ? p.start + minLen : p.end;

/// Một thanh ở hàng cả ngày: từ ngày [from] tới [to] (chỉ số ngày trong khoảng đang xem, gồm cả hai đầu) ở hàng [row].
class Bar<T> {
  Bar(this.item, this.from, this.to, this.row);
  final T item;
  final int from, to;
  final int row;
}

/// Xếp các thanh [from, to] (chỉ số ngày) vào hàng: thanh bắt đầu sớm / dài hơn ở trên.
List<Bar<T>> layoutBars<T>(List<(T, int, int)> items) {
  final sorted = [...items]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : (b.$3 - b.$2).compareTo(a.$3 - a.$2));
  final rows = <List<(int, int)>>[];
  final out = <Bar<T>>[];
  for (final (item, f, t) in sorted) {
    var r = rows.indexWhere((row) => row.every((x) => t < x.$1 || f > x.$2));
    if (r < 0) {
      r = rows.length;
      rows.add([]);
    }
    rows[r].add((f, t));
    out.add(Bar(item, f, t, r));
  }
  return out;
}
