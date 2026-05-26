import 'package:flutter/material.dart';
import 'ai_chat_design.dart';

enum AIChatComposerPlacement { center, bottom }

/// دستورات slash برای میانبر سریع
class SlashCommand {
  final String command;
  final String description;
  final String prompt;
  final IconData icon;

  const SlashCommand({
    required this.command,
    required this.description,
    required this.prompt,
    required this.icon,
  });
}

const kSlashCommands = [
  SlashCommand(
    command: '/گزارش',
    description: 'گزارش جامع مالی',
    prompt: 'یک گزارش جامع از وضعیت مالی کسب‌وکار شامل فروش، هزینه‌ها و سود تهیه کن.',
    icon: Icons.bar_chart_rounded,
  ),
  SlashCommand(
    command: '/فاکتور',
    description: 'جستجوی فاکتورها',
    prompt: 'فاکتورهای اخیر کسب‌وکار را نشان بده.',
    icon: Icons.receipt_long_outlined,
  ),
  SlashCommand(
    command: '/موجودی',
    description: 'وضعیت موجودی انبار',
    prompt: 'وضعیت موجودی انبار و کالاهای کم‌موجود را بررسی کن.',
    icon: Icons.inventory_2_outlined,
  ),
  SlashCommand(
    command: '/مشتریان',
    description: 'لیست مشتریان و بدهکاران',
    prompt: 'لیست مشتریان با بیشترین بدهی را نشان بده.',
    icon: Icons.people_outline_rounded,
  ),
  SlashCommand(
    command: '/dashboard',
    description: 'خلاصه داشبورد',
    prompt: 'خلاصه‌ای از وضعیت کلی کسب‌وکار امروز بده.',
    icon: Icons.dashboard_outlined,
  ),
  SlashCommand(
    command: '/مقایسه',
    description: 'مقایسه ماهانه',
    prompt: 'فروش و درآمد این ماه را با ماه گذشته مقایسه کن.',
    icon: Icons.compare_arrows_rounded,
  ),
  SlashCommand(
    command: '/هشدار',
    description: 'هشدارهای مالی',
    prompt: 'هشدارها و نکات مهم مالی کسب‌وکار را بررسی کن.',
    icon: Icons.warning_amber_rounded,
  ),
];

class AIChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final AIChatComposerPlacement placement;
  final bool sending;
  final bool disabled;
  final bool voiceStarting;
  final bool voiceActive;
  final bool voiceRecording;
  final VoidCallback onSend;
  final VoidCallback? onMic;
  final VoidCallback? onStopVoice;
  final VoidCallback? onStopGenerating;
  final VoidCallback? onAttach;

  const AIChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placement,
    required this.sending,
    required this.disabled,
    required this.voiceStarting,
    required this.voiceActive,
    required this.voiceRecording,
    required this.onSend,
    this.onMic,
    this.onStopVoice,
    this.onStopGenerating,
    this.onAttach,
  });

  @override
  State<AIChatComposer> createState() => _AIChatComposerState();
}

