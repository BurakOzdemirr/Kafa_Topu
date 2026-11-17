import 'package:material_ui/material_ui.dart';

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart' hide Colors;
import 'package:flutter/material.dart' as mat show Colors;
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(GameWidget(game: KafaTopuGame()));
}

enum GameState { menu, characterSelect, playing, paused, goalCelebration, gameOver }
enum PowerUpType { freeze, superKick, bigHead }

class KafaTopuGame extends FlameGame with KeyboardEvents {
  late Player player1;
  late Player player2;
  late Ball ball;
  PowerUpBox? activePowerUpBox;

  late TextComponent scoreText;
  late TextComponent timerText;
  late TextComponent bannerText;
  late TextComponent subBannerText;
  late StartOverlayButton actionButton;
  late StartOverlayButton secondaryButton;
  late PauseButton pauseButton;

  Color p1Jersey = mat.Colors.redAccent.shade700;
  Color p1Hair = const Color(0xFF2C1E16);
  Color p2Jersey = mat.Colors.amber.shade700;
  Color p2Hair = const Color(0xFFD4AF37);

  GameState state = GameState.menu;

  int score1 = 0;
  int score2 = 0;
  double matchTime = 180.0;
  double celebrationTimer = 0.0;
  double powerUpSpawnTimer = 10.0;

  double botReactionTimer = 0.0;
  double screenShakeTimer = 0.0;
  final Random _rng = Random();

  double get groundY => size.y - 60;
  final double goalWidth = 55;
  final double goalHeight = 152;

  final SoundFX soundFX = SoundFX();

  @override
  Color backgroundColor() => const Color(0xFF0A2E63);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await soundFX.init();

    add(StadiumBackground());
    add(GoalComponent(isLeft: true));
    add(GoalComponent(isLeft: false));

    player1 = Player(
      jerseyColor: p1Jersey,
      hairColor: p1Hair,
      facingRight: true,
      speed: 350,
      isBot: false,
    );
    player2 = Player(
      jerseyColor: p2Jersey,
      hairColor: p2Hair,
      facingRight: false,
      speed: 235,
      isBot: true,
    );
    ball = Ball();
    addAll([player1, player2, ball]);

    add(ScoreboardHUD());

