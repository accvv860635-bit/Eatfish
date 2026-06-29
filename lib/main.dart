import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BigFishApp());
}

class BigFishApp extends StatelessWidget {
  const BigFishApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '大魚吃小魚',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xff18c7bb),
        scaffoldBackgroundColor: const Color(0xff061821),
      ),
      home: const HomeScreen(),
    );
  }
}
