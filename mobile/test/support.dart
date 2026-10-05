import 'package:shared_notebook/domain/models.dart';
import 'package:shared_notebook/domain/repositories.dart';

class TestStore implements WorkStore {
  final records = <String, Json>{};
  bool fail = false, failRemove = false;
  @override
  Future<List<WorkingCopy>> list(String ownerId) async => records.values
      .map((j) => WorkingCopy.fromJson(clone(j)))
      .where((c) => c.ownerId == ownerId)
      .toList();
  @override
  Future<void> put(WorkingCopy copy) async {
    if (fail) throw StateError('disk full');
    records[copy.localId] = clone(copy.toJson());
  }

  @override
  Future<void> remove(String id) async {
    if (fail || failRemove) throw StateError('disk full');
    records.remove(id);
  }
}

class FakeNotebook implements NotebookRepository {
  bool available = false, loseResponse = false, failGrants = false;
  int writes = 0, jobsRead = 0;
  final commands = <Command>[];
  Json cloud = {'title': '日记', 'body': '云端原文'};
  int revision = 1;
  final characterValue = const Character('role', '小林', '虚构角色', '温和', 1, 1);
  final entryValue = Entry(
    'entry',
    '一天的记录',
    '私人内容',
    'user',
    null,
    1,
    null,
    DateTime.utc(2026, 10, 5),
  );
  final conversationValue = Conversation(
    'conversation',
    'role',
    null,
    DateTime.utc(2026, 10, 5),
  );
  List<Job> jobValues = [];
  List<Message> messageValues = [];
  @override
  Future<bool> capability() async => available;
  @override
  Future<Page<Character>> characters({String? cursor}) async =>
      Page([characterValue], null);
  @override
  Future<Character> character(String id) async => characterValue;
  @override
  Future<Page<Entry>> entries({String? characterId, String? cursor}) async =>
      Page(characterId == null ? [entryValue] : [], null);
  @override
  Future<Entry> entry(String id) async => entryValue;
  @override
  Future<Page<Grant>> grants(String characterId, {String? cursor}) async {
    if (failGrants) throw const ApiFailure('NETWORK_ERROR', '读取失败');
    return cursor == null
        ? const Page([], 'next')
        : const Page([Grant('grant', 'role', 'entry', 1, 1, true)], null);
  }

  @override
  Future<Page<Conversation>> conversations(
    String characterId, {
    String? cursor,
  }) async => Page([conversationValue], null);
  @override
  Future<Conversation> conversation(String id) async => conversationValue;
  @override
  Future<Page<Message>> messages(String id, {String? cursor}) async =>
      Page(messageValues, null);
  @override
  Future<Page<Memory>> memories(String characterId, {String? cursor}) async =>
      const Page([], null);
  @override
  Future<Page<Job>> jobs(String characterId, {String? cursor}) async =>
      Page(jobValues, null);
  @override
  Future<Job> job(String id) async {
    jobsRead++;
    return jobValues.firstWhere((j) => j.id == id);
  }

  @override
  Future<MutationResult> execute(Command c) async {
    commands.add(c);
    if (!commands.take(commands.length - 1).any((v) => v.key == c.key)) {
      writes++;
      if (c.kind == 'entry') {
        cloud = clone(c.body)..remove('revision');
      }
    }
    if (loseResponse) {
      loseResponse = false;
      throw const ApiFailure('NETWORK_ERROR', '响应丢失');
    }
    if (c.kind == 'entry') {
      return MutationResult('entry', revision: revision, fields: clone(cloud));
    }
    return const MutationResult('result', message: '当前未分享给这个角色');
  }

  @override
  Future<MutationResult> latest(WorkingCopy c) async =>
      MutationResult('entry', revision: revision, fields: clone(cloud));
}
