import 'dart:async';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'desktop_host.dart';

final class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    required this.client,
    required this.sessionId,
    super.key,
  });

  final DshClient client;
  final String sessionId;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

final class _WorkspacePageState extends State<WorkspacePage> {
  final _folders = <String>[];
  DshWorkspaceListing? _listing;
  String? _file;
  DshWorkspaceText? _text;
  String? _error;
  bool _busy = true;

  String get _directory => _folders.join('/');
  String get _filePath => [..._folders, _file!].join('/');

  @override
  void initState() {
    super.initState();
    unawaited(_showDirectory());
  }

  Future<void> _load(Future<void> Function() read) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await read();
    } on DshRemoteException catch (error) {
      if (mounted) {
        setState(() {
          _error = switch (error.code) {
            'workspace-file/not-text' => '此文件不是 UTF-8 文本。',
            'workspace-file/too-large' => '文件超过操作的大小限制，下载上限为 10 MiB。',
            _ => desktopError(error),
          };
        });
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = desktopError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDirectory() => _load(() async {
    _file = null;
    _text = null;
    _listing = null;
    final result = await widget.client.listWorkspace(
      widget.sessionId,
      _directory,
    );
    if (mounted) setState(() => _listing = result);
  });

  Future<void> _showText(int offset) => _load(() async {
    final result = await widget.client.readWorkspaceText(
      widget.sessionId,
      _filePath,
      offset: offset,
      limit: 100,
    );
    if (mounted) setState(() => _text = result);
  });

  Future<void> _download() => _load(() async {
    final name = _file!;
    final bytes = BytesBuilder(copy: false);
    await widget.client.readFile(
      widget.sessionId,
      _filePath,
      onChunk: bytes.add,
      maxBytes: maxDesktopFileBytes,
    );
    if (!mounted) return;
    final saved = await FilePicker.saveFile(
      fileName: name,
      bytes: bytes.takeBytes(),
    );
    if (mounted && saved != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('文件已保存')));
    }
  });

  void _goUp() {
    if (_file == null && _folders.isNotEmpty) _folders.removeLast();
    unawaited(_showDirectory());
  }

  void _open(DshWorkspaceEntry entry) {
    if (entry.isDirectory) {
      _folders.add(entry.name);
      unawaited(_showDirectory());
    } else {
      _file = entry.name;
      unawaited(_showText(1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final text = _text;
    final listing = _listing;
    final entries = [
      for (final entry in listing?.entries ?? const <DshWorkspaceEntry>[])
        if (entry.name != '.' &&
            entry.name != '..' &&
            !entry.name.contains('/') &&
            !entry.name.contains('\\') &&
            !entry.name.contains('\x00'))
          entry,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('工作区文件'),
        actions: [
          if (file != null && widget.client.canReadFileBytes)
            IconButton(
              onPressed: _busy ? null : _download,
              tooltip: '下载文件',
              icon: const Icon(Icons.download_outlined),
            ),
          IconButton(
            onPressed: _busy || (file == null && _folders.isEmpty)
                ? null
                : _goUp,
            tooltip: '上一级',
            icon: const Icon(Icons.drive_folder_upload_outlined),
          ),
          IconButton(
            onPressed: _busy
                ? null
                : (file == null
                      ? _showDirectory
                      : () => _showText(text?.offset ?? 1)),
            tooltip: '刷新文件',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                file == null
                    ? (_directory.isEmpty ? '工作区根目录' : _directory)
                    : _filePath,
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (file != null && text != null)
              Expanded(
                child: ListView(
                  key: ValueKey((file, text.offset)),
                  padding: const EdgeInsets.all(16),
                  children: [
                    SelectableText(
                      text.lines == 0 ? '没有文本内容。' : text.text,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    OverflowBar(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: !_busy && text.offset > 1
                              ? () => _showText(
                                  (text.offset - 100).clamp(1, text.offset),
                                )
                              : null,
                          child: const Text('上一页'),
                        ),
                        TextButton(
                          onPressed: !_busy && !text.eof && text.lines > 0
                              ? () => _showText(text.offset + text.lines)
                              : null,
                          child: const Text('下一页'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (file == null && listing != null) ...[
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('此文件夹为空。'),
                ),
              if (listing.truncated)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('主机限制了此目录返回的条目数量。'),
                ),
              Expanded(
                child: ListView.builder(
                  key: ValueKey(_directory),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      leading: Icon(
                        entry.isDirectory
                            ? Icons.folder_outlined
                            : Icons.description_outlined,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: entry.isDirectory
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: _busy || (!entry.isDirectory && !entry.isFile)
                          ? null
                          : () => _open(entry),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
