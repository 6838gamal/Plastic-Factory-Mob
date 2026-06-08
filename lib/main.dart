import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_strings.dart';
import 'data/supabase/supabase_config.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/pages/setup/setup_required_page.dart';

bool _supabaseReady = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Hive.initFlutter();

  if (SupabaseConfig.isConfigured) {
    try {
      await SupabaseConfig.initialize();
      _supabaseReady = true;
    } catch (e) {
      _supabaseReady = false;
    }
  }

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

    if (!_supabaseReady) {
      return MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        locale: const Locale('ar', 'SA'),
        localizationsDelegates: localizationsDelegates,
        supportedLocales: supportedLocales,
        home: const SetupRequiredPage(),
      );
    }

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
