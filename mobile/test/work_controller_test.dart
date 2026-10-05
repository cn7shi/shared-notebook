import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_notebook/application/work_controller.dart';
import 'package:shared_notebook/application/read_controllers.dart';
import 'package:shared_notebook/data/local_store.dart';
import 'package:shared_notebook/domain/models.dart';

import 'support.dart';

void main() {
  late FakeNotebook repo;
  late TestStore disk;
  late Workspace w;
  setUp(() {
    repo = FakeNotebook();
    disk = TestStore();
    w = Workspace(repo, disk, 'owner');
  });
  Future<WorkController> entry() async {
    final c = w.control(await w.draft('entry', '日记'));
    c.edit({'title': '日记', 'body': '本机输入'});
    await c.persist();
    return c;
  }

  test('failed durable write never reaches HTTP', () async {
    final c = await entry();
    disk.fail = true;
    expect(await c.submit(), isNull);
    expect(repo.writes, 0);
    expect(c.localSaved, isFalse);
    expect(c.copy.fields['body'], '本机输入');
    c.dispose();
  });
  test(
    'lost create response resumes same command after restart, no duplicate',
    () async {
      final c = await entry();
      repo.loseResponse = true;
      expect(await c.submit(), isNull);
      final key = c.copy.pending!.key;
      c.dispose();
      final resumed = w.control((await disk.list('owner')).single);
      expect(await resumed.submit(), isNotNull);
      expect(repo.writes, 1);
      expect(repo.commands.last.key, key);
      expect(await disk.list('owner'), isEmpty);
      resumed.dispose();
    },
  );
  test('replay of committed create with newer remote text requires explicit comparison', () async {
    final c = await entry();
    repo.loseResponse = true;
    await c.submit();
    repo.cloud = {'title': '日记', 'body': '另一处的修改'};
    repo.revision = 2;
    expect(await c.submit(), isNull);
    expect(c.conflict, isTrue);
    expect(c.copy.fields['body'], '本机输入');
    expect(c.canEdit, isFalse);
    await c.resolve(await c.latest(), keepLocal: false);
    expect(c.copy.fields['body'], '另一处的修改');
    expect(repo.writes, 1);
    expect(c.copy.pending, isNull);
    c.dispose();
  });
  test('explicit keep local uses latest revision and a new command', () async {
    final c = await entry();
    repo.loseResponse = true;
    await c.submit();
    final original = c.copy.pending!.key;
    repo.cloud = {'title': '日记', 'body': '别处修改'};
    repo.revision = 2;
    await c.submit();
    await c.resolve(await c.latest(), keepLocal: true);
    expect(repo.commands.last.key, isNot(original));
    expect(repo.commands.last.body['revision'], 2);
    expect(c.result, isNotNull);
    expect(repo.cloud['body'], '本机输入');
    c.dispose();
  });
  test(
    'acknowledgement disk failure retains command even for nontext action',
    () async {
      final c = w.control(
        w.action(
          'share',
          '分享',
          {'characterId': 'role', 'entryId': 'entry'},
          {'active': true, 'entryRevision': 1, 'revision': 0},
        ),
      );
      final key = c.copy.pending!.key;
      disk.failRemove = true;
      expect(await c.submit(), isNull);
      expect(c.copy.pending!.key, key);
      disk.failRemove = false;
      final resumed = w.control((await disk.list('owner')).single);
      final r = await resumed.submit();
      expect(repo.writes, 1);
      expect(r!.message, '当前未分享给这个角色');
      c.dispose();
      resumed.dispose();
    },
  );
  test('disabled provider keeps text but never queues a new message', () async {
    final c = w.control(
      await w.draft(
        'message',
        '想说的话',
        refs: {'conversationId': 'conversation'},
      ),
    );
    c.edit({'body': '今天很开心'});
    expect(await c.submit(), isNull);
    expect(repo.writes, 0);
    expect(c.copy.pending, isNull);
    expect((await disk.list('owner')).single.fields['body'], '今天很开心');
    await expectLater(
      w.generation('diary', '日记', {'characterId': 'role'}),
      throwsA(isA<ApiFailure>()),
    );
    c.dispose();
  });
  test('unknown message result replays original request even if provider later disabled', () async {
    repo.available = true;
    repo.loseResponse = true;
    final c = w.control(
      await w.draft('message', '话', refs: {'conversationId': 'conversation'}),
    );
    c.edit({'body': '一句话'});
    await c.submit();
    final key = c.copy.pending!.key;
    repo.available = false;
    expect(await c.submit(), isNotNull);
    expect(repo.commands.last.key, key);
    expect(repo.writes, 1);
    expect(c.copy.fields['body'], '');
    c.dispose();
  });
  test('owner-scoped Sembast copies survive close and reopen', () async {
    final db = await databaseFactoryMemory.openDatabase('owners');
    final store = LocalWorkStore(db);
    for (final owner in ['a', 'b']) {
      final space = Workspace(repo, store, owner);
      final c = space.control(await space.draft('entry', '日记'));
      c.edit({'body': owner});
      await c.persist();
      c.dispose();
    }
    await db.close();
    final reopened = await databaseFactoryMemory.openDatabase('owners');
    final copies = await LocalWorkStore(reopened).list('a');
    expect(copies, hasLength(1));
    expect(copies.single.fields['body'], 'a');
    await reopened.close();
  });
  test(
    'grant on later page is visible; failed refresh never implies private',
    () async {
      final c = EntryController(repo, 'entry');
      await c.refresh();
      expect(c.sharesKnown, isTrue);
      expect(c.shares.single.grant!.active, isTrue);
      repo.failGrants = true;
      await c.refresh();
      expect(c.sharesKnown, isFalse);
      expect(c.error, isNotNull);
      expect(
        () => c.share(w, c.shares.single, false),
        throwsA(isA<ApiFailure>()),
      );
      c.dispose();
    },
  );
  test('cyclic pagination fails instead of claiming complete state', () async {
    await expectLater(
      everyPage<int>((cursor) async => const Page([1], 'repeat')),
      throwsA(isA<ApiFailure>()),
    );
  });
  test(
    'job polling updates terminal state without dropping loaded history',
    () async {
      final pending = Job(
        'job',
        'role',
        'diary',
        'running',
        null,
        null,
        null,
        DateTime.utc(2026),
      );
      repo.jobValues = [pending];
      final c = CharacterController(repo, 'role');
      await c.refresh();
      repo.jobValues = [
        Job(
          'job',
          'role',
          'diary',
          'failed',
          null,
          null,
          'PROVIDER_NOT_CONFIGURED',
          DateTime.utc(2026),
        ),
      ];
      await c.poll();
      expect(c.jobs.items.single.status, 'failed');
      expect(c.jobs.items.single.explanation, contains('未生成内容'));
      final reads = repo.jobsRead;
      await c.poll();
      expect(repo.jobsRead, reads);
      c.dispose();
    },
  );
}
