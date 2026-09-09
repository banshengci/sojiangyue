import 'package:songjiang_reader/l10n/generated/L10n.dart';
import 'package:songjiang_reader/models/opds_catalog.dart';
import 'package:songjiang_reader/config/opds_prefs.dart';
import 'package:songjiang_reader/service/book.dart';
import 'package:songjiang_reader/service/opds/opds_service.dart';
import 'package:songjiang_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';

/// OPDS 书源管理页。
class OpdsSettingsPage extends ConsumerStatefulWidget {
  const OpdsSettingsPage({super.key});

  @override
  ConsumerState<OpdsSettingsPage> createState() => _OpdsSettingsPageState();
}

class _OpdsSettingsPageState extends ConsumerState<OpdsSettingsPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  bool _testing = false;
  List<OpdsCatalog> _catalogs = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
    _userController = TextEditingController();
    _passController = TextEditingController();
    _catalogs = OpdsPrefs.catalogs;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _catalogs = OpdsPrefs.catalogs);
  }

  Future<void> _addOrEdit({OpdsCatalog? existing}) async {
    if (existing != null) {
      _nameController.text = existing.name;
      _urlController.text = existing.url;
      _userController.text = existing.username ?? '';
      _passController.text = existing.password ?? '';
    } else {
      _nameController.clear();
      _urlController.clear();
      _userController.clear();
      _passController.clear();
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null
            ? L10n.of(context).opdsAddCatalog
            : L10n.of(context).opdsEditCatalog),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).opdsCatalogName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).opdsCatalogUrl,
                  hintText: 'https://…/opds',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userController,
                decoration: InputDecoration(
                  labelText: L10n.of(context).opdsUsername,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.of(context).opdsPassword,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.of(context).commonSave),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || url.isEmpty) {
      SjToast.show(L10n.of(context).opdsNameUrlRequired);
      return;
    }
    if (Uri.tryParse(url) == null || !(url.startsWith('http'))) {
      SjToast.show(L10n.of(context).opdsInvalidUrl);
      return;
    }

    if (existing != null) {
      await OpdsPrefs.updateCatalog(existing.copyWith(
        name: name,
        url: url,
        username: _userController.text.trim(),
        password: _passController.text,
      ));
    } else {
      await OpdsPrefs.addCatalog(
        name: name,
        url: url,
        username: _userController.text.trim().isEmpty
            ? null
            : _userController.text.trim(),
        password: _passController.text.isEmpty ? null : _passController.text,
      );
    }
    _reload();
    SjToast.show(L10n.of(context).commonSuccess);
  }

  Future<void> _test(OpdsCatalog catalog) async {
    setState(() => _testing = true);
    try {
      final service = OpdsService();
      final feed = await service.loadRoot(catalog);
      if (!mounted) return;
      SjToast.show(
          '${L10n.of(context).commonSuccess} · ${feed.title} (${feed.entries.length})');
    } catch (e) {
      if (!mounted) return;
      SjToast.show('${L10n.of(context).commonFailed}: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showCatalogActions(OpdsCatalog catalog) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(L10n.of(context).opdsEditCatalog),
              onTap: () {
                Navigator.pop(sheetContext);
                _addOrEdit(existing: catalog);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(L10n.of(context).opdsRemoveCatalog),
              onTap: () {
                Navigator.pop(sheetContext);
                _remove(catalog);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(OpdsCatalog catalog) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L10n.of(context).opdsRemoveCatalog),
        content: Text(catalog.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(L10n.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(L10n.of(context).commonDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await OpdsPrefs.removeCatalog(catalog.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).opdsTitle),
        actions: [
          IconButton(
            tooltip: L10n.of(context).opdsAddCatalog,
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEdit(),
          ),
        ],
      ),
      body: _catalogs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.library_books_outlined,
                        size: 56, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(L10n.of(context).opdsEmptyHint, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _addOrEdit(),
                      icon: const Icon(Icons.add),
                      label: Text(L10n.of(context).opdsAddCatalog),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: _catalogs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final catalog = _catalogs[index];
                return ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(catalog.name),
                  subtitle: Text(
                    catalog.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_testing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          tooltip: L10n.of(context).opdsTestConnection,
                          icon: const Icon(Icons.network_check),
                          onPressed: () => _test(catalog),
                        ),
                      IconButton(
                        tooltip: L10n.of(context).opdsBrowse,
                        icon: const Icon(Icons.folder_open),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  OpdsBrowserPage(catalog: catalog),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OpdsBrowserPage(catalog: catalog),
                      ),
                    );
                  },
                  onLongPress: () => _showCatalogActions(catalog),
                );
              },
            ),
    );
  }
}

