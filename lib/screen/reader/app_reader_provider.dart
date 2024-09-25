import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wenku8x/main.dart';
import 'package:wenku8x/screen/reader/reader_provider.dart';
import 'package:wenku8x/utils/log.dart';

import '../../http/api.dart';

part 'app_reader_provider.g.dart';

@riverpod
class AppReader extends _$AppReader {
  (List<String>, String, String) cachedTextAndTitle = ([], "", "");
  late Directory bookDir;
  late File metaFile;
  late ScrollController scrollController = ScrollController();
  late BuildContext ctx;
  int? initCIndex;

  @override
  Reader build((String, String, int) arg) {
    final themeId = sp.getString("themeId");
    final textStyle = TextStyle(
        fontSize: sp.getDouble("fontSize") ?? 18,
        height: sp.getDouble("lineHeight") ?? 1.7);
    scrollController.addListener(_listenVertical);
    return Reader(
        name: arg.$1,
        aid: arg.$2,
        cIndex: arg.$3,
        themeId: themeId ?? "mulberry",
        textStyle: textStyle);
  }

  Future saveMetaFile() async {
    final docDir = await getApplicationDocumentsDirectory();
    metaFile = File("${bookDir.path}/meta.json");
    var exist = await metaFile.exists();
    if(exist){
      await metaFile.writeAsString(jsonEncode(RecordMeta(cIndex: state.cIndex, progress: state.progress)));
    }else{
      await metaFile.create();
      await metaFile.writeAsString(jsonEncode(RecordMeta(cIndex: state.cIndex, progress: state.progress)));
    }
  }

  Future initCatalog() async {
    final docDir = await getApplicationDocumentsDirectory();
    bookDir = Directory("${docDir.path}/books/${state.aid}");
    metaFile = File("${bookDir.path}/meta.json");
    final recordMeta = (initCIndex != null)
        ? RecordMeta(cIndex: initCIndex!, pIndex: 0)
        : (metaFile.existsSync()
            ? RecordMeta.fromJson(json.decode(metaFile.readAsStringSync()))
            : const RecordMeta());
    final file = File("${bookDir.path}/catalog.json");
    List<Chapter> chapters = [];
    if (file.existsSync()) {
      // 如果存在目录文件，直接从文件读取并更新目录
      chapters =
          (json.decode(file.readAsStringSync()) as List<dynamic>).map((e) {
        return Chapter(cid: e['cid'], name: e['name']);
      }).toList();
    } else {
      if (!bookDir.existsSync()) bookDir.createSync(recursive: true);
      chapters = await API.getNovelIndex(state.aid);
      file.writeAsString(jsonEncode(chapters));
    }
    state = state.copyWith(catalog: chapters, cIndex: recordMeta.cIndex, progress: recordMeta.progress);
    Log.i(state);
  }

  Future<(List<String>, String, String)> fetchContentTextAndTitle(
      int? ci) async {
    final index = ci ?? state.cIndex;
    final cid = state.catalog[index].cid;
    final file = File("${bookDir.path}/$cid.txt");
    String text = file.existsSync()
        ? file.readAsStringSync()
        : await API.getNovelContent(state.aid, cid);
    // String text = await API.getNovelContent(state.aid, cid);
    List<String> textArr = text.split(RegExp(r"\n\s*|\s{2,}"));
    textArr.removeRange(0, 2);
    file.writeAsString(text);
    // Log.i(text);
    debugPrint("${text}");
    return (textArr, state.catalog[index].name, text);
  }

  Future<void> initChapter({int? cIndex, int? pIndex}) async {
    final (textArr, name, text) =
        await fetchContentTextAndTitle(cIndex ?? state.cIndex);
    initCIndex = null;
    state = state.copyWith(cachedText: text, cIndex: cIndex ?? state.cIndex);
  }

  Future loadNextChapter() async {
    int latestChapterIndex = state.cIndex;
    cachedTextAndTitle = await fetchContentTextAndTitle(latestChapterIndex + 1);
    state = state.copyWith(
        cachedText: cachedTextAndTitle.$3, cIndex: latestChapterIndex + 1);
    scrollController.jumpTo(0);
  }

  Future loadPreviousChapter() async {
    int latestChapterIndex = state.cIndex;
    cachedTextAndTitle = await fetchContentTextAndTitle(latestChapterIndex - 1);
    state = state.copyWith(
        cachedText: cachedTextAndTitle.$3, cIndex: latestChapterIndex - 1);
    scrollController.jumpTo(0);
  }

  void refresh({int? cIndex}) async {
    ref.read(loadingProvider.notifier).state = true;
    ref.read(readerMenuStateProvider.notifier).reset();
    state = state.copyWith(
      pages: [],
      catalog: [],
    );
    String recordMetaString = json
        .encode(RecordMeta(cIndex: cIndex ?? state.cIndex, pIndex: 0).toJson());
    if (!metaFile.existsSync()) metaFile.createSync(recursive: true);
    metaFile.writeAsString(recordMetaString);
    await initCatalog();
    initChapter(cIndex: cIndex ?? state.cIndex, pIndex: 0);
    scrollController.jumpTo(0);
  }

  void _listenVertical() {
    if (scrollController.position.maxScrollExtent > 0) {
      var progress = scrollController.position.pixels /
          scrollController.position.maxScrollExtent;
      state = state.copyWith(progress: progress);
      Log.i(progress);
    }
  }

  void jumpFromProgress({double? progress}) {
    final targetPosition = progress?? state.progress * scrollController.position.maxScrollExtent;
    Log.i(targetPosition);
    scrollController.jumpTo(targetPosition);
    state = state.copyWith(progress: progress?? state.progress);
  }

  void jumpToIndex(int index) async {
    await initChapter(cIndex: index);
    ref.read(readerMenuStateProvider.notifier).reset();
    scrollController.jumpTo(0);
  }

  onTap() {
    // 如果子菜单开启，则不响应翻页 只关闭子菜单
    if (ref.read(readerMenuStateProvider).subMenusVisible) {
      ref.read(readerMenuStateProvider.notifier).dispatch(
            menuCatalogVisible: false,
            menuThemeVisible: false,
            menuTextVisible: false,
            menuConfigVisible: false,
            menuTopVisible: true,
            menuBottomVisible: true,
          );
      return;
    }
    ref.read(readerMenuStateProvider.notifier).toggleInitialBars();
    // // 如果父菜单开启，则不响应翻页，只关闭父菜单
    // if (ref.read(readerMenuStateProvider).parentMenuVisible) {
    //   ref.read(readerMenuStateProvider.notifier).reset();
    //   return;
    // }
  }
}
