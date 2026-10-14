import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/widgets/sue_widgets.dart';
import '../data/auth_providers.dart';

/// The way in, drawn to the "Log in" artboards: the gavel stage, the promise
/// in two lines, and the fields on their own soft cards.
///
/// The canvas signs you in with a phone number and an OTP; this court runs on
/// an email and a password, so the fields say so. Everything around them —
/// the stage, the type, the blue key, the small print — is the artboard's.
///
/// On a tablet the two tablet artboards split it: the pitch on the left, the
/// form on the right.
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
    final tablet = context.isTablet;

    final pitch = Column(
      crossAxisAlignment: tablet
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SueStage(tone: SueTone.orange, height: 196),
        const SizedBox(height: 18),
        // Text.rich, not RichText: RichText starts from no style at all, so
        // the headline lost the app's typeface and set in the fallback.
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Sue your friends.\n'),
              TextSpan(
                text: 'Win the verdict.',
                style: TextStyle(color: context.palette.accent),
              ),
            ],
          ),
          textAlign: tablet ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            fontSize: tablet ? 40 : 36,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -.8,
            color: context.colors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Petty drama, settled by your friends and an AI judge with no chill.',
          textAlign: tablet ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: context.palette.inkDim,
          ),
        ),
      ],
    );

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tablet) ...[
            Text(
              _creating ? 'Join the court' : 'Welcome back',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _creating
                  ? 'Make an account and start filing.'
                  : "Log in to see who's being sued today.",
              style: TextStyle(fontSize: 15, color: context.palette.inkDim),
            ),
            const SizedBox(height: 18),
          ],
          if (_creating) ...[
            _Field(
              controller: _name,
              label: 'What should the court call you?',
              hint: 'Alex',
              textInputAction: TextInputAction.next,
              capitalise: true,
              validator: (value) => (value?.trim() ?? '').isEmpty
                  ? 'The court needs a name.'
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          _Field(
            controller: _email,
            label: 'Email',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofill: const [AutofillHints.email],
            validator: (value) =>
                RegExp(
                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                ).hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter a valid email.',
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _password,
            label: 'Password',
            hint: 'At least 8 characters',
            obscure: true,
            textInputAction: TextInputAction.done,
            autofill: const [AutofillHints.password],
            validator: (value) =>
                (value ?? '').length < 8 ? 'At least 8 characters.' : null,
            onSubmitted: (_) => _submit(),
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            InlineError(
              error is ApiException
                  ? error.message
                  : 'Could not sign in. Try again.',
            ),
          ],
          const SizedBox(height: 12),
          SueButton(
            label: _creating ? 'CREATE ACCOUNT' : 'SIGN IN',
            height: 58,
            radius: 16,
            glyph: CourtGlyph.arrowRight,
            busy: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: 10),
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
    );

    const smallPrint =
        'Cases stay private to your court unless you make them public.';

    return CourtBackground(
      hero: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: tablet
              ? Padding(
                  padding: const EdgeInsets.all(suePagePad),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Center(child: pitch),
                        ),
                      ),
                      const SizedBox(width: suePagePad),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SueCard(
                            radius: 26,
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                form,
                                const SizedBox(height: 6),
                                Text(
                                  smallPrint,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: context.palette.inkDim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 34, 20, 28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          pitch,
                          const SizedBox(height: 18),
                          form,
                          const SizedBox(height: 10),
                          Text(
                            smallPrint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: context.palette.inkDim,
                            ),
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

/// A field on its own soft card, as the artboard draws the phone box: 56 high,
/// radius 16, no outline, the label carried by the hint.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.autofill,
    this.obscure = false,
    this.capitalise = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<String>? autofill;
  final bool obscure;
  final bool capitalise;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: .6,
            color: context.palette.inkDim,
          ),
        ),
      ),
      SueCard(
        small: true,
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofill,
          textCapitalization: capitalise
              ? TextCapitalization.words
              : TextCapitalization.none,
          validator: validator,
          onFieldSubmitted: onSubmitted,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
        ),
      ),
    ],
  );
}
