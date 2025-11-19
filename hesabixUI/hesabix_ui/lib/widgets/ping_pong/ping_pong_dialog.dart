import 'package:flutter/material.dart';
import 'ping_pong_game.dart';
import '../../services/ping_pong_service.dart';
import '../../models/ping_pong_score_model.dart';
import 'dart:async';

class PingPongDialog extends StatefulWidget {
  const PingPongDialog({super.key});

  @override
  State<PingPongDialog> createState() => _PingPongDialogState();
}

class _PingPongDialogState extends State<PingPongDialog> {
  int _currentScore = 0;
  int _survivalTime = 0;
  final int _heroModeUsesRemaining = 3;
  final bool _heroModeActive = false;
  PingPongScore? _bestScore;
  List<LeaderboardEntry>? _leaderboard;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLoadingLeaderboard = true;
  
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _loadBestScore();
    _loadLeaderboard();
    
    // تایمر برای به‌روزرسانی UI
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBestScore() async {
    try {
      final best = await PingPongService.getBestScore();
      setState(() {
        _bestScore = best;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری بهترین امتیاز: $e')),
        );
      }
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() {
      _isLoadingLeaderboard = true;
    });
    try {
      final list = await PingPongService.getLeaderboard(limit: 10);
      if (mounted) {
        setState(() {
          _leaderboard = list;
          _isLoadingLeaderboard = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _leaderboard = const [];
          _isLoadingLeaderboard = false;
        });
      }
    }
  }

  Future<void> _handleGameEnd(
    int score,
    int survivalTime,
    int heroModeUses,
    double difficultyLevel,
  ) async {
    setState(() {
      _isSaving = true;
    });

    try {
      await PingPongService.saveScore(
        score: score,
        survivalTime: survivalTime,
        heroModeUses: heroModeUses,
        difficultyLevel: difficultyLevel,
      );

      // به‌روزرسانی بهترین امتیاز
      await _loadBestScore();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('امتیاز شما با موفقیت ذخیره شد!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ذخیره امتیاز: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _handleScoreUpdate(int score, int survivalTime) {
    setState(() {
      _currentScore = score;
      _survivalTime = survivalTime;
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screen = MediaQuery.of(context).size;
          final maxWidth = screen.width * 0.96;
          final maxHeight = screen.height * 0.96;
          final panelWidth = screen.width < 480 ? 108.0 : 132.0;
          final containerPadding = screen.width < 480 ? 8.0 : 12.0;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
              minWidth: 320,
              minHeight: 280,
            ),
            child: Container(
              width: maxWidth.clamp(320, 1100),
              height: maxHeight.clamp(280, 900),
              padding: EdgeInsets.all(containerPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Game area: fills all available height
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: PingPongGame(
                          onGameEnd: _handleGameEnd,
                          onScoreUpdate: _handleScoreUpdate,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Side vertical panel: info, help, actions
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: panelWidth, maxWidth: panelWidth),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Leaderboard (Top players)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'نفرات برتر',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.start,
                            ),
                          ),
                          if (_isLoadingLeaderboard)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          else
                            _buildLeaderboardList(theme),
                          const SizedBox(height: 8),
                          Divider(color: theme.colorScheme.outlineVariant),
                          const SizedBox(height: 8),
                          // Best score (compact)
                          if (_bestScore != null && !_isLoading)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.emoji_events,
                                        color: theme.colorScheme.secondary,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'بهترین',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: theme.colorScheme.secondary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_bestScore!.score} • ${_formatTime(_bestScore!.survivalTime)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          if (_bestScore != null && !_isLoading) const SizedBox(height: 8),
                          // Live stats
                          _buildInfoCard(
                            theme,
                            'امتیاز',
                            _currentScore.toString(),
                            Icons.stars,
                          ),
                          const SizedBox(height: 8),
                          _buildInfoCard(
                            theme,
                            'زمان',
                            _formatTime(_survivalTime),
                            Icons.timer,
                          ),
                          const SizedBox(height: 8),
                          _buildInfoCard(
                            theme,
                            'قهرمان',
                            '🔥x$_heroModeUsesRemaining',
                            Icons.shield,
                            isActive: _heroModeActive,
                          ),
                          const SizedBox(height: 8),
                          Divider(color: theme.colorScheme.outlineVariant),
                          const SizedBox(height: 8),
                          // Controls help (vertical)
                          _buildControlHint(theme, '← →', 'حرکت'),
                          const SizedBox(height: 6),
                          _buildControlHint(theme, 'Space', 'قهرمان'),
                          const SizedBox(height: 6),
                          _buildControlHint(theme, 'ESC', 'بستن'),
                          const Spacer(),
                          if (_isSaving)
                            const Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 36,
                            child: FilledButton.tonal(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('بستن'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLeaderboardList(ThemeData theme) {
    final items = _leaderboard ?? const <LeaderboardEntry>[];
    if (items.isEmpty) {
      return Text(
        'هنوز رکوردی ثبت نشده',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
        textAlign: TextAlign.start,
      );
    }
    // نمایش حداکثر 6 آیتم برای تناسب با پنل باریک
    final display = items.take(6).toList();
    return Column(
      children: [
        for (final e in display)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${e.rank}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    e.userName.isNotEmpty ? e.userName : 'کاربر ${e.userId}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stars, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 2),
                    Text(
                      '${e.score}',
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInfoCard(
    ThemeData theme,
    String label,
    String value,
    IconData icon, {
    bool isActive = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border.all(
                color: theme.colorScheme.secondary,
                width: 2,
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: isActive
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.primary,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isActive
                  ? theme.colorScheme.onSecondaryContainer
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlHint(ThemeData theme, String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.colorScheme.outline,
              width: 1,
            ),
          ),
          child: Text(
            key,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

