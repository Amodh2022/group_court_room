import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../../core/widgets/sue_widgets.dart';
import '../../auth/data/auth_providers.dart';
import '../../cases/data/case_providers.dart';
import '../../cases/presentation/create_case_screen.dart' show CaseLimits;
import '../../courts/data/court_providers.dart';
import '../data/invite_providers.dart';

/// Answering a summons, in the app.
///
/// The summons is a capability link: the token is the whole authorisation, so
/// this screen deliberately works signed in or not, exactly as the web page
/// does. Somebody who already has the app should never have to leave it to
/// paste their own link into a browser.
class DefendScreen extends ConsumerStatefulWidget {
  const DefendScreen({super.key, required this.token});

  /// The raw summons token from the link.
  final String token;

  @override
  ConsumerState<DefendScreen> createState() => _DefendScreenState();
}

class _DefendScreenState extends ConsumerState<DefendScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _body = TextEditingController();

  bool _submitting = false;
  String? _submitError;
  DefenseAccepted? _accepted;

  @override
  void initState() {
    super.initState();
    _body.addListener(_onBodyChanged);
  }

  void _onBodyChanged() => setState(() {});

  @override
  void dispose() {
    _body.removeListener(_onBodyChanged);
    _nickname.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final accepted = await ref
          .read(apiClientProvider)
          .submitDefense(
            widget.token,
            nickname: _nickname.text.trim(),
            body: _body.text.trim(),
          );
      if (!mounted) return;
      // The case has moved on, and so has anything listing it.
      ref.invalidate(sharedCasesProvider);
      ref.invalidate(casesProvider);
      setState(() {
        _accepted = accepted;
        _submitting = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error.fields?.values.firstOrNull ?? error.message;
        _submitting = false;
      });
    }
  }

  String? _validateNickname(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'The court needs a name to put on the record.';
    if (name.length > CaseLimits.nicknameMax) {
      return 'Keep it under ${CaseLimits.nicknameMax} characters.';
    }
    return null;
  }

  String? _validateBody(String? value) {
    final text = (value ?? '').trim();
    if (text.length < CaseLimits.accusationMin) {
      return 'Say at least ${CaseLimits.accusationMin} characters in your '
          'defence.';
    }
    if (text.length > CaseLimits.accusationMax) {
      return 'That is longer than the court will read.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(invitePreviewProvider(widget.token));

    final close = RoundIconButton(
      glyph: CourtGlyph.close,
      label: 'Close',
      onTap: () => context.canPop() ? context.pop() : context.go('/'),
    );

    return CourtScaffold(
      title: 'Your defence',
      maxWidth: 640,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Row(
          children: [
            close,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOU HAVE BEEN SUED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: context.palette.inkDim,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Your defence',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: preview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Every failure looks the same here, exactly as the server intends:
        // a revoked link and a link that never existed are one answer.
        error: (error, _) => _Invalid(
          message: error is ApiException && !error.isNetwork
              ? null
              : 'Could not reach the courthouse. Check your connection.',
          onRetry: () => ref.invalidate(invitePreviewProvider(widget.token)),
        ),
        data: (data) {
          if (_accepted != null) return _Filed(accepted: _accepted!);
          if (data.alreadySubmitted) return _AlreadyAnswered(preview: data);
          return _Form(
            formKey: _formKey,
            preview: data,
            nickname: _nickname,
            body: _body,
            submitting: _submitting,
            submitError: _submitError,
            validateNickname: _validateNickname,
            validateBody: _validateBody,
            onSubmit: _submit,
          );
        },
      ),
    );
  }
}

/// The charge, then the box to answer it in.
class _Form extends StatelessWidget {
  const _Form({
    required this.formKey,
    required this.preview,
    required this.nickname,
    required this.body,
    required this.submitting,
    required this.submitError,
    required this.validateNickname,
    required this.validateBody,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final InvitePreview preview;
  final TextEditingController nickname;
  final TextEditingController body;
  final bool submitting;
  final String? submitError;
  final String? Function(String?) validateNickname;
  final String? Function(String?) validateBody;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final remaining = CaseLimits.accusationMax - body.text.trim().length;

    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
        children: [
          _ChargeCard(preview: preview),
          const SizedBox(height: 18),
          Text(
            'YOUR SIDE OF IT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: context.palette.inkDim,
            ),
          ),
          const SizedBox(height: 10),
          SueCard(
            radius: 22,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: nickname,
                  textCapitalization: TextCapitalization.words,
                  maxLength: CaseLimits.nicknameMax,
                  validator: validateNickname,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'What should the court call you?',
                    hintText: 'Sam',
                    counterText: '',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
                Divider(color: context.palette.lineSoft, height: 14),
                TextFormField(
                  controller: body,
                  maxLines: null,
                  minLines: 4,
                  maxLength: CaseLimits.accusationMax,
                  textCapitalization: TextCapitalization.sentences,
                  validator: validateBody,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 17,
                    height: 1.35,
                  ),
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  decoration: const InputDecoration(
                    hintText: 'Tell the court what really happened.',
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.only(top: 6),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$remaining characters left',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: remaining < 0
                          ? CourtColors.red
                          : context.palette.inkDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (submitError != null) ...[
            const SizedBox(height: 12),
            InlineError(submitError!),
          ],
          const SizedBox(height: 18),
          SueButton(
            label: 'ENTER MY DEFENCE',
            height: 56,
            busy: submitting,
            onPressed: submitting ? null : onSubmit,
          ),
          const SizedBox(height: 10),
          Text(
            preview.juryCount == 0
                ? 'The judge reads both sides before ruling. You get one answer.'
                : '${preview.juryCount} ${preview.juryCount == 1 ? 'juror is' : 'jurors are'} '
                      'already seated. You get one answer.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.palette.inkDim,
            ),
          ),
          const CourtDisclaimer(
            text:
                'Your defence is shown to the judge and the jury of this case, '
                'and to nobody else unless the verdict is published.',
          ),
        ],
      ),
    );
  }
}

