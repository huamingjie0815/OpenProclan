import 'package:flutter/material.dart';

import 'account_api.dart';
import 'l10n/app_localizations.dart';
import 'red.dart';

enum _Mode { login, register }

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.client,
    required this.onSignedIn,
    this.onLocale,
  });

  final AccountClient client;
  final ValueChanged<String> onSignedIn;
  final ValueChanged<String>? onLocale;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _password = TextEditingController();
  final _username = TextEditingController();

  var _mode = _Mode.login;
  var _busy = false;
  var _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  void _switch(_Mode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final l = AppLocalizations.of(context);
    final username = _username.text.trim();
    final password = _password.text;
    final problem = _validate(l, username, password);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _Mode.login:
          final token = await widget.client.login(
            username: username,
            password: password,
          );
          if (!mounted) {
            return;
          }
          widget.onSignedIn(token);
        case _Mode.register:
          final token = await widget.client.register(
            username: username,
            password: password,
          );
          if (!mounted) {
            return;
          }
          widget.onSignedIn(token);
      }
    } on AccountException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = accountMessage(l, error));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = l.offline);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String? _validate(AppLocalizations l, String username, String password) {
    if (username.isEmpty ||
        username.length > 32 ||
        username.contains('\n') ||
        username.contains('\r')) {
      return l.invalidUsername;
    }
    if (password.length < 8 || password.length > 128) {
      return l.invalidPassword;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final l = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final title = switch (_mode) {
      _Mode.login => l.loginTitle,
      _Mode.register => l.registerTitle,
    };
    final subtitle = switch (_mode) {
      _Mode.login => l.loginSubtitle,
      _Mode.register => l.registerSub,
    };
    final action = switch (_mode) {
      _Mode.login => l.signIn,
      _Mode.register => l.register,
    };
    final form = _AuthCard(
      title: title,
      subtitle: subtitle,
      action: action,
      mode: _mode,
      busy: _busy,
      obscure: _obscure,
      error: _error,
      password: _password,
      username: _username,
      onSubmit: _submit,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      onRegister: () => _switch(_Mode.register),
      onLogin: () => _switch(_Mode.login),
    );
    return Scaffold(
      backgroundColor: Red.bg,
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(flex: 106, child: _AuthVisual()),
                Expanded(
                  flex: 94,
                  child: CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _AuthPanel(
                          onLocale: widget.onLocale,
                          centered: true,
                          child: form,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              children: [
                const _AuthVisual(compact: true),
                _AuthPanel(onLocale: widget.onLocale, child: form),
              ],
            ),
    );
  }
}

class _AuthVisual extends StatelessWidget {
  const _AuthVisual({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final tight = width < 470;
    final now = DateTime.now();
    final zh = l.localeName.startsWith('zh');
    final date = zh ? '${now.month}月${now.day}日' : _enDate(now);
    final headline = compact
        ? (tight ? 36.0 : (width * 0.09).clamp(38.0, 54.0))
        : (width * 0.052).clamp(44.0, 74.0);
    final side = compact
        ? (tight ? 18.0 : 24.0)
        : (width * 0.05).clamp(28.0, 64.0);
    return DecoratedBox(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/card-seaside.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xD1000000), Color(0x4D000000), Color(0x4D000000)],
            stops: [0, 0.72, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              right: compact
                  ? BorderSide.none
                  : const BorderSide(color: Color(0xFF27272A)),
              bottom: compact
                  ? const BorderSide(color: Color(0xFF27272A))
                  : BorderSide.none,
            ),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x6B000000), Color(0xDB000000)],
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: compact ? (tight ? 280 : 320) : 320,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                side,
                compact ? (tight ? 24 : 32) : 40,
                side,
                compact ? (tight ? 22 : 28) : 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.authHeadline1,
                    style: Red.text(
                      size: headline,
                      height: 1.03,
                      letterSpacing: headline * -0.035,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    l.authHeadline2,
                    style: Red.text(
                      size: headline,
                      height: 1.03,
                      letterSpacing: headline * -0.035,
                      color: const Color(0x94FFFFFF),
                    ),
                  ),
                  SizedBox(height: compact ? 16 : 24),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 460 : 390),
                    child: Text(
                      l.authVisualSub,
                      style: Red.text(
                        size: tight ? 12.5 : (compact ? 14 : 15),
                        height: tight ? 1.65 : 1.7,
                        color: const Color(0xA3FFFFFF),
                      ),
                    ),
                  ),
                  if (!compact) const Spacer(),
                  if (compact) SizedBox(height: tight ? 24 : 32),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0x2EFFFFFF))),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: tight ? 18 : (compact ? 24 : 32),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            date,
                            style: Red.text(
                              size: tight ? 17 : 20,
                              height: 1.2,
                              weight: FontWeight.w500,
                              color: const Color(0xEBFFFFFF),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            l.authVisualFoot.toUpperCase(),
                            style: Red.text(
                              size: 11,
                              height: 1.3,
                              letterSpacing: 0.7,
                              color: const Color(0x85FFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _enDate(DateTime now) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[now.month - 1]} ${now.day}';
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.child,
    required this.onLocale,
    this.centered = false,
  });

  final Widget child;
  final ValueChanged<String>? onLocale;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final tight = width < 470;
    final en = Localizations.localeOf(context).languageCode == 'en';
    final side = centered
        ? (width * 0.05).clamp(24.0, 72.0)
        : (tight ? 12.0 : 20.0);
    final column = Column(
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (!centered && onLocale != null)
          Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 432),
              child: SizedBox(
                width: double.infinity,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _LangMini(en: en, onLocale: onLocale!),
                ),
              ),
            ),
          ),
        if (!centered && onLocale != null) SizedBox(height: tight ? 8 : 12),
        child,
        const SizedBox(height: 18),
        Text(
          l.authFoot,
          textAlign: TextAlign.center,
          style: Red.text(
            size: 10.5,
            height: 1.5,
            letterSpacing: 0.3,
            color: Red.meta,
          ),
        ),
      ],
    );
    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        side,
        centered ? 72 : (tight ? 12 : 24),
        side,
        centered ? 44 : (tight ? 40 : 48),
      ),
      child: column,
    );
    if (!centered || onLocale == null) {
      return ColoredBox(color: Red.bg, child: body);
    }
    return ColoredBox(
      color: Red.bg,
      child: Stack(
        children: [
          body,
          Positioned(
            top: 28,
            right: (width * 0.04).clamp(20.0, 44.0),
            child: _LangMini(en: en, onLocale: onLocale!),
          ),
        ],
      ),
    );
  }
}

