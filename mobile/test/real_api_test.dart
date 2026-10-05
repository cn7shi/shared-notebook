import 'package:flutter_test/flutter_test.dart';
import 'package:shared_notebook/application/read_controllers.dart';
import 'package:shared_notebook/application/work_controller.dart';
import 'package:shared_notebook/data/api.dart';
import 'package:shared_notebook/domain/models.dart';
import 'package:uuid/uuid.dart';

import 'support.dart';

class LoseOneResponse extends HttpNotebookRepository {
  bool lose = true;
  LoseOneResponse(super.api);
  @override
  Future<MutationResult> execute(Command c) async {
    final result = await super.execute(c);
    if (lose) {
      lose = false;
      throw const ApiFailure('NETWORK_ERROR', '测试：响应丢失');
    }
    return result;
  }
}

void main() {
  const base = String.fromEnvironment('TEST_API_BASE_URL');
  group(
    'real API',
    () {
      late ApiClient api;
      late HttpNotebookRepository repo;
      late Workspace w;
      late Session user;
      Command command(String kind, Json refs, Json body) =>
          Command(const Uuid().v4(), kind, refs, body);
      Future<String> role() async => (await repo.execute(
        command('character', {}, {
          'name': '小林',
          'background': '虚构角色，喜欢散步',
          'style': '温和',
        }),
      )).id;
      Future<String> entry([String body = '今天看到了花 📝']) async =>
          (await repo.execute(
            command('entry', {}, {'title': '一天的记录', 'body': body}),
          )).id;
      setUpAll(() async {
        api = ApiClient(base);
        user = await api.authenticate(
          'mobile-${DateTime.now().microsecondsSinceEpoch}@example.test',
          'mobile-integration-password',
          register: true,
        );
        api.useToken(user.token);
        repo = HttpNotebookRepository(api);
        w = Workspace(repo, TestStore(), user.userId);
      });
      tearDownAll(() async {
        await api.logout();
        api.client.close();
      });
      test('private entry, explicit share, edit invalidation and old replay stay revoked', () async {
        final r = await role(), e = await entry();
        expect((await repo.grants(r)).items, isEmpty);
        final share = command(
          'share',
          {'characterId': r, 'entryId': e},
          {'active': true, 'entryRevision': 1, 'revision': 0},
        );
        await repo.execute(share);
        await repo.execute(
          command(
            'entry',
            {'id': e},
            {'title': '一天的记录', 'body': '改写后的中文\n与 emoji 📝', 'revision': 1},
          ),
        );
        expect((await repo.entry(e)).revision, 2);
        expect((await repo.grants(r)).items.single.active, isFalse);
        expect((await repo.execute(share)).message, '当前未分享给这个角色');
        expect((await repo.grants(r)).items.single.active, isFalse);
      });
      test('memory creation, revision update and revocation invalidate derived background', () async {
        final r = await role(), e = await entry();
        await repo.execute(
          command(
            'share',
            {'characterId': r, 'entryId': e},
            {'active': true, 'entryRevision': 1, 'revision': 0},
          ),
        );
        final fields = {
          'body': '喜欢看花',
          'sources': [
            {'entryId': e, 'revision': 1},
          ],
          'active': true,
        };
        final m = await repo.execute(
          command('memory', {'characterId': r}, fields),
        );
        await repo.execute(
          command(
            'memory',
            {'id': m.id, 'characterId': r},
            {...fields, 'body': '喜欢散步看花', 'revision': 1},
          ),
        );
        final copy = await w.draft(
          'memory',
          '记忆',
          id: m.id,
          refs: {'characterId': r},
          fields: fields,
          revision: 1,
        );
        expect((await repo.latest(copy)).revision, 2);
        await repo.execute(
          command(
            'share',
            {'characterId': r, 'entryId': e},
            {'active': false, 'entryRevision': 1, 'revision': 1},
          ),
        );
        expect((await repo.memories(r)).items.single.active, isFalse);
      });
      test(
        'lost create response then concurrent edit is preserved for comparison',
        () async {
          final disk = TestStore(),
              loss = LoseOneResponse(api),
              space = Workspace(LoseOneResponse(api), TestStore(), user.userId);
          final c = WorkController(
            loss,
            disk,
            await space.draft('entry', '日记'),
          );
          c.edit({'title': '响应恢复', 'body': '本机原文'});
          expect(await c.submit(), isNull);
          final key = c.copy.pending!.key;
          final receipt = await api.request('GET', '/operations/$key');
          await repo.execute(
            command(
              'entry',
              {'id': receipt['resourceId']},
              {'title': '云端新标题', 'body': '另一端的最新内容', 'revision': 1},
            ),
          );
          final restored = WorkController(
            repo,
            disk,
            (await disk.list(user.userId)).single,
          );
          expect(await restored.submit(), isNull);
          expect(restored.conflict, isTrue);
          expect(restored.copy.fields['body'], '本机原文');
          final latest = await restored.latest();
          expect(latest.fields!['body'], '另一端的最新内容');
          await restored.resolve(latest, keepLocal: false);
          expect(await disk.list(user.userId), isEmpty);
          c.dispose();
          restored.dispose();
        },
      );
      test('linked chat retains message and exposes disabled-provider failure truthfully', () async {
        expect(await repo.capability(), isFalse);
        final r = await role(), e = await entry();
        await repo.execute(
          command(
            'share',
            {'characterId': r, 'entryId': e},
            {'active': true, 'entryRevision': 1, 'revision': 0},
          ),
        );
        final conv = await repo.execute(
          command('conversation', {'characterId': r}, {'entryId': e}),
        );
        final chat = ChatController(w, conv.id);
        await chat.refresh();
        expect(chat.linkedEntry!.id, e);
        chat.composer!.edit({'body': '未发送的话'});
        expect(await chat.send(), isNull);
        expect((await repo.messages(conv.id)).items, isEmpty);
        // Exercise the server's persisted failure path directly; UI refuses new sends while disabled.
        final result = await repo.execute(
          command(
            'message',
            {'conversationId': conv.id},
            {'body': '测试服务端失败保留'},
          ),
        );
        Job job = await repo.job(result.id);
        for (var i = 0; i < 40 && job.pending; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          job = await repo.job(result.id);
        }
        expect(job.status, 'failed');
        expect(job.errorCode, 'PROVIDER_NOT_CONFIGURED');
        expect((await repo.messages(conv.id)).items.single.body, '测试服务端失败保留');
        expect((await repo.entries(characterId: r)).items, isEmpty);
        chat.dispose();
      });
      test('grant listing beyond first page is fully checked', () async {
        final r = await role();
        String? first;
        for (var i = 0; i < 31; i++) {
          final e = await entry('分页记录 $i');
          first ??= e;
          await repo.execute(
            command(
              'share',
              {'characterId': r, 'entryId': e},
              {'active': true, 'entryRevision': 1, 'revision': 0},
            ),
          );
        }
        final grants = await everyPage(
          (cursor) => repo.grants(r, cursor: cursor),
        );
        expect(grants, hasLength(31));
        expect(grants.any((g) => g.entryId == first), isTrue);
        final c = EntryController(repo, first!);
        await c.refresh();
        expect(c.sharesKnown, isTrue);
        expect(
          c.shares.singleWhere((s) => s.character.id == r).grant!.active,
          isTrue,
        );
        c.dispose();
      });
    },
    skip: base.isEmpty
        ? 'Set TEST_API_BASE_URL to run against the real local backend.'
        : false,
  );
}
