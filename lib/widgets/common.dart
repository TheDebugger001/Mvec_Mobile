import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/icons.dart';
import '../core/theme.dart';
import 'motion.dart';
import 'theme_switch.dart';

/// "Ikiguzi" brush-script wordmark, as on the Landing page design.
class MvLogo extends StatelessWidget {
  const MvLogo({super.key, this.size = 26, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Ikiguzi',
      maxLines: 1,
      softWrap: false,
      style: GoogleFonts.kaushanScript(
        fontSize: size * 1.05,
        fontWeight: FontWeight.w400,
        color: color ?? context.mv.accentDeep,
        height: 1.1,
      ),
    );
  }
}

/// Network image with the MVEC placeholder when missing or failing.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.src, this.fit = BoxFit.cover, this.radius = 0, this.size});
  final String? src;
  final BoxFit fit;
  final double radius;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final url = resolveImageUrl(src);
    Widget placeholder() => Container(
          width: size,
          height: size,
          color: mv.soft,
          alignment: Alignment.center,
          child: Icon(Icons.image_outlined, color: mv.textMuted.withValues(alpha: .6), size: 30),
        );
    final child = url.isEmpty
        ? placeholder()
        : CachedNetworkImage(
            imageUrl: url,
            fit: fit,
            width: size,
            height: size,
            // Shimmer while loading, then a short fade so images never pop in.
            fadeInDuration: Motion.reduced(context) ? Duration.zero : const Duration(milliseconds: 260),
            fadeOutDuration: const Duration(milliseconds: 120),
            fadeInCurve: Motion.out,
            placeholder: (_, __) => Skeleton(width: size, height: size, radius: 0),
            errorWidget: (_, __, ___) => placeholder(),
          );
    return radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child) : child;
  }
}

/// Round avatar: photo or first letter.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.radius = 18});
  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final u = resolveImageUrl(url);
    return CircleAvatar(
      radius: radius,
      backgroundColor: MvColors.brand,
      foregroundImage: u.isEmpty ? null : CachedNetworkImageProvider(u),
      child: Text(
        name.trim().isEmpty ? 'M' : name.trim()[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * .9),
      ),
    );
  }
}

// ─── Buttons ─────────────────────────────────────────────────────────────────

/// Brand-teal call to action (`.gradient-btn`).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.success = false,
    this.expand = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  /// Briefly shows a check after the action is confirmed (e.g. added to cart).
  final bool success;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final row = Row(
      key: ValueKey(success ? 'ok' : loading ? 'busy' : 'idle'),
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        else if (success)
          const Icon(Icons.check_rounded, size: 19, color: Colors.white)
        else if (icon != null)
          Icon(icon, size: 18, color: Colors.white),
        if (loading || success || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12.5 : 13.5,
            ),
          ),
        ),
      ],
    );
    final child = AnimatedSwitcher(
      duration: Motion.reduced(context) ? Duration.zero : Motion.quick,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: .85, end: 1).animate(a), child: c)),
      child: row,
    );
    final button = Opacity(
      opacity: enabled ? 1 : .55,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: context.isDarkMode ? MvColors.gradientDark : MvColors.gradient,
            borderRadius: BorderRadius.circular(MvRadius.button),
            boxShadow: const [BoxShadow(color: Color(0x2E064F65), blurRadius: 14, offset: Offset(0, 6))],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(MvRadius.button),
            onTap: enabled ? onPressed : null,
            child: Container(
              constraints: BoxConstraints(minHeight: compact ? 40 : 48),
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20, vertical: compact ? 8 : 12),
              child: child,
            ),
          ),
        ),
      ),
    );
    return Semantics(container: true, button: true, enabled: enabled, child: Pressable(enabled: enabled, child: button));
  }
}