    scoreText = TextComponent(
      text: '0   -   0',
      position: Vector2(size.x / 2, 18),
      anchor: Anchor.topCenter,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: mat.Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    timerText = TextComponent(
      text: '03:00',
      position: Vector2(size.x / 2, 54),
      anchor: Anchor.topCenter,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: mat.Colors.amberAccent,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    pauseButton = PauseButton(
      position: Vector2(size.x - 64, 18),
      onPressed: togglePause,
    );

    addAll([scoreText, timerText, pauseButton]);

    bannerText = TextComponent(
      text: 'KAFA TOPU 2',
      position: Vector2(size.x / 2, size.y * 0.25),
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: mat.Colors.white,
          fontSize: 52,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(color: mat.Colors.black87, offset: Offset(3, 3), blurRadius: 6),
          ],
        ),
      ),
    );

    subBannerText = TextComponent(
      text: 'Dev Kafalar, Süper Güçler ve Büyük Mücadele!',
      position: Vector2(size.x / 2, size.y * 0.38),
      anchor: Anchor.center,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: mat.Colors.amberAccent,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: mat.Colors.black87, offset: Offset(2, 2), blurRadius: 4),
          ],
        ),
      ),
    );

    actionButton = StartOverlayButton(
      label: 'OYUNA BAŞLA',
      position: Vector2(size.x / 2 - 110, size.y * 0.48),
      onPressed: () => setState(GameState.characterSelect),
    );

    secondaryButton = StartOverlayButton(
      label: 'YENİDEN BAŞLAT',
      position: Vector2(size.x / 2 - 110, size.y * 0.62),
      color: const Color(0xFFE65100),
      onPressed: startMatch,
    )..isVisible = false;

    addAll([bannerText, subBannerText, actionButton, secondaryButton]);

    setupControls();
    resetPositions();
    updateUIForState();
  }

  void setState(GameState newState) {
    state = newState;
    updateUIForState();
  }

  void updateUIForState() {
    if (state == GameState.menu) {
      bannerText.text = 'KAFA TOPU 2';
      subBannerText.text = 'Dev Kafalar ve Süper Güçlerle Donatıldı!';
      actionButton.label = 'OYUNA BAŞLA';
      actionButton.onPressed = () => setState(GameState.characterSelect);
      actionButton.isVisible = true;
      secondaryButton.isVisible = false;
      pauseButton.isVisible = false;
    } else if (state == GameState.characterSelect) {
      bannerText.text = 'TAKIMINI SEÇ';
      subBannerText.text = 'Forma Rengini Belirle ve Sahaya Çık!';
      actionButton.label = 'MAÇA BAŞLA';
      actionButton.onPressed = startMatch;
      actionButton.isVisible = true;
      secondaryButton.isVisible = false;
      pauseButton.isVisible = false;
    } else if (state == GameState.playing) {
      bannerText.text = '';
      subBannerText.text = '';
      actionButton.isVisible = false;
      secondaryButton.isVisible = false;
      pauseButton.isVisible = true;
    }
  }

  void setupControls() {
    const btnSize = 68.0;
    final bottomY = size.y - btnSize - 18;

    add(ControlButton(
      label: '◀',
      position: Vector2(28, bottomY),
      buttonSize: btnSize,
      onPressed: () {
        if (state == GameState.playing && !player1.isFrozen) player1.moveDir = -1;
      },
      onReleased: () {
        if (player1.moveDir < 0) player1.moveDir = 0;
      },
    ));

    add(ControlButton(
      label: '▶',
      position: Vector2(28 + btnSize + 18, bottomY),
      buttonSize: btnSize,
      onPressed: () {
        if (state == GameState.playing && !player1.isFrozen) player1.moveDir = 1;
      },
      onReleased: () {
        if (player1.moveDir > 0) player1.moveDir = 0;
      },
    ));

    add(ControlButton(
      label: '⚽',
      position: Vector2(size.x - (btnSize * 2) - 46, bottomY),
      buttonSize: btnSize,
      color: mat.Colors.orangeAccent.withValues(alpha: 0.8),
      onPressed: () {
        if (state == GameState.playing && !player1.isFrozen) player1.kick();
      },
    ));

    add(ControlButton(
      label: '▲',
      position: Vector2(size.x - btnSize - 28, bottomY),
      buttonSize: btnSize,
      color: mat.Colors.lightGreenAccent.withValues(alpha: 0.8),
      onPressed: () {
        if (state == GameState.playing && !player1.isFrozen) player1.jump();
      },
    ));
  }

  void togglePause() {
    if (state == GameState.playing) {
      state = GameState.paused;
      bannerText.text = 'OYUN DURAKLATILDI';
      subBannerText.text = 'Skor: $score1 - $score2';
      actionButton.label = 'DEVAM ET';
      actionButton.isVisible = true;
      secondaryButton.isVisible = true;
    } else if (state == GameState.paused) {
      state = GameState.playing;
      bannerText.text = '';
      subBannerText.text = '';
      actionButton.isVisible = false;
      secondaryButton.isVisible = false;
    }
  }

  void startMatch() {
    score1 = 0;
    score2 = 0;
    matchTime = 180.0;
    powerUpSpawnTimer = 10.0;
    activePowerUpBox?.removeFromParent();
    activePowerUpBox = null;

    setState(GameState.playing);

    player1.jerseyColor = p1Jersey;
    player1.hairColor = p1Hair;
    player2.jerseyColor = p2Jersey;
    player2.hairColor = p2Hair;

    resetPositions();
    soundFX.playWhistle();
  }

  void resetPositions() {
    scoreText.text = '$score1   -   $score2';

    player1.position = Vector2(goalWidth + 45, groundY - player1.height / 2);
    player1.velocity = Vector2.zero();
    player1.moveDir = 0;
    player1.isFrozen = false;

    player2.position = Vector2(size.x - goalWidth - 45, groundY - player2.height / 2);
    player2.velocity = Vector2.zero();
    player2.moveDir = 0;
    player2.isFrozen = false;

    ball.position = Vector2(size.x / 2, size.y * 0.25);
    ball.velocity = Vector2.zero();
    ball.rotationAngle = 0;
    ball.trail.clear();
  }

  void triggerGoal(bool player1Scored) {
    if (state != GameState.playing) return;

    if (player1Scored) {
      score1++;
    } else {
      score2++;
    }
    scoreText.text = '$score1   -   $score2';
    state = GameState.goalCelebration;
    celebrationTimer = 2.0;
    screenShakeTimer = 0.35;

    bannerText.text = 'GOOOOL!';
    subBannerText.text = player1Scored ? 'Müthiş Şut!' : 'Rakip Ağları Sarsarak Gol Attı!';

    soundFX.playGoal();
    spawnConfetti();
  }

  void spawnConfetti() {
    final colors = [
      mat.Colors.redAccent,
      mat.Colors.amber,
      mat.Colors.lightGreenAccent,
      mat.Colors.cyanAccent,
      mat.Colors.white,
    ];
    for (int i = 0; i < 55; i++) {
      add(ConfettiParticle(
        startPos: Vector2(size.x * (0.2 + _rng.nextDouble() * 0.6), size.y * 0.2),
        color: colors[_rng.nextInt(colors.length)],
      ));
    }
  }

  void endMatch() {
    state = GameState.gameOver;
    soundFX.playWhistle();

    if (score1 > score2) {
      bannerText.text = 'KAZANDIN!';
      subBannerText.text = 'Maç Sonucu: $score1 - $score2';
    } else if (score2 > score1) {
      bannerText.text = 'KAYBETTİN!';
      subBannerText.text = 'Maç Sonucu: $score1 - $score2';
    } else {
      bannerText.text = 'BERABERE!';
      subBannerText.text = 'Maç Sonucu: $score1 - $score2';
    }

    actionButton.label = 'TEKRAR OYNA';
    actionButton.onPressed = startMatch;
    actionButton.isVisible = true;
    secondaryButton.isVisible = false;
    pauseButton.isVisible = false;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    if (screenShakeTimer > 0) {
      final dx = (_rng.nextDouble() - 0.5) * 12;
      final dy = (_rng.nextDouble() - 0.5) * 12;
      canvas.translate(dx, dy);
    }
    super.render(canvas);

    if (state == GameState.characterSelect) {
      _renderColorPicker(canvas);
    }

    canvas.restore();
  }

  void _renderColorPicker(Canvas canvas) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Forma Rengini Değiştirmek İçin Dokun / Tıkla\n(Kırmızı, Sarı, Mavi, Mor)',
        style: TextStyle(color: mat.Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset((size.x - textPainter.width) / 2, size.y * 0.52));
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (screenShakeTimer > 0) screenShakeTimer -= dt;

    if (state == GameState.goalCelebration) {
      celebrationTimer -= dt;
      if (celebrationTimer <= 0) {
        bannerText.text = '';
        subBannerText.text = '';
        state = GameState.playing;
        resetPositions();
      }
      return;
    }

    if (state != GameState.playing) return;

    matchTime -= dt;
    if (matchTime <= 0) {
      matchTime = 0;
      timerText.text = '00:00';
      endMatch();
      return;
    }

    int minutes = matchTime ~/ 60;
    int seconds = (matchTime % 60).toInt();
    timerText.text = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    powerUpSpawnTimer -= dt;
    if (powerUpSpawnTimer <= 0 && activePowerUpBox == null) {
      powerUpSpawnTimer = 14.0;
      activePowerUpBox = PowerUpBox(
        position: Vector2(size.x / 2, groundY - 100),
      );
      add(activePowerUpBox!);
    }

    updateBotAI(dt);
    checkPlayerBallCollision(player1);
    checkPlayerBallCollision(player2);
    checkGoalPostCollision();
    checkPowerUpBoxCollision();

    if (ball.position.x - ball.radius < goalWidth - 15 &&
        ball.position.y > groundY - goalHeight) {
      triggerGoal(false);
    } else if (ball.position.x + ball.radius > size.x - goalWidth + 15 &&
        ball.position.y > groundY - goalHeight) {
      triggerGoal(true);
    }
  }

  void checkPowerUpBoxCollision() {
    if (activePowerUpBox == null) return;

    for (var player in [player1, player2]) {
      final pDist = (player.position - activePowerUpBox!.position).length;
      final bDist = (ball.position - activePowerUpBox!.position).length;

      if (pDist < 45 || bDist < 35) {
        applyRandomPowerUp(player == player1);
        activePowerUpBox?.removeFromParent();
        activePowerUpBox = null;
        break;
      }
    }
  }

  void applyRandomPowerUp(bool isPlayer1) {
    final types = PowerUpType.values;
    final chosenType = types[_rng.nextInt(types.length)];

    final target = isPlayer1 ? player1 : player2;
    final opponent = isPlayer1 ? player2 : player1;

    switch (chosenType) {
      case PowerUpType.freeze:
        opponent.isFrozen = true;
        Future.delayed(const Duration(seconds: 3), () => opponent.isFrozen = false);
        subBannerText.text = isPlayer1 ? '⚡ Rakip Donduruldu!' : '❄️ Bot Seni Dondurdu!';
        break;
      case PowerUpType.superKick:
        target.hasSuperKick = true;
        subBannerText.text = isPlayer1 ? '🔥 Ateşli Şut Yüklendi!' : '🔥 Bot Süper Şut Aldı!';
        break;
      case PowerUpType.bigHead:
        target.isMegaHead = true;
        Future.delayed(const Duration(seconds: 5), () => target.isMegaHead = false);
        subBannerText.text = isPlayer1 ? '🗿 Mega Dev Kafa Aktif!' : '🗿 Botun Kafası Devleşti!';
        break;
    }
  }

  void updateBotAI(double dt) {
    botReactionTimer -= dt;
    if (botReactionTimer > 0) return;
    botReactionTimer = 0.22;

    final ballX = ball.position.x;
    final botX = player2.position.x;
    final distToBallX = ballX - botX;
    final distToBallY = ball.position.y - player2.position.y;

    if (player2.isFrozen) {
      player2.moveDir = 0;
      return;
    }

    if (ballX > size.x * 0.42) {
      if (distToBallX < -22) {
        player2.moveDir = -1;
      } else if (distToBallX > 22) {
        player2.moveDir = 1;
      } else {
        player2.moveDir = 0;
      }

      if (distToBallY < -45 && distToBallX.abs() < 65 && player2.isOnGround && _rng.nextDouble() < 0.7) {
        player2.jump();
      }

      if (distToBallX < 12 && distToBallX > -50 && distToBallY.abs() < 48) {
        player2.kick();
      }
    } else {
      final homeX = size.x - goalWidth - 55;
      if ((botX - homeX).abs() > 22) {
        player2.moveDir = botX > homeX ? -0.65 : 0.65;
      } else {
        player2.moveDir = 0;
      }
    }
  }

  void checkPlayerBallCollision(Player player) {
    final closestX = ball.position.x.clamp(
      player.position.x - player.width / 2,
      player.position.x + player.width / 2,
    );
    final closestY = ball.position.y.clamp(
      player.position.y - player.height / 2,
      player.position.y + player.height / 2,
    );

    final dx = ball.position.x - closestX;
    final dy = ball.position.y - closestY;
    final distance = sqrt(dx * dx + dy * dy);

    if (distance < ball.radius) {
      final nx = distance == 0 ? 0.0 : dx / distance;
      final ny = distance == 0 ? -1.0 : dy / distance;

      final overlap = ball.radius - distance;
      ball.position.x += nx * overlap;
      ball.position.y += ny * overlap;

      double powerMul = player.hasSuperKick ? 1.6 : 1.0;
      ball.velocity.x = (nx * 430 + player.velocity.x * 0.65) * powerMul;
      ball.velocity.y = ((ny * 430 - 140) * powerMul).clamp(-750, 400);

      if (player.hasSuperKick) player.hasSuperKick = false;
      soundFX.playKick();
    }
  }

  void checkGoalPostCollision() {
    final postY = groundY - goalHeight;
    if (ball.position.x - ball.radius < goalWidth &&
        (ball.position.y - postY).abs() < ball.radius + 4) {
      ball.velocity.y = -ball.velocity.y.abs() * 0.85;
      ball.velocity.x = ball.velocity.x.abs() * 0.8;
      soundFX.playKick();
    }
    if (ball.position.x + ball.radius > size.x - goalWidth &&
        (ball.position.y - postY).abs() < ball.radius + 4) {
      ball.velocity.y = -ball.velocity.y.abs() * 0.85;
      ball.velocity.x = -ball.velocity.x.abs() * 0.8;
      soundFX.playKick();
    }
  }

  @override
  KeyEventResult onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (keysPressed.contains(LogicalKeyboardKey.escape)) {
      if (state == GameState.playing || state == GameState.paused) {
        togglePause();
        return KeyEventResult.handled;
      }
    }

    if (state != GameState.playing || player1.isFrozen) return KeyEventResult.ignored;

    if (keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA)) {
      player1.moveDir = -1;
    } else if (keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD)) {
      player1.moveDir = 1;
    } else {
      player1.moveDir = 0;
    }

    if (keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW)) {
      player1.jump();
    }

    if (keysPressed.contains(LogicalKeyboardKey.space)) {
      player1.kick();
    }

    return KeyEventResult.handled;
  }
}

