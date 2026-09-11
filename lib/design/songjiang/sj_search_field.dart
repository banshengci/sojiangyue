import 'package:flutter/material.dart';

import 'sj_tokens.dart';

/// 搜索栏（圆角胶囊 / 白底 / 细描边）。
///
/// 传入 [controller] 时渲染可输入的真实输入框；
/// 否则渲染「图标 + 占位文字」的只读样式（并可用 [onTap] 跳转到搜索页）。
class SjSearchField extends StatelessWidget {
  const SjSearchField({
    super.key,
    this.hint = '搜索书名、作者或笔记',
    this.controller,
    this.focusNode,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.trailing,
    this.autofocus = false,
  });

  final String hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);

    final Widget content = controller == null
        ? Row(
            children: [
              Icon(Icons.search, size: SjSizes.iconGrid, color: c.inkSoft),
              const SizedBox(width: SjSpace.m),
              Expanded(child: Text(hint, style: SjText.body(c.inkSoft))),
              if (trailing != null) trailing!,
            ],
          )
        : Row(
            children: [
              Icon(Icons.search, size: SjSizes.iconGrid, color: c.inkSoft),
              const SizedBox(width: SjSpace.m),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  cursorColor: c.pine,
                  textInputAction: TextInputAction.search,
                  style: SjText.body(c.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: SjText.body(c.inkSoft),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          );

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(SjSizes.radiusPill),
        border: Border.all(color: c.cardBorder),
      ),
      child: InkWell(
        onTap: controller == null ? onTap : null,
        borderRadius: BorderRadius.circular(SjSizes.radiusPill),
        child: content,
      ),
    );
  }
}
