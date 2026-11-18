import 'dart:async';
import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import 'desktop_host.dart';
import 'session_page.dart';

String scheduleTimingText(ScheduleTask task) {
  final zone = task.timeZone == null ? '' : '（${task.timeZone}）';
  return switch (task.kind) {
    'at' => '单次：${task.scheduledAt?.toLocal() ?? '时间未知'}',
    'after' => '创建后 ${task.afterSeconds ?? '?'} 秒执行一次',
    'every' => '每 ${task.everySeconds ?? '?'} 秒重复',
    'daily' => '每天 ${task.time ?? '?'} $zone',
    'weekly' => '每周 ${task.weekdays.join('、')} 日，${task.time ?? '?'} $zone',
    'cron' || 'rrule' => '${task.expression ?? '周期规则'} $zone',
    _ => task.kind,
  };
}

String scheduleCreatePrompt({
  required String title,
  required String prompt,
  required ScheduleTiming timing,
}) {
  final arguments = scheduleCreateArguments(title: title, prompt: prompt, timing: timing);
  return '请调用 schedule_create 工具创建自动化任务，严格使用以下 JSON 参数，不要自行更改：\n'
      '${const JsonEncoder.withIndent('  ').convert(arguments)}';
}

final class SchedulesPage extends StatefulWidget {
  const SchedulesPage({required this.client, this.sessionId, super.key});

  final DshClient client;
  final String? sessionId;

  @override
  State<SchedulesPage> createState() => _SchedulesPageState();
}

final class _SchedulesPageState extends State<SchedulesPage> {
  final _search = TextEditingController();
  List<ScheduleTask> _tasks = const [];
  String _filter = 'active';
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var tasks = await widget.client.scheduleCatalog();
      final sessionId = widget.sessionId;
      if (sessionId != null) {
        tasks = tasks.where((task) => task.active && (task.involvedSessionIds.contains(sessionId) || task.sessionId == sessionId)).toList();
      }
      tasks = [...tasks]..sort((a, b) => (b.scheduledAt ?? b.lastDeliveredAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.scheduledAt ?? a.lastDeliveredAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
      if (mounted) setState(() => _tasks = tasks);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ScheduleTask> get _visible {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final task in _tasks)
        if ((_filter == 'all' || _filter == 'active' && task.active || _filter == 'ended' && !task.active) &&
            (query.isEmpty || '${task.title}\n${task.prompt}\n${scheduleTimingText(task)}'.toLowerCase().contains(query)))
          task,
    ];
  }

