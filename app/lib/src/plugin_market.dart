import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';

import 'desktop_host.dart';

final officialMarketUri = Uri.parse('https://go.dshtui.com/market/index.json');
final allMarketUri = Uri.parse('https://api.dshfind.com/market/dsh-index.json');

const maxMarketIndexBytes = 8 * 1024 * 1024;

Future<MarketIndex> fetchMarketIndex(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw HostConnectionException('插件市场返回 HTTP ${response.statusCode}。');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxMarketIndexBytes) {
        throw const HostConnectionException('插件市场索引过大，已停止下载。');
      }
      bytes.add(chunk);
    }
    try {
      return parseMarketIndex(jsonDecode(utf8.decode(bytes.takeBytes())), uri);
    } on FormatException {
      throw const HostConnectionException('插件市场索引不是有效的 JSON。');
    } on MarketIndexException catch (error) {
      throw HostConnectionException('插件市场索引格式不兼容：$error');
    }
  } on HostConnectionException {
    rethrow;
  } on Object catch (error) {
    throw HostConnectionException('暂时无法读取插件市场：$error');
  } finally {
    client.close();
  }
}
