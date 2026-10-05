import 'dart:async';

import 'package:flutter/material.dart';

import '../application/read_controllers.dart';
import '../application/session_controller.dart';
import '../domain/models.dart';

const paper = Color(0xfffaf7f1),
    ink = Color(0xff353d3c),
    accent = Color(0xff8f513e),
    muted = Color(0xff6d7774);
final routes = RouteObserver<ModalRoute<void>>();

class AppScope extends InheritedWidget {
  final SessionController session;
  const AppScope({super.key, required this.session, required super.child});
  static SessionController? sessionOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.session;
  @override
  bool updateShouldNotify(AppScope old) => session != old.session;
}

class ContentWidth extends StatelessWidget {
  final Widget child;
  const ContentWidth({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: child,
    ),
  );
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
String dateLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ==
    true;

class Problem extends StatelessWidget {
  final ApiFailure? error;
  final VoidCallback retry;
  const Problem(this.error, {super.key, required this.retry});
  @override
  Widget build(BuildContext context) => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error!.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: () async {
                  final session = AppScope.sessionOf(context);
                  if (error!.code == 'UNAUTHORIZED' && session != null) {
                    try {
                      await session.logout(expired: true);
                    } catch (_) {
                      if (context.mounted) {
                        showMessage(context, '登录信息清理失败，请重试。');
                      }
                    }
                  } else {
                    retry();
                  }
                },
                child: Text(error!.code == 'UNAUTHORIZED' ? '重新登录' : '重试'),
              ),
            ],
          ),
        );
}

class PageList<T> extends StatelessWidget {
  final PagedController<T> controller;
  final Widget Function(T) item;
  final String empty;
  const PageList({
    super.key,
    required this.controller,
    required this.item,
    required this.empty,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.busy) const LinearProgressIndicator(),
        Problem(controller.error, retry: controller.refresh),
        if (!controller.busy &&
            controller.error == null &&
            controller.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              empty,
              style: const TextStyle(color: muted, height: 1.8),
            ),
          ),
        ...controller.items.map(item),
        if (controller.next != null)
          TextButton(
            onPressed: controller.busy ? null : controller.more,
            child: const Text('加载更多'),
          ),
      ],
    ),
  );
}

/// Routes covered by another screen, and apps in the background, stop polling.
mixin VisibleRefresh<T extends StatefulWidget> on State<T>
    implements RouteAware {
  late final ticker = ForegroundRefresh(refreshVisible);
  late final lifecycle = _LifecycleObserver(didChangeAppLifecycleState);
  bool visible = true, foreground = true;
  Future<void> refreshVisible();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(lifecycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routes.subscribe(this, route);
    _update();
  }

  void _update() => ticker.setActive(visible && foreground);
  @override
  void didPush() {
    visible = true;
    _update();
  }

  @override
  void didPushNext() {
    visible = false;
    _update();
  }

  @override
  void didPopNext() {
    visible = true;
    _update();
    unawaited(refreshVisible());
  }

  @override
  void didPop() {
    visible = false;
    _update();
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _update();
    if (foreground && visible) unawaited(refreshVisible());
  }

  @override
  void dispose() {
    ticker.dispose();
    routes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(lifecycle);
    super.dispose();
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  final void Function(AppLifecycleState) change;
  _LifecycleObserver(this.change);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => change(state);
}
