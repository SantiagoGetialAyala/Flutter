import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.light = false, this.compact = false});
  final bool light, compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 34 : 45,
        height: compact ? 34 : 45,
        decoration: BoxDecoration(
          color: light
              ? Colors.white.withValues(alpha: .12)
              : const Color(0xFFE8F0E7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.spa_rounded,
          size: compact ? 23 : 31,
          color: light ? const Color(0xFFD2E4B9) : AppTheme.forest,
        ),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'RiTech',
            style: TextStyle(
              fontSize: compact ? 23 : 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: light ? Colors.white : AppTheme.forest,
            ),
          ),
          if (!compact)
            Text(
              'Exportación inteligente',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: .3,
                color: light ? Colors.white70 : AppTheme.muted,
              ),
            ),
        ],
      ),
    ],
  );
}

class OriginImage extends StatelessWidget {
  const OriginImage({
    super.key,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.radius = 12,
  });
  final double? width, height;
  final Alignment alignment;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Image.asset(
      'assets/images/origin-hero.jpg',
      width: width,
      height: height,
      fit: BoxFit.cover,
      alignment: alignment,
      errorBuilder: (_, _, _) => Container(
        width: width,
        height: height,
        color: const Color(0xFFE6EEDD),
        child: const Icon(
          Icons.coffee_rounded,
          color: AppTheme.forest,
          size: 28,
        ),
      ),
    ),
  );
}
