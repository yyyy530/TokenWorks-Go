import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import 'desktop_host.dart';
import 'plugin_market.dart';

typedef MarketIndexLoader = Future<MarketIndex> Function(Uri uri);

final class PluginsPage extends StatefulWidget {
  const PluginsPage({required this.client, this.marketLoader = fetchMarketIndex, super.key});

  final DshClient client;
  final MarketIndexLoader marketLoader;

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

final class _PluginsPageState extends State<PluginsPage> {
  List<PluginBundle> _bundles = const [];
  MarketIndex? _market;
  final _search = TextEditingController();
  String _marketKind = 'official';
  String? _category;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInstalled());
    unawaited(_loadMarket());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadInstalled() async {
    setState(() => _error = null);
    try {
      final bundles = await widget.client.listBundles();
      if (mounted) setState(() => _bundles = bundles);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    }
  }

  Future<void> _loadMarket() async {
    setState(() {
      _busy = true;
      _error = null;
      _category = null;
    });
    try {
      final market = await widget.marketLoader(_marketKind == 'official' ? officialMarketUri : allMarketUri);
      if (mounted) setState(() => _market = market);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(PluginBundle bundle, bool enabled) async {
    setState(() => _busy = true);
    try {
      final result = await widget.client.setBundleEnabled(bundle.name, enabled);
      if (!result.succeeded) throw HostConnectionException(pluginOperationError(result));
      await _loadInstalled();
      if (mounted && result.needsRestart) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，重启主机引擎后生效。')));
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<MarketPlugin> get _visibleMarket {
    final market = _market;
    if (market == null) return const [];
    final query = _search.text.trim().toLowerCase();
    return [
      for (final plugin in market.plugins)
        if ((_category == null || plugin.category == _category) &&
            (query.isEmpty || '${plugin.displayTitle()}\n${plugin.name}\n${plugin.displayDescription() ?? ''}'.toLowerCase().contains(query)))
          plugin,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('插件'),
          bottom: const TabBar(tabs: [Tab(text: '已安装'), Tab(text: '插件市场')]),
          actions: [IconButton(onPressed: _busy ? null : _loadInstalled, tooltip: '刷新', icon: const Icon(Icons.refresh))],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    _installedView(),
                    _marketView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _installedView() {
    if (_bundles.isEmpty) return const Center(child: Text('这台主机还没有插件条目。'));
    final groups = [
      ('你安装的插件', _bundles.where((bundle) => !bundle.official).toList()),
      ('DSH 官方', _bundles.where((bundle) => bundle.official).toList()),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (!widget.client.canInstallPlugins)
          const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('当前连接只能开关插件；安装和卸载请在电脑上的 DSH 中执行。'))),
        for (final (title, bundles) in groups) ...[
          if (bundles.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          for (final bundle in bundles)
            Card(
              child: ListTile(
                title: Text(bundle.title()),
                subtitle: Text('${bundle.version ?? bundle.installTargetVersion ?? bundle.name}${bundle.error == null ? '' : ' · ${bundle.error!.code}'}'),
                trailing: bundle.installed && bundle.readOnlyReason == null
                    ? Switch(value: bundle.enabled, onChanged: _busy ? null : (value) => _toggle(bundle, value))
                    : null,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => PluginBundleDetailPage(client: widget.client, bundle: bundle)),
                ).then((_) => _loadInstalled()),
              ),
            ),
        ],
      ],
    );
  }

  Widget _marketView() {
    final market = _market;
    final plugins = _visibleMarket;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'official', label: Text('官方')),
              ButtonSegment(value: 'all', label: Text('全部')),
            ],
            selected: {_marketKind},
            onSelectionChanged: _busy ? null : (value) {
              setState(() => _marketKind = value.single);
              unawaited(_loadMarket());
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索插件', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (market != null && market.categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: const Text('全部分类'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
                ),
                for (final entry in market.categories.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(entry.value.title.resolve('zh')),
                      selected: _category == entry.key,
                      onSelected: (_) => setState(() => _category = entry.key),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: market == null
              ? Center(child: Text(_busy ? '正在读取市场…' : '市场暂时不可用。'))
              : plugins.isEmpty
              ? const Center(child: Text('没有符合条件的插件。'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: plugins.length,
                  itemBuilder: (_, index) {
                    final plugin = plugins[index];
                    return Card(
                      child: ListTile(
                        title: Text(plugin.displayTitle()),
                        subtitle: Text('${plugin.displayDescription() ?? plugin.name}\n${plugin.latest.version}${plugin.latest.enginesDsh == null ? '' : ' · 需要 DSH ${plugin.latest.enginesDsh}'}'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => MarketPluginDetailPage(client: widget.client, plugin: plugin)),
                        ).then((_) => _loadInstalled()),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

String pluginOperationError(PluginOperationResult result) {
  final error = result.error;
  if (error != null) return '${error.code}${error.diagnostic == null ? '' : '：${error.diagnostic}'}';
  final output = result.packageResult?.output.trim();
  if (output != null && output.isNotEmpty) {
    return output.length > 1000 ? output.substring(output.length - 1000) : output;
  }
  return '插件操作未完成：${result.application.wire}';
}

final class PluginBundleDetailPage extends StatefulWidget {
  const PluginBundleDetailPage({required this.client, required this.bundle, super.key});

  final DshClient client;
  final PluginBundle bundle;

  @override
  State<PluginBundleDetailPage> createState() => _PluginBundleDetailPageState();
}

final class _PluginBundleDetailPageState extends State<PluginBundleDetailPage> {
  late bool _enabled = widget.bundle.enabled;
  bool _busy = false;
  String? _error;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    try {
      final result = await widget.client.setBundleEnabled(widget.bundle.name, value);
      if (!result.succeeded) throw HostConnectionException(pluginOperationError(result));
      if (mounted) setState(() => _enabled = value);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('卸载插件？'),
        content: Text('将从当前主机移除「${widget.bundle.title()}」，插件保存的数据和设置会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('卸载')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var undo = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: const Text('4 秒后卸载，点撤销可取消。'),
        action: SnackBarAction(label: '撤销', onPressed: () => undo = true),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 4));
    if (undo) return;
    if (!mounted) {
      await widget.client.removeBundle(widget.bundle.name);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.client.removeBundle(widget.bundle.name);
      if (!result.succeeded) throw HostConnectionException(pluginOperationError(result));
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = widget.bundle;
    return Scaffold(
      appBar: AppBar(title: Text(bundle.title())),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Text(bundle.name, style: Theme.of(context).textTheme.titleMedium),
          Text('版本：${bundle.version ?? bundle.installTargetVersion ?? '未知'}'),
          if (bundle.summary() case final summary?) ...[
            const SizedBox(height: 12),
            Text(summary),
          ],
          if (bundle.installed)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用'),
              subtitle: Text(bundle.readOnlyReason ?? '开关对这台主机上的所有对话生效。'),
              value: _enabled,
              onChanged: _busy || bundle.readOnlyReason != null ? null : _toggle,
            ),
          if (bundle.removable && widget.client.canInstallPlugins)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(onPressed: _busy ? null : _remove, icon: const Icon(Icons.delete_outline), label: const Text('卸载')),
            ),
          const SizedBox(height: 20),
          if (bundle.rows.isNotEmpty) Text('插件条目', style: Theme.of(context).textTheme.titleLarge),
          for (final row in bundle.rows)
            ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(row.meta?.title?.resolve('zh') ?? row.rowId), subtitle: Text(row.moduleName)),
          const SizedBox(height: 12),
          const Text('插件的完整设置请在桌面 DSH 网页版中修改；原生设置表单尚未迁移。'),
        ],
      ),
    );
  }
}

final class MarketPluginDetailPage extends StatefulWidget {
  const MarketPluginDetailPage({required this.client, required this.plugin, super.key});

  final DshClient client;
  final MarketPlugin plugin;

  @override
  State<MarketPluginDetailPage> createState() => _MarketPluginDetailPageState();
}

final class _MarketPluginDetailPageState extends State<MarketPluginDetailPage> {
  bool _busy = false;
  String? _error;
  String? _message;

  Future<void> _install({List<String>? approvedBuilds}) async {
    final target = widget.plugin.latest.installTarget(widget.plugin.name);
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final inspection = await widget.client.inspectPlugin(target.spec, registry: target.registry);
      if (inspection case PluginInspectionRefused(:final problem, :final reason)) {
        throw HostConnectionException('主机拒绝安装：$problem\n$reason');
      }
      if (approvedBuilds == null) {
        if (!mounted) return;
        final accepted = inspection as PluginInspectionAccepted;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('确认安装插件'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${accepted.name ?? widget.plugin.name}@${accepted.version ?? widget.plugin.latest.version}'),
                const SizedBox(height: 8),
                Text('来源：${accepted.registry ?? target.registry ?? '主机默认 npm 注册表'}'),
                if (widget.plugin.labels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('风险标记：${widget.plugin.labels.join('、')}\n风险标记描述包具备的能力，不代表安全保证。'),
                ],
                const SizedBox(height: 8),
                const Text('安装会在当前主机下载并运行插件包。'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('安装')),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final requestId = 'market-${DateTime.now().microsecondsSinceEpoch}';
      final result = await widget.client.installBundle(
        target.spec,
        requestId: requestId,
        enabled: true,
        saveExact: true,
        registry: target.registry,
        approvedBuilds: approvedBuilds,
      );
      if (approvedBuilds == null && result.pendingBuilds.isNotEmpty) {
        if (!mounted) return;
        final approved = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('允许构建脚本并重试？'),
            content: Text('这些软件包的构建脚本被拦下，会在当前主机运行：\n\n${result.pendingBuilds.join('\n')}\n\n看清软件包列表后再允许。'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('允许并重试')),
            ],
          ),
        );
        if (approved == true && mounted) {
          await _install(approvedBuilds: result.pendingBuilds);
        }
        return;
      }
      if (!result.succeeded) throw HostConnectionException(pluginOperationError(result));
      if (mounted) {
        setState(() => _message = result.needsRestart ? '已安装，重启主机引擎后生效。' : '插件已安装并启用。');
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    return Scaffold(
      appBar: AppBar(title: Text(plugin.displayTitle())),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_message case final message?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          Text(plugin.name, style: Theme.of(context).textTheme.titleMedium),
          Text('最新版本：${plugin.latest.version}'),
          if (plugin.latest.enginesDsh case final requirement?) Text('需要 DSH：$requirement'),
          if (plugin.author case final author?) Text('作者：$author'),
          if (plugin.displayDescription() case final description?) ...[
            const SizedBox(height: 16),
            Text(description),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            children: [
              if (plugin.category case final category?) Chip(label: Text(category)),
              for (final label in plugin.labels) Chip(label: Text(label)),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy || !widget.client.canInstallPlugins ? null : _install,
            icon: const Icon(Icons.download),
            label: const Text('安装到当前主机'),
          ),
          if (!widget.client.canInstallPlugins)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('当前连接不能直接安装，请在电脑上的 DSH 中执行安装命令。'),
            ),
        ],
      ),
    );
  }
}
