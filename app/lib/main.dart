import 'package:flutter/material.dart';
import 'package:tokenworks_core/tokenworks_core.dart';

import 'src/demo_data.dart';

void main() => runApp(const TokenWorksGoApp());

final class TokenWorksGoApp extends StatelessWidget {
  const TokenWorksGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1769AA);
    return MaterialApp(
      title: 'TokenWorks-Go',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
      ),
      home: const WorkspaceHome(),
    );
  }
}

final class WorkspaceHome extends StatefulWidget {
  const WorkspaceHome({super.key});

  @override
  State<WorkspaceHome> createState() => WorkspaceHomeState();
}

final class WorkspaceHomeState extends State<WorkspaceHome> {
  WorkspaceMode selectedMode = WorkspaceMode.standard;
  final composer = TextEditingController();

  /// Test-visible selection state: the active WorkspaceMode after user taps.
  @visibleForTesting
  WorkspaceMode get activeMode => selectedMode;

  @override
  void dispose() {
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('TokenWorks-Go'),
        actions: [
          IconButton(
            tooltip: '主机与连接',
            onPressed: () {},
            icon: const Icon(Icons.devices_outlined),
          ),
        ],
      ),
      drawer: const SessionDrawer(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            AccountCard(account: demoAccount),
            const SizedBox(height: 28),
            Text(
              '今天想一起完成什么？',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            const Text('选择一个工作区，让任务从开始走到交付。'),
            const SizedBox(height: 20),
            ModeSelector(
              selected: selectedMode,
              onChanged: (mode) => setState(() => selectedMode = mode),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.blueGrey.shade100),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: composer,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '描述任务，/ 调用技能，@ 引用文件或对话',
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        IconButton(
                          tooltip: '添加附件',
                          onPressed: () {},
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        const Text('默认工作区'),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          label: const Text('开始'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('进行中的工作', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final session in demoSessions) SessionTile(session: session),
          ],
        ),
      ),
    );
  }
}

final class AccountCard extends StatelessWidget {
  const AccountCard({required this.account, super.key});
  final AccountSnapshot account;

  @override
  Widget build(BuildContext context) {
    final quota = account.quotas.first;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.school_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('校园网 · ${account.models.length} 个模型 · 剩余 ${quota.remaining}%'),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

final class ModeSelector extends StatelessWidget {
  const ModeSelector({required this.selected, required this.onChanged, super.key});
  final WorkspaceMode selected;
  final ValueChanged<WorkspaceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<WorkspaceMode>(
      showSelectedIcon: false,
      segments: [
        for (final mode in WorkspaceMode.values)
          ButtonSegment(value: mode, label: Text(mode.label)),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

final class SessionTile extends StatelessWidget {
  const SessionTile({required this.session, super.key});
  final SessionSummary session;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(session.isRunning ? Icons.sync : Icons.chat_bubble_outline),
        title: Text(session.title),
        subtitle: Text('${session.workspace} · ${session.mode.label}模式'),
        trailing: session.needsAttention
            ? const Badge(child: Icon(Icons.notifications_outlined))
            : const Icon(Icons.chevron_right),
        onTap: () {},
      ),
    );
  }
}

final class SessionDrawer extends StatelessWidget {
  const SessionDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text('我的工作区'),
              subtitle: Text('会话与文件按主机隔离'),
            ),
            for (final session in demoSessions)
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: Text(session.title),
                subtitle: Text(session.workspace),
              ),
            const Divider(),
            const ListTile(leading: Icon(Icons.extension_outlined), title: Text('插件与技能')),
            const ListTile(leading: Icon(Icons.schedule_outlined), title: Text('自动化任务')),
            const ListTile(leading: Icon(Icons.settings_outlined), title: Text('设置')),
          ],
        ),
      ),
    );
  }
}