/// Outlined secondary action (`.outline-btn`).
class OutlineBtn extends StatelessWidget {
  const OutlineBtn({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
    this.compact = false,
    this.danger = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final bool compact;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    final color = danger ? MvColors.dangerBtn : mv.accentDeep;
    final enabled = onPressed != null && !loading;
    final button = Opacity(
      opacity: enabled ? 1 : .55,
      child: Material(
        color: mv.surface,
        borderRadius: BorderRadius.circular(MvRadius.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(MvRadius.button),
          onTap: enabled ? onPressed : null,
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 40 : 48),
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 18, vertical: compact ? 8 : 12),
            decoration: BoxDecoration(
              border: Border.all(color: danger ? color : (context.isDarkMode ? const Color(0xFF396273) : const Color(0xFFB5D2DB))),
              borderRadius: BorderRadius.circular(MvRadius.button),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                else if (icon != null)
                  Icon(icon, size: 18, color: color),
                if (loading || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: compact ? 12.5 : 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(container: true, button: true, enabled: enabled, child: Pressable(enabled: enabled, child: button));
  }
}

/// Solid dark/danger button (`.buy-btn`, `.danger-btn`).
class SolidButton extends StatelessWidget {
  const SolidButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
    this.icon,
    this.expand = false,
    this.compact = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final IconData? icon;
  final bool expand;
  final bool compact;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final button = Opacity(
      opacity: enabled ? 1 : .55,
      child: Material(
        color: color ?? const Color(0xFF172B34),
        borderRadius: BorderRadius.circular(MvRadius.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(MvRadius.button),
          onTap: enabled ? onPressed : null,
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 40 : 48),
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 18, vertical: compact ? 8 : 12),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else if (icon != null)
                  Icon(icon, size: 18, color: Colors.white),
                if (loading || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: compact ? 12.5 : 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(container: true, button: true, enabled: enabled, child: Pressable(enabled: enabled, child: button));
  }
}

/// White button for use on a brand-teal panel (the cart and checkout totals).
class OnBrandButton extends StatelessWidget {
  const OnBrandButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      child: Pressable(
        enabled: enabled,
        child: Opacity(
        opacity: enabled ? 1 : .6,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MvRadius.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(MvRadius.button),
            onTap: enabled ? onPressed : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MvColors.brand))
                  else if (icon != null)
                    Icon(icon, size: 18, color: MvColors.brand),
                  if (loading || icon != null) const SizedBox(width: 8),
                  Flexible(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MvColors.brand, fontWeight: FontWeight.w800, fontSize: 14.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ─── Cards, headings, states ─────────────────────────────────────────────────

/// White bordered panel (`.data-card`).
class DataCard extends StatelessWidget {
  const DataCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 14),
      padding: padding,
      width: double.infinity,
      decoration: BoxDecoration(
        color: mv.surface,
        borderRadius: BorderRadius.circular(MvRadius.card),
        border: Border.all(color: mv.border),
        boxShadow: context.mvCardShadow,
      ),
      child: child,
    );
  }
}

/// Eyebrow + title + subtitle at the top of a page (`.page-title`).
class PageTitle extends StatelessWidget {
  const PageTitle({super.key, this.eyebrow, required this.title, this.subtitle, this.trailing});
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Text(eyebrow!.toUpperCase(), style: context.mvEyebrow.copyWith(fontSize: 11, letterSpacing: 1.6)),
                if (eyebrow != null) const SizedBox(height: 4),
                Text(title, style: context.mvH1.copyWith(fontSize: 20)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: TextStyle(color: mv.textMuted, fontSize: 13, height: 1.4)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Section header with an optional "View all" link (`.section-heading`).
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.eyebrow, this.actionLabel, this.onAction});
  final String title;
  final String? eyebrow;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) Text(eyebrow!, style: context.mvEyebrow.copyWith(fontSize: 10.5, letterSpacing: 1.6)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: mv.text)),
              ],
            ),
          ),
          if (actionLabel != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(actionLabel!.replaceAll(RegExp(r'\s*→\s*$'), ''), style: TextStyle(color: mv.accentDeep, fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 16, color: mv.accentDeep),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inbox_outlined, this.action});
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: mv.soft, shape: BoxShape.circle),
              child: Icon(icon, color: mv.accentDeep, size: 28),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: mv.text)),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(color: mv.textMuted, fontSize: 13, height: 1.4)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: context.mv.accent)),
            if (label != null) ...[
              const SizedBox(height: 12),
              Text(label!, style: TextStyle(color: context.mv.textMuted, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry, this.title = "Couldn't load this page"});
  final Object error;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: title,
      message: errorText(error),
      action: onRetry == null ? null : OutlineBtn(label: 'Try again', icon: Icons.refresh_rounded, onPressed: onRetry),
    );
  }
}