/// 浏览 OPDS 目录并下载书籍。
class OpdsBrowserPage extends ConsumerStatefulWidget {
  const OpdsBrowserPage({super.key, required this.catalog});

  final OpdsCatalog catalog;

  @override
  ConsumerState<OpdsBrowserPage> createState() => _OpdsBrowserPageState();
}

class _OpdsBrowserPageState extends ConsumerState<OpdsBrowserPage> {
  final OpdsService _service = OpdsService();
  /// 进入子目录前的 URL 栈（用于返回上级）
  final List<String> _trail = [];
  String _currentUrl = '';
  OpdsFeed? _feed;
  String? _error;
  bool _loading = false;
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.catalog.url;
    _load(_currentUrl);
  }

  Future<void> _load(String url) async {
    setState(() {
      _loading = true;
      _error = null;
      _currentUrl = url;
    });
    try {
      final feed = await _service.loadFeed(widget.catalog, url);
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _enter(String subsectionUrl) {
    _trail.add(_currentUrl);
    _load(subsectionUrl);
  }

  void _back() {
    if (_trail.isEmpty) return;
    _load(_trail.removeLast());
  }

  Future<void> _download(OpdsEntry entry) async {
    if (entry.acquisitions.isEmpty) return;
    // 优先 epub，其次第一个
    final link = entry.acquisitions.firstWhere(
      (l) => l.fileExtension == 'epub',
      orElse: () => entry.acquisitions.first,
    );
    if (_downloading.contains(link.href)) return;
    setState(() => _downloading.add(link.href));
    try {
      final file = await _service.downloadAcquisition(
        widget.catalog,
        link,
        onProgress: (received, total) {
          // 简单：完成后一次性提示
        },
      );
      if (!mounted) return;
      await importBookList([file], context, ref);
    } catch (e) {
      if (!mounted) return;
      SjToast.show('${L10n.of(context).commonFailed}: $e');
    } finally {
      if (mounted) {
        setState(() => _downloading.remove(link.href));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return Scaffold(
      appBar: AppBar(
        title: Text(_trail.isEmpty
            ? widget.catalog.name
            : feed?.title ?? widget.catalog.name),
        leading: _trail.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _back,
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 12),
                        Text('$_error', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _load(_currentUrl),
                          child: Text(L10n.of(context).commonRetry),
                        ),
                      ],
                    ),
                  ),
                )
              : feed == null || feed.entries.isEmpty
                  ? Center(child: Text(L10n.of(context).opdsEmptyCatalog))
                  : RefreshIndicator(
                      onRefresh: () => _load(_currentUrl),
                      child: ListView.builder(
                        itemCount: feed.entries.length,
                        itemBuilder: (context, index) {
                          final entry = feed.entries[index];
                          final busy = entry.acquisitions.isNotEmpty &&
                              _downloading.contains(
                                entry.acquisitions
                                    .firstWhere(
                                      (l) => l.fileExtension == 'epub',
                                      orElse: () => entry.acquisitions.first,
                                    )
                                    .href,
                              );
                          return ListTile(
                            leading: entry.coverUrl == null
                                ? Icon(
                                    entry.isNavigation
                                        ? Icons.folder
                                        : Icons.menu_book_outlined,
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: CachedNetworkImage(
                                      imageUrl: entry.coverUrl!,
                                      width: 40,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          const Icon(Icons.menu_book_outlined),
                                    ),
                                  ),
                            title: Text(entry.title),
                            subtitle: entry.author == null
                                ? null
                                : Text(
                                    entry.author!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: entry.isNavigation
                                ? const Icon(Icons.chevron_right)
                                : busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.download),
                                        onPressed: entry.acquisitions.isEmpty
                                            ? null
                                            : () => _download(entry),
                                      ),
                            onTap: entry.isNavigation
                                ? () => _enter(entry.subsectionUrl!)
                                : entry.acquisitions.isNotEmpty
                                    ? () => _download(entry)
                                    : null,
                          );
                        },
                      ),
                    ),
    );
  }
}
