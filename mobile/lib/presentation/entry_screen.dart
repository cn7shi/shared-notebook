import 'package:flutter/material.dart';

import '../application/read_controllers.dart';
import '../application/work_controller.dart';
import '../domain/models.dart';
import 'action_screen.dart';
import 'chat_screen.dart';
import 'common.dart';
import 'editor_screen.dart';

class EntryScreen extends StatefulWidget {
  final Workspace workspace;
  final String id;
  const EntryScreen({super.key, required this.workspace, required this.id});
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  Workspace get w => widget.workspace;
  late final c = EntryController(w.repository, widget.id)..refresh();
  bool acting = false;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() task) async {
    if (acting) return;
    setState(() => acting = true);
    try {
      await task();
    } on ApiFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, '暂未完成，请保留输入后重试。');
    } finally {
      if (mounted) {
        await c.refresh();
        if (mounted) setState(() => acting = false);
      }
    }
  }

  Future<void> edit() => act(() async {
    final entry = c.entry!;
    final copy = await w.draft(
      'entry',
      '编辑日记',
      id: entry.id,
      fields: entry.fields,
      revision: entry.revision,
    );
    if (mounted) await editCopy(context, w, copy);
  });
  Future<void> share(ShareState target, bool active) => act(() async {
    final title = active
        ? '分享给${target.character.name}？'
        : '撤回给${target.character.name}的分享？';
    final body = active
        ? '《${c.entry!.title}》的当前内容将可用于这个角色之后的交流和虚构日记。修改原文后需要重新分享。'
        : '后续生成将排除这篇日记及相关记忆，进行中的旧任务会取消。历史对话仍可阅读，已发送到模型服务的内容无法收回。';
    if (!await confirm(
          context,
          title,
          body,
          action: active ? '确认分享' : '确认撤回',
        ) ||
        !mounted) {
      return;
    }
    final result = await perform(context, w, c.share(w, target, active));
    if (mounted && result != null) showMessage(context, result.message);
  });
  Future<void> chat(String characterId) => act(() async {
    final result = await perform(
      context,
      w,
      w.action(
        'conversation',
        '从这篇日记聊起',
        {'characterId': characterId},
        {'entryId': c.entry!.id},
      ),
    );
    if (mounted && result != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(workspace: w, id: result.id),
        ),
      );
    }
  });
  Future<void> memory(ShareState target) => act(() async {
    final e = c.entry!;
    final copy = await w.draft(
      'memory',
      '为${target.character.name}留下记忆',
      refs: {'characterId': target.character.id},
      fields: {
        'body': '',
        'sources': [
          {'entryId': e.id, 'revision': e.revision},
        ],
        'active': true,
      },
    );
    if (mounted) await editCopy(context, w, copy);
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final e = c.entry;
      return Scaffold(
        appBar: AppBar(
          title: Text(e?.author == 'character' ? '角色日记 · 虚构' : '我的日记'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: c.busy || acting ? null : c.refresh,
              icon: const Icon(Icons.refresh),
            ),
            if (e?.author == 'user')
              IconButton(
                tooltip: '编辑日记',
                onPressed: c.busy || acting ? null : edit,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (c.busy) const LinearProgressIndicator(),
              Problem(c.error, retry: c.refresh),
              if (e != null) ...[
                Text(
                  e.title,
                  style: const TextStyle(fontSize: 28, height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  dateLabel(e.createdAt),
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 24),
                SelectableText(
                  e.body,
                  style: const TextStyle(fontSize: 18, height: 1.9),
                ),
                const SizedBox(height: 36),
                if (e.author == 'character') ...[
                  const Text('这是基于角色设定的虚构记录。', style: TextStyle(color: muted)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: c.busy || acting
                        ? null
                        : () => chat(e.characterId!),
                    child: const Text('从这篇日记聊起'),
                  ),
                ] else ...[
                  const Divider(),
                  const Text('分享给谁', style: TextStyle(fontSize: 22)),
                  const SizedBox(height: 12),
                  const Text('保存不会自动分享。每个角色只看到你明确授权的版本。'),
                  if (!c.sharesKnown)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('分享状态尚未确认，请刷新。'),
                    )
                  else if (c.shares.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('还没有角色。这篇日记暂未分享。'),
                    )
                  else
                    ...c.shares.map((s) {
                      final active = s.grant?.applies(e) == true;
                      final ready = !c.busy && !acting && c.error == null;
                      return Card(
                        margin: const EdgeInsets.only(top: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                s.character.name,
                                style: const TextStyle(fontSize: 20),
                              ),
                              Text(
                                active ? '当前版本已分享' : '当前版本未分享',
                                style: const TextStyle(color: muted),
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: ready
                                        ? () => share(s, !active)
                                        : null,
                                    child: Text(active ? '撤回分享' : '分享这篇日记'),
                                  ),
                                  if (active) ...[
                                    TextButton(
                                      onPressed: ready
                                          ? () => chat(s.character.id)
                                          : null,
                                      child: const Text('从这里聊起'),
                                    ),
                                    TextButton(
                                      onPressed: ready ? () => memory(s) : null,
                                      child: const Text('留下记忆'),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}