/// Renders an [AsyncValue] with the app's loading / error / data states.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.data, this.onRetry, this.loadingLabel, this.skipLoadingOnRefresh = true});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final String? loadingLabel;
  final bool skipLoadingOnRefresh;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: skipLoadingOnRefresh,
      data: data,
      loading: () => LoadingState(label: loadingLabel),
      error: (e, _) => ErrorState(error: e, onRetry: onRetry),
    );
  }
}

/// Inline success / error banner (`.form-alert`).
class Notice extends StatelessWidget {
  const Notice({super.key, required this.text, this.ok = false, this.info = false, this.onClose, this.child});
  final String text;
  final bool ok;
  final bool info;
  final VoidCallback? onClose;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final Color bg, fg;
    final IconData icon;
    if (ok) {
      bg = dark ? const Color(0xFF0F2F25) : MvColors.successBg;
      fg = dark ? const Color(0xFF6EE0B4) : MvColors.successText;
      icon = Icons.check_circle_outline_rounded;
    } else if (info) {
      bg = dark ? const Color(0xFF123C4C) : MvColors.infoBoxBg;
      fg = dark ? MvColors.accentLight : MvColors.infoBoxText;
      icon = Icons.info_outline_rounded;
    } else {
      bg = dark ? const Color(0xFF3A1414) : MvColors.errorBg;
      fg = dark ? const Color(0xFFFF9D90) : MvColors.errorText;
      icon = Icons.error_outline_rounded;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: fg)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600, height: 1.35)),
                if (child != null) child!,
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, size: 18, color: fg),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}

/// Soft informational box (`.verified-box`).
class InfoBox extends StatelessWidget {
  const InfoBox({super.key, required this.title, required this.text, this.child});
  final String title;
  final String text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(
        color: dark ? MvColors.darkSoft : MvColors.infoBoxBg,
        border: Border.all(color: dark ? const Color(0xFF28505F) : MvColors.infoBoxBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: context.mv.text, fontSize: 14)),
          const SizedBox(height: 4),
          Text(text, style: TextStyle(color: dark ? MvColors.darkMuted : MvColors.infoBoxText, fontSize: 12.5, height: 1.4)),
          if (child != null) ...[const SizedBox(height: 10), child!],
        ],
      ),
    );
  }
}

/// Coloured status pill (`.status`).
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = StatusTone.neutral});
  final String label;
  final StatusTone tone;

  /// Picks a tone from common backend status words.
  factory StatusChip.of(String status, {String? label}) {
    final s = status.toUpperCase();
    const good = {'ACTIVE', 'VERIFIED', 'SUCCESS', 'RELEASED', 'PAID', 'RECEIVED', 'DELIVERED', 'COMPLETED', 'APPROVED', 'RESOLVED', 'TRUSTED', 'LIVE', 'ON'};
    const bad = {'REJECTED', 'FAILED', 'SUSPENDED', 'BLOCKED', 'BLOCK', 'CANCELLED', 'HIGH', 'AT RISK', 'OFF', 'REFUNDED', 'EXPIRED'};
    const warn = {'PENDING', 'PROCESSING', 'WAITING', 'IN_PROGRESS', 'OPEN', 'MEDIUM', 'WATCH', 'UNVERIFIED', 'PAUSED', 'DRAFT', 'OUT_OF_STOCK', 'SHIPPED', 'OUT_FOR_DELIVERY', 'CONFIRMED', 'UNDER_REVIEW', 'INVESTIGATE'};
    final tone = good.contains(s) ? StatusTone.good : bad.contains(s) ? StatusTone.bad : warn.contains(s) ? StatusTone.warn : StatusTone.neutral;
    return StatusChip(label ?? statusLabel(status), tone: tone);
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final (bg, fg) = switch (tone) {
      StatusTone.good => (dark ? const Color(0xFF0F2F25) : MvColors.successBg, dark ? const Color(0xFF6EE0B4) : MvColors.successText),
      StatusTone.warn => (dark ? const Color(0xFF332712) : MvColors.warningBg, dark ? const Color(0xFFFFC66B) : MvColors.warningText),
      StatusTone.bad => (dark ? const Color(0xFF3A1414) : MvColors.errorBg, dark ? const Color(0xFFFF9D90) : MvColors.errorText),
      StatusTone.neutral => (dark ? MvColors.darkSurface2 : MvColors.neutralBg, dark ? MvColors.darkMuted : MvColors.neutralText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}

enum StatusTone { good, warn, bad, neutral }

/// KPI tile (`.metric`).
class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, this.sub, this.icon = 'chart'});
  final String label;
  final String value;
  final String? sub;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: mv.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: mv.border)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: context.isDarkMode ? MvColors.darkSoft : MvColors.metricIconBg, borderRadius: BorderRadius.circular(9)),
            child: Icon(mvIcon(icon), color: mv.accentDeep, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: mv.textMuted)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedValueText(value, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: mv.text)),
                ),
                if (sub != null) Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: mv.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-column grid of [MetricCard]s that collapses to one column on very
