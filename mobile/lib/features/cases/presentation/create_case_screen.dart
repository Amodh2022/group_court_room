import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../courts/data/court_providers.dart';
import '../../courts/presentation/user_search_sheet.dart';
import '../data/case_providers.dart';

/// Mirrors the server's limits so the user is corrected before a round trip.
/// The server stays the authority.
class CaseLimits {
  const CaseLimits._();
  static const titleMin = 3;
  static const titleMax = 80;
  static const accusationMin = 10;
  static const accusationMax = 1000;
  static const nicknameMax = 40;
}

class CreateCaseScreen extends ConsumerStatefulWidget {
  const CreateCaseScreen({super.key, this.courtId});

  /// Pre-selects a court, e.g. when filing from a court's own page.
  final String? courtId;

  @override
  ConsumerState<CreateCaseScreen> createState() => _CreateCaseScreenState();
}

class _CreateCaseScreenState extends ConsumerState<CreateCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _accusation = TextEditingController();
  final _nickname = TextEditingController();

  String _category = CaseCategory.all.first.id;
  String? _courtId;
  UserRef? _accused;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _courtId = widget.courtId;
    // Drives the live character counter without a rebuild of the whole form.
    _accusation.addListener(_onAccusationChanged);
  }

  void _onAccusationChanged() => setState(() {});

  @override
  void dispose() {
    _accusation.removeListener(_onAccusationChanged);
    _title.dispose();
    _accusation.dispose();
    _nickname.dispose();
    super.dispose();
  }

  String? _validateTitle(String? value) {
    final text = value?.trim() ?? '';
    if (text.length < CaseLimits.titleMin) {
      return 'Give the case a name (at least ${CaseLimits.titleMin} characters).';
    }
    if (text.length > CaseLimits.titleMax) {
      return 'Keep the title under ${CaseLimits.titleMax} characters.';
    }
    return null;
  }

  String? _validateAccusation(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'The court needs to hear the charge.';
    if (text.length < CaseLimits.accusationMin) {
      return 'Tell the court a bit more — at least ${CaseLimits.accusationMin} characters.';
    }
    if (text.length > CaseLimits.accusationMax) {
      return 'Keep it under ${CaseLimits.accusationMax} characters.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final created = await ref
          .read(caseActionsProvider)
          .create(
            title: _title.text.trim(),
            category: _category,
            accusation: _accusation.text.trim(),
            defendantNickname: _accused?.displayName ?? _nickname.text.trim(),
            courtId: _courtId,
            accusedUserId: _accused?.userId,
          );
      if (!mounted) return;
      // The raw invite token exists only in this response, so go straight to
      // the share screen with it rather than re-fetching the case.
      context.pushReplacement('/cases/${created.id}/invite', extra: created);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error.fields?.values.firstOrNull ?? error.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = CaseLimits.accusationMax - _accusation.text.trim().length;

    return CourtScaffold(
      title: 'File a case',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
          children: [
            const PageTitle(
              label: 'New filing',
              title: 'What are we arguing about?',
              subtitle:
                  'Keep it harmless and specific. Your friends will be on the jury.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('The charge'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: CaseLimits.titleMax,
                    decoration: const InputDecoration(
                      labelText: 'Case title',
                      hintText: 'The Last Pizza Slice',
                    ),
                    validator: _validateTitle,
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Category'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in CaseCategory.all)
                        ChoiceChip(
                          label: Text('${category.emoji}  ${category.label}'),
                          selected: _category == category.id,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _category == category.id
                                ? context.colors.onPrimary
                                : context.palette.inkDim,
                          ),
                          onSelected: (_) =>
                              setState(() => _category = category.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel('What happened'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accusation,
                    maxLines: 6,
                    maxLength: CaseLimits.accusationMax,
                    textCapitalization: TextCapitalization.sentences,
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    decoration: const InputDecoration(
                      hintText:
                          'My friend ate the last pizza slice right after '
                          'saying they were full.',
                      alignLabelWithHint: true,
                    ),
                    validator: _validateAccusation,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '$remaining characters left',
                      textAlign: TextAlign.right,
                      style: context.text.bodySmall?.copyWith(
                        color: remaining < 0
                            ? CourtColors.guilty
                            : context.palette.inkDim,
                        fontWeight: remaining < 0
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Your court (optional)'),
                  const SizedBox(height: 4),
                  Text(
                    'Everyone in the court is seated as the jury.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.palette.inkDim,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('No court'),
                        selected: _courtId == null,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _courtId = null),
                      ),
                      for (final court
                          in ref.watch(courtsProvider).valueOrNull ??
                              const <Court>[])
                        ChoiceChip(
                          label: Text(court.name),
                          selected: _courtId == court.id,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => _courtId = court.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('The defendant (optional)'),
                  const SizedBox(height: 12),
                  if (_accused != null)
                    InputChip(
                      label: Text(
                        '${_accused!.displayName} (@${_accused!.handle})',
                      ),
                      onDeleted: () => setState(() => _accused = null),
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.person_search_outlined),
                      label: const Text('Pick a friend by handle'),
                      onPressed: () async {
                        final user = await pickUser(
                          context,
                          title: 'Who is the accused?',
                        );
                        if (user != null) setState(() => _accused = user);
                      },
                    ),
                  if (_accused == null) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nickname,
                      maxLength: CaseLimits.nicknameMax,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Or just a nickname',
                        hintText: 'SliceBandit',
                        counterText: '',
                        helperText:
                            'Use the same name every time and their record '
                            'follows them from case to case.',
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                  if (_submitError != null) InlineError(_submitError!),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('File the case'),
                  ),
                  const CourtDisclaimer(
                    text:
                        'Keep it harmless. The court will not make jokes about '
                        'anything serious — and neither should you.',
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