class _LangMini extends StatelessWidget {
  const _LangMini({required this.en, required this.onLocale});

  final bool en;
  final ValueChanged<String> onLocale;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Red.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LangChip(label: '中文', selected: !en, onTap: () => onLocale('zh')),
            _LangChip(
              label: 'English',
              selected: en,
              onTap: () => onLocale('en'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected ? Red.accent : Colors.transparent,
        foregroundColor: selected ? Red.accentOn : Red.muted,
        minimumSize: const Size(44, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        textStyle: Red.text(
          size: 10.5,
          height: 1,
          weight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
      child: Text(label),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.mode,
    required this.busy,
    required this.obscure,
    required this.error,
    required this.password,
    required this.username,
    required this.onSubmit,
    required this.onToggleObscure,
    required this.onRegister,
    required this.onLogin,
  });

  final String title;
  final String subtitle;
  final String action;
  final _Mode mode;
  final bool busy;
  final bool obscure;
  final String? error;
  final TextEditingController password;
  final TextEditingController username;
  final VoidCallback onSubmit;
  final VoidCallback onToggleObscure;
  final VoidCallback onRegister;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 470
        ? const EdgeInsets.fromLTRB(18, 22, 18, 22)
        : EdgeInsets.all(width >= 900 ? 32 : 26);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 432),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Red.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Red.border),
          ),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Red.text(
                    size: width < 470 ? 28 : 32,
                    height: 1.15,
                    weight: FontWeight.w500,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: Red.text(size: 13.5, height: 1.6, color: Red.muted),
                ),
                const SizedBox(height: 16),
                _Field(
                  controller: username,
                  label: l.username,
                  hint: l.usernamePlaceholder,
                ),
                if (mode == _Mode.register) ...[
                  const SizedBox(height: 7),
                  Text(
                    l.usernameNote,
                    style: Red.text(size: 10.5, height: 1.5, color: Red.meta),
                  ),
                ],
                const SizedBox(height: 16),
                _Field(
                  controller: password,
                  label: mode == _Mode.login ? l.password : l.newPassword,
                  hint: mode == _Mode.login
                      ? l.passwordPlaceholder
                      : l.newPasswordPlaceholder,
                  secret: obscure,
                  onSubmit: onSubmit,
                  onToggle: onToggleObscure,
                ),
                if (mode != _Mode.login) ...[
                  const SizedBox(height: 7),
                  Text(
                    l.passwordHint,
                    style: Red.text(size: 10.5, height: 1.5, color: Red.meta),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(top: 1),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Red.dangerFg),
                        ),
                        child: Text(
                          '!',
                          style: Red.text(
                            size: 10,
                            height: 1,
                            weight: FontWeight.w600,
                            color: Red.dangerFg,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          error!,
                          style: Red.text(
                            size: 12,
                            height: 1.5,
                            color: Red.dangerFg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                _Primary(label: action, busy: busy, onPressed: onSubmit),
                const SizedBox(height: 14),
                ..._links(l),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _links(AppLocalizations l) {
    return switch (mode) {
      _Mode.login => [_Link(label: l.needAccount, onPressed: onRegister)],
      _Mode.register => [_Link(label: l.haveAccount, onPressed: onLogin)],
    };
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.secret = false,
    this.bare = false,
    this.onSubmit,
    this.onToggle,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool secret;
  final bool bare;
  final VoidCallback? onSubmit;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      obscureText: secret,
      keyboardType: TextInputType.text,
      textInputAction: onSubmit == null
          ? TextInputAction.next
          : TextInputAction.done,
      autocorrect: false,
      enableSuggestions: !secret,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
      style: Red.text(size: 16, height: 1.2),
      cursorColor: Red.accent,
      decoration: InputDecoration(
        isCollapsed: true,
        hintText: hint,
        hintStyle: Red.text(size: 16, height: 1.2, color: Red.meta),
        contentPadding: EdgeInsets.fromLTRB(
          14,
          14,
          onToggle == null ? 14 : 44,
          14,
        ),
        filled: true,
        fillColor: Red.surfaceWarm,
        enabledBorder: _border(Red.border),
        focusedBorder: _border(Red.accent),
        border: _border(Red.border),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!bare) ...[
          Text(
            label.toUpperCase(),
            style: Red.text(
              size: 11,
              height: 1.2,
              weight: FontWeight.w500,
              letterSpacing: 0.9,
              color: Red.fg2,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (onToggle == null)
          field
        else
          Stack(
            alignment: Alignment.centerRight,
            children: [
              field,
              IconButton(
                onPressed: onToggle,
                icon: Icon(
                  secret
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: Red.meta,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

OutlineInputBorder _border(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: color),
  );
}

class _Primary extends StatelessWidget {
  const _Primary({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Opacity(
      opacity: busy ? 0.55 : 1,
      child: SizedBox(
        height: 50,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Red.accent,
            disabledBackgroundColor: Red.accent,
            disabledForegroundColor: Red.accentOn,
            foregroundColor: Red.accentOn,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            textStyle: Red.text(
              size: 14,
              height: 1,
              weight: FontWeight.w600,
              color: Red.accentOn,
            ),
          ),
          child: Text(busy ? l.pleaseWait : label),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Red.muted,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: Red.text(size: 12, color: Red.muted, height: 1.4),
      ),
    );
  }
}
