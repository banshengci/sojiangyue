import 'package:songjiang_reader/config/local_dict_prefs.dart';
import 'package:songjiang_reader/config/translate_prefs.dart';
import 'package:songjiang_reader/dao/vocab.dart';
import 'package:songjiang_reader/enums/lang_list.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/vocab_item.dart';
import 'package:songjiang_reader/service/translate/index.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:songjiang_reader/widgets/common/axis_flex.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'dart:async';

class TranslationMenu extends StatefulWidget {
  const TranslationMenu({
    super.key,
    required this.content,
    required this.decoration,
    required this.axis,
    this.contextText,
    this.bookId,
    this.bookTitle,
    this.chapter,
  });
  final String content;
  final BoxDecoration decoration;
  final Axis axis;
  final String? contextText;
  final int? bookId;
  final String? bookTitle;
  final String? chapter;

  @override
  State<TranslationMenu> createState() => _TranslationMenuState();
}

class _TranslationMenuState extends State<TranslationMenu> {
  Widget? _translationWidget;
  String? _localDictDef;
  Timer? _debounceTimer;
  bool _translationInitialized = false;
  bool _savingVocab = false;

  @override
  void initState() {
    super.initState();
    _initializeTranslation();
  }

  void _initializeTranslation() {
    // Use addPostFrameCallback to ensure the UI is rendered first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _translationInitialized) return;

      // Debounce: Delay the translation call to ensure context has stopped updating
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
        if (!mounted || _translationInitialized) return;

        // 1) 本地词典优先（短词/短语，离线）
        final def = await LocalDictPrefs.lookup(widget.content);
        if (!mounted) return;

        // 2) AI 翻译仍加载（本地命中时作为补充；未命中则作主结果）
        final effectiveContextText =
            (widget.contextText?.trim().isEmpty ?? true)
                ? null
                : widget.contextText;
        final aiWidget = translateText(
          widget.content,
          contextText: effectiveContextText,
        );

        setState(() {
          _localDictDef = def;
          _translationWidget = aiWidget;
          _translationInitialized = true;
        });
      });
    });
  }

  Future<void> _saveVocab() async {
    if (_savingVocab) return;
    setState(() => _savingVocab = true);
    try {
      final trimmed = widget.content.trim();
      if (trimmed.isEmpty) {
        SjToast.show(L10n.of(context).commonInputCannotBeEmpty);
        return;
      }
      await vocabDao.save(VocabItem(
        term: trimmed,
        bookId: widget.bookId,
        bookTitle: widget.bookTitle,
        chapter: widget.chapter,
        createTime: DateTime.now(),
      ));
      if (!mounted) return;
      SjToast.show(L10n.of(context).vocabSaved);
    } finally {
      if (mounted) setState(() => _savingVocab = false);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Widget _langPicker(bool isFrom) {
    final MenuController menuController = MenuController();

    return PointerInterceptor(
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          maximumSize: WidgetStateProperty.all(const Size(300, 300)),
        ),
        controller: menuController,
        menuChildren: [
          for (var lang in LangListEnum.values)
            PointerInterceptor(
              child: MenuItemButton(
                onPressed: () {
                  if (isFrom) {
                    TranslatePrefs.from = lang;
                  } else {
                    TranslatePrefs.to = lang;
                  }
                },
                child: Text(lang.getNative(context)),
              ),
            ),
        ],
        builder: (context, controller, child) {
          return GestureDetector(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Text(
              isFrom
                  ? TranslatePrefs.from.getNative(context)
                  : TranslatePrefs.to.getNative(context),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: Container(
          height: widget.axis == Axis.vertical ? double.infinity : 170,
          width: widget.axis == Axis.vertical ? 100 : double.infinity,
          decoration: widget.decoration,
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.content,
                  style: const TextStyle(
                    fontSize: 16,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_localDictDef != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withAlpha(80),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L10n.of(context).localDictHit,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(_localDictDef!),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.of(context).aiTranslateFallback,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                    ],
                    _translationWidget ??
                        const SizedBox(
                          height: 20,
                          child: Center(child: Text('...')),
                        ),
                    const Divider(),
                    AxisFlex(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      axis: widget.axis,
                      children: [
                        _langPicker(true),
                        Transform.rotate(
                            angle: widget.axis == Axis.horizontal ? 0 : 1.57,
                            child: Icon(Icons.arrow_forward_ios, size: 16)),
                        _langPicker(false),
                        if (widget.axis == Axis.horizontal) const Spacer(),
                        PointerInterceptor(
                          child: TextButton.icon(
                            onPressed: _savingVocab ? null : _saveVocab,
                            icon: _savingVocab
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.bookmark_add_outlined,
                                    size: 18),
                            label: Text(L10n.of(context).vocabSave),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