  Future<void> _openDetail(ScheduleTask task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ScheduleDetailPage(client: widget.client, task: task)),
    );
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final sessionId = widget.sessionId;
    if (sessionId == null) return;
    final request = await showDialog<({String title, String prompt, ScheduleTiming timing})>(
      context: context,
      builder: (_) => const _ScheduleCreateDialog(),
    );
    if (request == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.prompt(
        sessionId,
        scheduleCreatePrompt(title: request.title, prompt: request.prompt, timing: request.timing),
        timeZone: request.timing is AtTiming
            ? (request.timing as AtTiming).timeZone
            : switch (request.timing) {
                DailyTiming(:final timeZone) => timeZone,
                WeeklyTiming(:final timeZone) => timeZone,
                CronTiming(:final timeZone) => timeZone,
                _ => null,
              },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已交给当前对话的模型创建，请在对话中确认 schedule_create 工具调用。')),
        );
        Navigator.of(context).pop();
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自动化任务'),
        actions: [
          IconButton(onPressed: _busy ? null : _load, tooltip: '刷新', icon: const Icon(Icons.refresh)),
          if (widget.sessionId != null)
            IconButton(onPressed: _busy ? null : _create, tooltip: '新建', icon: const Icon(Icons.add)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索名称、指令和规则', border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'active', label: Text('已开启')),
                  ButtonSegment(value: 'ended', label: Text('已结束')),
                  ButtonSegment(value: 'all', label: Text('全部')),
                ],
                selected: {_filter},
                onSelectionChanged: (value) => setState(() => _filter = value.single),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: visible.isEmpty
                  ? Center(child: Text(_busy ? '正在读取主机任务…' : '没有符合条件的任务。'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: visible.length,
                      itemBuilder: (_, index) {
                        final task = visible[index];
                        return Card(
                          child: ListTile(
                            title: Text(task.title),
                            subtitle: Text('${scheduleTimingText(task)}\n${task.active ? '下次：${task.scheduledAt?.toLocal() ?? '未知'}' : '已结束'}${task.lastDeliveredAt == null ? '' : ' · 上次：${task.lastDeliveredAt!.toLocal()}'}'),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openDetail(task),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

final class ScheduleDetailPage extends StatefulWidget {
  const ScheduleDetailPage({required this.client, required this.task, super.key});

  final DshClient client;
  final ScheduleTask task;

  @override
  State<ScheduleDetailPage> createState() => _ScheduleDetailPageState();
}

final class _ScheduleDetailPageState extends State<ScheduleDetailPage> {
  late ScheduleTask _task = widget.task;
  List<ScheduleRun> _runs = const [];
  String? _nextBefore;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_history());
  }

  Future<void> _history({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await widget.client.scheduleHistory(_task, before: more ? _nextBefore : null);
      if (mounted) {
        setState(() {
          _runs = more ? [..._runs, ...page.runs] : page.runs;
          _nextBefore = page.nextBefore;
          if (page.missing case final code?) _error = '主机返回：$code';
        });
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.client.runScheduledTask(_task, timeZone: _task.timeZone);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已请求立即运行。')));
      await _history();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    if (!_task.active) return;
    final result = await showDialog<({String title, String prompt, ScheduleTiming? timing})>(
      context: context,
      builder: (_) => _ScheduleEditDialog(task: _task),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final update = await widget.client.editSchedule(_task, title: result.title, prompt: result.prompt, timing: result.timing);
      if (update.updated && update.task != null) {
        if (mounted) setState(() => _task = update.task!);
        await _history();
      } else {
        if (mounted) setState(() => _error = '主机没有保存修改：${update.code ?? update.message ?? '未知原因'}');
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除自动化任务？'),
        content: Text('将删除「${_task.title}」及其运行历史，此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.deleteSchedule(_task);
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openSession() {
    final id = _task.sessionId;
    if (id == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SessionPage(client: widget.client, sessionId: id, title: _task.title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_task.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Text(scheduleTimingText(_task), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('状态：${_task.status ?? (_task.active ? 'active' : 'inactive')}'),
            Text('下次运行：${_task.scheduledAt?.toLocal() ?? '无'}'),
            const SizedBox(height: 16),
            Text('指令', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            SelectableText(_task.prompt),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(onPressed: _busy || !_task.active ? null : _run, icon: const Icon(Icons.play_arrow), label: const Text('立即运行')),
                OutlinedButton(onPressed: _busy || !_task.active ? null : _edit, child: const Text('编辑')),
                if (_task.sessionId != null) OutlinedButton(onPressed: _openSession, child: const Text('关联对话')),
                TextButton(onPressed: _busy ? null : _delete, child: const Text('删除')),
              ],
            ),
            const SizedBox(height: 24),
            Text('运行历史', style: Theme.of(context).textTheme.titleLarge),
            if (_runs.isEmpty && !_busy) const Padding(padding: EdgeInsets.only(top: 8), child: Text('还没有运行记录。')),
            for (final run in _runs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('投递：${run.deliveredAt?.toLocal() ?? '未知'}'),
                subtitle: Text('计划：${run.scheduledAt?.toLocal() ?? '未知'}${run.targetSessionId == null ? '' : ' · 会话 ${run.targetSessionId}'}'),
              ),
            if (_nextBefore != null)
              TextButton(onPressed: _busy ? null : () => _history(more: true), child: const Text('加载更早记录')),
          ],
        ),
      ),
    );
  }
}

final class _ScheduleCreateDialog extends StatefulWidget {
  const _ScheduleCreateDialog();

  @override
  State<_ScheduleCreateDialog> createState() => _ScheduleCreateDialogState();
}

final class _ScheduleCreateDialogState extends State<_ScheduleCreateDialog> {
  final _title = TextEditingController();
  final _prompt = TextEditingController();
  final _timing = ScheduleTimingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _timing.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final timing = _timing.build();
      if (_title.text.trim().isEmpty || _prompt.text.trim().isEmpty) {
        throw const FormatException('请填写名称和指令。');
      }
      Navigator.of(context).pop((title: _title.text.trim(), prompt: _prompt.text.trim(), timing: timing));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建自动化任务'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _prompt, maxLines: 4, decoration: const InputDecoration(labelText: '到点发送的指令', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          ScheduleTimingEditor(controller: _timing),
          if (_error case final error?) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          const Text('任务由当前对话的主机创建，时间按主机时区。'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('交给对话创建')),
      ],
    );
  }
}

final class _ScheduleEditDialog extends StatefulWidget {
  const _ScheduleEditDialog({required this.task});

  final ScheduleTask task;

  @override
  State<_ScheduleEditDialog> createState() => _ScheduleEditDialogState();
}

final class _ScheduleEditDialogState extends State<_ScheduleEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  final _timing = ScheduleTimingController();
  bool _changeTiming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task.title);
    _prompt = TextEditingController(text: widget.task.prompt);
    _timing.setKind(widget.task.kind == 'after' ? 'every' : widget.task.kind);
    if (widget.task.everySeconds case final seconds?) _timing.everySeconds.text = '$seconds';
    if (widget.task.time case final time?) {
      _timing.atTime.text = time;
      _timing.dailyTime.text = time;
      _timing.weeklyTime.text = time;
    }
    if (widget.task.expression case final expression?) _timing.cron.text = expression;
    if (widget.task.timeZone case final zone?) _timing.timeZone.text = zone;
    _timing.weekdays.addAll(widget.task.weekdays);
  }

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    _timing.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final timing = _changeTiming ? _timing.build() : null;
      if (_title.text.trim().isEmpty || _prompt.text.trim().isEmpty) {
        throw const FormatException('名称和指令不能为空。');
      }
      Navigator.of(context).pop((title: _title.text.trim(), prompt: _prompt.text.trim(), timing: timing));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑自动化任务'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _title, decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _prompt, maxLines: 4, decoration: const InputDecoration(labelText: '指令', border: OutlineInputBorder())),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('同时修改运行时间'),
            value: _changeTiming,
            onChanged: (value) => setState(() => _changeTiming = value),
          ),
          if (_changeTiming) ScheduleTimingEditor(controller: _timing),
          if (_error case final error?) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

final class ScheduleTimingKind extends ValueNotifier<String> {
  ScheduleTimingKind() : super('every');

  void refresh() => notifyListeners();
}

/// Mutable form state kept outside the widget so the dialog can validate and
/// build the protocol timing without a second parallel model.
final class ScheduleTimingController {
  final kind = ScheduleTimingKind();
  final date = TextEditingController();
  final atTime = TextEditingController(text: '09:00:00');
  final everySeconds = TextEditingController(text: '3600');
  final dailyTime = TextEditingController(text: '09:00:00');
  final weeklyTime = TextEditingController(text: '09:00:00');
  final weekdays = <int>{1};
  final cron = TextEditingController();
  final timeZone = TextEditingController(text: 'Asia/Shanghai');

  void setKind(String value) => kind.value = const {'at', 'every', 'daily', 'weekly', 'cron'}.contains(value) ? value : 'every';

  void toggleWeekday(int day, bool selected) {
    if (selected) {
      weekdays.add(day);
    } else {
      weekdays.remove(day);
    }
    kind.refresh();
  }

  void dispose() {
    kind.dispose();
    date.dispose();
    atTime.dispose();
    everySeconds.dispose();
    dailyTime.dispose();
    weeklyTime.dispose();
    cron.dispose();
    timeZone.dispose();
  }

  ScheduleTiming build() {
    final zone = timeZone.text.trim();
    if (zone.isEmpty) throw const FormatException('请填写 IANA 时区，例如 Asia/Shanghai。');
    String time(TextEditingController controller) {
      final value = controller.text.trim();
      final match = RegExp(r'^(\d{2}):(\d{2})(?::(\d{2}))?$').firstMatch(value);
      if (match == null) throw const FormatException('时间格式应为 HH:mm:ss。');
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final second = int.parse(match.group(3) ?? '00');
      if (hour > 23 || minute > 59 || second > 59) throw const FormatException('时间超出有效范围。');
      return '${match.group(1)}:${match.group(2)}:${match.group(3) ?? '00'}';
    }

    return switch (kind.value) {
      'at' => AtTiming(
          date: _validDate(date.text.trim()),
          time: time(atTime),
          timeZone: zone,
        ),
      'every' => EveryTiming(_validEvery(everySeconds.text.trim())),
      'daily' => DailyTiming(time: time(dailyTime), timeZone: zone),
      'weekly' => WeeklyTiming(time: time(weeklyTime), timeZone: zone, weekdays: _validWeekdays(weekdays)),
      'cron' => CronTiming(expression: _validCron(cron.text.trim()), timeZone: zone),
      _ => throw const FormatException('请选择运行规则。'),
    };
  }

  static String _validDate(String value) {
    final date = DateTime.tryParse('${value}T00:00:00');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) || date == null) {
      throw const FormatException('日期格式应为 YYYY-MM-DD。');
    }
    return value;
  }

  static int _validEvery(String value) {
    final seconds = int.tryParse(value);
    if (seconds == null || seconds < EveryTiming.minSeconds) {
      throw const FormatException('重复间隔至少为 60 秒。');
    }
    return seconds;
  }

  static List<int> _validWeekdays(Set<int> days) {
    if (days.isEmpty) throw const FormatException('每周任务至少选择一天。');
    return days.toList()..sort();
  }

  static String _validCron(String value) {
    if (value.split(RegExp(r'\s+')).length != 5) {
      throw const FormatException('cron 表达式应包含五个字段。');
    }
    return value;
  }
}

final class ScheduleTimingEditor extends StatelessWidget {
  const ScheduleTimingEditor({required this.controller, super.key});

  final ScheduleTimingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: controller.kind,
      builder: (_, kind, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: '运行规则', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'at', child: Text('单次定时')),
              DropdownMenuItem(value: 'every', child: Text('按秒周期重复')),
              DropdownMenuItem(value: 'daily', child: Text('每天')),
              DropdownMenuItem(value: 'weekly', child: Text('每周')),
              DropdownMenuItem(value: 'cron', child: Text('cron 表达式')),
            ],
            onChanged: (value) => controller.setKind(value!),
          ),
          const SizedBox(height: 12),
          if (kind == 'at') ...[
            TextField(controller: controller.date, decoration: const InputDecoration(labelText: '日期 YYYY-MM-DD', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: controller.atTime, decoration: const InputDecoration(labelText: '时间 HH:mm:ss', border: OutlineInputBorder())),
          ] else if (kind == 'every')
            TextField(controller: controller.everySeconds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '间隔秒数（至少 60）', border: OutlineInputBorder()))
          else if (kind == 'daily')
            TextField(controller: controller.dailyTime, decoration: const InputDecoration(labelText: '每天时间 HH:mm:ss', border: OutlineInputBorder()))
          else if (kind == 'weekly') ...[
            TextField(controller: controller.weeklyTime, decoration: const InputDecoration(labelText: '每周时间 HH:mm:ss', border: OutlineInputBorder())),
            Wrap(
              spacing: 4,
              children: [
                for (final day in [1, 2, 3, 4, 5, 6, 7])
                  FilterChip(
                    label: Text('周${['一', '二', '三', '四', '五', '六', '日'][day - 1]}'),
                    selected: controller.weekdays.contains(day),
                    onSelected: (selected) => controller.toggleWeekday(day, selected),
                  ),
              ],
            ),
          ] else if (kind == 'cron')
            TextField(controller: controller.cron, decoration: const InputDecoration(labelText: '分 时 日 月 周', border: OutlineInputBorder())),
          if (kind != 'every') ...[
            const SizedBox(height: 12),
            TextField(controller: controller.timeZone, decoration: const InputDecoration(labelText: 'IANA 时区', hintText: 'Asia/Shanghai', border: OutlineInputBorder())),
          ],
        ],
      ),
    );
  }
}
