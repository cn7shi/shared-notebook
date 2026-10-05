import 'dart:convert';

typedef Json = Map<String, dynamic>;
Json clone(Json value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));

class ApiFailure implements Exception {
  final String code, message;
  const ApiFailure(this.code, this.message);
}

class Session {
  final String token, userId, email;
  const Session(this.token, this.userId, this.email);
  factory Session.fromJson(Json j) =>
      Session(j['accessToken'], j['user']['id'], j['user']['email']);
  Json toJson() => {
    'accessToken': token,
    'user': {'id': userId, 'email': email},
  };
}

class Page<T> {
  final List<T> items;
  final String? next;
  const Page(this.items, this.next);
}

class Character {
  final String id, name, background, style;
  final int revision, contextVersion;
  const Character(
    this.id,
    this.name,
    this.background,
    this.style,
    this.revision,
    this.contextVersion,
  );
  factory Character.fromJson(Json j) => Character(
    j['id'],
    j['name'],
    j['background'],
    j['style'],
    j['revision'],
    j['contextVersion'],
  );
  Json get fields => {'name': name, 'background': background, 'style': style};
}

class Entry {
  final String id, title, body, author;
  final String? characterId;
  final int revision;
  final int? contextVersion;
  final DateTime createdAt;
  Entry(
    this.id,
    this.title,
    this.body,
    this.author,
    this.characterId,
    this.revision,
    this.contextVersion,
    this.createdAt,
  );
  factory Entry.fromJson(Json j) => Entry(
    j['id'],
    j['title'],
    j['body'],
    j['author'],
    j['characterId'],
    j['revision'],
    j['contextVersion'],
    DateTime.parse(j['createdAt']),
  );
  Json get fields => {'title': title, 'body': body};
}

class Grant {
  final String id, characterId, entryId;
  final int revision, entryRevision;
  final bool active;
  const Grant(
    this.id,
    this.characterId,
    this.entryId,
    this.revision,
    this.entryRevision,
    this.active,
  );
  factory Grant.fromJson(Json j) => Grant(
    j['id'],
    j['characterId'],
    j['entryId'],
    j['revision'],
    j['entryRevision'],
    j['active'],
  );
  bool applies(Entry e) => active && entryRevision == e.revision;
}

class Conversation {
  final String id, characterId;
  final String? entryId;
  final DateTime createdAt;
  Conversation(this.id, this.characterId, this.entryId, this.createdAt);
  factory Conversation.fromJson(Json j) => Conversation(
    j['id'],
    j['characterId'],
    j['entryId'],
    DateTime.parse(j['createdAt']),
  );
}

class Message {
  final String id, role, body;
  final int sequence;
  final DateTime createdAt;
  Message(this.id, this.role, this.body, this.sequence, this.createdAt);
  factory Message.fromJson(Json j) => Message(
    j['id'],
    j['role'],
    j['body'],
    j['sequence'],
    DateTime.parse(j['createdAt']),
  );
}

class Memory {
  final String id, characterId, body;
  final List<Json> sources;
  final int revision;
  final bool active;
  const Memory(
    this.id,
    this.characterId,
    this.body,
    this.sources,
    this.revision,
    this.active,
  );
  factory Memory.fromJson(Json j) => Memory(
    j['id'],
    j['characterId'],
    j['body'],
    (j['sources'] as List).map((v) => Json.from(v)).toList(),
    j['revision'],
    j['active'],
  );
  Json get fields => {'body': body, 'sources': sources, 'active': active};
}

class Job {
  final String id, characterId, kind, status;
  final String? conversationId, resultId, errorCode;
  final DateTime createdAt;
  Job(
    this.id,
    this.characterId,
    this.kind,
    this.status,
    this.conversationId,
    this.resultId,
    this.errorCode,
    this.createdAt,
  );
  factory Job.fromJson(Json j) => Job(
    j['id'],
    j['characterId'],
    j['kind'],
    j['status'],
    j['conversationId'],
    j['resultId'],
    j['errorCode'],
    DateTime.parse(j['createdAt']),
  );
  bool get pending => status == 'pending' || status == 'running';
  bool get retryable =>
      status == 'failed' &&
      !['STALE_TURN', 'CONTEXT_CHANGED'].contains(errorCode);
  String get explanation => switch (status) {
    'pending' => '等待处理',
    'running' => '正在生成',
    'succeeded' => '已完成',
    'cancelled' => '分享或背景已变化，这次生成已取消',
    _ => switch (errorCode) {
      'PROVIDER_NOT_CONFIGURED' => '模型服务尚未接入，未生成内容',
      'PROVIDER_TIMEOUT' => '生成超时，可明确重试',
      'WORKER_INTERRUPTED' => '任务中断；重试可能再次调用模型服务',
      'INVALID_MODEL_RESULT' => '返回内容无效，未发布',
      _ => '生成失败，原消息仍保留',
    },
  };
}

class Command {
  final String key, kind;
  final Json refs, body;
  Command(this.key, this.kind, this.refs, this.body);
  factory Command.fromJson(Json j) =>
      Command(j['key'], j['kind'], Json.from(j['refs']), Json.from(j['body']));
  Json toJson() => {'key': key, 'kind': kind, 'refs': refs, 'body': body};
}

class MutationResult {
  final String id;
  final int? revision;
  final Json? fields;
  final String message;
  const MutationResult(
    this.id, {
    this.revision,
    this.fields,
    this.message = '已保存',
  });
}

class WorkingCopy {
  final String localId, ownerId, kind;
  String label;
  String? resourceId;
  final Json refs;
  Json fields, saved;
  int revision;
  Command? pending;
  WorkingCopy({
    required this.localId,
    required this.ownerId,
    required this.kind,
    required this.label,
    this.resourceId,
    Json? refs,
    Json? fields,
    Json? saved,
    this.revision = 0,
    this.pending,
  }) : refs = refs ?? {},
       fields = fields ?? {},
       saved = saved ?? {};
  bool get dirty => pending != null || jsonEncode(fields) != jsonEncode(saved);
  factory WorkingCopy.fromJson(Json j) => WorkingCopy(
    localId: j['localId'],
    ownerId: j['ownerId'],
    kind: j['kind'],
    label: j['label'],
    resourceId: j['resourceId'],
    refs: Json.from(j['refs']),
    fields: Json.from(j['fields']),
    saved: Json.from(j['saved']),
    revision: j['revision'],
    pending: j['pending'] == null
        ? null
        : Command.fromJson(Json.from(j['pending'])),
  );
  Json toJson() => {
    'localId': localId,
    'ownerId': ownerId,
    'kind': kind,
    'label': label,
    'resourceId': resourceId,
    'refs': refs,
    'fields': fields,
    'saved': saved,
    'revision': revision,
    'pending': pending?.toJson(),
  };
}
