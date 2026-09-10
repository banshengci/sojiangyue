import 'package:songjiang_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// AI 对话页：由 AiChatStream 自带 AppBar（历史/新对话/字号），
/// 外层不再套一层同名标题，避免双标题占空间。
class AiChatPage extends ConsumerWidget {
  const AiChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AiChatStream();
  }
}