// --- YARDIMCI BİLEŞEN SINIFLARI ---

class PauseButton extends PositionComponent with TapCallbacks {
  final VoidCallback onPressed;
  bool isVisible = true;

  PauseButton({required Vector2 position, required this.onPressed})
      : super(position: position, size: Vector2.all(44));

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;
    final rect = RRect.fromRectAndRadius(size.toRect(), const Radius.circular(10));
    canvas.drawRRect(rect, Paint()..color = mat.Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = mat.Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final barPaint = Paint()..color = mat.Colors.white;
    canvas.drawRect(const Rect.fromLTWH(14, 12, 5, 20), barPaint);
    canvas.drawRect(const Rect.fromLTWH(25, 12, 5, 20), barPaint);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (isVisible) onPressed();
  }
}

class StartOverlayButton extends PositionComponent with TapCallbacks {
  String label;
  VoidCallback onPressed;
  final Color color;
  bool isVisible = true;

  StartOverlayButton({
    required this.label,
    required Vector2 position,
    required this.onPressed,
    this.color = const Color(0xFF43A047),
  }) : super(position: position, size: Vector2(220, 54));

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    final rect = RRect.fromRectAndRadius(size.toRect(), const Radius.circular(27));
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = mat.Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: mat.Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, (height - textPainter.height) / 2),
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (isVisible) onPressed();
  }
}

