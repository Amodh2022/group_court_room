import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_icons.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/sue_widgets.dart';
import '../../../core/widgets/court_widgets.dart';
import '../../courts/data/court_providers.dart';
import '../../courts/presentation/courts_screen.dart' show courtMonogram;
import '../../courts/presentation/user_search_sheet.dart';
import '../../game/data/game_providers.dart';
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

  /// How petty the plaintiff says it is, 1-3. Multiplies the XP the case pays
  /// out if they win — and the XP they lose if they do not.
  int _petty = 1;
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
            pettyLevel: _petty,
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

  /// Switching court drops an accused who is not in the new room: better than
  /// filing against somebody who cannot be notified.
  void _pickCourt(String? id) {
    final courts = ref.read(courtsProvider).valueOrNull ?? const <Court>[];
    setState(() {
      _courtId = id;
      if (_accused != null &&
          !(courts
              .where((c) => c.id == id)
              .expand((c) => c.members)
              .any((m) => m.userId == _accused!.userId))) {
        _accused = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = CaseLimits.accusationMax - _accusation.text.trim().length;
    final courts = ref.watch(courtsProvider).valueOrNull ?? const <Court>[];
    final court = courts.where((c) => c.id == _courtId).firstOrNull;
    final candidates = court?.members ?? const <UserRef>[];

    // The three steps as groups, so the tablet artboard can set the first two
    // beside the third instead of running all three down one column.
    final accused = <Widget>[
      // 1 — the accused.
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
          final user = await pickUser(context, title: 'Who is the accused?');
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
    ];

    final charge = <Widget>[
      // 2 — the charge.
      _Step(
        number: 2,
        title: _accused == null && _nickname.text.trim().isEmpty
            ? 'What did they do?'
            : 'What did $_accusedName do?',
      ),
      const SizedBox(height: 10),
      SueCard(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardLabel('CASE TITLE'),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: CaseLimits.titleMax,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
            const _CardLabel('THE CHARGE'),
            TextFormField(
              controller: _accusation,
              maxLines: null,
              minLines: 2,
              maxLength: CaseLimits.accusationMax,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 18,
                height: 1.3,
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
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final category in CaseCategory.all)
            _ChoicePill(
              label: category.label,
              selected: _category == category.id,
              onTap: () => setState(() => _category = category.id),
            ),
        ],
      ),
    ];

    final petty = <Widget>[
      // 3 — the stake.
      const _Step(number: 3, title: 'How petty is it?'),
      const SizedBox(height: 10),
      _PettyPicker(
        level: _petty,
        onPick: (level) => setState(() => _petty = level),
      ),
    ];

    final jury = <Widget>[
      // 4 — the jury.
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
    ];

    final dock = BottomDock(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_submitError != null) ...[
            InlineError(_submitError!),
            const SizedBox(height: 10),
          ],
          _FilingKeyRow(
            // Only an account the court can notify earns a named key; a
            // nickname is just a label, so the verb stays neutral.
            label: _accused == null ? 'File the case' : 'Sue $_accusedName',
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
    );

    final close = RoundIconButton(
      glyph: CourtGlyph.close,
      label: 'Close',
      onTap: () => context.canPop() ? context.pop() : context.go('/'),
    );

    final picker = _CourtPicker(
      courts: courts,
      selected: court,
      onPick: _pickCourt,
    );

    return CourtScaffold(
      title: 'File a case',
      // The tablet artboard sets the accused and the charge beside the jury
      // instead of running the three steps down one column.
      tablet: Column(
        children: [
          Expanded(
            child: SueTabletPage(
              header: Row(
                children: [
                  close,
                  const SizedBox(width: 14),
                  Expanded(
                    child: SueTabletHeader(
                      title: 'File a case',
                      subtitle: court?.name,
                    ),
                  ),
                  picker,
                ],
              ),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SueColumns(
                      start: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...accused,
                            const SizedBox(height: 18),
                            ...charge,
                          ],
                        ),
                      ],
                      end: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: jury,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          dock,
        ],
      ),
      header: ScreenHeader(
        title: 'File a case',
        titleSize: 28,
        eyebrow: court == null ? null : 'IN ${court.name.toUpperCase()}',
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        leading: close,
        trailing: [picker],
      ),
      bottom: dock,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            ...accused,
            const SizedBox(height: 18),
            ...charge,
            const SizedBox(height: 18),
            ...petty,
            const SizedBox(height: 18),
            ...jury,
          ],
        ),
      ),
    );
  }
}

