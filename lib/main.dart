import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_strings.dart';
import 'presentation/providers/theme_provider.dart';
import 'data/local/local_data_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Hive.initFlutter();
  await LocalDataService.seedIfNeeded();
  // Sync dropdown lists from the backend in the background —
  // does not block startup; falls back to local data if offline.
  LocalDataService.syncFromApi();

  runApp(const ProviderScope(child: PlasticFactoryApp()));
}

class PlasticFactoryApp extends ConsumerWidget {
  const PlasticFactoryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final lightTheme = AppTheme.lightTheme();
    final darkTheme = AppTheme.darkTheme();

    const localizationsDelegates = [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
    const supportedLocales = [Locale('ar', 'SA'), Locale('en', 'US')];

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: const Locale('ar', 'SA'),
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales,
      routerConfig: router,
    );
  }
}
