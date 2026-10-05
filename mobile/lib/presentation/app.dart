import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../application/session_controller.dart';
import '../application/work_controller.dart';
import '../domain/repositories.dart';
import 'common.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SharedNotebookApp extends StatefulWidget {
  final AccountRepository account;
  final NotebookRepository notebook;
  final SessionStore sessions;
  final WorkStore work;
  const SharedNotebookApp({
    super.key,
    required this.account,
    required this.notebook,
    required this.sessions,
    required this.work,
  });
  @override
  State<SharedNotebookApp> createState() => _SharedNotebookAppState();
}

class _SharedNotebookAppState extends State<SharedNotebookApp> {
  late final session = SessionController(widget.account, widget.sessions)
    ..restore();
  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final user = session.session;
      return AppScope(
        session: session,
        child: MaterialApp(
          key: ValueKey(user?.userId),
          title: '双方记事本',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          navigatorObservers: [routes],
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: paper,
            colorScheme: ColorScheme.fromSeed(
              seedColor: accent,
              surface: paper,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: paper,
              foregroundColor: ink,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
          ),
          home: user == null
              ? LoginScreen(controller: session)
              : HomeScreen(
                  workspace: Workspace(
                    widget.notebook,
                    widget.work,
                    user.userId,
                  ),
                  email: user.email,
                ),
        ),
      );
    },
  );
}
