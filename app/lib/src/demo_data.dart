import 'package:tokenworks_core/tokenworks_core.dart';

final demoAccount = AccountSnapshot(
  displayName: '统一身份用户',
  models: const [
    SchoolModel(
      id: 'demo-school-model',
      displayName: '学校模型（演示）',
      contextWindow: 128000,
      maxOutput: 8192,
      supportsImages: true,
      reasoningLevels: ['Medium', 'High'],
    ),
  ],
  quotas: [
    QuotaWindow(
      id: '24h',
      remaining: 82.4,
      limit: 100,
      resetsAt: DateTime.utc(2026, 11, 18),
    ),
  ],
  network: NetworkScope.campus,
);

final demoSessions = <SessionSummary>[
  SessionSummary(
    id: 'demo-research',
    title: '多模态大模型文献综述',
    workspace: '科研资料',
    mode: WorkspaceMode.research,
    updatedAt: DateTime.utc(2026, 11, 17, 11, 30),
    isRunning: true,
  ),
  SessionSummary(
    id: 'demo-office',
    title: '问卷统计与组会报告',
    workspace: '数据分析',
    mode: WorkspaceMode.standard,
    updatedAt: DateTime.utc(2026, 11, 17, 10),
    needsAttention: true,
  ),
];
