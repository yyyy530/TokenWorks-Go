import 'package:flutter/material.dart';

import 'src/desktop_home.dart';
import 'src/desktop_host.dart';

void main() => runApp(const TokenWorksGoApp());

final class TokenWorksGoApp extends StatelessWidget {
  const TokenWorksGoApp({
    super.key,
    this.store = const DesktopStore(),
    this.connect = connectDesktop,
  });

  final DesktopStore store;
  final DesktopConnector connect;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1769AA);
    return MaterialApp(
      title: 'TokenWorks-Go',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: blue)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.dark,
        ),
      ),
      home: DesktopHome(store: store, connect: connect),
    );
  }
}
