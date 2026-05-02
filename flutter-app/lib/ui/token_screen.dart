import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/auth_provider.dart';

// Android / Windows / Linux / macOS — на Telegram-бот с подпиской
const _subscribeUrl =
    'https://t.me/StocksiUltimate_bot?start=r61558uapp';

// iOS — только информационный сайт (Apple не пустит ссылку с упоминанием
// подписки/покупки в обход In-App Purchase)
const _infoUrl = 'https://stocksi-ultimate.ru';

class TokenScreen extends ConsumerStatefulWidget {
  const TokenScreen({super.key});

  @override
  ConsumerState<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends ConsumerState<TokenScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  late final AnimationController _shakeCtrl;
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _shakeCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.stage == AuthStage.error) {
        _shakeCtrl.forward(from: 0);
      }
    });

    final stage = auth.stage;
    final isSuccess = stage == AuthStage.success;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F1820),
              Color(0xFF1A2733),
              Color(0xFF131E28),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.05),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: isSuccess
                    ? _SuccessCard(
                        key: const ValueKey('success'),
                        onContinue: () =>
                            ref.read(authProvider.notifier).goToNewsList(),
                      )
                    : _EntryCard(
                        key: const ValueKey('entry'),
                        controller: _controller,
                        stage: stage,
                        errorMessage: auth.errorMessage,
                        shakeCtrl: _shakeCtrl,
                        glowCtrl: _glowCtrl,
                        onApply: () {
                          ref.read(authProvider.notifier).applyToken(
                                _controller.text,
                              );
                        },
                        onTextChanged: () {
                          ref.read(authProvider.notifier).resetError();
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final TextEditingController controller;
  final AuthStage stage;
  final String? errorMessage;
  final AnimationController shakeCtrl;
  final AnimationController glowCtrl;
  final VoidCallback onApply;
  final VoidCallback onTextChanged;

  const _EntryCard({
    super.key,
    required this.controller,
    required this.stage,
    required this.errorMessage,
    required this.shakeCtrl,
    required this.glowCtrl,
    required this.onApply,
    required this.onTextChanged,
  });

  @override
  Widget build(BuildContext context) {
    final applying = stage == AuthStage.applying;
    return AnimatedBuilder(
      animation: shakeCtrl,
      builder: (context, child) {
        final t = shakeCtrl.value;
        // затухающий синус для эффекта «дрожание»
        final dx = t == 0 ? 0.0 : (1 - t) * 10 * math.sin(t * 8 * math.pi);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedBuilder(
            animation: glowCtrl,
            builder: (_, __) => Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Белое пульсирующее свечение за логотипом
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white
                                .withOpacity(0.25 + glowCtrl.value * 0.25),
                            blurRadius: 32 + glowCtrl.value * 20,
                            spreadRadius: 4,
                          ),
                          BoxShadow(
                            color: Colors.white
                                .withOpacity(0.1 + glowCtrl.value * 0.15),
                            blurRadius: 48 + glowCtrl.value * 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    // Логотип Ultimate
                    SvgPicture.asset(
                      'assets/logo_u.svg',
                      width: 96,
                      height: 96,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Добро пожаловать',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Введите токен Ultimate для подключения к ленте новостей',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.65),
                ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: controller,
            enabled: !applying,
            onChanged: (_) => onTextChanged(),
            onSubmitted: (_) => onApply(),
            autofocus: true,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              letterSpacing: 0.4,
            ),
            decoration: InputDecoration(
              hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.35),
                fontFamily: 'monospace',
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: errorMessage != null
                      ? Colors.red.shade300
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF4C9EFF),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: errorMessage != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      errorMessage!,
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 13,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 20),
          _ApplyButton(
            applying: applying,
            onPressed: applying ? null : onApply,
          ),
          const SizedBox(height: 20),
          const _SubscribeLink(),
        ],
      ),
    );
  }
}

class _SubscribeLink extends StatelessWidget {
  const _SubscribeLink();

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context)
        .colorScheme
        .onSurface
        .withOpacity(0.55);
    final linkStyle = const TextStyle(
      color: Color(0xFF679CF6),
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFF679CF6),
    );

    final isIos = !kIsWeb && Platform.isIOS;

    if (isIos) {
      // Нейтральная формулировка, ведём на информационный сайт
      return Center(
        child: Text.rich(
          TextSpan(
            text: 'Информация о сервисе',
            style: linkStyle.copyWith(fontSize: 13),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                await launchUrl(
                  Uri.parse(_infoUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
          ),
        ),
      );
    }

    // Android / Windows / Linux / macOS — прямая ссылка на подписку
    return Center(
      child: Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 13, color: subtle),
          children: [
            const TextSpan(text: 'Нет подписки? '),
            TextSpan(
              text: 'Подписаться',
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () async {
                  await launchUrl(
                    Uri.parse(_subscribeUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────

class _ApplyButton extends StatelessWidget {
  final bool applying;
  final VoidCallback? onPressed;
  const _ApplyButton({required this.applying, required this.onPressed});

  static const _gradient = LinearGradient(
    colors: [Color(0xFF4C9EFF), Color(0xFF7A5CFA)],
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: applying
            ? Center(
                key: const ValueKey('loading'),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _gradient,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4C9EFF).withOpacity(0.35),
                        blurRadius: 16,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
              )
            : Container(
                key: const ValueKey('button'),
                decoration: BoxDecoration(
                  gradient: _gradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4C9EFF).withOpacity(0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onPressed,
                    child: const Center(
                      child: Text(
                        'Применить',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────

class _SuccessCard extends StatefulWidget {
  final VoidCallback onContinue;
  const _SuccessCard({super.key, required this.onContinue});

  @override
  State<_SuccessCard> createState() => _SuccessCardState();
}

class _SuccessCardState extends State<_SuccessCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final circleT = Curves.elasticOut.transform(
              _ctrl.value.clamp(0, 1),
            );
            final checkT = ((_ctrl.value - 0.3) / 0.5).clamp(0.0, 1.0);
            return SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: circleT,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2EA44F).withOpacity(0.15),
                        border: Border.all(
                          color: const Color(0xFF2EA44F),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2EA44F).withOpacity(0.4),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: const Size(60, 60),
                    painter: _CheckmarkPainter(progress: checkT),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        Text(
          'Токен сохранён',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Всё готово — можно переходить к ленте новостей',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.65),
              ),
        ),
        const SizedBox(height: 32),
        _ContinueButton(onPressed: widget.onContinue),
      ],
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  final double progress;
  _CheckmarkPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = const Color(0xFF2EA44F)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    final p1 = Offset(w * 0.22, h * 0.52);
    final p2 = Offset(w * 0.44, h * 0.72);
    final p3 = Offset(w * 0.80, h * 0.32);

    final path = Path()..moveTo(p1.dx, p1.dy);
    if (progress <= 0.5) {
      final t = progress * 2;
      path.lineTo(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final t = (progress - 0.5) * 2;
      path.lineTo(p2.dx + (p3.dx - p2.dx) * t, p2.dy + (p3.dy - p2.dy) * t);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter old) =>
      old.progress != progress;
}

class _ContinueButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _ContinueButton({required this.onPressed});

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2EA44F)
                  .withOpacity(0.25 + _pulse.value * 0.25),
              blurRadius: 20 + _pulse.value * 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Material(
          color: const Color(0xFF2EA44F),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Перейти к ленте',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
