// lib/page/character/character_edit_page.dart
//
// 人物资料校对页：改字段、配头像、让 AI 补全空缺。
//
// 造梦 persona 的「资料校对 / AI 补全 / 头像裁剪」对应能力。此前松江阅的人物
// 详情页是纯只读的——蒸馏出来是什么就只能看什么，写错了也改不了。
//
// 头像裁剪没有引入 image_cropper（原生依赖），用纯 Dart 的 image 包做
// 「居中正方形裁剪 + 缩放到 256」，足够头像使用，且不增加原生依赖。

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:songjiang_reader/dao/character_dao.dart';
import 'package:songjiang_reader/design/songjiang/sj_tokens.dart';
import 'package:songjiang_reader/models/character_card.dart';
import 'package:songjiang_reader/service/ai/current_ai_pipeline.dart';
import 'package:songjiang_reader/service/character/character_enrich_service.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

import 'character_avatar.dart';
import 'characters_page_strings.dart';

class CharacterEditPage extends StatefulWidget {
  const CharacterEditPage({
    super.key,
    required this.bookId,
    required this.card,
  });

  final int bookId;
  final CharacterCard card;

  @override
  State<CharacterEditPage> createState() => _CharacterEditPageState();
}

class _CharacterEditPageState extends State<CharacterEditPage> {
  late final _nameController = TextEditingController(text: widget.card.name);
  late final _genderController =
      TextEditingController(text: widget.card.gender ?? '');
  late final _roleController =
      TextEditingController(text: widget.card.role ?? '');
  late final _aliasesController =
      TextEditingController(text: widget.card.aliases?.join('、') ?? '');
  late final _personalityController =
      TextEditingController(text: widget.card.personality ?? '');
  late final _motivationController =
      TextEditingController(text: widget.card.motivation ?? '');
  late final _backgroundController =
      TextEditingController(text: widget.card.background ?? '');
  late final _appearanceController =
      TextEditingController(text: widget.card.appearance ?? '');
  late final _firstChapterController =
      TextEditingController(text: widget.card.firstAppearanceChapter ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.card.description ?? '');

  late int _importance = widget.card.importance;
  String? _avatarPath;
  bool _saving = false;
  bool _enriching = false;

