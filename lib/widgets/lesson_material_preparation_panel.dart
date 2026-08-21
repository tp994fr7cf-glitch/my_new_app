import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/lesson_payload_size_validator.dart';
import '../models/lesson_whiteboard_board_set.dart';
import '../services/lesson_material_cache_service.dart';
import '../services/lesson_material_library_service.dart';
import '../services/lesson_material_storage_service.dart';
import 'lesson_material_library_picker.dart';

typedef LessonMaterialBoardSetSaveCallback =
    Future<void> Function(BoardSet boardSet);

class LessonMaterialPreparationPanel extends StatefulWidget {
  const LessonMaterialPreparationPanel({
    super.key,
    required this.courseId,
    required this.lessonId,
    required this.boardSet,
    required this.publishedBoardSet,
    required this.onBoardSetSaved,
    this.storageService = const LessonMaterialStorageService(),
    this.libraryService = const LessonMaterialLibraryService(),
    this.enabled = true,
  });

  final String courseId;
  final String? lessonId;
  final BoardSet boardSet;
  final BoardSet publishedBoardSet;
  final LessonMaterialBoardSetSaveCallback onBoardSetSaved;
  final LessonMaterialStorageService storageService;
  final LessonMaterialLibraryService libraryService;
  final bool enabled;

  @override
  State<LessonMaterialPreparationPanel> createState() =>
      _LessonMaterialPreparationPanelState();
}