/// narrow phones.
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 330 ? 1 : 2;
      if (cols == 1) {
        return Column(children: [for (final m in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: m)]);
      }
      // Tiles in the same row share the taller one's height, so rows line up.
      return Column(
        children: [
          for (var i = 0; i < children.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: i + 2 < children.length ? 10 : 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: children[i]),
                    const SizedBox(width: 10),
                    Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// A label/value line used in summaries (`.summary-lines`).
class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: bold ? mv.text : mv.textMuted, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontSize: bold ? 15 : 13))),
          const SizedBox(width: 8),
          Flexible(
            child: AnimatedValueText(value,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w700, color: valueColor ?? mv.text, fontSize: bold ? 17 : 13.5, )),
          ),
        ],
      ),
    );
  }
}

/// − 1 + stepper (`.qty`): a soft pill with round buttons.
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 100, this.busy = false});
  final int value;
  final int min;
  final int max;
  final bool busy;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final mv = context.mv;
    Widget btn(IconData icon, bool enabled, VoidCallback tap, String label) => Semantics(
          button: true,
          label: label,
          child: InkResponse(
            radius: 22,
            onTap: enabled && !busy ? tap : null,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon, size: 18, color: enabled && !busy ? mv.accentDeep : mv.textMuted.withValues(alpha: .45)),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: mv.surfaceMuted, borderRadius: BorderRadius.circular(999), border: Border.all(color: mv.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove_rounded, value > min, () => onChanged(value - 1), 'Decrease quantity'),
          SizedBox(width: 28, child: Center(child: AnimatedValueText('$value', style: TextStyle(fontWeight: FontWeight.w800, color: mv.text, fontSize: 14)))),
          btn(Icons.add_rounded, value < max, () => onChanged(value + 1), 'Increase quantity'),
        ],
      ),
    );
  }
}

/// Page / total pager (`Pagination.jsx`).
class PaginationBar extends StatelessWidget {
  const PaginationBar({super.key, required this.page, required this.total, required this.perPage, required this.onPage});
  final int page;
  final int total;
  final int perPage;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = (total / perPage).ceil();
    if (pages <= 1) return const SizedBox.shrink();
    final mv = context.mv;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous page',
          ),
          Text('Page $page of $pages', style: TextStyle(fontWeight: FontWeight.w700, color: mv.text, fontSize: 13)),
          IconButton(
            onPressed: page < pages ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

/// Dark mode switch for the dashboard top bars: the same sun/moon switch as
/// the storefront, so it looks the same everywhere.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) => const ThemeSwitch();
}

/// Shows a floating message at the bottom of the screen.
void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Row(
      children: [
        Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded, size: 20, color: error ? Colors.white : const Color(0xFF6EE0B4)),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
    backgroundColor: error ? MvColors.errorText : null,
    duration: const Duration(seconds: 3),
  ));
}

/// Asks "are you sure?" before a destructive action.
Future<bool> confirmDialog(BuildContext context, String message, {String confirm = 'Confirm', String title = 'Are you sure?', bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm, style: TextStyle(color: danger ? MvColors.errorText : ctx.mv.accentDeep, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Asks for a short piece of text (reasons, notes). Null when cancelled.
Future<String?> promptDialog(BuildContext context, String title, {String? hint, String confirm = 'Send', bool required = true, int lines = 3}) async {
  final controller = TextEditingController();
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, maxLines: lines, minLines: 1, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final t = controller.text.trim();
            if (required && t.isEmpty) return;
            Navigator.pop(ctx, t);
          },
          child: Text(confirm, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return res;
}
