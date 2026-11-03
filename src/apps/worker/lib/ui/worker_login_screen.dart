import 'package:flutter/material.dart';

import '../worker_app_controller.dart';
import 'worker_theme.dart';

enum _LoginMode { signIn, signUp }

enum _LoginMethod { password, code }

/// Email sign-up and sign-in. Matches the portal: password, or a 6-digit code.
class WorkerLoginScreen extends StatefulWidget {
  const WorkerLoginScreen({super.key, required this.controller});

  final WorkerAppController controller;

  @override
  State<WorkerLoginScreen> createState() => _WorkerLoginScreenState();
}

class _WorkerLoginScreenState extends State<WorkerLoginScreen> {
  final _email = TextEditingController(text: 'dev-user@edgemint.local');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();

  _LoginMode _mode = _LoginMode.signIn;
  _LoginMethod _method = _LoginMethod.password;
  bool _awaitingCode = false;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;
  String? _challengeId;
  String? _devCode;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  void _showSignUp() {
    setState(() {
      _mode = _LoginMode.signUp;
      _error = null;
      _password.clear();
      _confirm.clear();
      _obscure = true;
      if (_email.text.trim().toLowerCase() == 'dev-user@edgemint.local') {
        _email.clear();
      }
    });
  }

  void _showSignIn() {
    setState(() {
      _mode = _LoginMode.signIn;
      _awaitingCode = false;
      _error = null;
      _password.clear();
      _confirm.clear();
      _obscure = true;
      if (_email.text.trim().isEmpty) {
        _email.text = 'dev-user@edgemint.local';
      }
    });
  }

  Future<void> _submitPassword() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = _mode == _LoginMode.signUp
        ? await widget.controller.signUpWithEmail(
            email: _email.text,
            password: _password.text,
            confirmPassword: _confirm.text,
          )
        : await widget.controller.signInWithEmailPassword(
            email: _email.text,
            password: _password.text,
          );
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  Future<void> _requestCode() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.controller.requestEmailSignInCode(_email.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _error = result.error;
      if (result.challenge != null) {
        _challengeId = result.challenge!.challengeId;
        _devCode = result.challenge!.devCode;
        _code.clear();
        _awaitingCode = true;
      }
    });
  }

  Future<void> _verifyCode() async {
    final challengeId = _challengeId;
    if (challengeId == null) {
      setState(() => _error = 'Request a sign-in code first.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final error = await widget.controller.verifyEmailSignInCode(
      email: _email.text,
      challengeId: challengeId,
      code: _code.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final signingUp = _mode == _LoginMode.signUp;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: FibonaiMark(size: 72)),
                  const SizedBox(height: 18),
                  Text(
                    signingUp ? 'Create account' : 'Sign in',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    signingUp
                        ? 'Use your email and a password. The same account signs in to the portal.'
                        : 'Use the same email account as the FibonAI portal.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: WorkerColors.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: workerPanelDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!signingUp) ...[
                          _MethodSwitch(
                            method: _method,
                            onChanged: (method) {
                              setState(() {
                                _method = method;
                                _awaitingCode = false;
                                _error = null;
                                _devCode = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          key: const Key('worker-login-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          autocorrect: false,
                          enabled: !_awaitingCode,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        if (signingUp || _method == _LoginMethod.password) ...[
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('worker-login-password'),
                            controller: _password,
                            obscureText: _obscure,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: [
                              signingUp
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (signingUp) ...[
                          const SizedBox(height: 8),
                          Text(
                            'At least 8 characters',
                            key: const Key('worker-login-password-rule'),
                            style: TextStyle(
                              color: _password.text.length >= 8
                                  ? WorkerColors.success
                                  : WorkerColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('worker-login-confirm'),
                            controller: _confirm,
                            obscureText: _obscure,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: const InputDecoration(
                              labelText: 'Confirm password',
                            ),
                          ),
                        ],
                        if (!signingUp && _method == _LoginMethod.password) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Development password: edgemint-dev',
                            key: Key('worker-login-dev-password'),
                            style: TextStyle(
                              color: WorkerColors.dim,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (!signingUp &&
                            _method == _LoginMethod.code &&
                            _awaitingCode) ...[
                          const SizedBox(height: 12),
                          if (_devCode != null)
                            Text(
                              'Development code: $_devCode',
                              key: const Key('worker-login-dev-code'),
                              style: const TextStyle(
                                color: WorkerColors.primary,
                                fontSize: 13,
                              ),
                            ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('worker-login-otp'),
                            controller: _code,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            maxLength: 6,
                            decoration: const InputDecoration(
                              labelText: '6-digit code',
                              counterText: '',
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            key: const Key('worker-login-error'),
                            style: const TextStyle(color: WorkerColors.error),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const Key('worker-login-submit'),
                          onPressed: _submitting ? null : _onSubmit,
                          child: Text(
                            _submitting
                                ? 'Please wait'
                                : signingUp
                                ? 'Create account'
                                : _method == _LoginMethod.code && !_awaitingCode
                                ? 'Send code'
                                : _method == _LoginMethod.code
                                ? 'Verify'
                                : 'Sign in',
                          ),
                        ),
                        if (!signingUp &&
                            _method == _LoginMethod.code &&
                            _awaitingCode)
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () {
                                    setState(() {
                                      _awaitingCode = false;
                                      _devCode = null;
                                      _error = null;
                                    });
                                  },
                            child: const Text('Use a different email'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: Key(
                      signingUp
                          ? 'worker-login-show-signin'
                          : 'worker-login-show-signup',
                    ),
                    onPressed: _submitting
                        ? null
                        : (signingUp ? _showSignIn : _showSignUp),
                    child: Text(
                      signingUp
                          ? 'Already have an account? Sign in'
                          : 'Create account',
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

  Future<void> _onSubmit() {
    if (_mode == _LoginMode.signUp || _method == _LoginMethod.password) {
      return _submitPassword();
    }
    if (_awaitingCode) {
      return _verifyCode();
    }
    return _requestCode();
  }
}

class _MethodSwitch extends StatelessWidget {
  const _MethodSwitch({required this.method, required this.onChanged});

  final _LoginMethod method;
  final ValueChanged<_LoginMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MethodButton(
            label: 'Password',
            selected: method == _LoginMethod.password,
            buttonKey: const Key('worker-login-method-password'),
            onPressed: () => onChanged(_LoginMethod.password),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MethodButton(
            label: 'Email code',
            selected: method == _LoginMethod.code,
            buttonKey: const Key('worker-login-method-otp'),
            onPressed: () => onChanged(_LoginMethod.code),
          ),
        ),
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.label,
    required this.selected,
    required this.buttonKey,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final Key buttonKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: buttonKey,
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? WorkerColors.primaryContainer : null,
        side: BorderSide(
          color: selected ? WorkerColors.primary : WorkerColors.outlineVariant,
        ),
      ),
      child: Text(label),
    );
  }
}
