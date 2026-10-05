import 'package:sembast_web/sembast_web.dart';

Future<Database> openDraftDatabase() =>
    databaseFactoryWeb.openDatabase('shared-notebook-drafts');
