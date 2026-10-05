import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_notebook/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  Future<void> until(WidgetTester t, Finder finder) async {
    final end = DateTime.now().add(const Duration(seconds: 35));
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(finder, findsWidgets);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> tap(WidgetTester t, String label) async {
    final finder = find.text(label);
    t.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 20,
    );
    await Scrollable.ensureVisible(t.element(finder), alignment: 0.5);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Future<void> back(WidgetTester t) async {
    await t.tap(find.byTooltip('返回'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Android: role, private diary, explicit sharing, memory, edit revocation, linked chat and local recovery',
    (t) async {
      await app.main();
      await until(t, find.text('打开双方记事本'));
      await t.tap(find.text('第一次来，创建账户'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byType(TextFormField).at(0),
        'android-${DateTime.now().microsecondsSinceEpoch}@example.test',
      );
      await t.enterText(
        find.byType(TextFormField).at(1),
        'android-test-password-only',
      );
      await t.ensureVisible(find.text('创建我的账户'));
      await t.tap(find.text('创建我的账户'));
      await until(t, find.text('你的生活，由你决定分享给谁。'));
      await t.tap(find.text('角色'));
      await t.pumpAndSettle();
      await t.tap(find.text('创建角色'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('edit-name')), '小林');
      await t.enterText(
        find.byKey(const ValueKey('edit-background')),
        '虚构角色，住在有花园的小城。',
      );
      await t.enterText(
        find.byKey(const ValueKey('edit-style')),
        '简短温和，不替我做决定。',
      );
      await t.tap(find.text('保存'));
      await until(t, find.text('虚构角色'));
      expect(
        t
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('生成角色日记'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await back(t);
      await t.tap(find.text('我的日记'));
      await t.pumpAndSettle();
      await t.tap(find.text('写日记'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('edit-title')), '花园的一天');
      await t.enterText(
        find.byKey(const ValueKey('edit-body')),
        '今天看见了花 🌷\n这篇日记先属于我。',
      );
      await t.tap(find.text('保存'));
      await until(t, find.text('分享给谁'));
      await tap(t, '分享这篇日记');
      await until(t, find.text('分享给小林？'));
      await t.tap(find.text('暂不'));
      await t.pumpAndSettle();
      expect(find.text('当前版本未分享'), findsOneWidget);
      await tap(t, '分享这篇日记');
      await t.tap(find.text('确认分享'));
      await until(t, find.text('当前版本已分享'));
      // Remove transient feedback before the next tap; it must not obscure controls.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await tap(t, '留下记忆');
      await until(t, find.text('用于后续交流'));
      await t.enterText(find.byKey(const ValueKey('edit-body')), '我喜欢散步看花。');
      await t.tap(find.text('保存'));
      await until(t, find.text('分享给谁'));
      await t.tap(find.byTooltip('编辑日记'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('edit-body')),
        '傍晚又去了花园 🌷\n修改后需要重新决定分享。',
      );
      await t.tap(find.text('保存'));
      await until(t, find.text('当前版本未分享'));
      await tap(t, '分享这篇日记');
      await t.tap(find.text('确认分享'));
      await until(t, find.text('当前版本已分享'));
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await tap(t, '从这里聊起');
      await until(t, find.text('从这篇日记开始'));
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('message-input')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(
        find.byKey(const ValueKey('message-input')),
        '等模型接入后，再聊聊这朵花。',
      );
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
      await back(t);
      await until(t, find.text('分享给谁'));
      await tap(t, '撤回分享');
      await t.tap(find.text('确认撤回'));
      await until(t, find.text('当前版本未分享'));
      await back(t);
      await until(t, find.text('留在本机 · 尚待完成'));
      await tap(t, '给小林的话');
      await until(t, find.text('从这篇日记开始'));
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('message-input')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('message-input')))
            .controller!
            .text,
        '等模型接入后，再聊聊这朵花。',
      );
      expect(find.textContaining('虚构回复'), findsNothing);
      expect(t.takeException(), isNull);
      await back(t);
      await t.tap(find.text('角色'));
      await t.pumpAndSettle();
      await tap(t, '小林');
      await until(t, find.text('虚构角色'));
      await tap(t, '记忆');
      await until(t, find.text('我喜欢散步看花。'));
      expect(find.text('已停用或来源失效 · 1 篇来源'), findsOneWidget);
      await back(t);
      await t.tap(find.text('我的日记'));
      await t.pumpAndSettle();
    },
  );
}
