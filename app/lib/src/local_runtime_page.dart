import 'dart:async';

import 'package:flutter/material.dart';

import 'local_runtime.dart';

final class LocalRuntimePage extends StatefulWidget {
  const LocalRuntimePage({super.key, required this.workspace});

  final Widget Function(LocalRuntimeAccess access) workspace;

  @override
  State<LocalRuntimePage> createState() => _LocalRuntimePageState();
}

final class _LocalRuntimePageState extends State<LocalRuntimePage> {
  static const _runtime = LocalRuntimeChannel();
  LocalRuntimeStatus? _status;
  Timer? _timer;
  bool _busy = false;
  bool _loading = false;
  bool _channelFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_busy && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final status = await _runtime.status();
      if (mounted) {
        setState(() {
          _status = status;
          _channelFailed = false;
        });
      }
    } on Exception {
      if (mounted) setState(() => _channelFailed = true);
    } finally {
      _loading = false;
    }
  }

  Future<void> _command(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } on Exception {
      if (mounted) setState(() => _channelFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWorkspace() async {
    final access = await _runtime.connection();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => widget.workspace(access)));
  }

  String _description(LocalRuntimeStatus status) => switch (status.phase) {
    'missing' => '此安装包未包含 Linux 环境。请安装内置 Linux 的版本。',
    'unsupported' => '本机引擎需要搭载 64 位 ARM 处理器的 Android 8.0 或更新设备。',
    'installing' => '正在从安装包解压 Ubuntu、Node.js 和 DSH，首次启动需要一些时间。',
    'starting' => '正在启动本机 DSH…',
    'running' => '本机 DSH 正在运行。',
    'stopping' => '正在停止本机 DSH…',
    'error' => switch (status.error) {
      'insufficient-space' => '可用空间不足。首次安装 Linux 环境需要约 1 GB 可用空间。',
      'installed-version' => '已有 Linux 环境的版本与安装包不同，需要先迁移本机数据。',
      'stop-failed' => '本机进程仍在运行，请重试停止。',
      'engine-exited' => '本机引擎已退出，可以重新启动。',
      _ => '未能启动本机引擎，可以重试。',
    },
    _ => '首次启动会从 APK 解压 Linux 环境。引擎在手机上运行，模型仍需在本机设置中配置。',
  };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final failedStop = status?.error == 'stop-failed';
    final canStart =
        status?.phase == 'stopped' || (status?.phase == 'error' && !failedStop);
    final running = status?.phase == 'running';
    return Scaffold(
      appBar: AppBar(title: const Text('本机运行')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('本机 Linux 环境', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              _channelFailed
                  ? '无法读取 Android 本机运行状态。'
                  : status == null
                  ? '正在检查本机环境…'
                  : _description(status),
            ),
            if (status == null || status.busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: status?.phase == 'installing' && status!.progress > 0
                    ? status.progress / 100
                    : null,
              ),
            ],
            const SizedBox(height: 20),
            if (canStart)
              FilledButton(
                onPressed: _busy ? null : () => _command(_runtime.start),
                child: const Text('启动本机引擎'),
              ),
            if (running)
              FilledButton(
                onPressed: _busy ? null : () => _command(_openWorkspace),
                child: const Text('进入本机工作区'),
              ),
            if (running || failedStop)
              OutlinedButton(
                onPressed: _busy ? null : () => _command(_runtime.stop),
                child: const Text('停止引擎'),
              ),
          ],
        ),
      ),
    );
  }
}
