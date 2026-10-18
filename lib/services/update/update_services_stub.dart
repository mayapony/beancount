import '../../data/repositories/app_state_repository.dart';
import 'app_version.dart';
import 'update_controller.dart';

/// Web/iOS：没有应用内更新入口。
UpdateController? createUpdateController({
  required AppStateRepository appState,
  required AppVersion version,
  DateTime Function()? now,
}) {
  return null;
}
