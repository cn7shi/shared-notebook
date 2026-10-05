import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

class SessionController extends ChangeNotifier {
  final AccountRepository account;
  final SessionStore store;
  Session? session;
  bool busy = true;
  String? error;
  bool _disposed = false;
  SessionController(this.account, this.store);
  void notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restore() async {
    try {
      session = await store.read();
      account.useToken(session?.token);
    } catch (_) {
      error = '无法读取本机登录信息，请重新登录。';
    }
    busy = false;
    notify();
  }

  Future<void> authenticate(
    String email,
    String password, {
    required bool register,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    notify();
    try {
      final result = await account.authenticate(
        email,
        password,
        register: register,
      );
      await store.write(result);
      account.useToken(result.token);
      session = result;
    } on ApiFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = '无法保留登录信息，请检查本机存储后重试。';
    } finally {
      busy = false;
      notify();
    }
  }

  Future<void> logout({bool expired = false}) async {
    if (!expired) {
      try {
        await account.logout();
      } on ApiFailure catch (e) {
        if (e.code != 'UNAUTHORIZED') rethrow;
      }
    }
    await store.clear();
    account.useToken(null);
    session = null;
    notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
