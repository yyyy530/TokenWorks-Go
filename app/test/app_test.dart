import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tokenworks_core/tokenworks_core.dart';
import 'package:tokenworks_go/main.dart';

void main() {
  testWidgets('renders account, four modes and active work', (tester) async {
    await tester.pumpWidget(const TokenWorksGoApp());
    expect(find.text('TokenWorks-Go'), findsOneWidget);
    expect(find.text('今天想一起完成什么？'), findsOneWidget);
    for (final mode in WorkspaceMode.values) {
      expect(find.text(mode.label), findsOneWidget);
    }
    expect(find.text('多模态大模型文献综述'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('问卷统计与组会报告'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('问卷统计与组会报告'), findsOneWidget);
  });

  testWidgets('mode selection actually updates the selected segment state', (tester) async {
    await tester.pumpWidget(const TokenWorksGoApp());
    final state = tester.state<WorkspaceHomeState>(find.byType(WorkspaceHome));
    expect(state.activeMode, WorkspaceMode.standard);

    await tester.tap(find.text('科研'));
    await tester.pump();
    expect(state.activeMode, WorkspaceMode.research);

    await tester.tap(find.text('学习'));
    await tester.pump();
    expect(state.activeMode, WorkspaceMode.study);

    // Composer content survives mode switches (no state reset).
    await tester.enterText(find.byType(TextField), '帮我整理文献');
    await tester.tap(find.text('标准'));
    await tester.pump();
    expect(state.activeMode, WorkspaceMode.standard);
    expect(find.text('帮我整理文献'), findsOneWidget);
  });

  testWidgets('drawer shows sessions, plugins and settings', (tester) async {
    await tester.pumpWidget(const TokenWorksGoApp());
    await tester.dragFrom(Offset.zero, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('我的工作区'), findsOneWidget);
    expect(find.text('多模态大模型文献综述'), findsWidgets);
    expect(find.text('插件与技能'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('account card reflects demo account snapshot', (tester) async {
    await tester.pumpWidget(const TokenWorksGoApp());
    expect(find.text('统一身份用户'), findsOneWidget);
    expect(find.textContaining('校园网'), findsOneWidget);
  });
}