class _LessonMaterialPreparationPanelState
    extends State<LessonMaterialPreparationPanel> {
  final LessonMaterialCacheService _materialCache =
      LessonMaterialCacheService();
  bool _busy = false;
  String? _message;
  LessonMaterialCacheStatus? _cacheStatus;
  LessonMaterialDownloadProgress? _cacheProgress;
  bool _cacheBusy = false;
  bool _cancelCacheDownload = false;

  BoardSet get _editableBoardSet => widget.boardSet.ensureEditable();
  int get _remainingCount =>
      maxLessonWhiteboardBoards - _editableBoardSet.boards.length;
  List<LessonWhiteboardBoard> get _materialBoards => _editableBoardSet
      .orderedBoards
      .where((board) => board.background != null)
      .toList();
  bool get _canUpload =>
      widget.enabled &&
      !_busy &&
      !_cacheBusy &&
      widget.courseId.trim().isNotEmpty &&
      (widget.lessonId?.trim().isNotEmpty ?? false) &&
      _remainingCount > 0;

  @override
  void initState() {
    super.initState();
    if (_materialCache.supported) {
      unawaited(_refreshCacheStatus());
    }
  }

  @override
  void didUpdateWidget(covariant LessonMaterialPreparationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId ||
        oldWidget.lessonId != widget.lessonId ||
        lessonMaterialFingerprint(oldWidget.boardSet) !=
            lessonMaterialFingerprint(widget.boardSet)) {
      unawaited(_refreshCacheStatus());
    }
  }

  Future<void> _refreshCacheStatus() async {
    final lessonId = widget.lessonId?.trim() ?? '';
    if (!_materialCache.supported ||
        widget.courseId.trim().isEmpty ||
        lessonId.isEmpty ||
        lessonMaterialStoragePaths(_editableBoardSet).isEmpty) {
      if (mounted && _cacheStatus != null) {
        setState(() => _cacheStatus = null);
      }
      return;
    }
    final status = await _materialCache.status(
      courseId: widget.courseId,
      lessonId: lessonId,
      boardSet: _editableBoardSet,
    );
    if (mounted) {
      setState(() => _cacheStatus = status);
    }
  }

  Future<void> _addPdf() async {
    if (!_canUpload) {
      _showUnavailableMessage();
      return;
    }
    setState(() {
      _busy = true;
      _message = 'PDFを読み込んでいます…';
    });
    PickedLessonPdf? pickedPdf;
    LessonMaterialUploadResult? uploaded;
    try {
      pickedPdf = await widget.storageService.pickPdf();
      if (pickedPdf == null || !mounted) {
        return;
      }
      final selectedPages = await _selectPdfPages(
        pickedPdf,
        maximumCount: _remainingCount,
      );
      if (selectedPages == null || selectedPages.isEmpty || !mounted) {
        return;
      }
      setState(() => _message = '選択したページだけの共有用PDFを作成しています…');
      uploaded = await widget.storageService.uploadSelectedPdfPages(
        courseId: widget.courseId,
        lessonId: widget.lessonId!.trim(),
        pickedPdf: pickedPdf,
        selectedPageNumbers: selectedPages,
      );
      await _appendAndSave(uploaded);
    } on LessonMaterialStorageException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (uploaded != null) {
        await _deleteUploadedAssetsBestEffort(uploaded);
      }
      if (mounted) {
        setState(() => _message = 'PDFの追加に失敗しました。時間をおいて再度お試しください。');
      }
    } finally {
      await pickedPdf?.dispose();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _addFromLibrary() async {
    if (!_canUpload) {
      _showUnavailableMessage();
      return;
    }
    setState(() {
      _busy = true;
      _message = '保存済み資料を読み込んでいます…';
    });
    PickedLessonPdf? pickedPdf;
    LessonMaterialUploadResult? uploaded;
    try {
      final items = await widget.libraryService.listItems();
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _message = null;
      });
      final selected = await showLessonMaterialLibraryPicker(
        context: context,
        items: items,
      );
      if (selected == null || !mounted) {
        return;
      }
      setState(() {
        _busy = true;
        _message = selected.isPdf ? 'PDFを読み込んでいます…' : '画像を読み込んでいます…';
      });
      if (selected.isPdf) {
        pickedPdf = await widget.storageService.openPdfFromStorage(
          storagePath: selected.sourceStoragePath,
          fileName: selected.fileName,
        );
        if (!mounted) {
          return;
        }
        final selectedPages = await _selectPdfPages(
          pickedPdf,
          maximumCount: _remainingCount,
        );
        if (selectedPages == null || selectedPages.isEmpty || !mounted) {
          return;
        }
        setState(() => _message = '選択したページだけの共有用PDFを作成しています…');
        uploaded = await widget.storageService.uploadSelectedPdfPages(
          courseId: widget.courseId,
          lessonId: widget.lessonId!.trim(),
          pickedPdf: pickedPdf,
          selectedPageNumbers: selectedPages,
        );
      } else {
        final image = await widget.storageService.openImageFromStorage(
          storagePath: selected.sourceStoragePath,
          fileName: selected.fileName,
        );
        if (!mounted) {
          return;
        }
        setState(() => _message = '画像をアップロードしています…');
        uploaded = await widget.storageService.uploadImages(
          courseId: widget.courseId,
          lessonId: widget.lessonId!.trim(),
          images: [image],
        );
      }
      await _appendAndSave(uploaded);
    } on LessonMaterialStorageException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (uploaded != null) {
        await _deleteUploadedAssetsBestEffort(uploaded);
      }
      if (mounted) {
        setState(() => _message = '保存済み資料の追加に失敗しました。時間をおいて再度お試しください。');
      }
    } finally {
      await pickedPdf?.dispose();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _addImages({required bool fromGallery}) async {
    if (!_canUpload) {
      _showUnavailableMessage();
      return;
    }
    setState(() {
      _busy = true;
      _message = '画像を読み込んでいます…';
    });
    LessonMaterialUploadResult? uploaded;
    try {
      final images = fromGallery
          ? await widget.storageService.pickGalleryImages(
              maximumCount: _remainingCount,
            )
          : await widget.storageService.pickImageFiles(
              maximumCount: _remainingCount,
            );
      if (images.isEmpty || !mounted) {
        return;
      }
      setState(() => _message = '画像をアップロードしています…');
      uploaded = await widget.storageService.uploadImages(
        courseId: widget.courseId,
        lessonId: widget.lessonId!.trim(),
        images: images,
      );
      await _appendAndSave(uploaded);
    } on LessonMaterialStorageException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (uploaded != null) {
        await _deleteUploadedAssetsBestEffort(uploaded);
      }
      if (mounted) {
        setState(() => _message = '画像の追加に失敗しました。時間をおいて再度お試しください。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _appendAndSave(LessonMaterialUploadResult result) async {
    if (result.backgrounds.isEmpty) {
      return;
    }
    final current = _editableBoardSet;
    if (result.backgrounds.length > _remainingCount) {
      throw const LessonMaterialStorageException(lessonBoardLimitMessage);
    }
    final newBoards = <LessonWhiteboardBoard>[];
    for (final entry in result.backgrounds.indexed) {
      var id = LessonWhiteboardBoard.generateId();
      while (current.boardById(id) != null ||
          newBoards.any((board) => board.id == id)) {
        id = LessonWhiteboardBoard.generateId();
      }
      final rawTitle = result.titles[entry.$1].trim();
      newBoards.add(
        LessonWhiteboardBoard(
          id: id,
          order: current.boards.length + entry.$1,
          title: rawTitle.length <= 60 ? rawTitle : rawTitle.substring(0, 60),
          background: entry.$2,
        ),
      );
    }
    final next = current.copyWith(
      boards: [...current.orderedBoards, ...newBoards],
    );
    validateBoardSetForPersistence(next);
    await widget.onBoardSetSaved(next);
    await _refreshCacheStatus();
    if (mounted) {
      setState(() {
        _message =
            '${newBoards.length}枚の資料を準備し、下書き保存しました。'
            'このまま配信・録音画面を開けます。';
      });
    }
  }

  Future<void> _removeMaterialBoard(LessonWhiteboardBoard board) async {
    final background = board.background;
    if (background == null || _busy) {
      return;
    }
    if (widget.publishedBoardSet.boardById(board.id)?.background != null) {
      setState(() => _message = '公開済みの資料はここから削除できません。');
      return;
    }
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('準備した資料を削除'),
        content: Text('「${board.title}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (shouldRemove != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _message = '資料を削除しています…';
    });
    try {
      final remaining = _editableBoardSet.orderedBoards
          .where((item) => item.id != board.id)
          .toList();
      final normalizedBoards = remaining.isEmpty
          ? const [
              LessonWhiteboardBoard(
                id: LessonWhiteboardBoard.defaultBoardId,
                order: 0,
              ),
            ]
          : [
              for (final entry in remaining.indexed)
                entry.$2.copyWith(order: entry.$1),
            ];
      final next = _editableBoardSet.copyWith(
        boards: normalizedBoards,
        switchEvents: [
          for (final event in _editableBoardSet.switchEvents)
            if (event.boardId != board.id) event,
        ],
        viewportEvents: [
          for (final event in _editableBoardSet.viewportEvents)
            if (event.boardId != board.id) event,
        ],
      );
      await widget.onBoardSetSaved(next);
      final stillUsed = next.boards.any(
        (item) => item.background?.assetId == background.assetId,
      );
      if (!stillUsed) {
        await widget.storageService.deleteMaterialAsset(background);
      }
      await _refreshCacheStatus();
      if (mounted) {
        setState(() => _message = '資料を削除し、下書き保存しました。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '資料の削除に失敗しました。');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<List<int>?> _selectPdfPages(
    PickedLessonPdf pickedPdf, {
    required int maximumCount,
  }) {
    final selected = <int>{};
    return showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('配信で共有するPDFページを選択'),
          content: SizedBox(
            width: 620,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '選択したページだけを受講者へ共有します。'
                  ' 残り$maximumCount枚まで追加できます。',
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: pickedPdf.document.pages.length,
                    itemBuilder: (context, index) {
                      final pageNumber = index + 1;
                      final isSelected = selected.contains(pageNumber);
                      final enabled =
                          isSelected || selected.length < maximumCount;
                      return InkWell(
                        key: ValueKey('prelive-material-pdf-page-$pageNumber'),
                        onTap: enabled
                            ? () {
                                setDialogState(() {
                                  if (!selected.add(pageNumber)) {
                                    selected.remove(pageNumber);
                                  }
                                });
                              }
                            : null,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              width: isSelected ? 3 : 1,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: PdfPageView(
                                  document: pickedPdf.document,
                                  pageNumber: pageNumber,
                                  maximumDpi: 96,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.topRight,
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: enabled
                                      ? (_) {
                                          setDialogState(() {
                                            if (!selected.add(pageNumber)) {
                                              selected.remove(pageNumber);
                                            }
                                          });
                                        }
                                      : null,
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: ColoredBox(
                                  color: Colors.black54,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      '$pageNumber',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              key: const ValueKey('prelive-material-pdf-confirm'),
              onPressed: selected.isEmpty
                  ? null
                  : () {
                      final pages = selected.toList()..sort();
                      Navigator.of(dialogContext).pop(pages);
                    },
              child: Text('${selected.length}ページを準備'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadCachedMaterials() async {
    final lessonId = widget.lessonId?.trim() ?? '';
    if (_cacheBusy ||
        _busy ||
        !_materialCache.supported ||
        widget.courseId.trim().isEmpty ||
        lessonId.isEmpty) {
      return;
    }
    setState(() {
      _cacheBusy = true;
      _cancelCacheDownload = false;
      _cacheProgress = const LessonMaterialDownloadProgress(
        downloadedBytes: 0,
        totalBytes: 0,
        completedFiles: 0,
        totalFiles: 0,
      );
    });
    try {
      final outcome = await _materialCache.downloadLesson(
        courseId: widget.courseId,
        lessonId: lessonId,
        boardSet: _editableBoardSet,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _cacheProgress = progress);
          }
        },
        isCancelled: () => _cancelCacheDownload,
        overwriteExisting: false,
        deleteUnlistedFiles: false,
        skipIfCurrent: true,
      );
      await _refreshCacheStatus();
      if (mounted) {
        setState(() {
          _message =
              outcome == LessonMaterialDownloadOutcome.skippedAlreadyCurrent
              ? 'この端末には、すでに必要な資料が保存されています。'
              : 'このレッスンの資料を端末内に保存しました。';
        });
      }
    } on LessonMaterialCacheCancelled {
      if (mounted) {
        setState(() => _message = '資料の保存をキャンセルしました。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '資料を保存できませんでした。時間をおいて再度お試しください。');
      }
    } finally {
      if (mounted) {
        setState(() {
          _cacheBusy = false;
          _cacheProgress = null;
        });
      }
    }
  }

  Future<void> _deleteCachedLessonMaterials() async {
    final lessonId = widget.lessonId?.trim() ?? '';
    if (_cacheBusy || lessonId.isEmpty) {
      return;
    }
    await _materialCache.deleteLesson(
      courseId: widget.courseId,
      lessonId: lessonId,
    );
    await _refreshCacheStatus();
  }

  Future<void> _deleteAllCachedMaterials() async {
    if (_cacheBusy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('端末内の資料をすべて削除しますか？'),
        content: const Text('他のレッスンで保存したPDF・画像も削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('すべて削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _materialCache.deleteAll();
    await _refreshCacheStatus();
  }

  String _formatCacheBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '$bytes B';
  }

  List<Widget> _buildCacheActions() {
    final lessonId = widget.lessonId?.trim() ?? '';
    if (!_materialCache.supported ||
        widget.courseId.trim().isEmpty ||
        lessonId.isEmpty ||
        lessonMaterialStoragePaths(_editableBoardSet).isEmpty) {
      return const [];
    }
    final status = _cacheStatus;
    final progress = _cacheProgress;
    final hasCurrentCache = status?.hasCurrentCache == true;
    return [
      const SizedBox(height: 16),
      const Divider(),
      const SizedBox(height: 12),
      Text('PDF・画像の端末保存', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      Text(
        status?.hasStaleCache == true
            ? 'まだ端末にない資料があります。保存すると、この端末での表示が速くなります。'
            : hasCurrentCache
            ? 'このレッスンの資料は端末内に保存済みです'
                  '（${_formatCacheBytes(status!.totalBytes)}）。'
            : '同じ端末で上げた資料は自動で残します。'
                  '別の端末で上げた資料があるときは、ここでまとめて保存できます。',
      ),
      if (progress != null) ...[
        const SizedBox(height: 10),
        LinearProgressIndicator(value: progress.fraction),
        const SizedBox(height: 4),
        Text('${progress.completedFiles} / ${progress.totalFiles}件'),
      ],
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('teacher-lesson-material-cache-save'),
            onPressed: _cacheBusy || _busy
                ? null
                : () => unawaited(_downloadCachedMaterials()),
            icon: const Icon(Icons.download),
            label: Text(
              hasCurrentCache && status?.hasStaleCache != true
                  ? '保存し直す'
                  : 'このレッスンの資料を保存',
            ),
          ),
          if (_cacheBusy)
            OutlinedButton(
              onPressed: () => _cancelCacheDownload = true,
              child: const Text('キャンセル'),
            ),
          if (hasCurrentCache || status?.hasStaleCache == true)
            OutlinedButton(
              onPressed: _cacheBusy
                  ? null
                  : () => unawaited(_deleteCachedLessonMaterials()),
              child: const Text('このレッスンの保存を削除'),
            ),
          TextButton(
            onPressed: _cacheBusy
                ? null
                : () => unawaited(_deleteAllCachedMaterials()),
            child: const Text('端末内の資料をすべて削除'),
          ),
        ],
      ),
    ];
  }

  void _showUnavailableMessage() {
    setState(() {
      if ((widget.lessonId?.trim().isEmpty ?? true)) {
        _message = '先にレッスン情報を保存すると、資料を準備できます。';
      } else if (_remainingCount <= 0) {
        _message = lessonBoardLimitMessage;
      }
    });
  }

  Future<void> _deleteUploadedAssetsBestEffort(
    LessonMaterialUploadResult result,
  ) async {
    final seen = <String>{};
    for (final background in result.backgrounds) {
      if (!seen.add(background.assetId)) {
        continue;
      }
      try {
        await widget.storageService.deleteMaterialAsset(background);
      } catch (_) {
        // A later cleanup can remove an orphan if draft persistence failed.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final materialBoards = _materialBoards;
    return Card.outlined(
      key: const ValueKey('prelive-material-preparation-panel'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.collections_bookmark_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '配信・録音前のPDF／画像資料',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${_editableBoardSet.boards.length}/'
                  '$maxLessonWhiteboardBoards枚',
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'ライブ配信や「録音しながら書く」を開始する前に、'
              '受講者へ見せる資料をここで準備します。',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('prelive-add-pdf-material'),
                  onPressed: _canUpload ? () => unawaited(_addPdf()) : null,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDFを追加'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('prelive-add-image-file'),
                  onPressed: _canUpload
                      ? () => unawaited(_addImages(fromGallery: false))
                      : null,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('画像ファイルを追加'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('prelive-add-image-gallery'),
                  onPressed: _canUpload
                      ? () => unawaited(_addImages(fromGallery: true))
                      : null,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('写真から追加'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('prelive-add-saved-material'),
                  onPressed: _canUpload
                      ? () => unawaited(_addFromLibrary())
                      : null,
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: const Text('保存済みから選ぶ'),
                ),
              ],
            ),
            if ((widget.lessonId?.trim().isEmpty ?? true)) ...[
              const SizedBox(height: 8),
              const Text('レッスン情報を一度保存すると、資料追加が有効になります。'),
            ],
            if (materialBoards.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '準備済み資料 ${materialBoards.length}枚',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              for (final board in materialBoards)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    board.background!.isPdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                  ),
                  title: Text(board.title),
                  subtitle: board.background!.isPdf
                      ? Text('共有PDF内 ${board.background!.pageNumber}ページ目')
                      : const Text('画像'),
                  trailing:
                      widget.publishedBoardSet
                              .boardById(board.id)
                              ?.background !=
                          null
                      ? const Tooltip(
                          message: '公開済み',
                          child: Icon(Icons.lock_outline),
                        )
                      : IconButton(
                          tooltip: '資料を削除',
                          onPressed: _busy
                              ? null
                              : () => unawaited(_removeMaterialBoard(board)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                ),
            ],
            ..._buildCacheActions(),
            if (_busy || _cacheBusy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!),
            ],
          ],
        ),
      ),
    );
  }
}
