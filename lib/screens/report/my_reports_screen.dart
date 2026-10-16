// lib/screens/report/my_reports_screen.dart
// 저장된 사고 리포트(PDF) 목록 - 테슬라 미니멀 스타일

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

import '../../utils/theme.dart';

class SavedReport {
  final File file;
  final String name;
  final DateTime modified;
  final int sizeBytes;

  SavedReport({
    required this.file,
    required this.name,
    required this.modified,
    required this.sizeBytes,
  });
}

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  List<SavedReport> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf') &&
              f.path.split(Platform.pathSeparator).last.startsWith('DriveGuard'))
          .toList();

      final reports = files.map((f) {
        final stat = f.statSync();
        return SavedReport(
          file: f,
          name: f.path.split(Platform.pathSeparator).last,
          modified: stat.modified,
          sizeBytes: stat.size,
        );
      }).toList()
        ..sort((a, b) => b.modified.compareTo(a.modified)); // 최신순

      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _reports = [];
        _loading = false;
      });
    }
  }

  Future<void> _openReport(SavedReport r) async {
    final result = await OpenFile.open(r.file.path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('리포트를 열 수 없습니다.')),
      );
    }
  }

  Future<void> _deleteReport(SavedReport r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDark,
        title: const Text('리포트 삭제',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text('${r.name}\n이 리포트를 삭제할까요?',
            style: const TextStyle(color: AppTheme.textSub, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: AppTheme.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await r.file.delete();
      } catch (_) {}
      _loadReports();
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : _reports.isEmpty
                      ? _buildEmpty()
                      : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.canPop() ? context.pop() : context.go('/'),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: 16),
          const Text(
            '내 리포트',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w400,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _loadReports,
            child: const Icon(Icons.refresh_rounded,
                size: 20, color: AppTheme.textSub),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.description_outlined,
              size: 56, color: AppTheme.textHint),
          SizedBox(height: 20),
          Text(
            '저장된 리포트가 없습니다',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w300,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '사고 분석 후 리포트를 저장하면\n여기에서 다시 볼 수 있어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w300,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: _reports.length,
      separatorBuilder: (_, __) =>
          Container(height: 0.5, color: AppTheme.divider),
      itemBuilder: (_, i) => _buildReportRow(_reports[i]),
    );
  }

  Widget _buildReportRow(SavedReport r) {
    final dateStr = DateFormat('yyyy.MM.dd  HH:mm').format(r.modified);
    return GestureDetector(
      onTap: () => _openReport(r),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.divider, width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.picture_as_pdf_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '사고 리포트',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$dateStr · ${_formatSize(r.sizeBytes)}',
                    style: const TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 11,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _deleteReport(r),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Icon(Icons.delete_outline_rounded,
                    color: AppTheme.textHint, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
