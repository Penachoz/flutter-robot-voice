import 'package:flutter/material.dart';
import 'pages/home_page.dart';

class RobotDogApp extends StatelessWidget {
  const RobotDogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RobotDog (UDP ultra-low-latency)',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}
