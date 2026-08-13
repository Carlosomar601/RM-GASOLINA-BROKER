import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Botón principal (verde) y variantes.
class OButton extends StatelessWidget {
  const OButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = OButtonVariant.primary,
    this.icon,
    this.trailing,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onTap;
  final OButtonVariant variant;
  final IconData? icon;
  final String? trailing;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final (bg, fg, border) = switch (variant) {
      OButtonVariant.primary => (C.green, const Color(0xFF0C130F), null),
      OButtonVariant.amber => (C.amber, const Color(0xFF1B1204), null),
      OButtonVariant.ghost => (Colors.transparent, C.bone, C.line),
      OButtonVariant.danger => (Colors.transparent, C.red, C.red),
    };
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        borderRadius: Radii.pill,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.pill,
          child: Container(
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: Radii.pill,
              border: border == null ? null : Border.all(color: border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  Gap.w8,
                ],
                Text(label,
                    style: display(size: 15, weight: FontWeight.w600, color: fg, letterSpacing: -0.1)),
                if (trailing != null) ...[
                  Gap.w8,
                  Text(trailing!, style: mono(size: 12, color: fg.withOpacity(0.7))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum OButtonVariant { primary, amber, ghost, danger }

/// Tarjeta base oscura.
class OCard extends StatelessWidget {
  const OCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = C.surface,
    this.borderColor = C.line,
    this.onTap,
    this.accent,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: Radii.card,
        border: Border.all(color: accent ?? borderColor, width: accent != null ? 1.4 : 1),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: Radii.card,
      child: InkWell(onTap: onTap, borderRadius: Radii.card, child: card),
    );
  }
}

/// Etiqueta mono en mayúsculas (usada arriba de cada bloque).
class OLabel extends StatelessWidget {
  const OLabel(this.text, {super.key, this.color = C.mutedDim});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: mono(size: 10, color: color, letterSpacing: 1.4),
      );
}

class OPill extends StatelessWidget {
  const OPill(this.text, {super.key, this.color = C.green, this.filled = false});
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.12),
          borderRadius: Radii.pill,
          border: filled ? null : Border.all(color: color.withOpacity(0.45)),
        ),
        child: Text(
          text,
          style: mono(
            size: 10,
            color: filled ? const Color(0xFF0C130F) : color,
            letterSpacing: 0.8,
          ),
        ),
      );
}

/// Cifra grande en mono, para dinero y litros.
class OMoney extends StatelessWidget {
  const OMoney(this.value, {super.key, this.size = 34, this.color = C.bone, this.prefix = r'$'});
  final double value;
  final double size;
  final Color color;
  final String prefix;

  @override
  Widget build(BuildContext context) => Text(
        '$prefix${value.toStringAsFixed(2)}',
        style: mono(size: size, weight: FontWeight.w600, color: color, letterSpacing: -1),
      );
}

/// Campo de texto del sistema.
class OField extends StatelessWidget {
  const OField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.obscure = false,
    this.keyboard,
    this.suffix,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscure;
  final TextInputType? keyboard;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OLabel(label),
          Gap.h8,
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboard,
            style: body(size: 15, weight: FontWeight.w500),
            cursorColor: C.green,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: body(size: 15, color: C.mutedDim),
              filled: true,
              fillColor: C.surface,
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              enabledBorder: const OutlineInputBorder(
                borderRadius: Radii.field,
                borderSide: BorderSide(color: C.line),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: Radii.field,
                borderSide: BorderSide(color: C.green, width: 1.4),
              ),
            ),
          ),
        ],
      );
}

/// Encabezado de pantalla con back y acción opcional.
class OHeader extends StatelessWidget {
  const OHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.action,
    this.step,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? action;
  final String? step;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onBack != null)
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 2),
                child: InkWell(
                  onTap: onBack,
                  borderRadius: Radii.pill,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: Radii.pill,
                      border: Border.all(color: C.line),
                    ),
                    child: const Icon(Icons.arrow_back, size: 18, color: C.bone),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step != null) ...[OLabel(step!), Gap.h4],
                  Text(title, style: display(size: 24)),
                  if (subtitle != null) ...[
                    Gap.h4,
                    Text(subtitle!, style: body(size: 13, color: C.mutedDim)),
                  ],
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      );
}

/// Fila etiqueta / valor para resúmenes.
class ORow extends StatelessWidget {
  const ORow(this.label, this.value, {super.key, this.valueColor = C.bone, this.strong = false});
  final String label;
  final String value;
  final Color valueColor;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: body(size: 14, color: strong ? C.bone : C.muted)),
            Text(
              value,
              style: mono(
                size: strong ? 16 : 13,
                weight: strong ? FontWeight.w600 : FontWeight.w500,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
}

/// Barra de progreso del flujo (autorización → llegada → surtido → recibo).
class OStepper extends StatelessWidget {
  const OStepper({super.key, required this.current, this.total = 4});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(total, (i) {
          final done = i <= current;
          return Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: done ? C.green : C.line,
                borderRadius: Radii.pill,
              ),
            ),
          );
        }),
      );
}

/// Marcador visual de producto (sin imágenes reales todavía).
class OThumb extends StatelessWidget {
  const OThumb({super.key, required this.seed, this.size = 46, this.tint = C.green});
  final String seed;
  final double size;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withOpacity(0.25)),
        ),
        child: Text(
          seed.isEmpty ? '?' : seed.substring(0, 1).toUpperCase(),
          style: display(size: size * 0.4, color: tint),
        ),
      );
}