class ControlButton extends PositionComponent with TapCallbacks {
  final String label;
  final double buttonSize;
  final Color? color;
  final VoidCallback onPressed;
  final VoidCallback? onReleased;

  bool isPressed = false;

  ControlButton({
    required this.label,
    required Vector2 position,
    required this.buttonSize,
    required this.onPressed,
    this.onReleased,
    this.color,
  }) : super(position: position, size: Vector2.all(buttonSize));

  @override
  void render(Canvas canvas) {
    final baseColor = color ?? mat.Colors.white.withValues(alpha: 0.45);
    final fillPaint = Paint()
      ..color = isPressed ? baseColor.withValues(alpha: 0.95) : baseColor;
    final borderPaint = Paint()
      ..color = mat.Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final center = Offset(buttonSize / 2, buttonSize / 2);
    canvas.drawCircle(center, buttonSize / 2, fillPaint);
    canvas.drawCircle(center, buttonSize / 2, borderPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: mat.Colors.black87,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        (buttonSize - textPainter.width) / 2,
        (buttonSize - textPainter.height) / 2,
      ),
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    isPressed = true;
    onPressed();
  }

  @override
  void onTapUp(TapUpEvent event) {
    isPressed = false;
    onReleased?.call();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    isPressed = false;
    onReleased?.call();
  }
}

