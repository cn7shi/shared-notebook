import 'package:flutter/material.dart';

import '../application/read_controllers.dart';
import '../application/work_controller.dart';
import '../domain/models.dart';
import 'action_screen.dart';
import 'chat_screen.dart';
import 'common.dart';
import 'editor_screen.dart';
import 'entry_screen.dart';

class CharacterScreen extends StatefulWidget {
  final Workspace workspace;
  final String id;
  const CharacterScreen({super.key, required this.workspace, required this.id});
  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen>
    with VisibleRefresh<CharacterScreen> {
  Workspace get w => widget.workspace;
  late final c = CharacterController(w.repository, widget.id)..refresh();
  bool acting = false;
  int tab = 0;
  @override
  Future<void> refreshVisible() => c.poll();
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
      if (mounted) showMessage(context, '暂未完成，请重试。');
    } finally {
      if (mounted) {
        await c.refresh();
        if (mounted) setState(() => acting = false);
      }
    }
  }

  Future<void> edit() => act(() async {
    final ch = c.character!;
    final copy = await w.draft(
      'character',
      '角色设定',
      id: ch.id,
      fields: ch.fields,
      revision: ch.revision,
    );
    if (mounted) await editCopy(context, w, copy);
  });
  Future<void> conversation() => act(() async {
    final result = await perform(
      context,
      w,
      w.action('conversation', '新的对话', {'characterId': widget.id}, {}),
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
  Future<void> generate([Job? job]) => act(() async {
    final copy = await w.generation(
      job == null ? 'diary' : 'retry',
      job == null ? '生成角色日记' : '重试生成',
      job == null ? {'characterId': widget.id} : {'id': job.id},
    );
    if (!mounted) return;
    if (!await confirm(
          context,
          job == null ? '生成一篇虚构日记？' : '重试这次生成？',
          '会使用当前允许的分享和背景调用模型服务。重试可能再次产生模型调用。',
          action: '开始',
        ) ||
        !mounted) {
      return;
    }
    final result = await perform(context, w, copy);
    if (mounted && result != null) {
      setState(() => tab = 3);
      showMessage(context, result.message);
    }
  });
  Future<void> memory(Memory m) => act(() async {
    final copy = await w.draft(
      'memory',
      '修正角色记忆',
      id: m.id,
      refs: {'characterId': widget.id},
      fields: m.fields,
      revision: m.revision,
    );
    if (mounted) await editCopy(context, w, copy);
  });
  Future<void> open(Widget screen) => act(() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final ch = c.character, ready = !acting && !c.busy;
      return Scaffold(
        appBar: AppBar(
          title: Text(ch?.name ?? '角色'),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: ready ? c.refresh : null,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '角色设定',
              onPressed: ready && ch != null ? edit : null,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (c.busy) const LinearProgressIndicator(),
              Problem(c.error, retry: c.refresh),
              if (ch != null) ...[
                const Text('虚构角色', style: TextStyle(color: accent)),
                const SizedBox(height: 8),
                Text(ch.name, style: const TextStyle(fontSize: 30)),
                if (ch.background.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      ch.background,
                      style: const TextStyle(height: 1.7),
                    ),
                  ),
                if (ch.style.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '交流风格：${ch.style}',
                      style: const TextStyle(color: muted),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  c.available == true
                      ? '角色内容由模型生成，请把它作为虚构交流。'
                      : c.available == false
                      ? '模型尚未接入，暂不能生成日记或回复。你仍可写日记、管理分享和保留想说的话。'
                      : '正在确认模型是否可用；暂不发送或生成。',
                  style: const TextStyle(color: muted, height: 1.7),
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: ready ? conversation : null,
                      child: const Text('新的对话'),
                    ),
                    OutlinedButton(
                      onPressed: ready && c.available == true
                          ? () => generate()
                          : null,
                      child: const Text('生成角色日记'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < 4; i++)
                      ChoiceChip(
                        label: Text(['日记', '对话', '记忆', '任务'][i]),
                        selected: tab == i,
                        onSelected: (_) => setState(() => tab = i),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (tab == 0)
                  PageList(
                    controller: c.entries,
                    empty: '还没有角色日记。生成后会保存在这里，刷新不会改写内容。',
                    item: (e) => Card(
                      child: ListTile(
                        title: Text(e.title),
                        subtitle: Text('虚构 · ${dateLabel(e.createdAt)}'),
                        onTap: () => open(EntryScreen(workspace: w, id: e.id)),
                      ),
                    ),
                  ),
                if (tab == 1)
                  PageList(
                    controller: c.conversations,
                    empty: '还没有对话。也可以从已分享的日记开始。',
                    item: (v) => Card(
                      child: ListTile(
                        title: Text(v.entryId == null ? '自由聊聊' : '从日记开始的对话'),
                        subtitle: Text(dateLabel(v.createdAt)),
                        onTap: () => open(ChatScreen(workspace: w, id: v.id)),
                      ),
                    ),
                  ),
                if (tab == 2) ...[
                  const Text(
                    '在已分享的日记详情里，可以留下带来源的记忆。这里可修正或停用。',
                    style: TextStyle(color: muted, height: 1.7),
                  ),
                  PageList(
                    controller: c.memories,
                    empty: '还没有记忆。',
                    item: (m) => Card(
                      child: ListTile(
                        title: Text(m.body),
                        subtitle: Text(
                          '${m.active ? '用于后续交流' : '已停用或来源失效'} · ${m.sources.length} 篇来源',
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => memory(m),
                      ),
                    ),
                  ),
                ],
                if (tab == 3)
                  PageList(
                    controller: c.jobs,
                    empty: '还没有生成任务。这里会保留失败和取消状态。',
                    item: (j) => JobCard(
                      job: j,
                      retry: ready && c.available == true && j.retryable
                          ? () => generate(j)
                          : null,
                      open:
                          j.status == 'succeeded' &&
                              j.kind == 'diary' &&
                              j.resultId != null
                          ? () =>
                                open(EntryScreen(workspace: w, id: j.resultId!))
                          : j.conversationId != null
                          ? () => open(
                              ChatScreen(workspace: w, id: j.conversationId!),
                            )
                          : null,
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback? retry, open;
  const JobCard({super.key, required this.job, this.retry, this.open});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${job.kind == 'diary' ? '角色日记' : '回复'} · ${dateLabel(job.createdAt)}',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          Text(job.explanation),
          if (job.pending)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (retry != null)
                TextButton(onPressed: retry, child: const Text('重试生成')),
              if (open != null)
                TextButton(
                  onPressed: open,
                  child: Text(job.kind == 'diary' ? '阅读日记' : '查看对话'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
