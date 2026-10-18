part of 'app_updates.dart';

final class AppUpdateState {
  const AppUpdateState({
    this.installed = '',
    this.status = AppUpdateStatus.idle,
    this.release,
    this.package,
    this.downloading = false,
    this.downloadFailed = false,
    this.downloadedBytes = 0,
    this.downloadedPackage,
    this.installing = false,
    this.installFailed = false,
  });
  factory AppUpdateState.fromController(AppUpdates controller) =>
      AppUpdateState(
        installed: controller.installed,
        status: controller.status,
        release: controller.release,
        package: controller.package,
        downloading: controller.downloading,
        downloadFailed: controller.downloadFailed,
        downloadedBytes: controller.downloadedBytes,
        downloadedPackage: controller.downloadedPackage,
        installing: controller.installing,
        installFailed: controller.installFailed,
      );
  final String installed;
  final AppUpdateStatus status;
  final AppRelease? release;
  final AppPackage? package;
  final bool downloading, downloadFailed, installing, installFailed;
  final int downloadedBytes;
  final File? downloadedPackage;
}
