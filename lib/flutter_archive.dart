// Copyright (c) 2020 KineApps. All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ExtractOperation { extract, skip, cancel }
typedef OnUnzipProgress = ExtractOperation Function(
    ZipEntry zipEntry, double progress);

String _extractOperationToString(ExtractOperation extractOperation) {
  switch (extractOperation) {
    case ExtractOperation.skip:
      return "skip";
    case ExtractOperation.cancel:
      return "cancel";
    default:
      return "extract";
  }
}

/// Utility class for zipping and unzipping ZIP archive files.
class FlutterArchive {
  static const MethodChannel _channel = MethodChannel('flutter_archive');

  /// Compress and save all files in [sourceDir] to [zipFile].
  ///
  /// By default zip all subdirectories recursively. Set [recurseSubDirs]
  /// to false to disable recursive zipping.
  static Future<void> zipDirectory(
      {@required Directory sourceDir,
      @required File zipFile,
      bool recurseSubDirs = true}) async {
    await _channel.invokeMethod('zipDirectory', <String, dynamic>{
      'sourceDir': sourceDir.path,
      'zipFile': zipFile.path,
      'recurseSubDirs': recurseSubDirs
    });
  }

  /// Compress given list of [files] and save the resulted archive to [zipFile].
  /// [sourceDir] is the root directory of [files] (all [files] must reside
  /// under the [sourceDir]).
  static Future<void> zipFiles(
      {@required Directory sourceDir,
      @required List<File> files,
      @required File zipFile}) async {
    var sourceDirPath = sourceDir.path;
    if (!sourceDirPath.endsWith(Platform.pathSeparator)) {
      sourceDirPath += Platform.pathSeparator;
    }
    final sourceDirPathLen = sourceDirPath.length;

    final relativeFilePaths = <String>[];
    files.forEach((f) {
      if (!f.path.startsWith(sourceDirPath)) {
        throw Exception('Files must reside under the rootDir');
      }
      final relativeFilePath = f.path.substring(sourceDirPathLen);
      assert(!relativeFilePath.startsWith(Platform.pathSeparator));
      relativeFilePaths.add(relativeFilePath);
    });
    await _channel.invokeMethod('zipFiles', <String, dynamic>{
      'sourceDir': sourceDir.path,
      'files': relativeFilePaths,
      'zipFile': zipFile.path,
    });
  }

  /// Extract [zipFile] to a given [destinationDir]. Optional callback function
  /// [onUnzipProgress] is called before extracting a zip entry.
  static Future<void> unzip(
      {@required File zipFile,
      @required Directory destinationDir,
      OnUnzipProgress onUnzipProgress}) async {
    final reportProgress = onUnzipProgress != null;
    if (reportProgress) {
      _channel.setMethodCallHandler((call) {
        if (call.method == 'progress') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final zipEntry = ZipEntry.fromMap(args);
          final progress = args["progress"] as double;
          final result = onUnzipProgress(zipEntry, progress);
          return Future.value(_extractOperationToString(result));
        }
        return Future.value();
      });
    }
    try {
      await _channel.invokeMethod('unzip', <String, dynamic>{
        'zipFile': zipFile.path,
        'destinationDir': destinationDir.path,
        'reportProgress': reportProgress,
      });
    } finally {
      if (reportProgress) {
        _channel.setMethodCallHandler(null);
      }
    }
  }
}

enum CompressionMethod { none, deflated }

class ZipEntry {
  const ZipEntry(
      {this.name,
      this.isDirectory,
      this.modificationDate,
      this.uncompressedSize,
      this.compressedSize,
      this.crc,
      this.compressionMethod});

  factory ZipEntry.fromMap(Map<String, dynamic> map) {
    return ZipEntry(
      name: map['name'] as String,
      isDirectory: map['isDirectory'] as bool == true,
      modificationDate: DateTime.fromMillisecondsSinceEpoch(
          map['modificationDate'] as int ?? 0),
      uncompressedSize: map['uncompressedSize'] as int,
      compressedSize: map['compressedSize'] as int,
      crc: map['crc'] as int,
      compressionMethod: map['compressionMethod'] == 'none'
          ? CompressionMethod.none
          : CompressionMethod.deflated,
    );
  }

  final String name;
  final bool isDirectory;
  final DateTime modificationDate;
  final int uncompressedSize;
  final int compressedSize;
  final int crc;
  final CompressionMethod compressionMethod;
}
