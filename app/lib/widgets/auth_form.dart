import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'common.dart';

/// Sign in with a 6-digit code sent by email (A-08). New emails get an account
/// automatically. Password sign-in stays available for the demo accounts.
class AuthForm extends ConsumerStatefulWidget {
  const AuthForm({super.key});

  @override
  ConsumerState<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<AuthForm> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _usePassword = false;
  bool _codeSent = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await guarded(context, action);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final repo = ref.read(repoProvider);
    final email = _email.text.trim();
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _email,
            enabled: !_codeSent,
            decoration: InputDecoration(labelText: s.email),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
          ),
          if (_usePassword) ...[
            TextField(
              controller: _password,
              decoration: InputDecoration(labelText: s.password),
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _run(() => repo.signIn(email, _password.text)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : () => _run(() => repo.signIn(_email.text.trim(), _password.text)),
              child: Text(s.signIn),
            ),
          ] else if (!_codeSent) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await repo.sendCode(_email.text.trim());
                      if (mounted) setState(() => _codeSent = true);
                    }),
              child: Text(s.sendCode),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(s.codeSent),
            TextField(
              controller: _code,
              decoration: InputDecoration(labelText: s.code),
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 8,
              onSubmitted: (_) => _run(() => repo.verifyCode(email, _code.text.trim())),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _run(() => repo.verifyCode(_email.text.trim(), _code.text.trim())),
              child: Text(s.verify),
            ),
            TextButton(onPressed: () => setState(() => _codeSent = false), child: Text(s.sendCode)),
          ],
          TextButton(
            onPressed: () => setState(() {
              _usePassword = !_usePassword;
              _codeSent = false;
            }),
            child: Text(_usePassword ? s.useCode : s.usePassword),
          ),
        ],
      ),
    );
  }
}
