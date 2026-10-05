import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sembast/sembast.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage storage;
  const SecureSessionStore([this.storage = const FlutterSecureStorage()]);
  @override
  Future<Session?> read() async {
    final value = await storage.read(key: 'shared-notebook-session');
    return value == null ? null : Session.fromJson(jsonDecode(value));
  }

  @override
  Future<void> write(Session session) => storage.write(
    key: 'shared-notebook-session',
    value: jsonEncode(session.toJson()),
  );
  @override
  Future<void> clear() => storage.delete(key: 'shared-notebook-session');
}

class LocalWorkStore implements WorkStore {
  final Database database;
  final _copies = stringMapStoreFactory.store('working-copies');
  LocalWorkStore(this.database);
  @override
  Future<List<WorkingCopy>> list(String ownerId) async =>
      (await _copies.find(
            database,
            finder: Finder(filter: Filter.equals('ownerId', ownerId)),
          ))
          .map((r) => WorkingCopy.fromJson(Map<String, dynamic>.from(r.value)))
          .toList();
  @override
  Future<void> put(WorkingCopy copy) async {
    await _copies.record(copy.localId).put(database, copy.toJson());
  }

  @override
  Future<void> remove(String id) async {
    await _copies.record(id).delete(database);
  }
}
