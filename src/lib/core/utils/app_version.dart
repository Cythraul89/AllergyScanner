import 'package:package_info_plus/package_info_plus.dart';

/// App version, read once at startup so the About screen and the Open Food
/// Facts User-Agent agree.
class AppVersion {
  const AppVersion({required this.version, required this.buildNumber});

  /// Fallback used when the platform channel is unavailable (e.g. in a test).
  const AppVersion.unknown() : version = '0.0.0', buildNumber = '0';

  static Future<AppVersion> load() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return AppVersion(version: info.version, buildNumber: info.buildNumber);
  }

  final String version;
  final String buildNumber;

  String get display => '$version ($buildNumber)';
}
