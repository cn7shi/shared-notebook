import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/read_controllers.dart';
import '../application/work_controller.dart';
import '../domain/models.dart';
import 'action_screen.dart';
import 'character_screen.dart';
import 'common.dart';
import 'entry_screen.dart';

class ChatScreen extends StatefulWidget {
  final Workspace workspace;
  final String id;
  const ChatScreen({super.key, required this.workspace, required this.id});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with VisibleRefresh<ChatScreen> {
  Workspace get w => widget.workspace;
  late final c = ChatController(w, widget.id)..refresh();
  final input = TextEditingController();
  bool canPop = false, leaving = false, acting = false;
  @override
  Future<void> refreshVisible() async {
    if (c.pending && c.composer?.busy != true) await c.refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) c.composer?.persist();
  }

  @override
  void dispose() {
    input.dispose();
    c.dispose();
    super.dispose();
  }

  Future<void> leave() async {
    if (leaving || acting || c.composer?.busy == true) return;
    setState(() => leaving = true);
    await c.composer?.persist();
    if (!mounted) return;
    if (c.composer?.localSaved == false) {
      setState(() => leaving = false);
      showMessage(context, '本机保存失败，请先复制输入。');
      return;
    }
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> send({bool recovering = false}) async {
    final result = recovering ? await c.composer?.submit() : await c.send();
    if (!mounted) return;
    if (result != null) {
      input.text = c.composer!.copy.fields['body'];
      if (recovering) await c.refresh();
    }
  }

  Future<void> retry(Job j) async {
    if (acting) return;
    setState(() => acting = true);
    try {
      final copy = await w.generation('retry', '重试生成回复', {'id': j.id});
      if (!mounted) return;
      if (!await confirm(
            context,
            '重试生成回复？',
            '会按当前分享和背景重新调用模型服务。原消息仍保留，较早轮次可能已经无法重试。',
            action: '重试',
          ) ||
          !mounted) {
        return;
      }
      await perform(context, w, copy);
      if (mounted) await c.refresh();
    } on ApiFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, '未能确认操作，请重试。');
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> clearInput() async {
    final composer = c.composer!;
    if (!await confirm(
      context,
      '清理本机输入？',
      '这会移除尚待确认的本机请求。已发送到云端的消息不会删除，请刷新对话核对。',
      action: '清理',
    )) {
      return;
    }
    try {
      await composer.discard();
      // A new editor may be created only after the old request is explicitly discarded.
      if (!mounted) return;
      composer.dispose();
      c.composer = null;
      input.clear();
      await c.refresh();
    } catch (_) {
      if (mounted) showMessage(context, '本机清理失败，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: canPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final composer = c.composer;
        if (composer != null && input.text != composer.copy.fields['body']) {
          input.text = composer.copy.fields['body'];
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: '返回',
              onPressed: leave,
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(c.character?.name ?? '对话'),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: c.busy ? null : c.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (c.busy) const LinearProgressIndicator(),
                Problem(c.error, retry: c.refresh),
                if (c.linkedEntry != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(c.linkedEntry!.title),
                      subtitle: const Text('从这篇日记开始'),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EntryScreen(
                              workspace: w,
                              id: c.linkedEntry!.id,
                            ),
                          ),
                        );
                        if (mounted) await c.refresh();
                      },
                    ),
                  ),
                const Text(
                  '和虚构角色的交流。分享或背景变化后，旧内容仍可阅读，但不会继续作为角色的背景。',
                  style: TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: c.messages,
                  builder: (context, _) {
                    final messages = [...c.messages.items]
                      ..sort((a, b) => a.sequence.compareTo(b.sequence));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Problem(c.messages.error, retry: c.messages.refresh),
                        if (c.messages.next != null)
                          TextButton(
                            onPressed: c.messages.busy ? null : c.messages.more,
                            child: const Text('加载更早的消息'),
                          ),
                        if (messages.isEmpty &&
                            !c.messages.busy &&
                            c.messages.error == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              '还没有消息，想说的话可以先写下来。',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        ...messages.map(
                          (m) => Container(
                            margin: const EdgeInsets.only(bottom: 16, top: 4),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: m.role == 'user'
                                  ? const Color(0xffeee4d9)
                                  : const Color(0xffe8efeb),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.role == 'user'
                                      ? '我'
                                      : '${c.character?.name ?? '角色'} · 虚构回复',
                                  style: const TextStyle(color: muted),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  m.body,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    height: 1.7,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                ...c.jobs
                    .where((j) => j.status != 'succeeded')
                    .map(
                      (j) => JobCard(
                        job: j,
                        retry: !acting && c.available == true && j.retryable
                            ? () => retry(j)
                            : null,
                      ),
                    ),
                const Divider(height: 32),
                Text(
                  c.available == true
                      ? '只会使用目前获准的分享与背景。'
                      : c.available == false
                      ? '模型尚未接入，想说的话可先保留在本机。'
                      : '暂未确认模型可用，输入仍可保留。',
                  style: const TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 16),
                if (composer != null)
                  ListenableBuilder(
                    listenable: composer,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Problem(
                          composer.error,
                          retry: () =>
                              send(recovering: composer.copy.pending != null),
                        ),
                        TextField(
                          key: const ValueKey('message-input'),
                          controller: input,
                          readOnly: !composer.canEdit,
                          minLines: 3,
                          maxLines: null,
                          maxLength: 20000,
                          decoration: const InputDecoration(
                            labelText: '想说的话',
                            alignLabelWithHint: true,
                          ),
                          onChanged: (v) => composer.edit({'body': v}),
                        ),
                        Text(
                          composer.status,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        if (composer.copy.pending != null)
                          TextButton(
                            onPressed: composer.busy ? null : clearInput,
                            child: const Text('清理本机输入'),
                          ),
                        Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: input.text),
                                );
                                if (context.mounted) {
                                  showMessage(context, '输入已复制');
                                }
                              },
                              child: const Text('复制输入'),
                            ),
                            if (composer.copy.pending != null)
                              FilledButton(
                                onPressed: composer.busy
                                    ? null
                                    : () => send(recovering: true),
                                child: const Text('确认上次发送结果'),
                              )
                            else
                              FilledButton(
                                onPressed:
                                    c.available == true &&
                                        !c.pending &&
                                        !composer.busy &&
                                        !acting
                                    ? send
                                    : null,
                                child: Text(composer.busy ? '正在发送…' : '发送'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    ),
  );
}