class ConfettiParticle extends PositionComponent {
  final Color color;
  late Vector2 velocity;
  double life = 2.0;

  ConfettiParticle({required Vector2 startPos, required this.color})
      : super(position: startPos, size: Vector2(10, 6)) {
    final rng = Random();
    velocity = Vector2(
      (rng.nextDouble() - 0.5) * 450,
      -150 - rng.nextDouble() * 250,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    life -= dt;
    if (life <= 0) {
      removeFromParent();
      return;
    }
    velocity.y += 550 * dt;
    position += velocity * dt;
    angle += 6 * dt;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(size.toRect(), Paint()..color = color);
  }
}

// --- SES EFEKTİ ---

class SoundFX {
  final AudioPlayer _kickPlayer = AudioPlayer();
  final AudioPlayer _jumpPlayer = AudioPlayer();
  final AudioPlayer _goalPlayer = AudioPlayer();
  final AudioPlayer _whistlePlayer = AudioPlayer();

  BytesSource? _kickSrc;
  BytesSource? _jumpSrc;
  BytesSource? _goalSrc;
  BytesSource? _whistleSrc;

  Future<void> init() async {
    _kickSrc = BytesSource(_generateWav(startFreq: 190, endFreq: 65, durationMs: 90));
    _jumpSrc = BytesSource(_generateWav(startFreq: 220, endFreq: 480, durationMs: 120));
    _goalSrc = BytesSource(_generateWav(startFreq: 440, endFreq: 880, durationMs: 450));
    _whistleSrc = BytesSource(_generateWav(startFreq: 2400, endFreq: 2100, durationMs: 320));
  }

  void playKick() {
    if (_kickSrc != null) _kickPlayer.play(_kickSrc!, volume: 0.5);
  }

  void playJump() {
    if (_jumpSrc != null) _jumpPlayer.play(_jumpSrc!, volume: 0.35);
  }

  void playGoal() {
    if (_goalSrc != null) _goalPlayer.play(_goalSrc!, volume: 0.6);
  }

  void playWhistle() {
    if (_whistleSrc != null) _whistlePlayer.play(_whistleSrc!, volume: 0.45);
  }

  Uint8List _generateWav({
    required double startFreq,
    required double endFreq,
    required int durationMs,
  }) {
    const sampleRate = 22050;
    final numSamples = (sampleRate * durationMs) ~/ 1000;
    final dataSize = numSamples * 2;
    final byteData = ByteData(44 + dataSize);

    byteData.setUint32(0, 0x52494646, Endian.big);
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    byteData.setUint32(8, 0x57415645, Endian.big);
    byteData.setUint32(12, 0x666d7420, Endian.big);
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    byteData.setUint32(36, 0x64617461, Endian.big);
    byteData.setUint32(40, dataSize, Endian.little);

    double phase = 0;
    for (int i = 0; i < numSamples; i++) {
      final t = i / numSamples;
      final freq = startFreq + (endFreq - startFreq) * t;
      final envelope = (1.0 - t);
      phase += (2 * pi * freq) / sampleRate;
      final sample = (sin(phase) * envelope * 28000).toInt().clamp(-32768, 32767);
      byteData.setInt16(44 + i * 2, sample, Endian.little);
    }
    return byteData.buffer.asUint8List();
  }
}

// --- STADYUM VE TARAFTARLAR ---

class ScoreboardHUD extends PositionComponent with HasGameReference<KafaTopuGame> {
  @override
  void render(Canvas canvas) {
    final cx = game.size.x / 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, 48), width: 210, height: 74),
      const Radius.circular(14),
    );
    canvas.drawRRect(rect, Paint()..color = mat.Colors.black.withValues(alpha: 0.72));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = mat.Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}

