import 'package:flutter/material.dart';

import '../application/work_controller.dart';
import '../domain/models.dart';
import 'common.dart';

Future<MutationResult?> perform(
  BuildContext context,
  Workspace w,
  WorkingCopy copy, {
  bool start = true,
}) async {
  final c = w.control(copy);
  try {
    return await Navigator.push<MutationResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ActionScreen(controller: c, start: start),
      ),
    );
  } finally {
    c.dispose();
  }
}

class ActionScreen extends StatefulWidget {
  final WorkController controller;
  final bool start;
  const ActionScreen({
    super.key,
    required this.controller,
    required this.start,
  });
  @override
  State<ActionScreen> createState() => _ActionScreenState();
}

class _ActionScreenState extends State<ActionScreen> {
  WorkController get c => widget.controller;
  bool canPop = false;
  @override
  void initState() {
    super.initState();
    if (widget.start) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) submit();
      });
    }
  }

  void pop([MutationResult? result]) {
    setState(() => canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, result);
    });
  }

  Future<void> submit() async {
    final result = await c.submit();
    if (mounted && result != null) pop(result);
  }

  Future<void> leave() async {
    if (c.busy) return;
    await c.persist();
    if (!mounted) return;
    if (c.localSaved) {
      pop();
    } else {
      showMessage(context, '本机状态未保留，请先重试。');
    }
  }

  Future<void> discard() async {
    if (!await confirm(
      context,
      '清理本机请求？',
      '清理不会撤销已经完成的云端操作。返回详情刷新，核对分享或任务的当前状态。',
      action: '清理',
    )) {
      return;
    }
    try {
      await c.discard();
      if (mounted) pop();
    } catch (_) {
      if (mounted) showMessage(context, '清理失败，请重试。');
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
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回',
            onPressed: c.busy ? null : leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(c.copy.label),
        ),
        body: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (c.busy) const LinearProgressIndicator(),
              const SizedBox(height: 24),
              const Text(
                '原请求会保留在本机。网络中断后，请明确重试以确认当前结果。',
                style: TextStyle(height: 1.8),
              ),
              Problem(c.error, retry: submit),
              Text(c.status),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: c.busy ? null : submit,
                child: const Text('重试原请求'),
              ),
              TextButton(
                onPressed: c.busy ? null : discard,
                child: const Text('清理本机请求'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
