// TeamWork (vn.flygo.teamwork): dữ liệu như máy chủ trả (flygo-chat-server teamwork/README.md). Đọc rộng tay: trường
// thiếu thì lấy mặc định, để app cũ vẫn chạy khi máy chủ thêm trường mới.
import '../todo/model.dart';

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
  });
  final String id;
  String key, name, color, status, owner, myRole;
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
  });
  final String id, taskId, taskKey, botId, botName, startedBy;
  String state; // queued | running | review | done | failed | cancelled | blocked
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
      );
  Map<String, dynamic> toJson() => {
        'id': id,
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
  });
  final String id, taskId, author, authorName, via;
  final String? agentName;
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

/// Kết quả "AI hỗ trợ": chữ, đề xuất việc con, đề xuất người làm + ngày. Không ghi gì cho tới khi người dùng duyệt.
class TwAiResult {
  const TwAiResult({this.text, this.subtasks = const [], this.suggestion});
  final String? text;
  final List<TwAiSubtask> subtasks;
  final TwAiSuggestion? suggestion;
  factory TwAiResult.fromJson(Map j) => TwAiResult(
        text: _ns(j['text']),
        subtasks: [for (final s in _maps(j['subtasks'])) TwAiSubtask.fromJson(s)],
        suggestion: j['suggestion'] is Map ? TwAiSuggestion.fromJson(j['suggestion'] as Map) : null,
      );
}

class TwAiSubtask {
  TwAiSubtask({required this.title, this.assignee, this.start, this.due, this.selected = true});
  String title;
  TwAssignee? assignee;
  DateTime? start, due;
  bool selected;
  factory TwAiSubtask.fromJson(Map m) => TwAiSubtask(
        title: _s(m['title']),
        assignee: m['assignee'] is Map
            ? TwAssignee.fromJson(m['assignee'] as Map)
            : (_ns(m['assignee']) == null ? null : TwAssignee(kind: 'user', id: _s(m['assignee']), name: _s(m['assignee_name'], _s(m['assignee'])))),
        start: parseDay(m['start']),
        due: parseDay(m['due']),
      );
}

class TwAiSuggestion {
  const TwAiSuggestion({this.assignees = const [], this.start, this.due, this.reason = ''});
  final List<TwAssignee> assignees;
  final DateTime? start, due;
  final String reason;
  factory TwAiSuggestion.fromJson(Map m) =>
      TwAiSuggestion(assignees: [for (final a in _maps(m['assignees'])) TwAssignee(kind: _s(a['kind'], 'user'), id: _s(a['id']), name: _s(a['name'], _s(a['id'])))], start: parseDay(m['start']), due: parseDay(m['due']), reason: _s(m['reason']));
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

List<TBlock> blocksFromJson(Object? v) {
  if (v is String) return markdownToBlocks(v);
  return [
    for (final b in _maps(v))
      () {
        final blk = TBlock.fromJson(b);
        final runs = _maps(b['r']);
        for (var i = 0; i < runs.length && i < blk.r.length; i++) {
          final m = runs[i]['m'];
          if (m is Map) blk.r[i].f = blk.r[i].f.copyWith(a: mentionLink(_s(m['k'] ?? m['kind'], 'user'), _s(m['id'])));
        }
        return blk;
      }(),
  ];
}

List<Map<String, dynamic>> blocksToJson(List<TBlock> blocks) => [
      for (final b in blocks)
        () {
          final j = b.toJson();
          final runs = (j['r'] as List).cast<Map<String, dynamic>>();
          for (final r in runs) {
            final m = mentionOf(r['a'] as String?);
            if (m != null) {
              r.remove('a');
              r['m'] = {'k': m.$1, 'id': m.$2};
            }
          }
          return j;
        }(),
    ];

/// Chữ thuần của nội dung (tìm kiếm, xem trước).
String blocksText(List<TBlock> blocks) => blocks.map((b) => b.text).where((s) => s.isNotEmpty).join('\n');

/// Markdown đơn giản → khối (dùng khi máy chủ trả chữ thay cho khối, hoặc AI soạn).
List<TBlock> markdownToBlocks(String md) {
  final out = <TBlock>[];
  for (final line in md.replaceAll('\r', '').split('\n')) {
    final l = line.trimRight();
    if (l.isEmpty) continue;
    String t = 'p';
    var s = l;
    bool done = false;
    final ck = RegExp(r'^\s*[-*] \[( |x|X)\] ').firstMatch(s);
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
    } else if (RegExp(r'^\s*[-*•] ').hasMatch(s)) {
      t = 'ul';
      s = s.replaceFirst(RegExp(r'^\s*[-*•] '), '');
    } else if (RegExp(r'^\s*\d+[.)] ').hasMatch(s)) {
      t = 'ol';
      s = s.replaceFirst(RegExp(r'^\s*\d+[.)] '), '');
    } else if (s.startsWith('> ')) {
      t = 'quote';
      s = s.substring(2);
    } else if (s == '---') {
      out.add(TBlock(t: 'hr'));
      continue;
    }
    out.add(TBlock(t: t, r: _inline(s), done: done));
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

/// Khối → Markdown (bản giao việc gửi agent).
String blocksToMarkdown(List<TBlock> blocks) {
  final out = <String>[];
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    final text = b.r.map((r) {
      var x = r.x;
      if (r.f.c) x = '`$x`';
      if (r.f.b) x = '**$x**';
      if (r.f.i) x = '*$x*';
      return x;
    }).join();
    final ind = '  ' * b.ind;
    out.add(switch (b.t) {
      'h1' => '# $text',
      'h2' => '## $text',
      'h3' => '### $text',
      'ul' => '$ind- $text',
      'ol' => '${ind}1. $text',
      'check' => '$ind- [${b.done ? 'x' : ' '}] $text',
      'quote' => '> $text',
      'code' => '`$text`',
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
