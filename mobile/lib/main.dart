import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/api.dart';
import 'data/local_store.dart';
import 'data/open_store.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const configured = String.fromEnvironment('API_BASE_URL');
  final base = configured.isNotEmpty
      ? configured
      : kIsWeb
      ? 'http://127.0.0.1:3300'
      : 'http://10.0.2.2:3300';
  final uri = Uri.tryParse(base);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      (kReleaseMode && uri.scheme != 'https')) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('请配置有效的 HTTPS 服务地址。'))),
      ),
    );
    return;
  }
  try {
    final database = await openDraftDatabase();
    final api = ApiClient(base);
    runApp(
      SharedNotebookApp(
        account: api,
        notebook: HttpNotebookRepository(api),
        sessions: const SecureSessionStore(),
        work: LocalWorkStore(database),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('本机存储无法打开，请检查存储权限后重试。'))),
      ),
    );
  }
}
