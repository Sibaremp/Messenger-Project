import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/import_repository.dart';

enum ImportStatus { idle, loading, success, error }

class ImportState {
  final ImportStatus status;
  final ImportResult? result;
  final String? error;
  final String? fileName;

  const ImportState({
    this.status = ImportStatus.idle,
    this.result,
    this.error,
    this.fileName,
  });

  ImportState copyWith({
    ImportStatus? status,
    ImportResult? result,
    String? error,
    String? fileName,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return ImportState(
      status: status ?? this.status,
      result: clearResult ? null : (result ?? this.result),
      error: clearError ? null : (error ?? this.error),
      fileName: fileName ?? this.fileName,
    );
  }
}

class ImportNotifier extends StateNotifier<ImportState> {
  final ImportRepository _repo;

  ImportNotifier(this._repo) : super(const ImportState());

  Future<void> importFile(String fileName, Uint8List bytes) async {
    state = state.copyWith(
      status: ImportStatus.loading,
      fileName: fileName,
      clearResult: true,
      clearError: true,
    );
    try {
      final result = await _repo.importPeople(fileName, bytes);
      state = state.copyWith(status: ImportStatus.success, result: result);
    } catch (e) {
      state = state.copyWith(
          status: ImportStatus.error, error: e.toString(), clearResult: true);
    }
  }

  void reset() => state = const ImportState();
}

final importProvider =
    StateNotifierProvider.autoDispose<ImportNotifier, ImportState>((ref) {
  return ImportNotifier(ref.watch(importRepositoryProvider));
});
