import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_people.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../courts/data/court_providers.dart';
import '../../courts/presentation/courts_screen.dart' show courtMonogram;
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

/// Filing, drawn to the "File a case" artboard: numbered steps, a charge you
/// write in the display face, and one violet key at the foot.
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

  /// Who the case is against, as the court will name them.
  String get _accusedName {
    if (_accused != null) return _accused!.displayName;
    final nickname = _nickname.text.trim();
    return nickname.isEmpty ? 'them' : nickname;
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
    final courts = ref.watch(courtsProvider).valueOrNull ?? const <Court>[];
    final court = courts.where((c) => c.id == _courtId).firstOrNull;
    final candidates = court?.members ?? const <UserRef>[];

    return CourtScaffold(
      title: 'File a case',
      header: ScreenHeader(
        title: 'File a case',
        titleSize: 28,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        leading: RoundIconButton(
          glyph: CourtGlyph.close,
          label: 'Close',
          onTap: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        trailing: [
          _CourtPicker(
            courts: courts,
            selected: court,
            onPick: (id) => setState(() {
              _courtId = id;
              // The accused came from the old court's roster; drop them rather
              // than file against somebody who is not in the room.
              if (_accused != null &&
                  !(courts
                      .where((c) => c.id == id)
                      .expand((c) => c.members)
                      .any((m) => m.userId == _accused!.userId))) {
                _accused = null;
              }
            }),
          ),
        ],
      ),
      bottom: BottomDock(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_submitError != null) ...[
              InlineError(_submitError!),
              const SizedBox(height: 10),
            ],
            CourtKey(
              // Only an account the court can notify earns a named key; a
              // nickname is just a label, so the verb stays neutral.
              label: _accused == null ? 'File the case' : 'Sue $_accusedName',
              glyph: CourtGlyph.gavel,
              height: 60,
              busy: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
            const SizedBox(height: 8),
            Text(
              _accused == null && _nickname.text.trim().isEmpty
                  ? 'They get a window to mount a defense.'
                  : '$_accusedName gets a window to mount a defense.',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.palette.inkDim,
              ),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
          children: [
            // 1 — the accused.
            const _Step(number: 1, title: 'Who are you suing?'),
            const SizedBox(height: 10),
            _AccusedPicker(
              candidates: candidates,
              accused: _accused,
              onPick: (user) => setState(() {
                _accused = user;
                if (user != null) _nickname.clear();
              }),
              onSearch: () async {
                final user = await pickUser(
                  context,
                  title: 'Who is the accused?',
                );
                if (user != null) {
                  setState(() {
                    _accused = user;
                    _nickname.clear();
                  });
                }
              },
            ),
            if (_accused == null) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _nickname,
                maxLength: CaseLimits.nicknameMax,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Or just a nickname',
                  hintText: 'SliceBandit',
                  counterText: '',
                  helperText:
                      'Use the same name every time and their record follows '
                      'them from case to case.',
                  helperMaxLines: 2,
                ),
              ),
            ],

            const SizedBox(height: 18),
            // 2 — the charge.
            _Step(
              number: 2,
              title: _accused == null && _nickname.text.trim().isEmpty
                  ? 'What did they do?'
                  : 'What did $_accusedName do?',
            ),
            const SizedBox(height: 10),
            Container(
              decoration: courtChunk(context, radius: 22),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _CardLabel('CASE TITLE'),
                  TextFormField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: CaseLimits.titleMax,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'The Last Pizza Slice',
                      filled: false,
                      isDense: true,
                      counterText: '',
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    validator: _validateTitle,
                  ),
                  Divider(color: context.palette.lineSoft, height: 12),
                  const SizedBox(height: 4),
                  const _CardLabel('THE CHARGE', color: CourtColors.redInk),
                  TextFormField(
                    controller: _accusation,
                    maxLines: null,
                    minLines: 2,
                    maxLength: CaseLimits.accusationMax,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      fontFamily: courtDisplayFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                      height: 1.25,
                    ),
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    decoration: const InputDecoration(
                      hintText: 'State the crime. Be dramatic.',
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.only(top: 4),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    validator: _validateAccusation,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$remaining characters left',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: remaining < 0
                            ? CourtColors.red
                            : context.palette.inkDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in CaseCategory.all)
                  _ChoicePill(
                    label: '${category.emoji}  ${category.label}',
                    selected: _category == category.id,
                    onTap: () => setState(() => _category = category.id),
                  ),
              ],
            ),

            const SizedBox(height: 18),
            // 3 — the jury.
            const _Step(number: 3, title: 'Who is on the jury?'),
            const SizedBox(height: 10),
            _JuryPicker(
              courts: courts,
              selected: _courtId,
              onPick: (id) => setState(() => _courtId = id),
            ),

            const CourtDisclaimer(
              text:
                  'Keep it harmless. The court will not make jokes about '
                  'anything serious — and neither should you.',
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered step heading: an ink disc and the question.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.colors.onSurface,
        ),
        child: Text(
          '$number',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            height: 1,
            color: context.colors.surface,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: courtDisplayFont,
            fontWeight: FontWeight.w700,
            fontSize: 19,
            height: 1.15,
          ),
        ),
      ),
    ],
  );
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.5,
      color: color ?? context.palette.inkDim,
    ),
  );
}

