// TeamWork (vn.flygo.teamwork): dữ liệu như máy chủ trả (flygo-chat-server teamwork/README.md). Đọc rộng tay: trường
// thiếu thì lấy mặc định, để app cũ vẫn chạy khi máy chủ thêm trường mới.
import '../todo/model.dart';
import 'cover.dart';

// ------------------------------------------------------------ tiện ích đọc JSON
String _s(Object? v, [String d = '']) => v == null ? d : '$v';
String? _ns(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
bool _b(Object? v) => v == true || v == 1 || v == '1';
List<Map> _maps(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];
List<String> _strs(Object? v) => [for (final x in (v is List ? v : const [])) '$x'];

/// Ngày dạng YYYY-MM-DD → DateTime UTC 0 giờ; sai dạng → null.
DateTime? parseDay(Object? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${v ?? ''}');
  return m == null ? null : DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

String dayStr(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime dayOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

// ------------------------------------------------------------ vai trò
const kRoles = ['viewer', 'member', 'admin', 'owner'];
const kRoleNames = {'owner': 'Chủ dự án', 'admin': 'Quản trị', 'member': 'Thành viên', 'viewer': 'Người xem'};
int roleRank(String? r) => kRoles.indexOf(r ?? '');

// ------------------------------------------------------------ trạng thái
/// Nhóm của trạng thái: backlog (chưa bắt đầu), started (đang làm), done (đã xong), closed (đã đóng).
const kCategories = ['backlog', 'started', 'done', 'closed'];
const kCategoryNames = {'backlog': 'Chưa bắt đầu', 'started': 'Đang làm', 'done': 'Đã xong', 'closed': 'Đã đóng'};

class TwStatus {
  TwStatus({
    required this.id,
    this.projectId = '',
    required this.name,
    this.color = '#8B8D98',
    this.category = 'backlog',
    this.pos = 0,
    this.wip,
    this.isStart = false,
    this.adminOnly = false,
    this.review = false,
    this.closeSubtasksPrompt = false,
  });
  final String id, projectId;
  String name, color, category;
  int pos;
  int? wip;
  bool isStart, adminOnly, review, closeSubtasksPrompt;

  bool get isDone => category == 'done';
  bool get isClosed => category == 'closed' || category == 'done';

  factory TwStatus.fromJson(Map m) => TwStatus(
        id: _s(m['id']),
        projectId: _s(m['project_id']),
        name: _s(m['name']),
        color: _s(m['color'], '#8B8D98'),
        category: kCategories.contains(m['category']) ? '${m['category']}' : 'backlog',
        pos: _i(m['pos']),
        wip: m['wip'] == null ? null : _i(m['wip']),
        isStart: _b(m['is_start']),
        adminOnly: _b(m['admin_only']),
        review: _b(m['review']),
        closeSubtasksPrompt: _b(m['close_subtasks_prompt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_id': projectId,
        'name': name,
        'color': color,
        'category': category,
        'pos': pos,
        'wip': wip,
        'is_start': isStart,
        'admin_only': adminOnly,
        'review': review,
        'close_subtasks_prompt': closeSubtasksPrompt,
      };

  TwStatus copy() => TwStatus.fromJson(toJson());
}

class TwLabel {
  TwLabel({required this.id, this.projectId = '', required this.name, this.color = '#5B5BD6'});
  final String id, projectId;
  String name, color;
  factory TwLabel.fromJson(Map m) => TwLabel(id: _s(m['id']), projectId: _s(m['project_id']), name: _s(m['name']), color: _s(m['color'], '#5B5BD6'));
  Map<String, dynamic> toJson() => {'id': id, 'project_id': projectId, 'name': name, 'color': color};
}

/// Thành viên dự án: một người, một phòng ban, một vai trò Flygo ID hoặc mọi người.
class TwMember {
  TwMember({required this.subjectType, required this.subjectId, required this.role, this.name = ''});
  final String subjectType, subjectId;
  String role, name;
  String get key => '$subjectType:$subjectId';
  factory TwMember.fromJson(Map m) => TwMember(
        subjectType: _s(m['subject_type'], 'user'),
        subjectId: _s(m['subject_id']),
        role: _s(m['role'], 'member'),
        name: _s(m['name'], _s(m['subject_id'])),
      );
  Map<String, dynamic> toJson() => {'subject_type': subjectType, 'subject_id': subjectId, 'role': role, 'name': name};
}

/// Kết quả tìm chủ thể (để thêm thành viên): người / phòng ban / vai trò / mọi người.
class TwSubject {
  const TwSubject(this.type, this.id, this.name, {this.sub = ''});
  final String type, id, name, sub;
  factory TwSubject.fromJson(Map m, [String? type]) =>
      TwSubject(_s(m['type'] ?? m['subject_type'], type ?? 'user'), _s(m['id']), _s(m['name'] ?? m['display_name'], _s(m['id'])), sub: m['members'] != null ? '${_i(m['members'])} người' : _s(m['sub'] ?? m['dept'] ?? m['username']));
}

/// Agent AI (bot flygo-agent) có thể giao việc.
class TwAgent {
  const TwAgent({required this.id, required this.name, this.ownerId = '', this.ownerName = '', this.username = ''});
  final String id, name, ownerId, ownerName, username;
  String get label => ownerName.isEmpty ? name : '$name (của $ownerName)';
  factory TwAgent.fromJson(Map m) => TwAgent(
        id: _s(m['id'] ?? m['bot_id']),
        name: _s(m['name'] ?? m['display_name'], _s(m['username'])),
        ownerId: _s(m['owner_id']),
        ownerName: _s(m['owner_name']),
        username: _s(m['username']),
      );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'owner_id': ownerId, 'owner_name': ownerName, 'username': username};
}

// ------------------------------------------------------------ dự án
const kProjectStatuses = ['planning', 'active', 'paused', 'done', 'cancelled'];
const kProjectStatusNames = {'planning': 'Lên kế hoạch', 'active': 'Đang chạy', 'paused': 'Tạm dừng', 'done': 'Hoàn thành', 'cancelled': 'Huỷ'};
const kProjectStatusColors = {'planning': '#8B8D98', 'active': '#1E7BFF', 'paused': '#D6409F', 'done': '#1F9D55', 'cancelled': '#B0B4BE'};

class TwProject {
  TwProject({
    required this.id,
    required this.key,
    required this.name,
    this.description = const [],
    this.color = '#5B5BD6',
    this.status = 'active',
    this.deptIds = const [],
    this.deptNames = const [],
    this.start,
    this.due,
    this.owner = '',
    this.archived = false,
    this.myRole = 'viewer',
    this.counts = const {},
    this.starred = false,
    this.defaultStatusId,
    this.memberPreview = const [],
    this.updatedAt = 0,
    this.chatChannel,
    this.cover,
  });
  final String id;
  String key, name, color, status, owner, myRole;
  /// Kênh chat gắn với dự án (bot đăng sự kiện vào đó).
  String? chatChannel;
  /// Hình nền (null = màu chuyển nhạt từ màu dự án).
  TwCover? cover;
  List<TBlock> description;
  List<String> deptIds, deptNames;
  DateTime? start, due;
  bool archived, starred;
  /// Số việc theo nhóm trạng thái (backlog / started / done / closed).
  Map<String, int> counts;
  String? defaultStatusId;
  /// Vài thành viên để vẽ avatar trên thẻ dự án.
  List<TwAssignee> memberPreview;
  int updatedAt;

  int get total => counts.values.fold(0, (a, b) => a + b);
  int get doneCount => counts['done'] ?? 0;
  bool get canEdit => roleRank(myRole) >= roleRank('member');
  bool get canAdmin => roleRank(myRole) >= roleRank('admin');

  factory TwProject.fromJson(Map m) => TwProject(
        id: _s(m['id']),
        key: _s(m['key']),
        name: _s(m['name']),
        description: blocksFromJson(m['description']),
        color: _s(m['color'], '#5B5BD6'),
        status: kProjectStatuses.contains(m['status']) ? '${m['status']}' : 'active',
        deptIds: _strs(m['dept_ids']),
        deptNames: _strs(m['dept_names']),
        start: parseDay(m['start']),
        due: parseDay(m['due']),
        owner: _s(m['owner']),
        archived: _b(m['archived']),
        myRole: _s(m['my_role'], 'viewer'),
        counts: {for (final e in ((m['counts'] is Map ? (m['counts'] as Map)['by_category'] ?? m['counts'] : null) as Map? ?? const {}).entries) if (kCategories.contains(e.key)) '${e.key}': _i(e.value)},
        starred: _b(m['starred']),
        defaultStatusId: _ns(m['default_status_id']),
        memberPreview: [for (final a in _maps(m['member_preview'] ?? m['members_preview'])) TwAssignee.fromJson(a)],
        updatedAt: _i(m['updated_at']),
        chatChannel: _ns(m['chat_channel']),
        cover: TwCover.fromJson(m['cover']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'name': name,
        'description': blocksToJson(description),
        'color': color,
        'status': status,
        'dept_ids': deptIds,
        'dept_names': deptNames,
        'start': start == null ? null : dayStr(start!),
        'due': due == null ? null : dayStr(due!),
        'owner': owner,
        'archived': archived,
        'my_role': myRole,
        'counts': {'by_category': counts},
        'starred': starred,
        'default_status_id': defaultStatusId,
        'member_preview': [for (final a in memberPreview) a.toJson()],
        'updated_at': updatedAt,
        'chat_channel': chatChannel,
        'cover': cover?.toJson(),
      };
}

/// Dự án kèm cấu hình (trạng thái, nhãn, thành viên).
class TwProjectFull {
  TwProjectFull(this.project, {List<TwStatus>? statuses, List<TwLabel>? labels, List<TwMember>? members})
      : statuses = statuses ?? [],
        labels = labels ?? [],
        members = members ?? [] {
    this.statuses.sort((a, b) => a.pos.compareTo(b.pos));
  }
  TwProject project;
  List<TwStatus> statuses;
  List<TwLabel> labels;
  List<TwMember> members;

  TwStatus? status(String? id) => statuses.where((s) => s.id == id).firstOrNull;
  TwLabel? label(String id) => labels.where((l) => l.id == id).firstOrNull;
  TwStatus? get startStatus => statuses.where((s) => s.isStart).firstOrNull;
  TwStatus? get defaultStatus => status(project.defaultStatusId) ?? statuses.where((s) => s.category == 'backlog').firstOrNull ?? statuses.firstOrNull;
  TwStatus? get firstDone => statuses.where((s) => s.category == 'done').firstOrNull;
  TwStatus? get reviewStatus => statuses.where((s) => s.review).firstOrNull;

  factory TwProjectFull.fromJson(Map j) {
    final p = (j['project'] is Map ? j['project'] : j) as Map;
    return TwProjectFull(
      TwProject.fromJson(p),
      statuses: [for (final s in _maps(j['statuses'] ?? p['statuses'])) TwStatus.fromJson(s)],
      labels: [for (final l in _maps(j['labels'] ?? p['labels'])) TwLabel.fromJson(l)],
      members: [for (final m in _maps(j['members'] ?? p['members'])) TwMember.fromJson(m)],
    );
  }

  Map<String, dynamic> toJson() => {
        'project': project.toJson(),
        'statuses': [for (final s in statuses) s.toJson()],
        'labels': [for (final l in labels) l.toJson()],
        'members': [for (final m in members) m.toJson()],
      };
}

// ------------------------------------------------------------ việc
const kPriorityNames = {0: 'Không', 1: 'Khẩn', 2: 'Cao', 3: 'Vừa', 4: 'Thấp'};

class TwAssignee {
  const TwAssignee({required this.kind, required this.id, this.name = ''});
  final String kind, id, name; // kind: user | agent
  bool get isAgent => kind == 'agent';
  String get key => '$kind:$id';
  factory TwAssignee.fromJson(Map m) => TwAssignee(kind: _s(m['kind'], 'user'), id: _s(m['id']), name: _s(m['name'], _s(m['id'])));
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id, 'name': name};
  @override
  bool operator ==(Object other) => other is TwAssignee && other.kind == kind && other.id == id;
  @override
  int get hashCode => Object.hash(kind, id);
}

class TwEstimate {
  const TwEstimate(this.value, this.unit);
  final double value;
  final String unit; // h | d
  String get label => '${value == value.roundToDouble() ? value.toInt() : value.toString().replaceAll('.', ',')} ${unit == 'd' ? 'ngày' : 'giờ'}';
  static TwEstimate? fromJson(Object? m) => m is Map && m['value'] is num ? TwEstimate((m['value'] as num).toDouble(), _s(m['unit'], 'h')) : null;
  Map<String, dynamic> toJson() => {'value': value, 'unit': unit};
}

/// Tóm tắt lượt chạy agent mới nhất của một việc.
class TwRun {
  TwRun({
    required this.id,
    this.taskId = '',
    this.taskKey = '',
    required this.botId,
    this.botName = '',
    this.startedBy = '',
    this.state = 'queued',
    this.sessionChannel,
    this.error,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.kind = 'start',
    this.commentId,
    this.sessionHint,
    this.steps = const [],
    this.text,
    this.seq = 0,
    this.stepCount = 0,
    this.lastStep,
    this.summary,
    this.projectId = '',
    this.bypassEligible = false,
  });
  final String id, taskId, taskKey, botId, botName, startedBy;
  /// Dự án của lượt chạy (lượt "project" của khung AI dự án không gắn với việc nào).
  final String projectId;
  /// Lượt chạy được phép chạy không cần duyệt (chủ bot xác nhận).
  final bool bypassEligible;
  String state; // queued | running | review | done | failed | cancelled | blocked
  /// start (Bắt đầu / trạng thái bắt đầu) | mention (@nhắc agent trong bình luận).
  final String kind;
  /// Bình luận đã @nhắc agent (lượt chạy mention).
  final String? commentId;
  /// Phiên sẵn có của việc + agent + người này: gửi tiếp vào đó thay vì mở phiên mới.
  final String? sessionHint;
  /// Tiến độ runner đẩy lên (GET /api/runs/:id): các bước + chữ đang viết.
  List<TwRunStep> steps;
  String? text, lastStep, summary;
  int seq, stepCount;
  bool get finished => const ['review', 'done', 'failed', 'cancelled', 'blocked'].contains(state);
  bool get failed => const ['failed', 'blocked', 'cancelled'].contains(state);
  String? sessionChannel, error;
  int createdAt, updatedAt;
  bool get active => state == 'queued' || state == 'running';
  factory TwRun.fromJson(Map m) => TwRun(
        id: _s(m['id']),
        taskId: _s(m['task_id']),
        taskKey: _s(m['task_key']),
        botId: _s(m['bot_id']),
        botName: _s(m['bot_name']),
        startedBy: _s(m['started_by']),
        state: _s(m['state'], 'queued'),
        sessionChannel: _ns(m['session_channel']),
        error: _ns(m['error']),
        createdAt: _i(m['created_at']),
        updatedAt: _i(m['updated_at']),
        kind: _s(m['kind'], 'start'),
        commentId: _ns(m['comment_id']),
        sessionHint: _ns(m['session_hint']),
        steps: [for (final x in _maps(m['progress'] is Map ? (m['progress'] as Map)['steps'] : m['progress'] ?? m['steps'])) TwRunStep.fromJson(x)],
        text: _ns(m['text']),
        seq: _i(m['seq'] ?? (m['progress'] is Map ? (m['progress'] as Map)['seq'] : null)),
        stepCount: _i(m['step_count']),
        lastStep: m['last_step'] is Map ? _ns((m['last_step'] as Map)['title']) : _ns(m['last_step']),
        summary: _ns(m['summary']),
        projectId: _s(m['project_id']),
        bypassEligible: _b(m['bypass_eligible']),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'comment_id': commentId,
        'session_hint': sessionHint,
        'task_id': taskId,
        'task_key': taskKey,
        'bot_id': botId,
        'bot_name': botName,
        'started_by': startedBy,
        'state': state,
        'session_channel': sessionChannel,
        'error': error,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// Một bước tiến độ của lượt chạy agent (như thẻ tiến trình trong chat).
class TwRunStep {
  const TwRunStep({required this.id, required this.kind, required this.title, this.detail, this.status = 'running', this.at = 0});
  final String id, kind, title, status; // kind: tool | think | text | plan | approval; status: running | done | error
  final String? detail;
  final int at;
  factory TwRunStep.fromJson(Map m) => TwRunStep(id: _s(m['id']), kind: _s(m['kind'], 'tool'), title: _s(m['title']), detail: _ns(m['detail']), status: _s(m['status'], 'running'), at: _i(m['at']));
}

const kRunStateNames = {
  'queued': 'đang chờ mở phiên',
  'running': 'đang làm',
  'review': 'đã nộp, chờ duyệt',
  'done': 'xong',
  'failed': 'báo lỗi',
  'cancelled': 'đã dừng',
  'blocked': 'không chạy được',
};

class TwTask {
  TwTask({
    required this.id,
    required this.projectId,
    this.number = 0,
    required this.key,
    this.parentId,
    required this.title,
    this.description = const [],
    required this.statusId,
    this.priority = 0,
    this.start,
    this.due,
    this.estimate,
    this.progress,
    this.rank = '',
    this.labels = const [],
    this.assignees = const [],
    this.watchers = const [],
    this.createdBy = '',
    this.createdAt = 0,
    this.updatedAt = 0,
    this.doneAt,
    this.version = 0,
    this.deletedAt,
    this.subTotal = 0,
    this.subDone = 0,
    this.commentCount = 0,
    this.attachmentCount = 0,
    this.run,
    this.reactions = const [],
    this.blockedBy = const [],
    this.statusInfo,
    this.createdByName = '',
  });
  final String id, projectId;
  int number;
  String key, title, statusId, rank, createdBy;
  String? parentId;
  List<TBlock> description;
  int priority;
  DateTime? start, due;
  TwEstimate? estimate;
  int? progress;
  List<String> labels, watchers;
  List<TwAssignee> assignees;
  int createdAt, updatedAt, version;
  int? doneAt, deletedAt;
  int subTotal, subDone, commentCount, attachmentCount;
  TwRun? run;
  List<TwReaction> reactions;
  /// Id các việc chặn việc này (phụ thuộc "xong trước, bắt đầu sau"), để vẽ mũi tên Gantt.
  List<String> blockedBy;
  /// Trạng thái kèm theo (danh sách "Việc của tôi", tìm kiếm: dự án có thể chưa tải cấu hình).
  TwStatus? statusInfo;
  String createdByName;

  bool get hasAgent => assignees.any((a) => a.isAgent);
  /// % xong: chỉnh tay, hoặc theo việc con.
  int get percent => progress ?? (subTotal == 0 ? 0 : (subDone * 100 / subTotal).round());

  factory TwTask.fromJson(Map m) => TwTask(
        id: _s(m['id']),
        projectId: _s(m['project_id']),
        number: _i(m['number']),
        key: _s(m['key']),
        parentId: _ns(m['parent_id']),
        title: _s(m['title']),
        description: blocksFromJson(m['description']),
        statusId: _s(m['status_id']),
        priority: _i(m['priority']),
        start: parseDay(m['start']),
        due: parseDay(m['due']),
        estimate: TwEstimate.fromJson(m['estimate']),
        progress: m['progress'] == null ? null : _i(m['progress']),
        rank: _s(m['rank']),
        labels: _strs(m['labels']),
        assignees: [for (final a in _maps(m['assignees'])) TwAssignee.fromJson(a)],
        watchers: _strs(m['watchers']),
        createdBy: _s(m['created_by']),
        createdAt: _i(m['created_at']),
        updatedAt: _i(m['updated_at']),
        doneAt: m['done_at'] == null ? null : _i(m['done_at']),
        version: _i(m['version']),
        deletedAt: m['deleted_at'] == null ? null : _i(m['deleted_at']),
        subTotal: _i(m['sub_total']),
        subDone: _i(m['sub_done']),
        commentCount: _i(m['comment_count']),
        attachmentCount: _i(m['attachment_count']),
        run: m['agent_run'] is Map ? TwRun.fromJson(m['agent_run'] as Map) : null,
        reactions: [for (final r in _maps(m['reactions'])) TwReaction.fromJson(r)],
        blockedBy: _strs(m['blocked_by']),
        createdByName: _s(m['created_by_name']),
        statusInfo: m['status'] is Map
            ? TwStatus.fromJson(m['status'] as Map)
            : (m['category'] != null ? TwStatus(id: _s(m['status_id']), name: _s(m['status_name']), category: _s(m['category']), color: _s(m['status_color'], _catColor(_s(m['category'])))) : null),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'project_id': projectId,
        'number': number,
        'key': key,
        'parent_id': parentId,
        'title': title,
        'description': blocksToJson(description),
        'status_id': statusId,
        'priority': priority,
        'start': start == null ? null : dayStr(start!),
        'due': due == null ? null : dayStr(due!),
        'estimate': estimate?.toJson(),
        'progress': progress,
        'rank': rank,
        'labels': labels,
        'assignees': [for (final a in assignees) a.toJson()],
        'watchers': watchers,
        'created_by': createdBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'done_at': doneAt,
        'version': version,
        'deleted_at': deletedAt,
        'sub_total': subTotal,
        'sub_done': subDone,
        'comment_count': commentCount,
        'attachment_count': attachmentCount,
        'agent_run': run?.toJson(),
        'reactions': [for (final r in reactions) r.toJson()],
        'blocked_by': blockedBy,
        'created_by_name': createdByName,
        if (statusInfo != null) 'status': statusInfo!.toJson(),
      };

  TwTask copy() => TwTask.fromJson(toJson());
}

class TwLink {
  const TwLink({required this.id, required this.fromTask, required this.toTask, required this.type, this.otherKey = '', this.otherTitle = '', this.otherStatusId = ''});
  final String id, fromTask, toTask, type, otherKey, otherTitle, otherStatusId; // type: blocks | relates | duplicates
  /// Máy chủ trả {id, type, direction: out|in, task:{id, key, title, status_id}} so với việc đang xem ([self]).
  factory TwLink.fromJson(Map m, [String self = '']) {
    final o = m['task'] is Map ? m['task'] as Map : (m['other'] is Map ? m['other'] as Map : const {});
    final dir = _s(m['direction']);
    final other = _s(o['id']);
    return TwLink(
      id: _s(m['id']),
      fromTask: _s(m['from_task'] ?? (dir == 'in' ? other : self)),
      toTask: _s(m['to_task'] ?? (dir == 'in' ? self : other)),
      type: _s(m['type'], 'relates'),
      otherKey: _s(m['other_key'] ?? o['key']),
      otherTitle: _s(m['other_title'] ?? o['title']),
      otherStatusId: _s(m['other_status_id'] ?? o['status_id']),
    );
  }
  Map<String, dynamic> toJson() => {'id': id, 'from_task': fromTask, 'to_task': toTask, 'type': type, 'other_key': otherKey, 'other_title': otherTitle, 'other_status_id': otherStatusId};
}

class TwReaction {
  const TwReaction(this.emoji, this.users);
  final String emoji;
  final List<String> users;
  factory TwReaction.fromJson(Map m) => TwReaction(_s(m['emoji']), _strs(m['users']));
  Map<String, dynamic> toJson() => {'emoji': emoji, 'users': users};
}

class TwAttachment {
  const TwAttachment({required this.id, this.taskId = '', this.commentId, required this.name, this.size = 0, this.mime = '', this.source = 'upload', this.driveUrl, this.createdBy = '', this.createdAt = 0});
  final String id, taskId, name, mime, source, createdBy;
  final String? commentId, driveUrl;
  final int size, createdAt;
  bool get isDrive => source == 'drive';
  bool get isImage => mime.startsWith('image/');
  String get ext {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toUpperCase();
  }

  factory TwAttachment.fromJson(Map m) => TwAttachment(
        id: _s(m['id']),
        taskId: _s(m['task_id']),
        commentId: _ns(m['comment_id']),
        name: _s(m['name']),
        size: _i(m['size']),
        mime: _s(m['mime']),
        source: _s(m['source'], 'upload'),
        driveUrl: _ns(m['drive_url']),
        createdBy: _s(m['created_by']),
        createdAt: _i(m['created_at']),
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'task_id': taskId,
        'comment_id': commentId,
        'name': name,
        'size': size,
        'mime': mime,
        'source': source,
        'drive_url': driveUrl,
        'created_by': createdBy,
        'created_at': createdAt,
      };
}

class TwComment {
  TwComment({
    required this.id,
    required this.taskId,
    this.parentId,
    required this.author,
    this.authorName = '',
    this.via = 'app',
    this.blocks = const [],
    this.createdAt = 0,
    this.editedAt,
    this.deleted = false,
    this.reactions = const [],
    this.attachments = const [],
    this.agentName,
    this.runs = const [],
  });
  final String id, taskId, author, authorName, via;
  final String? agentName;
  /// Lượt chạy agent mà bình luận này (@nhắc agent) tạo ra.
  List<TwRun> runs;
  final String? parentId;
  List<TBlock> blocks;
  final int createdAt;
  int? editedAt;
  bool deleted;
  List<TwReaction> reactions;
  List<TwAttachment> attachments;

  /// Bình luận do agent viết (via `agent:<bot>`): id bot.
  String? get agentBot => via.startsWith('agent:') ? via.substring(6) : null;

  factory TwComment.fromJson(Map m) => TwComment(
        id: _s(m['id']),
        taskId: _s(m['task_id']),
        parentId: _ns(m['parent_id']),
        author: _s(m['author']),
        authorName: _s(m['author_name'], _s(m['author'])),
        via: _s(m['via'], 'app'),
        blocks: blocksFromJson(m['blocks']),
        createdAt: _i(m['created_at']),
        editedAt: m['edited_at'] == null ? null : _i(m['edited_at']),
        deleted: _b(m['deleted']),
        reactions: [for (final r in _maps(m['reactions'])) TwReaction.fromJson(r)],
        attachments: [for (final a in _maps(m['attachments'])) TwAttachment.fromJson(a)],
        agentName: _ns(m['agent_name']),
        runs: [for (final r in _maps(m['runs'])) TwRun.fromJson(r)],
      );
}

class TwActivity {
  const TwActivity({required this.id, required this.actor, this.actorName = '', this.via = 'app', required this.type, this.data = const {}, this.at = 0, this.taskId = ''});
  final String id, actor, actorName, via, type, taskId;
  final Map data;
  final int at;
  factory TwActivity.fromJson(Map m) => TwActivity(
        id: _s(m['id']),
        actor: _s(m['actor']),
        actorName: _s(m['actor_name'], _s(m['actor'])),
        via: _s(m['via'], 'app'),
        type: _s(m['type']),
        data: m['data'] is Map ? m['data'] as Map : const {},
        at: _i(m['at']),
        taskId: _s(m['task_id']),
      );
}

String _catColor(String c) => switch (c) { 'started' => '#1E7BFF', 'done' => '#1F9D55', 'closed' => '#B0B4BE', _ => '#8B8D98' };

/// Chi tiết một việc: việc + cây việc con + liên kết + tệp + các lượt chạy agent.
class TwTaskDetail {
  TwTaskDetail(this.task, {this.subtasks = const [], this.links = const [], this.attachments = const [], this.runs = const [], this.parentKey, this.parentTitle});
  TwTask task;
  /// Việc con (phẳng, có parent_id; app tự dựng cây).
  List<TwTask> subtasks;
  List<TwLink> links;
  List<TwAttachment> attachments;
  List<TwRun> runs;
  String? parentKey, parentTitle;

  factory TwTaskDetail.fromJson(Map j) {
    final t = (j['task'] is Map ? j['task'] : j) as Map;
    final subs = <TwTask>[];
    void walk(Object? v) {
      for (final s in _maps(v)) {
        subs.add(TwTask.fromJson(s));
        walk(s['subtasks'] ?? s['children']);
      }
    }

    walk(j['subtasks'] ?? t['subtasks']);
    return TwTaskDetail(
      TwTask.fromJson(t),
      subtasks: subs,
      links: [for (final l in _maps(j['links'] ?? t['links'])) TwLink.fromJson(l, _s(t['id']))],
      attachments: [for (final a in _maps(j['attachments'] ?? t['attachments'])) TwAttachment.fromJson(a)],
      runs: [for (final r in _maps(j['runs'] ?? t['runs'])) TwRun.fromJson(r)],
      parentKey: _ns(j['parent_key'] ?? (_maps(j['parents']).isNotEmpty ? _maps(j['parents']).last['key'] : null)),
      parentTitle: _ns(j['parent_title'] ?? (_maps(j['parents']).isNotEmpty ? _maps(j['parents']).last['title'] : null)),
    );
  }
}

class TwNotification {
  TwNotification({required this.id, required this.type, this.text = '', this.taskKey, this.taskId, this.projectId, this.actorName = '', this.at = 0, this.read = false});
  final String id, type, text, actorName;
  final String? taskKey, taskId, projectId;
  final int at;
  bool read;
  factory TwNotification.fromJson(Map m) => TwNotification(
        id: _s(m['id']),
        type: _s(m['kind'] ?? m['type']),
        text: _s(m['text'] ?? m['message']),
        taskKey: _ns(m['task_key']),
        taskId: _ns(m['task_id']),
        projectId: _ns(m['project_id']),
        actorName: _s(m['actor_name']),
        at: _i(m['at'] ?? m['created_at']),
        read: _b(m['read']),
      );
  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'text': text, 'task_key': taskKey, 'task_id': taskId, 'project_id': projectId, 'actor_name': actorName, 'at': at, 'read': read};
}

/// Bộ lọc đã lưu.
class TwView {
  TwView({required this.id, required this.name, this.shared = false, this.query = const {}, this.owner = ''});
  final String id, owner;
  String name;
  bool shared;
  Map<String, dynamic> query;
  factory TwView.fromJson(Map m) => TwView(id: _s(m['id']), name: _s(m['name']), shared: _b(m['shared']), owner: _s(m['owner']), query: m['query'] is Map ? (m['query'] as Map).cast<String, dynamic>() : {});
}

// ------------------------------------------------------------ chữ có định dạng + @nhắc
/// @nhắc nằm trong đoạn chữ dạng link nội bộ `tw:<user|agent|task>:<id>` (máy chủ lưu ở thuộc tính `m`).
const kMentionScheme = 'tw:';

String mentionLink(String kind, String id) => '$kMentionScheme$kind:$id';

/// (kind, id) của một link @nhắc; null nếu là link thường.
(String, String)? mentionOf(String? a) {
  if (a == null || !a.startsWith(kMentionScheme)) return null;
  final rest = a.substring(kMentionScheme.length);
  final i = rest.indexOf(':');
  return i <= 0 ? null : (rest.substring(0, i), rest.substring(i + 1));
}

/// Một đoạn chữ từ JSON máy chủ (@nhắc ở thuộc tính m → link nội bộ).
TRun _runFrom(Map m) {
  final r = TRun.fromJson(m);
  final mm = m['m'];
  if (mm is Map) r.f = r.f.copyWith(a: mentionLink(_s(mm['k'] ?? mm['kind'], 'user'), _s(mm['id'])));
  return r;
}

/// Đoạn chữ → JSON máy chủ (link @nhắc → thuộc tính m). Bỏ đoạn rỗng.
List<Map<String, dynamic>> _runsJson(List<TRun> runs) => [
      for (final x in runs)
        if (x.x.isNotEmpty)
          () {
            final r = x.toJson();
            final m = mentionOf(r['a'] as String?);
            if (m != null) {
              r.remove('a');
              r['m'] = {'k': m.$1, 'id': m.$2};
            }
            return r;
          }(),
    ];

/// Khối bảng: rows → ô → đoạn chữ, hàng 0 là tiêu đề; align theo cột ('l' | 'c' | 'r').
class TwTableBlock extends TBlock {
  TwTableBlock({super.id, required this.rows, List<String>? align}) : align = align ?? [], super(t: 'table');
  List<List<List<TRun>>> rows;
  List<String> align;

  int get cols => rows.fold(0, (m, r) => r.length > m ? r.length : m);
  String alignOf(int col) => col < align.length ? align[col] : 'l';

  @override
  String get text => rows.map((r) => r.map((c) => c.map((x) => x.x).join()).join(' | ')).join('\n');

  @override
  TwTableBlock clone() => TwTableBlock(id: id, rows: [for (final r in rows) [for (final c in r) [for (final x in c) TRun(x.x, x.f)]]], align: [...align]);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        't': 'table',
        'rows': [for (final r in rows) [for (final c in r) _runsJson(c)]],
        if (align.isNotEmpty) 'align': align,
      };
}

/// Khối mã nhiều dòng (một khối cho cả đoạn), kèm ngôn ngữ nếu có. Không định dạng chữ bên trong.
class TwCodeBlock extends TBlock {
  TwCodeBlock({super.id, required String code, this.lang}) : super(t: 'code', r: [TRun(code)]);
  String? lang;
  String get code => r.map((x) => x.x).join();
  set code(String v) => r = [TRun(v)];
  @override
  TwCodeBlock clone() => TwCodeBlock(id: id, code: code, lang: lang);
  @override
  Map<String, dynamic> toJson() => {'id': id, 't': 'code', 'r': [if (code.isNotEmpty) {'x': code}], if (lang != null && lang!.isNotEmpty) 'lang': lang};
}

/// Mục danh sách số bắt đầu khác 1 (máy chủ gửi start).
class TwOlBlock extends TBlock {
  TwOlBlock({super.id, super.r, super.ind, required this.start}) : super(t: 'ol');
  int start;
  @override
  TBlock clone() => t == 'ol' ? TwOlBlock(id: id, r: [for (final x in r) TRun(x.x, x.f)], ind: ind, start: start) : TBlock(id: id, t: t, r: [for (final x in r) TRun(x.x, x.f)], done: done, ind: ind);
  @override
  Map<String, dynamic> toJson() => {...super.toJson(), if (t == 'ol') 'start': start};
}

List<TBlock> blocksFromJson(Object? v) {
  if (v is String) return markdownToBlocks(v);
  return [
    for (final b in _maps(v))
      if (b['t'] == 'table')
        TwTableBlock(
          id: _ns(b['id']),
          rows: [
            for (final r in (b['rows'] is List ? b['rows'] as List : const []))
              [for (final c in (r is List ? r : const [])) [for (final x in (c is List ? c : const [])) if (x is Map) _runFrom(x)]],
          ],
          align: _strs(b['align']),
        )
      else if (b['t'] == 'code')
        TwCodeBlock(id: _ns(b['id']), code: [for (final x in _maps(b['r'])) _s(x['x'])].join(), lang: _ns(b['lang']))
      else if (b['t'] == 'ol' && b['start'] is num && (b['start'] as num).toInt() != 1)
        TwOlBlock(id: _ns(b['id']), r: [for (final x in _maps(b['r'])) _runFrom(x)], ind: _i(b['ind']), start: (b['start'] as num).toInt())
      else
        () {
          final blk = TBlock.fromJson(b);
          blk.r = [for (final x in _maps(b['r'])) _runFrom(x)];
          // Kiểu khối lạ (bản máy chủ mới hơn) không có chữ: hiện chữ của mọi chuỗi bên trong để không mất nội dung.
          if (blk.r.isEmpty && !const ['p', 'h1', 'h2', 'h3', 'ul', 'ol', 'check', 'quote', 'hr'].contains(blk.t)) {
            final words = <String>[];
            void walk(Object? x) {
              if (x is Map) {
                if (x['x'] is String) words.add(x['x'] as String);
                x.forEach((k, v) => k == 'x' ? null : walk(v));
              } else if (x is List) {
                x.forEach(walk);
              }
            }

            walk(b);
            blk
              ..t = 'p'
              ..r = [TRun(words.join(' '))];
          }
          return blk;
        }(),
  ];
}

List<Map<String, dynamic>> blocksToJson(List<TBlock> blocks) => [
      for (final b in blocks)
        b is TwTableBlock || b is TwCodeBlock
            ? b.toJson()
            : () {
                final j = b.toJson();
                j['r'] = _runsJson(b.r);
                return j;
              }(),
    ];

/// Chữ thuần của nội dung (tìm kiếm, xem trước).
String blocksText(List<TBlock> blocks) => blocks.map((b) => b.text).where((s) => s.isNotEmpty).join('\n');

// ------------------------------------------------------------ bảng GFM
final _sepRe = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');
bool _pipeRow(String l) => l.trim().contains('|') && l.trim().length > 1;

/// Tách một dòng bảng thành các ô (bỏ dấu | đầu / cuối, giữ "\|").
List<String> _cells(String line) {
  var l = line.trim();
  if (l.startsWith('|')) l = l.substring(1);
  if (l.endsWith('|') && !l.endsWith(r'\|')) l = l.substring(0, l.length - 1);
  final out = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < l.length; i++) {
    if (l[i] == '\\' && i + 1 < l.length && l[i + 1] == '|') {
      buf.write('|');
      i++;
    } else if (l[i] == '|') {
      out.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(l[i]);
    }
  }
  out.add(buf.toString().trim());
  return out;
}

/// Bảng GFM bắt đầu ở dòng [i] (tiêu đề + dòng gạch + các hàng): (bảng, số dòng đã dùng) hoặc null.
(TwTableBlock, int)? parseGfmTable(List<String> lines, int i) {
  if (i + 1 >= lines.length || !_pipeRow(lines[i]) || !_sepRe.hasMatch(lines[i + 1]) || !lines[i + 1].contains('-')) return null;
  final head = _cells(lines[i]);
  final sep = _cells(lines[i + 1]);
  final align = [
    for (final c in sep) c.startsWith(':') && c.endsWith(':') ? 'c' : (c.endsWith(':') ? 'r' : 'l'),
  ];
  final rows = <List<List<TRun>>>[[for (final c in head) _inline(c)]];
  var j = i + 2;
  while (j < lines.length && _pipeRow(lines[j]) && !_sepRe.hasMatch(lines[j])) {
    final cells = _cells(lines[j]);
    rows.add([for (var k = 0; k < head.length; k++) _inline(k < cells.length ? cells[k] : '')]);
    j++;
  }
  return (TwTableBlock(rows: rows, align: align.length == head.length ? align : null), j - i);
}

/// Các đoạn văn thường liên tiếp là bảng Markdown (dán từ chỗ khác, hoặc nội dung cũ) → khối bảng.
/// Dòng có dấu | ngay sau một bảng được nối thêm làm hàng mới. Trả về null nếu không đổi gì.
List<TBlock>? foldTables(List<TBlock> blocks) {
  var changed = false;
  final out = <TBlock>[];
  var i = 0;
  String lineOf(TBlock b) => b.t == 'p' ? blocksToMarkdown([b]) : '';
  while (i < blocks.length) {
    final b = blocks[i];
    if (b.t == 'p') {
      final lines = [for (var k = i; k < blocks.length && blocks[k].t == 'p'; k++) lineOf(blocks[k])];
      final hit = parseGfmTable(lines, 0);
      if (hit != null) {
        out.add(hit.$1);
        i += hit.$2;
        changed = true;
        continue;
      }
      final prev = out.isNotEmpty ? out.last : null;
      final l = lineOf(b);
      if (prev is TwTableBlock && _pipeRow(l) && l.trim().startsWith('|')) {
        final cells = _cells(l);
        prev.rows.add([for (var k = 0; k < prev.cols; k++) _inline(k < cells.length ? cells[k] : '')]);
        i++;
        changed = true;
        continue;
      }
    }
    out.add(b);
    i++;
  }
  return changed ? out : null;
}

/// Markdown đơn giản → khối (máy chủ trả chữ thay cho khối, AI soạn, dán): tiêu đề, danh sách lồng nhau (2 dấu cách mỗi
/// cấp), ô tick, trích dẫn, đường kẻ, khối mã ``` và bảng GFM.
List<TBlock> markdownToBlocks(String md) {
  final out = <TBlock>[];
  final lines = md.replaceAll('\r', '').split('\n');
  for (var n = 0; n < lines.length; n++) {
    final l = lines[n].trimRight();
    if (l.trim().startsWith('```')) {
      final code = <String>[];
      n++;
      while (n < lines.length && !lines[n].trim().startsWith('```')) {
        code.add(lines[n]);
        n++;
      }
      out.add(TwCodeBlock(code: code.join('\n'), lang: l.trim().substring(3).trim().isEmpty ? null : l.trim().substring(3).trim()));
      continue;
    }
    final table = parseGfmTable(lines, n);
    if (table != null) {
      out.add(table.$1);
      n += table.$2 - 1;
      continue;
    }
    if (l.trim().isEmpty) continue;
    final ind = ((l.length - l.trimLeft().length) ~/ 2).clamp(0, 4);
    String t = 'p';
    var s = l.trimLeft();
    bool done = false;
    final ck = RegExp(r'^[-*] \[( |x|X)\] ').firstMatch(s);
    if (ck != null) {
      t = 'check';
      done = ck[1]!.toLowerCase() == 'x';
      s = s.substring(ck.end);
    } else if (s.startsWith('### ')) {
      t = 'h3';
      s = s.substring(4);
    } else if (s.startsWith('## ')) {
      t = 'h2';
      s = s.substring(3);
    } else if (s.startsWith('# ')) {
      t = 'h1';
      s = s.substring(2);
    } else if (RegExp(r'^[-*•] ').hasMatch(s)) {
      t = 'ul';
      s = s.substring(2);
    } else if (RegExp(r'^\d+[.)] ').hasMatch(s)) {
      t = 'ol';
      s = s.replaceFirst(RegExp(r'^\d+[.)] '), '');
    } else if (s.startsWith('> ')) {
      t = 'quote';
      s = s.substring(2);
    } else if (s == '---') {
      out.add(TBlock(t: 'hr'));
      continue;
    }
    out.add(TBlock(t: t, r: _inline(s), done: done, ind: t == 'ul' || t == 'ol' || t == 'check' ? ind : 0));
  }
  return out;
}

/// **đậm**, *nghiêng*, `mã` trong một dòng.
List<TRun> _inline(String s) {
  final out = <TRun>[];
  final re = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`');
  var i = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > i) out.add(TRun(s.substring(i, m.start)));
    if (m[1] != null) out.add(TRun(m[1]!, const TFmt(b: true)));
    if (m[2] != null) out.add(TRun(m[2]!, const TFmt(i: true)));
    if (m[3] != null) out.add(TRun(m[3]!, const TFmt(c: true)));
    i = m.end;
  }
  if (i < s.length) out.add(TRun(s.substring(i)));
  return out;
}

/// Đoạn chữ dạng Markdown một dòng (đậm, nghiêng, mã).
String runsToMarkdown(List<TRun> runs) => runs.map((r) {
      var x = r.x;
      if (r.f.c) x = '`$x`';
      if (r.f.b) x = '**$x**';
      if (r.f.i) x = '*$x*';
      return x;
    }).join();

/// Một ô bảng sửa dạng chữ Markdown → đoạn chữ.
List<TRun> inlineMarkdown(String s) => _inline(s);

/// Khối → Markdown (bản giao việc gửi agent).
String blocksToMarkdown(List<TBlock> blocks) {
  final out = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    if (b is TwTableBlock) {
      String row(List<List<TRun>> r) => '| ${[for (var k = 0; k < b.cols; k++) k < r.length ? runsToMarkdown(r[k]).replaceAll('|', r'\|') : ''].join(' | ')} |';
      if (b.rows.isEmpty) continue;
      out.add(row(b.rows.first));
      out.add('|${[for (var k = 0; k < b.cols; k++) switch (b.alignOf(k)) { 'c' => ':---:', 'r' => '---:', _ => '---' }].join('|')}|');
      for (final r in b.rows.skip(1)) {
        out.add(row(r));
      }
      continue;
    }
    final text = runsToMarkdown(b.r);
    final ind = '  ' * b.ind;
    out.add(switch (b.t) {
      'h1' => '# $text',
      'h2' => '## $text',
      'h3' => '### $text',
      'ul' => '$ind- $text',
      'ol' => '${ind}1. $text',
      'check' => '$ind- [${b.done ? 'x' : ' '}] $text',
      'quote' => '> $text',
      'code' => '```${b is TwCodeBlock ? b.lang ?? '' : ''}\n${b.text}\n```',
      'hr' => '---',
      _ => text,
    });
  }
  return out.join('\n');
}

// ------------------------------------------------------------ cây việc + thứ tự
/// Việc con trực tiếp của [parentId] trong [all], theo thứ tự rank.
List<TwTask> childrenOf(List<TwTask> all, String? parentId) => all.where((t) => t.parentId == parentId).toList()..sort(byRank);

int byRank(TwTask a, TwTask b) {
  final c = a.rank.compareTo(b.rank);
  return c != 0 ? c : a.number.compareTo(b.number);
}

/// Rank nằm giữa [a] và [b] (chuỗi so theo thứ tự từ điển, như máy chủ): a < kết quả < b. a / b rỗng = đầu / cuối.
String rankBetween(String a, String b) {
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  const lo = 0, hi = 35;
  final out = StringBuffer();
  var i = 0;
  while (true) {
    final ca = i < a.length ? digits.indexOf(a[i]) : lo;
    final cb = b.isEmpty || i >= b.length ? hi + 1 : digits.indexOf(b[i]);
    if (cb - ca > 1) {
      out.write(digits[(ca + cb) ~/ 2]);
      return out.toString();
    }
    out.write(digits[ca < 0 ? 0 : ca]);
    i++;
    if (i > 40) return '${out}i';
  }
}

// ------------------------------------------------------------ AI của dự án
/// Một cuộc trò chuyện AI của dự án (dùng chung một phiên của agent).
class TwAiThread {
  const TwAiThread({required this.id, this.title = '', this.botId = '', this.botName = '', this.updatedAt = 0, this.turnCount = 0});
  final String id, title, botId, botName;
  final int updatedAt, turnCount;
  factory TwAiThread.fromJson(Map m) => TwAiThread(
        id: _s(m['id']),
        title: _s(m['title'], 'Cuộc trò chuyện'),
        botId: _s(m['bot_id']),
        botName: _s(m['bot_name']),
        updatedAt: _i(m['updated_at']),
        turnCount: _i(m['turn_count'] ?? (m['turns'] is List ? (m['turns'] as List).length : 0)),
      );
}

/// Một lượt hỏi trong cuộc trò chuyện: lời người dùng + lượt chạy của agent.
class TwAiTurn {
  TwAiTurn({required this.prompt, this.action, this.at = 0, this.user = '', this.run});
  final String prompt, user;
  final String? action;
  final int at;
  TwRun? run;
  factory TwAiTurn.fromJson(Map m) => TwAiTurn(
        prompt: _s(m['prompt'] ?? m['text']),
        action: _ns(m['action']),
        at: _i(m['at'] ?? m['created_at']),
        user: _s(m['user'] ?? m['started_by']),
        run: m['run'] is Map ? TwRun.fromJson(m['run'] as Map) : null,
      );
}

/// Một thao tác agent đã làm trong lượt chạy (có thể hoàn tác).
class TwAiAction {
  TwAiAction({
    required this.id,
    required this.kind,
    this.summary = '',
    this.targetType = '',
    this.targetId = '',
    this.targetKey = '',
    this.targetTitle = '',
    this.at = 0,
    this.severity = 'normal',
    this.undone = false,
    this.undoable = true,
    this.conflict,
  });
  final String id, kind, summary, targetType, targetId, targetKey, targetTitle, severity;
  final int at;
  bool undone, undoable;
  String? conflict;
  bool get high => severity == 'high';
  factory TwAiAction.fromJson(Map m) {
    final t = m['target'] is Map ? m['target'] as Map : const {};
    return TwAiAction(
      id: _s(m['id']),
      kind: _s(m['kind'] ?? m['type']),
      summary: _s(m['summary'] ?? m['text']),
      targetType: _s(t['type'] ?? m['target_type']),
      targetId: _s(t['id'] ?? m['target_id']),
      targetKey: _s(t['key'] ?? m['target_key']),
      targetTitle: _s(t['title'] ?? m['target_title']),
      at: _i(m['at'] ?? m['created_at']),
      severity: _s(m['severity'], 'normal'),
      undone: _b(m['undone']) || m['undo_state'] == 'done',
      undoable: m['undoable'] != false,
      conflict: _ns(m['conflict'] is Map ? (m['conflict'] as Map)['message'] : m['conflict']),
    );
  }
}

/// Lệnh chờ app của người dùng làm bằng token của chính họ (tạo / gắn nhóm chat).
class TwUserOp {
  const TwUserOp({required this.id, required this.kind, required this.userId, this.projectId = '', this.params = const {}});
  final String id, kind, userId, projectId; // kind: channel_create | channel_link
  final Map<String, dynamic> params;
  factory TwUserOp.fromJson(Map m) => TwUserOp(
        id: _s(m['id']),
        kind: _s(m['kind']),
        userId: _s(m['user_id'] ?? m['user']),
        projectId: _s(m['project_id']),
        params: m['params'] is Map ? (m['params'] as Map).cast<String, dynamic>() : {},
      );
}