  @override
  void initState() {
    super.initState();
    _avatarPath = widget.card.avatarPath;
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _genderController,
      _roleController,
      _aliasesController,
      _personalityController,
      _motivationController,
      _backgroundController,
      _appearanceController,
      _firstChapterController,
      _descriptionController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- 头像 ----

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    List<int>? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) &&
        file.path != null &&
        File(file.path!).existsSync()) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      if (mounted) SjToast.show(CharactersPageText.avatarReadFailed);
      return;
    }

    try {
      final saved = await _cropAndSave(bytes);
      invalidateAvatarCache();
      if (!mounted) return;
      setState(() => _avatarPath = saved);
      SjToast.show(CharactersPageText.avatarSaved);
    } catch (e) {
      if (mounted) SjToast.show('头像处理失败：$e');
    }
  }

  /// 居中裁成正方形 → 缩放到 256 → 存到应用目录。
  Future<String> _cropAndSave(List<int> bytes) async {
    final decoded =
        img.decodeImage(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    if (decoded == null) throw StateError('无法解析这张图片');

    final side = decoded.width < decoded.height ? decoded.width : decoded.height;
    final square = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final resized = img.copyResize(square, width: 256, height: 256);
    final out = img.encodeJpg(resized, quality: 88);

    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'avatars'));
    await dir.create(recursive: true);
    final safe = widget.card.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = p.join(
      dir.path,
      '${widget.bookId}_${safe}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await File(path).writeAsBytes(out, flush: true);
    return path;
  }

  // ---- AI 补全 ----

  Future<void> _enrich() async {
    final model = resolveCurrentModel();
    if (model == null) {
      SjToast.show(CharactersPageText.needAiConfig);
      return;
    }

    // 只补「目前是空的」字段，已有内容不覆盖
    final targets = <EnrichField>[];
    if (_personalityController.text.trim().isEmpty) {
      targets.add(EnrichField.personality);
    }
    if (_motivationController.text.trim().isEmpty) {
      targets.add(EnrichField.motivation);
    }
    if (_backgroundController.text.trim().isEmpty) {
      targets.add(EnrichField.background);
    }
    if (_appearanceController.text.trim().isEmpty) {
      targets.add(EnrichField.appearance);
    }
    if (_descriptionController.text.trim().isEmpty) {
      targets.add(EnrichField.description);
    }
    if (_roleController.text.trim().isEmpty) {
      targets.add(EnrichField.role);
    }
    if (targets.isEmpty) {
      SjToast.show(CharactersPageText.enrichNothingMissing);
      return;
    }

    setState(() => _enriching = true);
    try {
      final relations = await characterDao.getRelationsForCharacter(
        widget.bookId,
        widget.card.name,
      );
      final world = await characterDao.getWorldSettings(widget.bookId);
      final filled = await CharacterEnrichService().complete(
        card: widget.card,
        model: model,
        relations: relations,
        world: world,
        fields: targets,
      );
      if (!mounted) return;
      if (filled.isEmpty) {
        SjToast.show(CharactersPageText.enrichNoResult);
        return;
      }
      setState(() {
        filled.forEach((k, v) {
          switch (EnrichField.values.firstWhere((f) => f.key == k)) {
            case EnrichField.personality:
              _personalityController.text = v;
            case EnrichField.motivation:
              _motivationController.text = v;
            case EnrichField.background:
              _backgroundController.text = v;
            case EnrichField.appearance:
              _appearanceController.text = v;
            case EnrichField.description:
              _descriptionController.text = v;
            case EnrichField.role:
              _roleController.text = v;
          }
        });
      });
      SjToast.show(CharactersPageText.enrichDone(filled.length));
    } catch (e) {
      if (mounted) SjToast.show('补全失败：$e');
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  // ---- 保存 ----

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      SjToast.show('人物名不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      final aliases = _aliasesController.text
          .split(RegExp(r'[、,，\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final updated = widget.card.copyWith(
        name: name,
        gender: _genderController.text.trim(),
        role: _roleController.text.trim(),
        aliases: aliases,
        personality: _personalityController.text.trim(),
        motivation: _motivationController.text.trim(),
        background: _backgroundController.text.trim(),
        appearance: _appearanceController.text.trim(),
        firstAppearanceChapter: _firstChapterController.text.trim(),
        description: _descriptionController.text.trim(),
        importance: _importance,
        avatarPath: _avatarPath ?? '',
        updatedAt: DateTime.now(),
      );
      await characterDao.saveCharacterWithRename(
        card: updated,
        previousName: widget.card.name,
      );
      if (!mounted) return;
      SjToast.show('已保存');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) SjToast.show('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SjColors.of(context);
    final avatarFile =
        (_avatarPath != null && File(_avatarPath!).existsSync())
            ? File(_avatarPath!)
            : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('校对人物资料'),
        actions: [
          IconButton(
            tooltip: 'AI 补全空缺字段',
            icon: _enriching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high_outlined),
            onPressed: _enriching ? null : _enrich,
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: c.frost,
                    backgroundImage:
                        avatarFile == null ? null : FileImage(avatarFile),
                    child: avatarFile == null
                        ? Text(
                            widget.card.name.isNotEmpty
                                ? widget.card.name[0]
                                : '?',
                            style: TextStyle(fontSize: 26, color: c.ink),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _pickAvatar,
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: const Text('设置头像'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _field('人物名 *', _nameController),
          Row(
            children: [
              Expanded(child: _field('性别', _genderController)),
              const SizedBox(width: 10),
              Expanded(child: _field('身份', _roleController)),
            ],
          ),
          _field('别名（顿号或逗号分隔）', _aliasesController),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('重要度 $_importance', style: SjText.meta(c.inkSoft)),
                Slider(
                  value: _importance.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '$_importance',
                  onChanged: (v) => setState(() => _importance = v.round()),
                ),
              ],
            ),
          ),
          _field('性格', _personalityController, maxLines: 2),
          _field('动机', _motivationController, maxLines: 2),
          _field('背景', _backgroundController, maxLines: 3),
          _field('外貌', _appearanceController, maxLines: 2),
          _field('首次出场', _firstChapterController),
          _field('简介', _descriptionController, maxLines: 3),
          const SizedBox(height: 8),
          Text(
            '提示：右上角「AI 补全」只会填补空白字段，'
            '并严格依据已有的资料卡与关系推断，不会编造原著没有的情节。',
            style: SjText.meta(c.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}
