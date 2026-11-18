import 'package:flutter/material.dart';

import 'desktop_host.dart';
import 'ustc_quota.dart';

final class UstcQuotaPage extends StatefulWidget {
  const UstcQuotaPage({required this.load, super.key});

  final Future<UstcQuotaSnapshot?> Function() load;

  @override
  State<UstcQuotaPage> createState() => _UstcQuotaPageState();
}

final class _UstcQuotaPageState extends State<UstcQuotaPage> {
  late Future<UstcQuotaSnapshot?> _snapshot = widget.load();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('学校额度')),
    body: SafeArea(
      child: FutureBuilder<UstcQuotaSnapshot?>(
        future: _snapshot,
        builder: (context, state) {
          final loaded = state.connectionState == ConnectionState.done;
          final snapshot = state.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!loaded)
                const LinearProgressIndicator()
              else ...[
                _summary(state.error, snapshot),
                if (snapshot != null)
                  for (final account in snapshot.accounts) _QuotaCard(account),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final updated = widget.load();
                      setState(() {
                        _snapshot = updated;
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新额度'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );

  Widget _summary(Object? error, UstcQuotaSnapshot? snapshot) {
    if (error != null) {
      return Text(
        error is FormatException ? '主机返回了不兼容的额度数据。' : desktopError(error),
      );
    }
    if (snapshot == null) return const Text('当前主机未提供额度查询。');
    if (snapshot.waitingForLogin) {
      return const Text('桌面 TokenWorks 的额度服务未就绪，请检查桌面登录。');
    }
    if (snapshot.accounts.isEmpty) return const Text('主机暂未返回学校额度。');
    final label = snapshot.fromTokenWorks ? '桌面 TokenWorks' : '桌面 USTC 模型配置';
    final time = snapshot.generatedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        time == null ? label : '$label · ${_localDateTime(context, time)}',
      ),
    );
  }
}

final class _QuotaCard extends StatelessWidget {
  const _QuotaCard(this.account);

  final UstcQuotaAccount account;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(account.label, style: Theme.of(context).textTheme.titleMedium),
          if (!account.available || account.stale) ...[
            const SizedBox(height: 4),
            Text(account.stale ? '部分额度来自上次查询' : '额度暂不可用'),
          ],
          for (final window in account.windows)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _QuotaWindowView(window),
            ),
        ],
      ),
    ),
  );
}

final class _QuotaWindowView extends StatelessWidget {
  const _QuotaWindowView(this.window);

  final UstcQuotaWindow window;

  @override
  Widget build(BuildContext context) {
    final resetsAt = window.resetsAt;
    final resetting =
        window.state == QuotaState.resetting ||
        (window.state == QuotaState.active &&
            resetsAt != null &&
            !resetsAt.isAfter(DateTime.now()));
    final remaining = window.remaining;
    final usedFraction = window.usedFraction;
    final value = resetting
        ? '等待重置'
        : remaining == null
        ? '待获取'
        : '剩余 ${_formatQuota(remaining)} / ${_formatQuota(window.limit!)}';
    final stale = window.state == QuotaState.stale ? '（上次查询）' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${window.label} · $value$stale'),
        if (!resetting && usedFraction != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: 1 - usedFraction,
            semanticsLabel: '${window.label} 剩余额度比例',
          ),
        ],
        if (resetsAt != null) Text('重置时间 ${_localDateTime(context, resetsAt)}'),
      ],
    );
  }
}

String _localDateTime(BuildContext context, DateTime time) {
  final local = time.toLocal();
  final formatter = MaterialLocalizations.of(context);
  final date = formatter.formatCompactDate(local);
  final clock = formatter.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: true,
  );
  return '$date $clock';
}

String _formatQuota(double value) {
  if (value > 0 && value < 0.01) return '<0.01';
  return value.toStringAsFixed(value == value.truncateToDouble() ? 0 : 2);
}
