import 'package:flutter/widgets.dart';

import 'app/bench_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final workbench = await Workbench.open();
  runApp(BenchApp(workbench: workbench));
}
