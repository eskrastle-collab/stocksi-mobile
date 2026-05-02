import 'package:flutter/material.dart';

/// Компактный тумблер 34×18, как в расширении Stocksi Ultimate.
/// Чёрно-серый off → синий on, белая круглая шашечка.
class CompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    final scheme = Theme.of(context).colorScheme;
    final activeColor = scheme.primary;
    // Контрастно относительно фона: полупрозрачный onSurface работает
    // в обеих темах (светлеет на dark, темнеет на light).
    final inactiveColor = scheme.onSurface.withOpacity(0.2);
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: disabled ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 34,
          height: 18,
          decoration: BoxDecoration(
            color: value ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