class StadiumBackground extends PositionComponent with HasGameReference<KafaTopuGame> {
  double cheerPhase = 0;

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state == GameState.goalCelebration) {
      cheerPhase += dt * 18;
    } else {
      cheerPhase += dt * 2.5;
    }
  }

  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    final groundY = game.groundY;

    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFF071E42), const Color(0xFF1565C0)],
      ).createShader(Rect.fromLTWH(0, 0, w, groundY - 110));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, groundY - 110), skyPaint);

    _drawFloodlight(canvas, 85, groundY - 195, true);
    _drawFloodlight(canvas, w - 85, groundY - 195, false);

    final standPaint = Paint()..color = const Color(0xFF121B54);
    canvas.drawRect(Rect.fromLTWH(0, groundY - 160, w, 160), standPaint);

    final tierLine = Paint()
      ..color = mat.Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 2;
    for (double y = groundY - 150; y < groundY - 25; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(w, y), tierLine);
    }

    final rng = Random(123);
    int fanIndex = 0;
    for (double x = 15; x < w; x += 22) {
      for (double y = groundY - 145; y < groundY - 30; y += 26) {
        fanIndex++;
        final shirtColors = [
          mat.Colors.redAccent,
          mat.Colors.amber,
          mat.Colors.white,
          mat.Colors.cyanAccent,
          mat.Colors.yellow,
          mat.Colors.purpleAccent,
        ];
        final col = shirtColors[rng.nextInt(shirtColors.length)];

        final jumpOffset = game.state == GameState.goalCelebration
            ? sin(cheerPhase + fanIndex).abs() * -6.0
            : sin(cheerPhase + fanIndex) * -1.2;

        final fy = y + jumpOffset;

        final bodyPaint = Paint()..color = col.withValues(alpha: 0.88);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, fy + 6, 10, 14), const Radius.circular(3)),
          bodyPaint,
        );

        if (game.state == GameState.goalCelebration) {
          final armPaint = Paint()
            ..color = col
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(Offset(x + 1, fy + 8), Offset(x - 3, fy + 1), armPaint);
          canvas.drawLine(Offset(x + 9, fy + 8), Offset(x + 13, fy + 1), armPaint);
        }

        final headPaint = Paint()..color = const Color(0xFFFFCC99);
        canvas.drawCircle(Offset(x + 5, fy + 2), 4.5, headPaint);
      }
    }

    final boardRect = Rect.fromLTWH(0, groundY - 28, w, 28);
    canvas.drawRect(boardRect, Paint()..color = const Color(0xFFB71C1C));

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '★ KAFA TOPU 2 ★ SUPERSUPER LEAGUE ★',
        style: TextStyle(color: mat.Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    for (double tx = 0; tx < w; tx += textPainter.width + 100) {
      textPainter.paint(canvas, Offset(tx, groundY - 21));
    }

    final grassDark = Paint()..color = const Color(0xFF1B5E20);
    final grassLight = Paint()..color = const Color(0xFF2E7D32);
    canvas.drawRect(Rect.fromLTWH(0, groundY, w, h - groundY), grassDark);

    const stripeWidth = 70.0;
    for (double x = 0; x < w; x += stripeWidth * 2) {
      canvas.drawRect(Rect.fromLTWH(x, groundY, stripeWidth, h - groundY), grassLight);
    }

    final linePaint = Paint()
      ..color = mat.Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 3.5;
    canvas.drawLine(Offset(0, groundY + 3), Offset(w, groundY + 3), linePaint);
    canvas.drawLine(Offset(w / 2, groundY), Offset(w / 2, h), linePaint);

    canvas.drawCircle(
      Offset(w / 2, groundY + (h - groundY) / 2),
      55,
      Paint()
        ..color = mat.Colors.white.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _drawFloodlight(Canvas canvas, double x, double y, bool isLeft) {
    canvas.drawLine(
      Offset(x, y),
      Offset(x, y + 40),
      Paint()
        ..color = mat.Colors.blueGrey.shade300
        ..strokeWidth = 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: 34, height: 18), const Radius.circular(4)),
      Paint()..color = mat.Colors.white,
    );
    final beamPath = Path()
      ..moveTo(x - 14, y + 8)
      ..lineTo(x + 14, y + 8)
      ..lineTo(isLeft ? x + 220 : x - 220, game.groundY)
      ..lineTo(isLeft ? x - 40 : x + 40, game.groundY)
      ..close();
    canvas.drawPath(
      beamPath,
      Paint()..color = mat.Colors.white.withValues(alpha: 0.06),
    );
  }
}

