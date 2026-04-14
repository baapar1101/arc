import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PingPongGame extends StatefulWidget {
  final Function(int score, int survivalTime, int heroModeUses, double difficultyLevel)? onGameEnd;
  final Function(int score, int survivalTime)? onScoreUpdate;

  const PingPongGame({
    super.key,
    this.onGameEnd,
    this.onScoreUpdate,
  });

  @override
  State<PingPongGame> createState() => _PingPongGameState();
}

class _PingPongGameState extends State<PingPongGame>
    with TickerProviderStateMixin {
  late AnimationController _gameController;
  late FocusNode _gameFocusNode;
  
  // ابعاد بازی
  static const double gameWidth = 600;
  static const double gameHeight = 400;
  static const double wallHeight = 20;
  static const double paddleHeight = 15;
  static const double paddleWidth = 100;
  static const double ballSize = 15;
  static const double heroWallHeight = 30;
  
  // وضعیت بازی
  bool _isPlaying = false;
  bool _gameOver = false;
  
  // موقعیت پدل
  double _paddleX = (gameWidth - paddleWidth) / 2;
  double _paddleSpeed = 0;
  static const double maxPaddleSpeed = 8.0;
  
  // موقعیت توپ
  double _ballX = gameWidth / 2;
  double _ballY = gameHeight / 2;
  double _ballVelocityX = 0;
  double _ballVelocityY = 0;
  final double _baseBallSpeed = 2.0;
  
  // حالت قهرمان
  bool _heroModeActive = false;
  int _heroModeUsesRemaining = 3;
  DateTime? _heroModeStartTime;
  static const int heroModeDurationSeconds = 5;
  
  // امتیاز و زمان
  int _score = 0;
  int _survivalTime = 0;
  DateTime? _gameStartTime;
  double _difficultyMultiplier = 1.0;
  

  @override
  void initState() {
    super.initState();
    _gameFocusNode = FocusNode(debugLabel: 'PingPongGame');
    _gameController = AnimationController(
      vsync: this,
      duration: const Duration(days: 1), // طولانی برای loop نامحدود
    )..repeat();
    
    _gameController.addListener(_updateGame);
    _startGame();
    // اطمینان از فوکوس گرفتن برای دریافت کلیدها
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _gameFocusNode.canRequestFocus) {
        _gameFocusNode.requestFocus();
      }
    });
  }

  void _startGame() {
    setState(() {
      _isPlaying = true;
      _gameOver = false;
      _paddleX = (gameWidth - paddleWidth) / 2;
      _ballX = gameWidth / 2;
      _ballY = wallHeight + 50;
      _score = 0;
      _survivalTime = 0;
      _heroModeUsesRemaining = 3;
      _heroModeActive = false;
      _difficultyMultiplier = 1.0;
      _gameStartTime = DateTime.now();
      _heroModeStartTime = null;
      
      // شروع توپ با سرعت تصادفی
      final random = math.Random();
      final movingRight = random.nextBool();
      final angle = (math.pi / 4) + (random.nextDouble() * math.pi / 6);
      _ballVelocityX = _baseBallSpeed * math.cos(angle) * (movingRight ? 1 : -1);
      _ballVelocityY = _baseBallSpeed * math.sin(angle);
    });
  }

  void _updateGame() {
    if (!_isPlaying || _gameOver) return;

    final now = DateTime.now();
    if (_gameStartTime != null) {
      _survivalTime = now.difference(_gameStartTime!).inSeconds;
      _score = _survivalTime;
      
      // محاسبه ضریب سختی (هر 30 ثانیه 50% سریع‌تر)
      _difficultyMultiplier = 1.0 + (_survivalTime / 30.0) * 0.5;
      
      if (widget.onScoreUpdate != null) {
        widget.onScoreUpdate!(_score, _survivalTime);
      }
    }

    // بررسی حالت قهرمان
    if (_heroModeActive && _heroModeStartTime != null) {
      final heroElapsed = now.difference(_heroModeStartTime!).inSeconds;
      if (heroElapsed >= heroModeDurationSeconds) {
        setState(() {
          _heroModeActive = false;
          _heroModeStartTime = null;
        });
      }
    }

    setState(() {
      // حرکت پدل
      _paddleX += _paddleSpeed;
      _paddleX = _paddleX.clamp(0.0, gameWidth - paddleWidth);

      // حرکت توپ
      final currentSpeed = _baseBallSpeed * _difficultyMultiplier;
      final velocityMagnitude = math.sqrt(
        _ballVelocityX * _ballVelocityX + _ballVelocityY * _ballVelocityY,
      );
      if (velocityMagnitude > 0) {
        _ballVelocityX = (_ballVelocityX / velocityMagnitude) * currentSpeed;
        _ballVelocityY = (_ballVelocityY / velocityMagnitude) * currentSpeed;
      }

      _ballX += _ballVelocityX;
      _ballY += _ballVelocityY;

      // برخورد با دیوارهای چپ و راست
      if (_ballX <= 0 || _ballX >= gameWidth - ballSize) {
        _ballVelocityX = -_ballVelocityX;
        _ballX = _ballX.clamp(0.0, gameWidth - ballSize);
      }

      // برخورد با دیوار بالا
      if (_ballY <= wallHeight) {
        _ballVelocityY = -_ballVelocityY;
        _ballY = wallHeight;
      }

      // برخورد با پدل یا دیوار قهرمان
      final paddleTop = gameHeight - paddleHeight;
      final heroWallTop = gameHeight - heroWallHeight;
      
      // بررسی برخورد با دیوار قهرمان
      if (_heroModeActive) {
        if (_ballY >= heroWallTop && _ballY <= gameHeight &&
            _ballX + ballSize >= 0 && _ballX <= gameWidth) {
          _ballVelocityY = -_ballVelocityY.abs();
          _ballY = heroWallTop;
        }
      }

      // بررسی برخورد با پدل
      if (_ballY >= paddleTop - ballSize && _ballY <= paddleTop + paddleHeight &&
          _ballX + ballSize >= _paddleX && _ballX <= _paddleX + paddleWidth) {
        // محاسبه زاویه بر اساس محل برخورد در پدل
        final hitPosition = (_ballX + ballSize / 2 - _paddleX) / paddleWidth;
        final angle = (math.pi / 3) * (hitPosition - 0.5); // -30 تا +30 درجه
        
        _ballVelocityX = currentSpeed * math.sin(angle);
        _ballVelocityY = -currentSpeed * math.cos(angle);
        _ballY = paddleTop - ballSize;
      }

      // بررسی باخت (توپ از زیر پدل رد شد)
      if (_ballY >= gameHeight) {
        _endGame();
      }
    });
  }

  void _endGame() {
    if (_gameOver) return;
    
    setState(() {
      _gameOver = true;
      _isPlaying = false;
    });

    if (widget.onGameEnd != null) {
      final heroModeUses = 3 - _heroModeUsesRemaining;
      widget.onGameEnd!(_score, _survivalTime, heroModeUses, _difficultyMultiplier);
    }
  }

  void _activateHeroMode() {
    if (_heroModeUsesRemaining > 0 && !_heroModeActive) {
      setState(() {
        _heroModeActive = true;
        _heroModeUsesRemaining--;
        _heroModeStartTime = DateTime.now();
      });
    }
  }

  void handleKeyPress(LogicalKeyboardKey key) {
    if (_gameOver) return;
    
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _paddleSpeed = -maxPaddleSpeed;
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      _paddleSpeed = maxPaddleSpeed;
    } else if (key == LogicalKeyboardKey.space) {
      _activateHeroMode();
    }
  }

  void handleKeyRelease(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      _paddleSpeed = 0;
    }
  }

  @override
  void dispose() {
    _gameFocusNode.dispose();
    _gameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return RawKeyboardListener(
      focusNode: _gameFocusNode,
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent) {
          handleKeyPress(event.logicalKey);
        } else if (event is RawKeyUpEvent) {
          handleKeyRelease(event.logicalKey);
        }
      },
      child: Container(
        constraints: const BoxConstraints.expand(),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outline,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: _GamePainter(
              paddleX: _paddleX,
              paddleY: gameHeight - paddleHeight,
              ballX: _ballX,
              ballY: _ballY,
              heroModeActive: _heroModeActive,
              theme: theme,
            ),
            child: _gameOver
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sports_esports,
                            size: 48,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'بازی تمام شد!',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'امتیاز: $_score',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _startGame,
                            child: const Text('بازی مجدد'),
                          ),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  final double paddleX;
  final double paddleY;
  final double ballX;
  final double ballY;
  final bool heroModeActive;
  final ThemeData theme;

  _GamePainter({
    required this.paddleX,
    required this.paddleY,
    required this.ballX,
    required this.ballY,
    required this.heroModeActive,
    required this.theme,
  });

  static const double gameWidth = 600;
  static const double gameHeight = 400;
  static const double wallHeight = 20;
  static const double paddleHeight = 15;
  static const double paddleWidth = 100;
  static const double ballSize = 15;
  static const double heroWallHeight = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // مقیاس رسپانسیو: تناسب حفظ شود (letterbox)
    final scale = math.min(size.width / gameWidth, size.height / gameHeight);
    final contentW = gameWidth * scale;
    final contentH = gameHeight * scale;
    final offsetX = (size.width - contentW) / 2;
    final offsetY = (size.height - contentH) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale, scale);

    // دیوار بالا
    paint.color = theme.colorScheme.primary;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, gameWidth, wallHeight),
      paint,
    );

    // دیوار قهرمان (اگر فعال باشد)
    if (heroModeActive) {
      paint.color = theme.colorScheme.secondary;
      paint.shader = LinearGradient(
        colors: [
          theme.colorScheme.secondary,
          theme.colorScheme.secondary.withValues(alpha: 0.7),
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      ).createShader(Rect.fromLTWH(0, gameHeight - heroWallHeight, gameWidth, heroWallHeight));
      canvas.drawRect(
        Rect.fromLTWH(0, gameHeight - heroWallHeight, gameWidth, heroWallHeight),
        paint,
      );
      
      // افکت درخشش
      paint.shader = null;
      paint.color = Colors.white.withValues(alpha: 0.3);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;
      canvas.drawRect(
        Rect.fromLTWH(0, gameHeight - heroWallHeight, gameWidth, heroWallHeight),
        paint,
      );
      paint.style = PaintingStyle.fill;
    }

    // پدل
    paint.color = theme.colorScheme.primaryContainer;
    paint.shader = null;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(paddleX, paddleY, paddleWidth, paddleHeight),
        const Radius.circular(4),
      ),
      paint,
    );

    // توپ
    paint.color = theme.colorScheme.error;
    canvas.drawCircle(
      Offset(ballX + ballSize / 2, ballY + ballSize / 2),
      ballSize / 2,
      paint,
    );
    
    // سایه توپ
    paint.color = Colors.black.withValues(alpha: 0.2);
    canvas.drawCircle(
      Offset(ballX + ballSize / 2 + 2, ballY + ballSize / 2 + 2),
      ballSize / 2,
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GamePainter oldDelegate) {
    return paddleX != oldDelegate.paddleX ||
        paddleY != oldDelegate.paddleY ||
        ballX != oldDelegate.ballX ||
        ballY != oldDelegate.ballY ||
        heroModeActive != oldDelegate.heroModeActive;
  }
}

