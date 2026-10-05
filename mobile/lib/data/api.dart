import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/repositories.dart';

class ApiClient implements AccountRepository {
  final String baseUrl;
  final http.Client client;
  String? _token;
  ApiClient(this.baseUrl, {http.Client? client})
    : client = client ?? http.Client();
  @override
  void useToken(String? token) => _token = token;
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? key,
  }) async {
    try {
      final request = http.Request(method, Uri.parse('$baseUrl/api/v1$path'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
        'Idempotency-Key': ?key,
      });
      if (body != null) request.body = jsonEncode(body);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 204) return {};
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode >= 400) {
        final error = decoded['error'];
        throw ApiFailure(
          error is Map ? error['code'] ?? 'SERVER_ERROR' : 'SERVER_ERROR',
          error is Map ? error['message'] ?? '服务暂不可用。' : '服务暂不可用。',
        );
      }
      if (decoded['data'] is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded['data']);
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure('NETWORK_ERROR', '连接超时，草稿会留在本机。');
    } on http.ClientException {
      throw const ApiFailure('NETWORK_ERROR', '连接失败，请检查网络后重试。');
    } on FormatException {
      throw const ApiFailure('SERVER_ERROR', '服务响应异常，请稍后重试。');
    }
  }

  @override
  Future<Session> authenticate(
    String email,
    String password, {
    required bool register,
  }) async => Session.fromJson(
    await request(
      'POST',
      register ? '/auth/register' : '/auth/login',
      body: {'email': email.trim(), 'password': password},
    ),
  );
  @override
  Future<void> logout() async {
    await request('POST', '/auth/logout');
  }
}

class HttpNotebookRepository implements NotebookRepository {
  final ApiClient api;
  HttpNotebookRepository(this.api);
  Future<Page<T>> _page<T>(
    String path,
    T Function(Json) decode,
    String? cursor,
  ) async {
    final j = await api.request(
      'GET',
      '$path?limit=30${cursor == null ? '' : '&cursor=${Uri.encodeComponent(cursor)}'}',
    );
    return Page(
      (j['items'] as List).map((e) => decode(Json.from(e))).toList(),
      j['nextCursor'],
    );
  }

  @override
  Future<bool> capability() async =>
      (await api.request('GET', '/capabilities'))['generationAvailable'] ==
      true;
  @override
  Future<Page<Character>> characters({String? cursor}) =>
      _page('/characters', Character.fromJson, cursor);
  @override
  Future<Character> character(String id) async =>
      Character.fromJson(await api.request('GET', '/characters/$id'));
  @override
  Future<Page<Entry>> entries({String? characterId, String? cursor}) => _page(
    characterId == null ? '/entries' : '/characters/$characterId/entries',
    Entry.fromJson,
    cursor,
  );
  @override
  Future<Entry> entry(String id) async =>
      Entry.fromJson(await api.request('GET', '/entries/$id'));
  @override
  Future<Page<Grant>> grants(String characterId, {String? cursor}) =>
      _page('/characters/$characterId/grants', Grant.fromJson, cursor);
  @override
  Future<Page<Conversation>> conversations(
    String characterId, {
    String? cursor,
  }) => _page(
    '/characters/$characterId/conversations',
    Conversation.fromJson,
    cursor,
  );
  @override
  Future<Conversation> conversation(String id) async =>
      Conversation.fromJson(await api.request('GET', '/conversations/$id'));
  @override
  Future<Page<Message>> messages(String id, {String? cursor}) =>
      _page('/conversations/$id/messages', Message.fromJson, cursor);
  @override
  Future<Page<Memory>> memories(String characterId, {String? cursor}) =>
      _page('/characters/$characterId/memories', Memory.fromJson, cursor);
  @override
  Future<Page<Job>> jobs(String characterId, {String? cursor}) =>
      _page('/characters/$characterId/jobs', Job.fromJson, cursor);
  @override
  Future<Job> job(String id) async =>
      Job.fromJson(await api.request('GET', '/jobs/$id'));
  @override
  Future<MutationResult> execute(Command c) async {
    final id = c.refs['id'], character = c.refs['characterId'];
    final (method, path) = switch (c.kind) {
      'entry' => (
        id == null ? 'POST' : 'PUT',
        id == null ? '/entries' : '/entries/$id',
      ),
      'character' => (
        id == null ? 'POST' : 'PUT',
        id == null ? '/characters' : '/characters/$id',
      ),
      'memory' => (
        id == null ? 'POST' : 'PUT',
        '/characters/$character/memories${id == null ? '' : '/$id'}',
      ),
      'share' => ('PUT', '/characters/$character/grants/${c.refs['entryId']}'),
      'conversation' => ('POST', '/characters/$character/conversations'),
      'message' => (
        'POST',
        '/conversations/${c.refs['conversationId']}/messages',
      ),
      'diary' => ('POST', '/characters/$character/diary-jobs'),
      'retry' => ('POST', '/jobs/$id/retry'),
      _ => throw const ApiFailure('INVALID_OPERATION', '无法识别本机请求，请保留内容。'),
    };
    final j = await api.request(method, path, key: c.key, body: c.body);
    return _result(c.kind, j);
  }

  MutationResult _result(String kind, Json j) => switch (kind) {
    'entry' => MutationResult(
      j['id'],
      revision: j['revision'],
      fields: Entry.fromJson(j).fields,
    ),
    'character' => MutationResult(
      j['id'],
      revision: j['revision'],
      fields: Character.fromJson(j).fields,
    ),
    'memory' => MutationResult(
      j['id'],
      revision: j['revision'],
      fields: Memory.fromJson(j).fields,
    ),
    'share' => MutationResult(
      j['id'],
      message: j['active'] == true ? '当前已分享给这个角色' : '当前未分享给这个角色',
    ),
    'message' ||
    'diary' ||
    'retry' => MutationResult(j['id'], message: Job.fromJson(j).explanation),
    _ => MutationResult(j['id']),
  };
  @override
  Future<MutationResult> latest(WorkingCopy copy) async {
    var id = copy.resourceId;
    if (id == null && copy.pending != null) {
      id = (await api.request(
        'GET',
        '/operations/${copy.pending!.key}',
      ))['resourceId'];
    }
    if (id == null) throw const ApiFailure('NOT_FOUND', '尚未找到云端记录。');
    if (copy.kind == 'entry') {
      final value = await entry(id);
      return MutationResult(id, revision: value.revision, fields: value.fields);
    }
    if (copy.kind == 'character') {
      final value = await character(id);
      return MutationResult(id, revision: value.revision, fields: value.fields);
    }
    if (copy.kind == 'memory') {
      String? cursor;
      do {
        final page = await memories(copy.refs['characterId'], cursor: cursor);
        for (final m in page.items) {
          if (m.id == id) {
            return MutationResult(m.id, revision: m.revision, fields: m.fields);
          }
        }
        cursor = page.next;
      } while (cursor != null);
    }
    throw const ApiFailure('NOT_FOUND', '尚未找到云端记录。');
  }
}
