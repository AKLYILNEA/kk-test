import 'bangumi.dart';

Future<({String version, Uri url})?> findKonekoUpdate(String current) async {
  final client = networkClient();
  try {
    final response = await client.get<dynamic>(
      'https://api.github.com/repos/AKLYILNEA/kk-test/releases/latest',
    );
    final release = jsonObject(response.data);
    final tag = jsonString(release['tag_name']);
    final version = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(tag);
    final installed = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(current);
    if (version == null || installed == null) {
      throw const FormatException('发布版本格式无效');
    }
    for (var i = 1; i <= 3; i++) {
      final order = int.parse(
        version.group(i)!,
      ).compareTo(int.parse(installed.group(i)!));
      if (order == 0) continue;
      if (order < 0) return null;
      return (
        version: tag,
        url: Uri.parse(
          'https://github.com/AKLYILNEA/kk-test/releases/tag/$tag',
        ),
      );
    }
    return null;
  } finally {
    client.close();
  }
}