/// Who is suing, and what over.
class _ChargeCard extends StatelessWidget {
  const _ChargeCard({required this.preview});

  final InvitePreview preview;

  @override
  Widget build(BuildContext context) => SueCard(
    radius: 22,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SuePair(
              a: preview.plaintiffName,
              b: preview.defendantNickname ?? 'You',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: preview.plaintiffName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: ' is suing you'),
                  ],
                ),
                style: TextStyle(fontSize: 13, color: context.palette.inkDim),
              ),
            ),
            if (preview.expiresAt != null)
              _Countdown(expiresAt: preview.expiresAt!),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'THE CHARGE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: context.palette.inkDim,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          preview.caseTitle,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          preview.accusation,
          style: const TextStyle(fontSize: 15, height: 1.45),
        ),
      ],
    ),
  );
}

/// How long is left to answer. Nothing is drawn once the clock has run out:
/// an empty countdown is worse than no countdown.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.expiresAt});

  final DateTime expiresAt;

  @override
  Widget build(BuildContext context) {
    final left = expiresAt.difference(DateTime.now());
    if (left.isNegative) return const SuePill('CLOSED', tone: SueTone.gray);
    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60);
    return SuePill(
      hours > 0 ? '${hours}H LEFT' : '${minutes}M LEFT',
      tone: SueTone.orange,
      round: false,
    );
  }
}

/// The receipt: the defence is on the record and cannot be rewritten.
class _Filed extends StatelessWidget {
  const _Filed({required this.accepted});

  final DefenseAccepted accepted;

  // CourtNotice scrolls and centres itself, so it is the body rather than a
  // row inside one: nested in a ListView it is handed an infinite height.
  @override
  Widget build(BuildContext context) => CourtNotice(
    icon: Icons.gavel,
    title: 'Your defence is on the record',
    message:
        'The judge has both sides of “${accepted.caseTitle}” now. '
        'You will hear when the court rules.',
    action: CourtKey(
      label: 'Back to the docket',
      glyph: CourtGlyph.home,
      onPressed: () => context.go('/'),
    ),
  );
}

/// This summons has already been answered.
class _AlreadyAnswered extends StatelessWidget {
  const _AlreadyAnswered({required this.preview});

  final InvitePreview preview;

  @override
  Widget build(BuildContext context) => CourtNotice(
    icon: Icons.lock_outline,
    title: preview.verdictReady
        ? 'The court has already ruled'
        : 'This defence is already in',
    message: preview.verdictReady
        ? 'A verdict has been handed down on “${preview.caseTitle}”.'
        : 'Somebody has already answered this summons. The court takes '
              'one defence per case.',
    action: CourtKey(
      label: 'Back to the docket',
      glyph: CourtGlyph.home,
      onPressed: () => context.go('/'),
    ),
  );
}

/// A summons that does not resolve. The reason is deliberately not given.
class _Invalid extends StatelessWidget {
  const _Invalid({required this.message, required this.onRetry});

  /// Null for a link the server rejected; set for a connection failure, which
  /// is worth retrying and is not the link's fault.
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => message != null
      ? CourtErrorView(message: message!, onRetry: onRetry)
      : CourtNotice(
          icon: Icons.link_off,
          title: 'This summons is no longer valid',
          message:
              'The link may have expired, been revoked, or never existed. '
              'Ask whoever sued you to send a fresh one.',
          action: CourtKey(
            label: 'Back to the docket',
            glyph: CourtGlyph.home,
            onPressed: () => context.go('/'),
          ),
        );
}