class GoalComponent extends PositionComponent with HasGameReference<KafaTopuGame> {
  final bool isLeft;
  GoalComponent({required this.isLeft});

  @override
  void render(Canvas canvas) {
    final gw = game.goalWidth;
    final gh = game.goalHeight;
    final gy = game.groundY;
    final startX = isLeft ? 0.0 : game.size.x - gw;

    final bgPaint = Paint()..color = mat.Colors.black.withValues(alpha: 0.25);
    canvas.drawRect(Rect.fromLTWH(startX, gy - gh, gw, gh), bgPaint);

    final netPaint = Paint()
      ..color = mat.Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.2;

    for (double x = startX; x <= startX + gw; x += 9) {
      canvas.drawLine(Offset(x, gy - gh), Offset(x, gy), netPaint);
    }
    for (double y = gy - gh; y <= gy; y += 11) {
      canvas.drawLine(Offset(startX, y), Offset(startX + gw, y), netPaint);
    }

    final postPaint = Paint()
      ..color = mat.Colors.white
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final postX = isLeft ? gw : game.size.x - gw;
    canvas.drawLine(Offset(startX, gy - gh), Offset(postX, gy - gh), postPaint);
    canvas.drawLine(Offset(postX, gy - gh), Offset(postX, gy), postPaint);
  }
}

// --- DEV KAFALI OYUNCU ---

class Player extends PositionComponent with HasGameReference<KafaTopuGame>, TapCallbacks {
  Color jerseyColor;
  Color hairColor;
  final bool facingRight;
  final double speed;
  final bool isBot;

  Vector2 velocity = Vector2.zero();
  double moveDir = 0;
  bool isOnGround = false;

  bool isFrozen = false;
  bool hasSuperKick = false;
  bool isMegaHead = false;

  double kickTimer = 0;
  final double kickDuration = 0.22;

  final double gravity = 1450;
  final double jumpForce = -640;

  Player({
    required this.jerseyColor,
    required this.hairColor,
    required this.facingRight,
    required this.speed,
    required this.isBot,
  }) : super(size: Vector2(58, 86), anchor: Anchor.center);

  void jump() {
    if (isOnGround && !isFrozen) {
      velocity.y = jumpForce;
      isOnGround = false;
      game.soundFX.playJump();
    }
  }

  void kick() {
    if (kickTimer <= 0 && !isFrozen) {
      kickTimer = kickDuration;
      final dir = facingRight ? 1.0 : -1.0;
      final footX = position.x + dir * 28;
      final footY = position.y + 30;

      final dx = game.ball.position.x - footX;
      final dy = game.ball.position.y - footY;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist < 65) {
        double power = hasSuperKick ? 1.5 : 1.0;
        game.ball.velocity.x = dir * 850 * power;
        game.ball.velocity.y = -500 * power;
        if (hasSuperKick) hasSuperKick = false;
        game.soundFX.playKick();
      }
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (game.state == GameState.characterSelect && !isBot) {
      final colors = [
        mat.Colors.redAccent.shade700,
        mat.Colors.amber.shade700,
        mat.Colors.blue.shade700,
        mat.Colors.purple.shade700,
      ];
      int currentIndex = colors.indexOf(game.p1Jersey);
      int nextIndex = (currentIndex + 1) % colors.length;
      game.p1Jersey = colors[nextIndex];
      jerseyColor = colors[nextIndex];
      game.soundFX.playJump();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state != GameState.playing) return;

    if (kickTimer > 0) kickTimer -= dt;

    if (isFrozen) {
      velocity.x = 0;
    } else {
      velocity.x = moveDir * speed;
    }

    velocity.y += gravity * dt;
    position += velocity * dt;

    if (position.y + height / 2 >= game.groundY) {
      position.y = game.groundY - height / 2;
      velocity.y = 0;
      isOnGround = true;
    }

    if (position.x - width / 2 < 0) {
      position.x = width / 2;
    } else if (position.x + width / 2 > game.size.x) {
      position.x = game.size.x - width / 2;
    }
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;

    if (isFrozen) {
      canvas.saveLayer(size.toRect(), Paint()..colorFilter = const ColorFilter.mode(mat.Colors.cyan, BlendMode.srcATop));
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(14, 52, w - 28, 24), const Radius.circular(6)),
      Paint()..color = jerseyColor,
    );

