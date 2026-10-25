import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'common.dart';

/// Email + password sign in / sign up.
class AuthForm extends ConsumerStatefulWidget {
  const AuthForm({super.key});

  @override
  ConsumerState<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<AuthForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _signUp = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final repo = ref.read(repoProvider);
    setState(() => _busy = true);
    await guarded(context, () async {
      if (_signUp) {
        await repo.signUp(_email.text.trim(), _password.text, _name.text.trim());
      } else {
        await repo.signIn(_email.text.trim(), _password.text);
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return AutofillGroup(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_signUp)
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: s.fullName),
            autofillHints: const [AutofillHints.name],
          ),
        TextField(
          controller: _email,
          decoration: InputDecoration(labelText: s.email),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        TextField(
          controller: _password,
          decoration: InputDecoration(labelText: s.password),
          obscureText: true,
          autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_signUp ? s.signUp : s.signIn)),
        TextButton(
          onPressed: () => setState(() => _signUp = !_signUp),
          child: Text(_signUp ? s.haveAccount : s.noAccount),
        ),
      ]),
    );
  }
}
