import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'l10n/l10n.dart';
import 'providers.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const DrishtiApp(),
  ));
}

class DrishtiApp extends ConsumerWidget {
  const DrishtiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'Drishti',
        debugShowCheckedModeBanner: false,
        locale: Locale(ref.watch(localeProvider)),
        supportedLocales: S.supportedLocales,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D6B5F)),
          useMaterial3: true,
        ),
        home: const HomeShell(),
      );
}
