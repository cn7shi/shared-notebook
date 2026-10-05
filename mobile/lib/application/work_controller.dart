import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

class Workspace {
  final NotebookRepository repository;
  final WorkStore store;
  final String owner;
  Workspace(this.repository, this.store, this.owner);
  Future<WorkingCopy> draft(
    String kind,
    String label, {
    String? id,
    Json? fields,
    Json? refs,
    int revision = 0,
  }) async {
    final identity = jsonEncode(refs ?? {});
    for (final c in await store.list(owner)) {
      if (c.kind == kind &&
          c.resourceId == id &&
          id != null &&
          jsonEncode(c.refs) == identity) {
        return c;
      }
      if (kind == 'message' &&
          c.kind == kind &&
          jsonEncode(c.refs) == identity) {
        return c;
      }
    }
    final initial =
        fields ??
        switch (kind) {
          'entry' => {'title': '', 'body': ''},
          'character' => {'name': '', 'background': '', 'style': ''},
          'message' => {'body': ''},
          _ => <String, dynamic>{},
        };
    return WorkingCopy(
      localId: const Uuid().v4(),
      ownerId: owner,
      kind: kind,
      label: label,
      resourceId: id,
      refs: refs,
      fields: clone(initial),
      saved: clone(initial),
      revision: revision,
    );
  }

  WorkingCopy action(String kind, String label, Json refs, Json body) =>
      WorkingCopy(
        localId: const Uuid().v4(),
        ownerId: owner,
        kind: 'action',
        label: label,
        refs: refs,
        pending: Command(const Uuid().v4(), kind, refs, body),
      );
  WorkController control(WorkingCopy copy) =>
      WorkController(repository, store, copy);
  Future<WorkingCopy> generation(String kind, String label, Json refs) async {
    if (!await repository.capability()) {
      throw const ApiFailure('PROVIDER_NOT_CONFIGURED', '模型尚未接入，暂不能生成内容。');
    }
    return action(kind, label, refs, {});
  }
}

class WorkController extends ChangeNotifier {
  final NotebookRepository repository;
  final WorkStore store;
  final WorkingCopy copy;
  bool busy = false, localSaved = true, _disposed = false;
  ApiFailure? error;
  Future<void> _disk = Future.value();
  int _version = 0;
  MutationResult? result;
  WorkController(this.repository, this.store, this.copy);
  bool get canEdit => !busy && copy.pending == null;
  bool get conflict =>
      error?.code == 'REVISION_CONFLICT' && copy.kind != 'action';
  String get status => !localSaved
      ? '正在保留输入，或本机保存失败'
      : copy.pending != null
      ? '等待确认上次操作'
      : copy.dirty
      ? '输入已保留在本机'
      : copy.resourceId == null
      ? '尚未提交'
      : '已与云端确认';
  void notify() {
    if (!_disposed) notifyListeners();
  }

  void edit(Json changes) {
    if (!canEdit) return;
    copy.fields.addAll(changes);
    error = null;
    localSaved = false;
    result = null;
    notify();
    unawaited(persist());
  }

  Future<void> persist() {
    final snapshot = WorkingCopy.fromJson(clone(copy.toJson())),
        version = ++_version;
    _disk = _disk.then((_) async {
      try {
        if (snapshot.dirty) {
          await store.put(snapshot);
        } else {
          await store.remove(snapshot.localId);
        }
        if (version == _version) localSaved = true;
      } catch (_) {
        localSaved = false;
        error = const ApiFailure('LOCAL_STORAGE_ERROR', '本机保存失败，请先复制内容。');
      }
      notify();
    });
    return _disk;
  }

