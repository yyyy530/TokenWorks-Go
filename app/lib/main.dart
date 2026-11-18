import 'package:flutter/material.dart';

import 'src/desktop_home.dart';
import 'src/desktop_host.dart';
import 'src/host_manager.dart';
import 'src/host_vault.dart';
import 'src/remote_host.dart';
import 'src/ssh_host.dart';

void main() => runApp(const TokenWorksGoApp());

final class TokenWorksGoApp extends StatefulWidget {
  const TokenWorksGoApp({super.key, this.manager, this.remoteAccess});

  final HostManager? manager;
  final RemoteHostAccess? remoteAccess;

  @override
  State<TokenWorksGoApp> createState() => _TokenWorksGoAppState();
}

final class _TokenWorksGoAppState extends State<TokenWorksGoApp> {
  late final HostManager _manager = widget.manager ??
      HostManager(
        vault: const MethodChannelHostVault(),
        legacyStore: const DesktopStore(),
        sshConnect: connectSshHost,
        remoteConnect: _remoteAccess.connect,
      );
  late final RemoteHostAccess _remoteAccess = widget.remoteAccess ??
      RemoteHostAccess(vault: widget.manager?.vault ?? const MethodChannelHostVault());

  @override
  void dispose() {
    _manager.dispose();
    _remoteAccess.close();
    super.dispose();
  }

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
      home: DesktopHome(manager: _manager, remoteAccess: _remoteAccess),
    );
  }
}
