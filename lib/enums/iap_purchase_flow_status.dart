/// IAP 购买流程状态。
///
/// 从 `lib/providers/iap.dart` 下沉到 `lib/enums/`。
/// 动机：`lib/models/iap_state.dart` 需要在模型字段上表达该类型，而
/// `docs/DEVELOPMENT.md` 规定 models 不依赖 service（同理不依赖 providers）。
/// 下沉后 models 与 providers 都只依赖 enums，`models <-> providers` 的
/// 2 文件循环依赖（tool/layer_gate.py 的 SCC）随之断开。
/// 行为无变化：仅类型定义位置移动，枚举值与顺序完全保持。
enum IapPurchaseFlowStatus { idle, pending, purchased, restored, error }
