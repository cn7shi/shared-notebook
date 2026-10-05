import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_notebook/application/work_controller.dart';
import 'package:shared_notebook/presentation/common.dart';
import 'package:shared_notebook/presentation/editor_screen.dart';
import 'package:shared_notebook/presentation/entry_screen.dart';
import 'package:shared_notebook/presentation/chat_screen.dart';

import 'support.dart';

class PollPage extends StatefulWidget {
  final VoidCallback poll;
  const PollPage(this.poll, {super.key});
  @override
  State<PollPage> createState() => _PollPageState();
}

class _PollPageState extends State<PollPage> with VisibleRefresh<PollPage> {
  @override
  Future<void> refreshVisible() async => widget.poll();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('covered')),
        ),
      ),
      child: const Text('cover'),
    ),
  );
}

void main() {
  testWidgets('sharing confirmation is idle and cancelling never writes', (
    t,
  ) async {
    final repo = FakeNotebook();
    await t.pumpWidget(
      MaterialApp(
        home: EntryScreen(
          workspace: Workspace(repo, TestStore(), 'user'),
          id: 'entry',
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('撤回分享'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('撤回分享'));
    await t.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
    expect(find.text('撤回给小林的分享？'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(repo.writes, 0);
    await t.tap(find.text('暂不'));
    await t.pumpAndSettle();
    expect(repo.writes, 0);
    expect(find.text('当前版本已分享'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    '360px editor handles keyboard and preserves Chinese input locally',
    (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      final disk = TestStore(), repo = FakeNotebook();
      final w = Workspace(repo, disk, 'user');
      final c = w.control(await w.draft('entry', '写日记'));
      await t.pumpWidget(MaterialApp(home: EditorScreen(controller: c)));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('edit-title')),
        '中文与 emoji 📝',
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('edit-body')), '第一行\n第二行');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect((await disk.list('user')).single.fields['body'], '第一行\n第二行');
      expect(repo.writes, 0);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('failed sharing read shows unknown and never a share button', (
    t,
  ) async {
    final repo = FakeNotebook()..failGrants = true;
    await t.pumpWidget(
      MaterialApp(
        home: EntryScreen(
          workspace: Workspace(repo, TestStore(), 'user'),
          id: 'entry',
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('分享状态尚未确认，请刷新。'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('当前版本未分享'), findsNothing);
    expect(find.text('分享这篇日记'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'unconfigured chat saves input with disabled send and no fake response',
    (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeNotebook(), disk = TestStore();
      await t.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: ChatScreen(
            workspace: Workspace(repo, disk, 'user'),
            id: 'conversation',
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('message-input')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(find.byKey(const ValueKey('message-input')), '以后想说的话');
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('发送'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        t
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('发送'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect((await disk.list('user')).single.fields['body'], '以后想说的话');
      expect(repo.writes, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('polling stops when another route covers screen and app pauses', (
    t,
  ) async {
    var polls = 0;
    await t.pumpWidget(
      MaterialApp(navigatorObservers: [routes], home: PollPage(() => polls++)),
    );
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 5));
    expect(polls, 1);
    await t.tap(find.text('cover'));
    await t.pumpAndSettle();
    final before = polls;
    await t.pump(const Duration(seconds: 15));
    expect(polls, before);
    Navigator.of(t.element(find.text('covered'))).pop();
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = polls;
    await t.pump(const Duration(seconds: 15));
    expect(polls, paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(polls, greaterThan(paused));
    await t.pumpWidget(const SizedBox());
  });
}