    double headScale = isMegaHead ? 1.35 : 1.0;
    canvas.save();
    canvas.translate(w / 2, 34);
    canvas.scale(headScale, headScale);
    canvas.translate(-w / 2, -34);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(4, 2, w - 8, 48), const Radius.circular(22)),
      Paint()..color = const Color(0xFFFFCC99),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(4, 0, w - 8, 16), const Radius.circular(12)),
      Paint()..color = hairColor,
    );

    final eyeX = facingRight ? w - 18 : 14.0;
    canvas.drawCircle(Offset(eyeX, 22), 6.0, Paint()..color = mat.Colors.white);
    canvas.drawCircle(Offset(eyeX + (facingRight ? 2 : -2), 22), 2.8, Paint()..color = mat.Colors.black);

    canvas.restore();

    canvas.save();
    canvas.translate(w / 2, h - 12);
    if (kickTimer > 0) {
      final progress = sin((kickTimer / kickDuration) * pi);
      canvas.rotate((facingRight ? -1.1 : 1.1) * progress);
    }
    final bootOffsetX = facingRight ? -4.0 : -22.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bootOffsetX, 0, 26, 12), const Radius.circular(5)),
      Paint()..color = mat.Colors.black87,
    );
    canvas.drawRect(Rect.fromLTWH(bootOffsetX + 6, 2, 12, 3), Paint()..color = mat.Colors.white);
    canvas.restore();

    if (isFrozen) {
      canvas.restore();
    }
  }
}

// --- UEFA TARZI YILDIZ TOP ---

class Ball extends PositionComponent with HasGameReference<KafaTopuGame> {
  final double radius = 20;
  Vector2 velocity = Vector2.zero();
  double rotationAngle = 0;
  final double gravity = 1150;
  final List<Vector2> trail = [];

  Ball() : super(size: Vector2.all(40), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    if (game.state != GameState.playing) return;

    if (velocity.length > 480) {
      trail.add(position.clone());
      if (trail.length > 8) trail.removeAt(0);
    } else if (trail.isNotEmpty) {
      trail.removeAt(0);
    }

    velocity.y += gravity * dt;
    velocity.x *= 0.994;
    position += velocity * dt;
    rotationAngle += (velocity.x * dt) / radius;

    if (position.y + radius >= game.groundY) {
      position.y = game.groundY - radius;
      velocity.y = -velocity.y * 0.78;
      if (velocity.y.abs() < 30) velocity.y = 0;
    }

    if (position.y - radius <= 0) {
      position.y = radius;
      velocity.y = -velocity.y * 0.8;
    }

    if (position.x - radius <= 0) {
      position.x = radius;
      velocity.x = -velocity.x * 0.8;
    } else if (position.x + radius >= game.size.x) {
      position.x = game.size.x - radius;
      velocity.x = -velocity.x * 0.8;
    }
  }

  @override
  void render(Canvas canvas) {
    for (int i = 0; i < trail.length; i++) {
      final offset = trail[i] - position + Vector2.all(radius);
      final alpha = (i + 1) / trail.length * 0.35;
      canvas.drawCircle(
        Offset(offset.x, offset.y),
        radius * ((i + 1) / trail.length) * 0.85,
        Paint()..color = mat.Colors.amberAccent.withValues(alpha: alpha),
      );
    }

    canvas.save();
    canvas.translate(radius, radius);
    canvas.rotate(rotationAngle);

    canvas.drawCircle(Offset.zero, radius, Paint()..color = mat.Colors.white);

    final starPaint = Paint()..color = const Color(0xFF1565C0);
    for (int i = 0; i < 5; i++) {
      final angle = (i * 2 * pi) / 5;
      final path = Path();
      for (int s = 0; s < 5; s++) {
        final starA = angle + (s * 2 * pi) / 5;
        final r = s.isEven ? 9.0 : 4.0;
        final px = cos(starA) * r;
        final py = sin(starA) * r;
        if (s == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(path, starPaint);
    }

    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..color = mat.Colors.black.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.restore();
  }
}

// --- SÜPER GÜÇ KUTUSU ---

class PowerUpBox extends PositionComponent with HasGameReference<KafaTopuGame> {
  double floatTimer = 0;

  PowerUpBox({required Vector2 position}) : super(position: position, size: Vector2.all(36), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    floatTimer += dt * 5;
    position.y += sin(floatTimer) * 0.4;
  }

  @override
  void render(Canvas canvas) {
    final rect = RRect.fromRectAndRadius(size.toRect(), const Radius.circular(8));
    canvas.drawRRect(rect, Paint()..color = mat.Colors.purpleAccent);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = mat.Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '?',
        style: TextStyle(color: mat.Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, (height - textPainter.height) / 2),
    );
  }
}