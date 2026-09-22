import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'core/utils/app_theme.dart';
import 'features/marketplace/presentation/Screens/main_navigation.dart';
import 'features/marketplace/presentation/providers/home_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  runApp(const MvecApp());
}

class MvecApp extends StatelessWidget {
  const MvecApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeProvider()..loadHomeFeed(),
      child: MaterialApp(
        title: 'Mvec Marketplace',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const MainNavigation(),
      ),
    );
  }
}