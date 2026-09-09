import 'package:flutter/material.dart';

enum SjButtonType { filled, outlined, text }

class SjButton extends StatelessWidget {
  const SjButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.disabled = false,
    this.isLoading = false,
    this.type = SjButtonType.filled,
    this.style,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
  })  : icon = null,
        label = null;

  const SjButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.disabled = false,
    this.isLoading = false,
    this.type = SjButtonType.filled,
    this.style,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
  }) : child = null;

  const SjButton.text({
    super.key,
    required this.onPressed,
    required this.child,
    this.disabled = false,
    this.isLoading = false,
    this.style,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
  })  : icon = null,
        label = null,
        type = SjButtonType.text;

  const SjButton.outlined({
    super.key,
    required this.onPressed,
    required this.child,
    this.disabled = false,
    this.isLoading = false,
    this.style,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
  })  : icon = null,
        label = null,
        type = SjButtonType.outlined;

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Clip clipBehavior;
  final Widget? child;
  final Widget? icon;
  final Widget? label;
  final bool disabled;
  final bool isLoading;
  final SjButtonType type;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? effectiveOnPressed =
        (disabled || isLoading) ? null : onPressed;
    final VoidCallback? effectiveOnLongPress =
        (disabled || isLoading) ? null : onLongPress;

    Widget buttonContent;

    if (isLoading) {
      buttonContent = SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.0,
          color: type == SjButtonType.filled
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.primary,
        ),
      );
      // When loading, if it's an icon button or has child, we essentially want to replace content with spinner
      // leveraging the button structure.
      // But for Icon buttons, `icon` param expects a Widget.
    } else {
      buttonContent = child ?? const SizedBox();
    }

    // Helper to build the specific button widget
    Widget buildButton({required Widget child}) {
      switch (type) {
        case SjButtonType.filled:
          return FilledButton(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            child: child,
          );
        case SjButtonType.outlined:
          return OutlinedButton(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            child: child,
          );
        case SjButtonType.text:
          return TextButton(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            child: child,
          );
      }
    }

    // Handle Icon constructors
    if (icon != null && label != null) {
      Widget iconToUse = isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: type == SjButtonType.filled
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.primary,
              ),
            )
          : icon!;

      switch (type) {
        case SjButtonType.filled:
          return FilledButton.icon(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            icon: iconToUse,
            label: label!,
          );
        case SjButtonType.outlined:
          return OutlinedButton.icon(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            icon: iconToUse,
            label: label!,
          );
        case SjButtonType.text:
          return TextButton.icon(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            icon: iconToUse,
            label: label!,
          );
      }
    }

    // Non-icon constructors
    if (isLoading) {
      return buildButton(
          child: SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2,
            color: type == SjButtonType.filled
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.primary),
      ));
    }

    return buildButton(child: buttonContent);
  }
}
