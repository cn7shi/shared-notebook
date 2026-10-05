import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'work_controller.dart';

class LoadController extends ChangeNotifier {
  bool busy = false, disposed = false;
  ApiFailure? error;
  void notify() {
    if (!disposed) notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || disposed) return;
    busy = true;
    error = null;
    notify();
    try {
      await action();
    } on ApiFailure catch (e) {
      error = e;
    } catch (_) {
      error = const ApiFailure('LOAD_FAILED', '暂时无法读取，请重试。');
    } finally {
      busy = false;
      notify();
    }
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class PagedController<T> extends LoadController {
  final Future<Page<T>> Function(String? cursor) load;
  List<T> items = [];
  String? next;
  PagedController(this.load);
  Future<void> refresh() => run(() async {
    final p = await load(null);
    items = p.items;
    next = p.next;
  });
  Future<void> more() => run(() async {
    if (next == null) return;
    final p = await load(next);
    items.addAll(p.items);
    next = p.next;
  });
}

Future<List<T>> everyPage<T>(
  Future<Page<T>> Function(String? cursor) load,
) async {
  final values = <T>[];
  String? cursor;
  final seen = <String>{};
  do {
    final page = await load(cursor);
    values.addAll(page.items);
    cursor = page.next;
    if (cursor != null && !seen.add(cursor)) {
      throw const ApiFailure('INVALID_PAGE', '列表未能完整读取，请刷新后再操作。');
    }
  } while (cursor != null);
  return values;
}

class HomeController extends LoadController {
  final Workspace workspace;
  late final entries = PagedController<Entry>(
    (cursor) => workspace.repository.entries(cursor: cursor),
  );
  late final characters = PagedController<Character>(
    (cursor) => workspace.repository.characters(cursor: cursor),
  );
  List<WorkingCopy> copies = [];
  HomeController(this.workspace);
  Future<void> refresh() => run(() async {
    copies = await workspace.store.list(workspace.owner);
    notify();
    await Future.wait([entries.refresh(), characters.refresh()]);
  });
  @override
  void dispose() {
    entries.dispose();
    characters.dispose();
    super.dispose();
  }
}

class ShareState {
  final Character character;
  final Grant? grant;
  const ShareState(this.character, this.grant);
}

class EntryController extends LoadController {
  final NotebookRepository repository;
  final String id;
  Entry? entry;
  List<ShareState> shares = [];
  bool sharesKnown = false;
  EntryController(this.repository, this.id);
  Future<void> refresh() => run(() async {
    sharesKnown = false;
    final e = await repository.entry(id);
    entry = e;
    notify();
    if (e.author == 'character') return;
    final characters = await everyPage(
      (cursor) => repository.characters(cursor: cursor),
    );
    final values = <ShareState>[];
    for (final character in characters) {
      final grants = await everyPage(
        (cursor) => repository.grants(character.id, cursor: cursor),
      );
      values.add(
        ShareState(character, grants.where((g) => g.entryId == id).firstOrNull),
      );
    }
    shares = values;
    sharesKnown = true;
  });
  WorkingCopy share(Workspace w, ShareState target, bool active) {
    if (!sharesKnown || busy || error != null || entry == null) {
      throw const ApiFailure('UNKNOWN_SHARING', '先确认最新分享状态。');
    }
    return w.action(
      'share',
      active ? '分享给${target.character.name}' : '撤回给${target.character.name}的分享',
      {'characterId': target.character.id, 'entryId': id},
      {
        'active': active,
        'entryRevision': entry!.revision,
        'revision': target.grant?.revision ?? 0,
      },
    );
  }
}

class CharacterController extends LoadController {
  final NotebookRepository repository;
  final String id;
  Character? character;
  bool? available;
  late final entries = PagedController<Entry>(
    (cursor) => repository.entries(characterId: id, cursor: cursor),
  );
  late final conversations = PagedController<Conversation>(
    (cursor) => repository.conversations(id, cursor: cursor),
  );
  late final memories = PagedController<Memory>(
    (cursor) => repository.memories(id, cursor: cursor),
  );
  late final jobs = PagedController<Job>(
    (cursor) => repository.jobs(id, cursor: cursor),
  );
  CharacterController(this.repository, this.id);
  Future<void> refresh() => run(() async {
    available = null;
    character = await repository.character(id);
    notify();
    await Future.wait([
      entries.refresh(),
      conversations.refresh(),
      memories.refresh(),
      jobs.refresh(),
    ]);
    available = await repository.capability();
  });
  Future<void> poll() async {
    if (busy || jobs.busy || !jobs.items.any((j) => j.pending)) return;
    await run(() async {
      var finished = false;
      for (var i = 0; i < jobs.items.length; i++) {
        if (!jobs.items[i].pending) continue;
        final value = await repository.job(jobs.items[i].id);
        jobs.items[i] = value;
        finished |= !value.pending;
      }
      jobs.notify();
      if (finished) {
        await Future.wait([entries.refresh(), conversations.refresh()]);
      }
    });
  }

  @override
  void dispose() {
    entries.dispose();
    conversations.dispose();
    memories.dispose();
    jobs.dispose();
    super.dispose();
  }
}

class ChatController extends LoadController {
  final Workspace workspace;
  final String id;
  Conversation? conversation;
  Character? character;
  Entry? linkedEntry;
  bool? available;
  List<Job> jobs = [];
  WorkController? composer;
  late final messages = PagedController<Message>(
    (cursor) => workspace.repository.messages(id, cursor: cursor),
  );
  ChatController(this.workspace, this.id);
  Future<void> refresh() => run(() async {
    available = null;
    final conv = await workspace.repository.conversation(id);
    conversation = conv;
    character = await workspace.repository.character(conv.characterId);
    if (conv.entryId != null) {
      linkedEntry = await workspace.repository.entry(conv.entryId!);
    }
    composer ??= workspace.control(
      await workspace.draft(
        'message',
        '给${character!.name}的话',
        refs: {'conversationId': id},
      ),
    );
    notify();
    await messages.refresh();
    jobs = (await everyPage(
      (cursor) => workspace.repository.jobs(conv.characterId, cursor: cursor),
    )).where((j) => j.conversationId == id).toList();
    available = await workspace.repository.capability();
  });
  bool get pending => jobs.any((j) => j.pending);
  Future<MutationResult?> send() async {
    if (available != true || pending || composer == null) return null;
    final result = await composer!.submit();
    if (result != null) await refresh();
    return result;
  }

  @override
  void dispose() {
    messages.dispose();
    composer?.dispose();
    super.dispose();
  }
}

/// Screens own visibility; no polling or automatic writes after navigation away.
class ForegroundRefresh {
  final Future<void> Function() refresh;
  Timer? _timer;
  ForegroundRefresh(this.refresh);
  void setActive(bool active) {
    _timer?.cancel();
    _timer = null;
    if (active) {
      _timer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(refresh()),
      );
    }
  }

  void dispose() => setActive(false);
}