/// A section label: small tracked capitals, as on the canvas. [number] is
/// kept so the call sites still read as steps; it is not drawn.
class _Step extends StatelessWidget {
  // ignore: unused_element_parameter
  const _Step({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title.toUpperCase(),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
      color: context.palette.inkDim,
    ),
  );
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
      color: context.palette.inkDim,
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
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // No `alignment` on the Container: given one, it expands to every
      // pixel the Wrap offers, and the pills stop being pills.
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? SueTone.blue.tint(context)
              : context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? SueTone.blue.fg(context)
                    : context.palette.inkDim,
              ),
            ),
          ],
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 92,
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? palette.accent : Colors.transparent,
              width: 2,
            ),
            boxShadow: courtHardShadow(context, dy: 4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              glyph != null
                  ? Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.surfaceAlt,
                      ),
                      child: CourtIcon(
                        glyph!,
                        size: 20,
                        color: palette.accent,
                        strokeWidth: 2.6,
                      ),
                    )
                  : SueAvatar(name: name, size: 44),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: context.colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? SueTone.blue.tint(context)
                : context.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? palette.accent : Colors.transparent,
              width: 2,
            ),
            boxShadow: courtHardShadow(context, dy: 4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (monogram != null)
                Text(
                  monogram!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                    color: selected ? palette.accent : palette.inkDim,
                  ),
                ),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.15,
                ),
              ),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: palette.inkDim),
              ),
            ],
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
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        boxShadow: courtHardShadow(context, dy: 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: SueTone.teal.fg(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              selected?.name ?? 'No court',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          const CourtIcon(CourtGlyph.chevronDown, size: 12, strokeWidth: 3),
        ],
      ),
    ),
  );
}

/// "HOW PETTY IS IT?" — the plaintiff's own stake on the case.
///
/// A multiplier, not a label: claiming a bin-day dispute is world-ending pays
/// three times as much when the court agrees, and costs three times as much
/// when it does not.
class _PettyPicker extends StatelessWidget {
  const _PettyPicker({required this.level, required this.onPick});

  final int level;
  final ValueChanged<int> onPick;

  static const _levels = [
    (1, 'Mildly annoyed', '×1 XP'),
    (2, 'Genuinely upset', '×2 XP'),
    (3, 'This is war', '×3 XP'),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (value, label, multiplier) in _levels) ...[
        if (value > 1) const SizedBox(width: 10),
        Expanded(
          child: _PettyTile(
            value: value,
            label: label,
            multiplier: multiplier,
            selected: value == level,
            onTap: () => onPick(value),
          ),
        ),
      ],
    ],
  );
}

class _PettyTile extends StatelessWidget {
  const _PettyTile({
    required this.value,
    required this.label,
    required this.multiplier,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final String label;
  final String multiplier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (value) {
      1 => SueTone.teal,
      2 => SueTone.gold,
      _ => SueTone.orange,
    };
    final colour = tone.fg(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $multiplier',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? tone.tint(context)
                : context.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colour : Colors.transparent,
              width: selected ? 2 : courtBorderThin,
            ),
            boxShadow: selected ? null : courtHardShadow(context, dy: 4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // One flame per level: the row reads as a scale before it reads
              // as words.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < value; i++)
                    CourtIcon(
                      CourtGlyph.flame,
                      size: 14,
                      color: selected ? colour : context.palette.inkFaint,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? colour : context.colors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                multiplier,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: selected ? colour : context.palette.inkDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The filing key, with the price on it.
///
/// The cost is the player's own balance read back from the server, so the key
/// can say plainly when it cannot be pressed rather than failing on tap.
class _FilingKeyRow extends ConsumerWidget {
  const _FilingKeyRow({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  /// Kept in step with the server's own filing fee.
  static const cost = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(gameStateProvider).valueOrNull?.player.coins;
    final broke = coins != null && coins < cost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SueButton(
          label: label.toUpperCase(),
          height: 56,
          busy: busy,
          onPressed: broke ? null : onPressed,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SueCoin(size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                broke
                    ? 'Filing costs $cost coins — you have $coins'
                    : 'Filing costs $cost coins'
                          '${coins == null ? '' : ' · you have $coins'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: broke ? CourtColors.red : context.palette.inkDim,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
