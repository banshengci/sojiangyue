import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:songjiang_reader/dao/book.dart';
import 'package:songjiang_reader/dao/tag.dart';
import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/tag.dart';
import 'package:songjiang_reader/providers/book_list.dart';
import 'package:songjiang_reader/providers/bookshelf_selection.dart';
import 'package:songjiang_reader/providers/tags.dart';
import 'package:songjiang_reader/utils/get_path/get_base_path.dart';
import 'package:songjiang_reader/utils/log/common.dart';
import 'package:songjiang_reader/utils/toast/common.dart';

/// 书架多选后的批量操作入口。
Future<void> showBookshelfBatchSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final selection = ref.read(bookshelfSelectionProvider);
  if (selection.isEmpty) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                L10n.of(sheetContext).batchSelectedCount(selection.length),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(L10n.of(sheetContext).batchAddTag),
              onTap: () {
                Navigator.pop(sheetContext);
                _showBatchTagDialog(context, ref, selection.toList());
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(L10n.of(sheetContext).batchChangeCover),
              onTap: () {
                Navigator.pop(sheetContext);
                _applyBatchCover(context, ref, selection.toList());
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _showBatchTagDialog(
  BuildContext context,
  WidgetRef ref,
  List<int> bookIds,
) async {
  final tagsAsync = ref.read(tagListProvider);
  final tags = tagsAsync.valueOrNull ?? <Tag>[];
  final selected = <int>{};

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: Text(L10n.of(dialogContext).batchAddTag),
            content: SizedBox(
              width: double.maxFinite,
              child: tags.isEmpty
                  ? Text(L10n.of(dialogContext).batchNoTags)
                  : SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tags.map((tag) {
                          final on = selected.contains(tag.id);
                          return FilterChip(
                            label: Text(tag.name),
                            selected: on,
                            onSelected: (value) {
                              setState(() {
                                if (value) {
                                  selected.add(tag.id);
                                } else {
                                  selected.remove(tag.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(L10n.of(dialogContext).commonCancel),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () async {
                        for (final bookId in bookIds) {
                          for (final tagId in selected) {
                            await bookTagDao.addRelation(
                                bookId: bookId, tagId: tagId);
                          }
                        }
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!context.mounted) return;
                        SjToast.show(L10n.of(context).batchTagApplied);
                        ref.read(bookshelfSelectionProvider.notifier).clear();
                      },
                child: Text(L10n.of(dialogContext).commonOk),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _applyBatchCover(
  BuildContext context,
  WidgetRef ref,
  List<int> bookIds,
) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  if (result == null || result.files.isEmpty) return;
  final path = result.files.first.path;
  if (path == null || path.isEmpty) {
    SjToast.show(L10n.of(context).importCannotGetFilePath);
    return;
  }
  final imageBytes = await File(path).readAsBytes();

  for (final bookId in bookIds) {
    try {
      final book = await bookDao.selectBookById(bookId);
      final oldCover = File(book.coverFullPath);
      if (await oldCover.exists()) {
        await oldCover.delete();
      }
      final newName =
          'cover/${book.id}-${DateTime.now().millisecondsSinceEpoch}.png';
      final newFile = File(getBasePath(newName));
      await newFile.parent.create(recursive: true);
      await newFile.writeAsBytes(imageBytes);
      await bookDao.updateBook(book.copyWith(coverPath: newName));
    } catch (e) {
      SjLog.warning('batch cover failed for $bookId: $e');
    }
  }

  ref.read(bookListProvider.notifier).refresh();
  ref.read(bookshelfSelectionProvider.notifier).clear();
  if (!context.mounted) return;
  SjToast.show(L10n.of(context).batchCoverApplied(bookIds.length));
}
