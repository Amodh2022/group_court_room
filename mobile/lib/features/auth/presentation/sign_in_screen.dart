import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../data/auth_providers.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final auth = ref.read(authControllerProvider.notifier);
    if (_creating) {
      await auth.register(_email.text, _password.text, _name.text);
    } else {
      await auth.signIn(_email.text, _password.text);
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final error = auth.hasError ? auth.error : null;

    return CourtBackground(
      hero: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // A dark squircle with the courthouse, like the web masthead.
                      Center(
                        child: Container(
                          width: 84,
                          height: 84,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.colors.onSurface,
                            shape: BoxShape.circle,
                            boxShadow: courtShadow(context),
                          ),
                          child: Icon(
                            Icons.account_balance,
                            size: 42,
                            color: context.colors.surface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Sue Me',
                        textAlign: TextAlign.center,
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Settle it in court.',
                        textAlign: TextAlign.center,
                        style: context.text.displayMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'File a case about a harmless disagreement, summon your '
                        'friend, seat the group chat as the jury, and let the '
                        'judge ruin somebody’s week.',
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.palette.inkDim,
                        ),
                      ),
                      const SizedBox(height: 28),
                      CourtCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_creating) ...[
                              TextFormField(
                                controller: _name,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                maxLength: 40,
                                decoration: const InputDecoration(
                                  labelText: 'What should the court call you?',
                                  hintText: 'Alex',
                                  counterText: '',
                                ),
                                validator: (value) {
                                  final name = value?.trim() ?? '';
                                  if (name.isEmpty) {
                                    return 'The court needs a name.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                            ],
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                              validator: (value) {
                                final v = value?.trim() ?? '';
                                if (!RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                ).hasMatch(v)) {
                                  return 'Enter a valid email.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              decoration: const InputDecoration(
                                labelText: 'Password',
                              ),
                              validator: (value) => (value ?? '').length < 8
                                  ? 'At least 8 characters.'
                                  : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (error != null)
                              InlineError(
                                error is ApiException
                                    ? error.message
                                    : 'Could not sign in. Try again.',
                              ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _submitting ? null : _submit,
                              child: _submitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _creating ? 'Create account' : 'Sign in',
                                    ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _creating = !_creating),
                        child: Text(
                          _creating
                              ? 'Already have an account? Sign in'
                              : 'New here? Create an account',
                        ),
                      ),
                    ],
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
