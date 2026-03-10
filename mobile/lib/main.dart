import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'features/workout/core/foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Hive.initFlutter();

  // Configure foreground-service options once at startup.
  // The actual service is only started when a workout begins.
  WorkoutForegroundService.init();

  runApp(
    const ProviderScope(
      child: WithForegroundTask(child: App()),
    ),
  );
}