  void validate() {
    final f = copy.fields;
    void text(String field, int max, {bool required = false}) {
      final v = f[field] as String? ?? '';
      if ((required && v.trim().isEmpty) || v.runes.length > max) {
        throw ApiFailure('VALIDATION_ERROR', '请检查输入，内容不能为空或超过 $max 字符。');
      }
    }

    switch (copy.kind) {
      case 'entry':
        text('title', 200, required: true);
        text('body', 20000, required: true);
      case 'character':
        text('name', 80, required: true);
        text('background', 8000);
        text('style', 2000);
      case 'memory':
        text('body', 4000, required: true);
      case 'message':
        text('body', 20000, required: true);
    }
  }

  bool _same(Json remote, Json submitted) {
    final expected = clone(submitted)..remove('revision');
    for (final key in ['name', 'title']) {
      if (expected[key] is String) {
        expected[key] = (expected[key] as String).trim();
      }
    }
    return expected.keys.every(
      (k) => jsonEncode(expected[k]) == jsonEncode(remote[k]),
    );
  }

  Future<MutationResult?> submit() async {
    if (busy || conflict) return null;
    busy = true;
    error = null;
    result = null;
    notify();
    try {
      if (copy.pending == null) {
        validate();
        if (!copy.dirty && copy.resourceId != null && copy.kind != 'message') {
          return MutationResult(copy.resourceId!);
        }
        if (copy.kind == 'message' && !await repository.capability()) {
          throw const ApiFailure(
            'PROVIDER_NOT_CONFIGURED',
            '模型尚未接入，想说的话已保留在本机。',
          );
        }
        copy.pending = Command(
          const Uuid().v4(),
          copy.kind,
          {...copy.refs, if (copy.resourceId != null) 'id': copy.resourceId},
          {
            ...clone(copy.fields),
            if (copy.resourceId != null && copy.kind != 'message')
              'revision': copy.revision,
          },
        );
      }
      await persist();
      if (!localSaved) {
        throw const ApiFailure('LOCAL_STORAGE_ERROR', '未能保留请求，暂不发送。');
      }
      final before = WorkingCopy.fromJson(clone(copy.toJson()));
      final pending = copy.pending!, saved = await repository.execute(pending);
      if (saved.fields != null && !_same(saved.fields!, pending.body)) {
        // The original write committed, but another device has since changed it.
        throw const ApiFailure('REVISION_CONFLICT', '云端已经有较新的内容，请比较后选择。');
      }
      copy.pending = null;
      if (copy.kind == 'message') {
        copy.fields = {'body': ''};
        copy.saved = {'body': ''};
      } else if (saved.fields != null) {
        copy.resourceId = saved.id;
        copy.revision = saved.revision!;
        copy.fields = clone(saved.fields!);
        copy.saved = clone(saved.fields!);
      }
      await persist();
      if (!localSaved) {
        copy.fields = before.fields;
        copy.saved = before.saved;
        copy.resourceId = before.resourceId;
        copy.revision = before.revision;
        copy.pending = before.pending;
        throw const ApiFailure('LOCAL_STORAGE_ERROR', '云端已接收，本机状态未确认，请重试。');
      }
      result = saved;
      return saved;
    } on ApiFailure catch (e) {
      error = e;
      await persist();
    } catch (_) {
      error = const ApiFailure('SAVE_FAILED', '暂时未能确认结果，请保留输入后重试。');
      await persist();
    } finally {
      busy = false;
      notify();
    }
    return null;
  }

  Future<MutationResult> latest() => repository.latest(copy);
  Future<void> resolve(MutationResult remote, {required bool keepLocal}) async {
    if (busy || remote.fields == null || remote.revision == null) return;
    busy = true;
    notify();
    copy.resourceId = remote.id;
    copy.revision = remote.revision!;
    copy.saved = clone(remote.fields!);
    copy.pending = null;
    if (!keepLocal) copy.fields = clone(remote.fields!);
    error = null;
    result = null;
    await persist();
    busy = false;
    notify();
    if (keepLocal && localSaved) await submit();
  }

  Future<void> discard() async {
    if (busy) return;
    busy = true;
    notify();
    try {
      await _disk;
      await store.remove(copy.localId);
    } finally {
      busy = false;
      notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