class _AIChatComposerState extends State<AIChatComposer> {
  bool _focused = false;
  bool _hasText = false;
  List<SlashCommand> _slashSuggestions = [];
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _slashOverlay;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onTextChanged);
    _hasText = widget.controller.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant AIChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    _removeSlashOverlay();
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onFocus() {
    final f = widget.focusNode.hasFocus;
    if (f != _focused) {
      setState(() => _focused = f);
      if (!f) _removeSlashOverlay();
    }
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final hasText = text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);

    // تشخیص slash command
    _updateSlashSuggestions(text);
  }

  void _updateSlashSuggestions(String text) {
    if (!text.startsWith('/') || text.contains(' ')) {
      if (_slashSuggestions.isNotEmpty || _slashOverlay != null) {
        setState(() => _slashSuggestions = []);
        _removeSlashOverlay();
      }
      return;
    }

    final query = text.toLowerCase();
    final matches = kSlashCommands
        .where((c) =>
            c.command.toLowerCase().startsWith(query) ||
            c.description.contains(query.replaceAll('/', '')))
        .toList();

    if (matches.isEmpty) {
      setState(() => _slashSuggestions = []);
      _removeSlashOverlay();
      return;
    }

    setState(() => _slashSuggestions = matches);
    _showSlashOverlay(matches);
  }

  void _showSlashOverlay(List<SlashCommand> commands) {
    _removeSlashOverlay();
    final overlay = Overlay.of(context);
    _slashOverlay = OverlayEntry(
      builder: (ctx) => Positioned(
        width: 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, -8),
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          child: _SlashCommandOverlay(
            commands: commands,
            onSelect: _selectSlashCommand,
          ),
        ),
      ),
    );
    overlay.insert(_slashOverlay!);
  }

  void _removeSlashOverlay() {
    _slashOverlay?.remove();
    _slashOverlay = null;
  }

  void _selectSlashCommand(SlashCommand cmd) {
    _removeSlashOverlay();
    setState(() => _slashSuggestions = []);
    widget.controller.text = cmd.prompt;
    widget.controller.selection = TextSelection.collapsed(
      offset: cmd.prompt.length,
    );
  }

  bool get _canSend => !widget.disabled && !widget.sending && _hasText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = AIChatDesign.isCompactWidth(context);
    final isCenter = widget.placement == AIChatComposerPlacement.center;

    return AnimatedContainer(
      duration: AIChatDesign.layoutTransition,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 24,
        isCenter ? 0 : 12,
        compact ? 16 : 24,
        isCenter ? 0 : MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AIChatDesign.contentMaxWidth,
          ),
          child: CompositedTransformTarget(
            link: _layerLink,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: AIChatDesign.composerDecoration(
              theme,
              focused: _focused,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Semantics(
                        textField: true,
                        label: 'متن پیام دستیار هوشمند',
                        child: TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          enabled: !widget.disabled,
                          minLines: 1,
                          maxLines: isCenter ? 4 : 6,
                          textInputAction: TextInputAction.send,
                          style: theme.textTheme.bodyLarge,
                          decoration: InputDecoration(
                            hintText: isCenter
                                ? 'هر سوالی دارید بپرسید...'
                                : 'پیام خود را بنویسید...',
                            hintStyle: TextStyle(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.65,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.fromLTRB(
                              compact ? 18 : 22,
                              compact ? 14 : 18,
                              8,
                              compact ? 14 : 18,
                            ),
                          ),
                          onSubmitted: (_) {
                            if (_canSend) widget.onSend();
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onStopGenerating != null)
                            IconButton(
                              tooltip: 'توقف تولید پاسخ',
                              onPressed: widget.onStopGenerating,
                              icon: Icon(
                                Icons.stop_circle_outlined,
                                color: scheme.error,
                              ),
                            ),
                          if (widget.onAttach != null)
                            IconButton(
                              tooltip: 'پیوست فایل به گفت‌وگو',
                              onPressed: widget.disabled || widget.sending
                                  ? null
                                  : widget.onAttach,
                              icon: Icon(
                                Icons.attach_file_rounded,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          if (widget.onMic != null)
                            IconButton(
                              tooltip: widget.voiceActive
                                  ? (widget.voiceRecording
                                        ? 'توقف ضبط صدا'
                                        : 'شروع ضبط صدا')
                                  : 'شروع مکالمه صوتی',
                              onPressed: widget.disabled || widget.voiceStarting
                                  ? null
                                  : widget.onMic,
                              icon: widget.voiceStarting
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.primary,
                                      ),
                                    )
                                  : Icon(
                                      widget.voiceActive
                                          ? (widget.voiceRecording
                                                ? Icons.mic_off_rounded
                                                : Icons.mic_none_rounded)
                                          : Icons.mic_none_rounded,
                                      color: widget.voiceActive
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                            ),
                          if (widget.voiceActive && widget.onStopVoice != null)
                            IconButton(
                              tooltip: 'پایان مکالمه صوتی',
                              onPressed: widget.voiceStarting
                                  ? null
                                  : widget.onStopVoice,
                              icon: Icon(
                                Icons.call_end_rounded,
                                color: scheme.error,
                              ),
                            ),
                          _SendButton(
                            sending: widget.sending,
                            enabled: _canSend,
                            onPressed: _canSend ? widget.onSend : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_focused && !compact)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.onStopGenerating != null
                                ? 'در حال تولید پاسخ هستم؛ هر زمان خواستید می‌توانید توقف بزنید.'
                                : 'برای عملیات ثبت یا ویرایش، قبل از اجرا از شما تأیید جداگانه گرفته می‌شود.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.72,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          ),   // CompositedTransformTarget
        ),
      ),
    );
  }
}

/// Overlay پیشنهادهای slash command
class _SlashCommandOverlay extends StatelessWidget {
  final List<SlashCommand> commands;
  final ValueChanged<SlashCommand> onSelect;

  const _SlashCommandOverlay({
    required this.commands,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: isDark ? scheme.surfaceContainerHigh : scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.flash_on_rounded,
                      size: 14, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    'دستورات سریع',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 8, endIndent: 8),
            ...commands.map(
              (cmd) => _SlashCommandTile(
                command: cmd,
                onTap: () => onSelect(cmd),
                theme: theme,
                scheme: scheme,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _SlashCommandTile extends StatelessWidget {
  final SlashCommand command;
  final VoidCallback onTap;
  final ThemeData theme;
  final ColorScheme scheme;

  const _SlashCommandTile({
    required this.command,
    required this.onTap,
    required this.theme,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(command.icon, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    command.command,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    command.description,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool sending;
  final bool enabled;
  final VoidCallback? onPressed;

  const _SendButton({
    required this.sending,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      enabled: enabled,
      label: sending ? 'در حال ارسال پیام' : 'ارسال پیام',
      child: Tooltip(
        message: enabled ? 'ارسال پیام' : 'ابتدا پیام را بنویسید',
        child: Material(
          color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: sending
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      size: 22,
                      color: enabled
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
