import 'dart:io';
import 'package:dio/dio.dart';

Future<void> main() async {
  final uri = Uri.parse(
      'http://wskacchm.mini1.cn:4000/update/?cltversion=80384&clttype=0&uin=2089540493&game_env=0&ver=1.58.0&apiid=110&lang=0&country=CN');
  final resp = await Dio().getUri(uri);
  stdout.writeln('status: ${resp.statusCode}');
  stdout.writeln('body: ${resp.data}');
}
