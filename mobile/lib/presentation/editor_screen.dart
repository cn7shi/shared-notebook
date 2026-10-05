import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/work_controller.dart';
import '../domain/models.dart';
import 'common.dart';

Future<MutationResult?> editCopy(
  BuildContext context,
  Workspace w,
  WorkingCopy copy,
) async {
  final controller = w.control(copy);
  try {
    return await Navigator.push<MutationResult>(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(controller: controller)),
    );
  } finally {
    controller.dispose();
  }
}

class EditorScreen extends StatefulWidget {
  final WorkController controller;
  const EditorScreen({super.key, required this.controller});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  WorkController get c => widget.controller;
  late final fields = <String, TextEditingController>{
    for (final e in c.copy.fields.entries)
      if (e.value is String) e.key: TextEditingController(text: e.value),
  };
  bool canPop = false, leaving = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) c.persist();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  void pop([MutationResult? value]) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, value);
    });
  }

  Future<void> leave() async {
    if (leaving || c.busy) return;
    setState(() => leaving = true);
    await c.persist();
    if (!mounted) return;
    if (!c.localSaved) {
      setState(() => leaving = false);
      showMessage(context, '本机保存失败，请先复制内容。');
      return;
    }
    pop();
  }

  Future<void> save() async {
    final result = await c.submit();
    if (mounted && result != null) pop(result);
  }

  Future<void> resolve() async {
    try {
      final remote = await c.latest();
      if (!mounted) return;
      String display(Json fields) => fields.entries
          .map(
            (e) =>
                '${switch (e.key) {
                  'title' => '标题',
                  'body' => '正文',
                  'name' => '名字',
                  'background' => '背景',
                  'style' => '交流风格',
                  'active' => '用于后续交流',
                  _ => '来源记录',
                }}：${e.value}',
          )
          .join('\n\n');
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('另一处也有新的修改'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('云端最新内容'),
                SelectableText(display(remote.fields!)),
                const Divider(),
                const Text('本机内容'),
                SelectableText(display(c.copy.fields)),
                const SizedBox(height: 16),
                const Text('保留本机会更新云端。修改日记将撤回旧版本的分享。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('暂不处理'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('使用云端'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保留本机并保存'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      await c.resolve(remote, keepLocal: choice);
      if (!mounted) return;
      for (final e in fields.entries) {
        e.value.text = c.copy.fields[e.key];
      }
      if (c.result != null) pop(c.result);
    } on ApiFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, '暂时无法读取最新内容，请保留输入。');
    }
  }

  Future<void> discard() async {
    if (!await confirm(
      context,
      '丢弃本机输入？',
      '会清理这里保留的输入和请求。已经提交的云端内容不会删除，已经完成的分享不会撤回；返回详情确认当前状态。',
      action: '丢弃',
    )) {
      return;
    }
    try {
      await c.discard();
      if (mounted) pop();
    } catch (_) {
      if (mounted) showMessage(context, '本机清理失败，请重试。');
    }
  }

  Widget field(String name, String label, int max, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: TextField(
      key: ValueKey('edit-$name'),
      controller: fields[name],
      readOnly: !c.canEdit,
      minLines: lines,
      maxLines: lines == 1 ? 1 : null,
      maxLength: max,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
      onChanged: (v) => c.edit({name: v}),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: canPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回',
            onPressed: c.busy ? null : leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(c.copy.label),
          actions: [
            IconButton(
              tooltip: '复制输入',
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: fields.values.map((f) => f.text).join('\n\n'),
                  ),
                );
                if (context.mounted) showMessage(context, '输入已复制');
              },
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (c.copy.kind == 'entry')
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                    '保存后只属于你。修改已分享的内容会撤回旧分享，需在详情重新选择角色。',
                    style: TextStyle(color: muted, height: 1.7),
                  ),
                ),
              if (c.copy.kind == 'character')
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                    '这是虚构角色。修改背景会重置后续交流所用的上下文；历史内容仍可阅读。',
                    style: TextStyle(color: muted, height: 1.7),
                  ),
                ),
              if (c.copy.pending != null)
                const Text('等待确认上次操作。重试会查询原请求结果，不会重复创建。'),
              if (c.error != null) ...[
                Problem(c.error, retry: c.conflict ? resolve : save),
                if (c.conflict)
                  TextButton(
                    onPressed: c.busy ? null : resolve,
                    child: const Text('查看并处理差异'),
                  ),
              ],
              if (fields.containsKey('title')) field('title', '日记标题', 200),
              if (fields.containsKey('name')) field('name', '角色名字', 80),
              if (fields.containsKey('background'))
                field('background', '角色背景', 8000, lines: 5),
              if (fields.containsKey('style'))
                field('style', '交流风格', 2000, lines: 3),
              if (fields.containsKey('body'))
                field(
                  'body',
                  c.copy.kind == 'memory' ? '希望角色记住的背景' : '写下今天',
                  c.copy.kind == 'memory' ? 4000 : 20000,
                  lines: 8,
                ),
              if (c.copy.kind == 'memory') ...[
                Text(
                  '基于 ${(c.copy.fields['sources'] as List).length} 篇已分享日记。来源撤回或改写后，这条记忆会失效。',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('用于后续交流'),
                  value: c.copy.fields['active'] == true,
                  onChanged: c.canEdit ? (v) => c.edit({'active': v}) : null,
                ),
              ],
              TextButton(
                onPressed: c.busy ? null : discard,
                child: const Text('丢弃本机输入'),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.status,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: c.busy || c.conflict ? null : save,
                  child: Text(
                    c.busy
                        ? '正在保存…'
                        : c.copy.pending != null
                        ? '重试保存'
                        : '保存',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
