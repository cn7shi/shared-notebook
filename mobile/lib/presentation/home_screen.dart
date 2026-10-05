import 'package:flutter/material.dart';

import '../application/read_controllers.dart';
import '../application/work_controller.dart';
import '../domain/models.dart';
import 'action_screen.dart';
import 'character_screen.dart';
import 'chat_screen.dart';
import 'common.dart';
import 'editor_screen.dart';
import 'entry_screen.dart';

class HomeScreen extends StatefulWidget {
  final Workspace workspace;
  final String email;
  const HomeScreen({super.key, required this.workspace, required this.email});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final c = HomeController(widget.workspace)..refresh();
  int tab = 0;
  bool opening = false;
  Workspace get w => widget.workspace;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await c.refresh();
  }

  Future<void> create() async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final kind = tab == 0 ? 'entry' : 'character';
      final copy = await w.draft(kind, tab == 0 ? '写日记' : '创建角色');
      if (!mounted) return;
      final result = await editCopy(context, w, copy);
      if (!mounted) return;
      await c.refresh();
      if (!mounted || result == null) return;
      await open(
        kind == 'entry'
            ? EntryScreen(workspace: w, id: result.id)
            : CharacterScreen(workspace: w, id: result.id),
      );
    } catch (_) {
      if (mounted) showMessage(context, '无法读取本机输入，请重试。');
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> resume(WorkingCopy copy) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      if (copy.kind == 'action') {
        await perform(context, w, copy, start: false);
      } else if (copy.kind == 'message') {
        await open(ChatScreen(workspace: w, id: copy.refs['conversationId']));
      } else {
        await editCopy(context, w, copy);
      }
      if (mounted) await c.refresh();
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> logout() async {
    final session = AppScope.sessionOf(context);
    if (!await confirm(
      context,
      '退出登录？',
      '本机未提交的输入会为此账户保留，重新登录同一账户后可以继续。',
      action: '退出',
    )) {
      return;
    }
    try {
      await session?.logout();
    } on ApiFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, '暂未退出，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('双方记事本'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: c.busy ? null : c.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '退出登录',
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ContentWidth(
        child: RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 110),
            children: [
              Text(
                tab == 0 ? '你的生活，由你决定分享给谁。' : '为一个虚构角色，留一页位置。',
                style: const TextStyle(fontSize: 26, height: 1.5, color: ink),
              ),
              const SizedBox(height: 12),
              Text(widget.email, style: const TextStyle(color: muted)),
              Problem(c.error, retry: c.refresh),
              if (c.copies.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  '留在本机 · 尚待完成',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...c.copies.map(
                  (copy) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.edit_note),
                      title: Text(copy.label),
                      subtitle: Text(copy.pending == null ? '继续输入' : '待确认上次操作'),
                      onTap: opening ? null : () => resume(copy),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (tab == 0)
                PageList(
                  controller: c.entries,
                  empty: '还没有日记。写下第一篇，只属于你。',
                  item: (e) => Card(
                    child: ListTile(
                      title: Text(e.title),
                      subtitle: Text(
                        '${dateLabel(e.createdAt)}\n${e.body}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      onTap: () => open(EntryScreen(workspace: w, id: e.id)),
                    ),
                  ),
                )
              else
                PageList(
                  controller: c.characters,
                  empty: '先创建一个角色，决定它的背景和交流风格。',
                  item: (ch) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(ch.name),
                      subtitle: Text(
                        ch.background.isEmpty ? '虚构角色' : ch.background,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () =>
                          open(CharacterScreen(workspace: w, id: ch.id)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: opening ? null : create,
        icon: Icon(tab == 0 ? Icons.edit_outlined : Icons.person_add_alt),
        label: Text(tab == 0 ? '写日记' : '创建角色'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: '我的日记',
          ),
          NavigationDestination(icon: Icon(Icons.people_outline), label: '角色'),
        ],
      ),
    ),
  );
}
