import 'models.dart';

abstract interface class AccountRepository {
  void useToken(String? token);
  Future<Session> authenticate(
    String email,
    String password, {
    required bool register,
  });
  Future<void> logout();
}

abstract interface class SessionStore {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

abstract interface class WorkStore {
  Future<List<WorkingCopy>> list(String ownerId);
  Future<void> put(WorkingCopy copy);
  Future<void> remove(String id);
}

abstract interface class NotebookRepository {
  Future<bool> capability();
  Future<Page<Character>> characters({String? cursor});
  Future<Character> character(String id);
  Future<Page<Entry>> entries({String? characterId, String? cursor});
  Future<Entry> entry(String id);
  Future<Page<Grant>> grants(String characterId, {String? cursor});
  Future<Page<Conversation>> conversations(
    String characterId, {
    String? cursor,
  });
  Future<Conversation> conversation(String id);
  Future<Page<Message>> messages(String id, {String? cursor});
  Future<Page<Memory>> memories(String characterId, {String? cursor});
  Future<Page<Job>> jobs(String characterId, {String? cursor});
  Future<Job> job(String id);
  Future<MutationResult> execute(Command command);
  Future<MutationResult> latest(WorkingCopy copy);
}
