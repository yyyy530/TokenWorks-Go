import 'models.dart';
import 'ports.dart';

final class LaunchPolicy {
  const LaunchPolicy();

  void validateSessionLaunch({
    required AccountSnapshot account,
    required HostProfile host,
    required SchoolModel model,
    required String workspace,
    required PermissionLevel permission,
    bool fullAccessConfirmed = false,
  }) {
    account.validate();
    host.validate();
    if (!account.models.any((item) => item.id == model.id)) {
      throw const IntegrationException(
        'model/unavailable',
        '所选模型不在学校当前下发的可用列表中。',
      );
    }
    if (workspace.trim().isEmpty) {
      throw const IntegrationException('workspace/required', '请先选择工作区。');
    }
    if (host.kind == HostKind.local &&
        account.network != NetworkScope.campus &&
        account.network != NetworkScope.tunnel) {
      throw const IntegrationException(
        'network/campus-required',
        '本机调用学校模型需要校园网或已连接的学校网络通道。',
      );
    }
    if (permission == PermissionLevel.fullAccess && !fullAccessConfirmed) {
      throw const IntegrationException(
        'permission/explicit-confirmation-required',
        '完全权限需要在新建会话时单独确认。',
      );
    }
  }
}