/// The pill row under the charge: one tap sets the category.
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? context.colors.onSurface : Colors.transparent,
      borderRadius: BorderRadius.circular(courtRadiusPill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // No `alignment` on the Container: given one, it expands to every
        // pixel the Wrap offers, and the pills stop being pills — each one
        // takes a whole row. A min-size Row centres the label instead.
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(courtRadiusPill),
            border: Border.all(
              color: context.palette.border,
              width: courtBorderThin,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? context.colors.surface
                      : context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The roster of the chosen court as tappable tiles, plus a search tile for
/// anybody who is not in it.
class _AccusedPicker extends StatelessWidget {
  const _AccusedPicker({
    required this.candidates,
    required this.accused,
    required this.onPick,
    required this.onSearch,
  });

  final List<UserRef> candidates;
  final UserRef? accused;
  final ValueChanged<UserRef?> onPick;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    // The accused may have come from a search rather than the roster; make
    // sure they are always on screen and always selectable.
    final people = [...candidates];
    if (accused != null && !people.any((p) => p.userId == accused!.userId)) {
      people.insert(0, accused!);
    }

    return LayoutBuilder(
      builder: (context, box) {
        // Five across on a phone, as on the canvas, but never narrower than a
        // tile that can hold a 46px avatar.
        final columns = ((box.maxWidth + 8) / 80).floor().clamp(3, 5);
        final width = (box.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final person in people)
              SizedBox(
                width: width,
                child: _PersonTile(
                  name: person.displayName,
                  selected: accused?.userId == person.userId,
                  onTap: () =>
                      onPick(accused?.userId == person.userId ? null : person),
                ),
              ),
            SizedBox(
              width: width,
              child: _PersonTile(
                name: 'Search',
                glyph: CourtGlyph.plus,
                selected: false,
                onTap: onSearch,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.name,
    required this.selected,
    required this.onTap,
    this.glyph,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final CourtGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: selected
                ? CourtColors.yellow
                : context.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(courtRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                height: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(courtRadius),
                  border: Border.all(
                    color: selected ? palette.border : palette.lineSoft,
                    width: courtBorderWidth,
                  ),
                  boxShadow: selected ? courtHardShadow(context) : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: glyph != null
                            ? palette.surfaceAlt
                            : tintFor(name),
                        border: Border.all(
                          color: palette.border,
                          width: courtBorderWidth,
                        ),
                      ),
                      child: glyph != null
                          ? CourtIcon(
                              glyph!,
                              size: 20,
                              color: context.colors.onSurface,
                              strokeWidth: 3,
                            )
                          : Text(
                              name.trim().isEmpty
                                  ? '?'
                                  : name.trim()[0].toUpperCase(),
                              style: const TextStyle(
                                fontFamily: courtDisplayFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                                height: 1,
                                color: CourtColors.lightInk,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: selected
                              ? CourtColors.lightInk
                              : context.colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              top: -8,
              right: -6,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CourtColors.red,
                  border: Border.all(color: CourtColors.lightInk, width: 2),
                ),
                child: const CourtIcon(
                  CourtGlyph.check,
                  size: 12,
                  color: Colors.white,
                  strokeWidth: 4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Which court is seated: every member of it becomes a juror.
class _JuryPicker extends StatelessWidget {
  const _JuryPicker({
    required this.courts,
    required this.selected,
    required this.onPick,
  });

  final List<Court> courts;
  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = ((box.maxWidth + 10) / 130).floor().clamp(2, 3);
      final width = (box.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: width,
            child: _JuryTile(
              title: 'Just a link',
              caption: 'Invite jurors yourself',
              selected: selected == null,
              onTap: () => onPick(null),
            ),
          ),
          for (final court in courts)
            SizedBox(
              width: width,
              child: _JuryTile(
                title: court.name,
                caption:
                    '${court.members.length} '
                    '${court.members.length == 1 ? 'juror' : 'jurors'}',
                monogram: courtMonogram(court.name),
                selected: selected == court.id,
                onTap: () => onPick(court.id),
              ),
            ),
        ],
      );
    },
  );
}

class _JuryTile extends StatelessWidget {
  const _JuryTile({
    required this.title,
    required this.caption,
    required this.selected,
    required this.onTap,
    this.monogram,
  });

  final String title;
  final String caption;
  final bool selected;
  final VoidCallback onTap;
  final String? monogram;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? CourtColors.orange
            : context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(courtRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 84,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(courtRadius),
              border: Border.all(
                color: palette.border,
                width: courtBorderWidth,
              ),
              boxShadow: selected ? courtHardShadow(context) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (monogram != null)
                  Text(
                    monogram!,
                    style: TextStyle(
                      fontFamily: courtDisplayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1,
                      color: selected ? CourtColors.lightInk : palette.inkDim,
                    ),
                  ),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    height: 1.15,
                    color: selected
                        ? CourtColors.lightInk
                        : context.colors.onSurface,
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? CourtColors.lightInk.withValues(alpha: 0.75)
                        : palette.inkDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The yellow court chip in the header.
class _CourtPicker extends StatelessWidget {
  const _CourtPicker({
    required this.courts,
    required this.selected,
    required this.onPick,
  });

  final List<Court> courts;
  final Court? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String?>(
    tooltip: 'Change court',
    onSelected: onPick,
    position: PopupMenuPosition.under,
    itemBuilder: (context) => [
      const PopupMenuItem<String?>(value: null, child: Text('No court')),
      for (final court in courts)
        PopupMenuItem<String?>(value: court.id, child: Text(court.name)),
    ],
    child: Container(
      height: 40,
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: CourtColors.yellow,
        borderRadius: BorderRadius.circular(courtRadiusPill),
        border: Border.all(
          color: context.palette.border,
          width: courtBorderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              selected?.name ?? 'No court',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: CourtColors.lightInk,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const CourtIcon(
            CourtGlyph.chevronDown,
            size: 14,
            color: CourtColors.lightInk,
            strokeWidth: 3.4,
          ),
        ],
      ),
    ),
  );
}
