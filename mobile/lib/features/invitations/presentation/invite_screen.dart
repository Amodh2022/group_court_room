import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_layout.dart';
import '../../../core/widgets/court_widgets.dart';

/// Shown once, immediately after filing.
///
/// Both raw tokens are returned only by POST /cases, so this screen receives
/// them via router `extra` rather than re-fetching the case. Two links, two
/// audiences: one person answers the charge, everyone else votes on it.
class InviteScreen extends ConsumerWidget {
  const InviteScreen({super.key, required this.caseId, this.created});

  final String caseId;
  final CaseDetail? created;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = created?.inviteUrl;
    final juryUrl = created?.juryUrl;

    return CourtScaffold(
      title: 'Summons issued',
      automaticallyImplyLeading: false,
      body: url == null
          ? CourtNotice(
              icon: Icons.link_off,
              title: 'This summons link is gone',
              message:
                  'A summons link is shown only once, when the case is filed. '
                  'Open the case to check whether a defense has arrived.',
              action: FilledButton(
                onPressed: () => context.go('/cases/$caseId'),
                child: const Text('Open the case'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                PageTitle(
                  label: 'Case filed',
                  title: 'Summon the defendant',
                  subtitle:
                      'Two links go out. One summons '
                      '${created!.defendantNickname ?? 'your friend'} to answer '
                      'the charge; the other seats the rest of the group as the '
                      'jury. Nobody sees the ruling until they have voted.',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.palette.surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionLabel('In the matter of'),
                            const SizedBox(height: 6),
                            Text(
                              created!.title,
                              style: context.text.titleLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _LinkCard(
                        spine: context.palette.accent,
                        child: ShareableLink(
                          label: 'Summons',
                          url: url,
                          hint:
                              'For the accused only — whoever opens it writes '
                              'the defense.',
                          onShare: () => SharePlus.instance.share(
                            ShareParams(
                              text:
                                  'You have been summoned to Group Chat '
                                  'Court: "${created!.title}". '
                                  'Defend yourself: $url',
                              subject:
                                  'Group Chat Court — you have been summoned',
                            ),
                          ),
                        ),
                      ),
                      if (juryUrl != null) ...[
                        const SizedBox(height: 14),
                        _LinkCard(
                          spine: CourtColors.greenFill,
                          child: ShareableLink(
                            label: 'Jury summons',
                            url: juryUrl,
                            hint:
                                'Drop this in the group chat. Everyone votes '
                                'guilty or not guilty before the verdict '
                                'unlocks.',
                            onShare: () => SharePlus.instance.share(
                              ShareParams(
                                text:
                                    'Jury duty: "${created!.title}" is in '
                                    'Group Chat Court. Vote before the '
                                    'verdict drops: $juryUrl',
                                subject:
                                    'Group Chat Court — you are on the jury',
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Summons link copied.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('Copy the summons link'),
                      ),
                      const SizedBox(height: 22),
                      // The way forward is the loudest thing on the screen: the
                      // share buttons above are secondary, this is "I am done".
                      FilledButton.icon(
                        key: const Key('summons-done'),
                        onPressed: () => context.go('/cases/$caseId'),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Done — track this case'),
                      ),
                      CourtDisclaimer(
                        text:
                            'Anyone with the summons link can file the defense, '
                            'so send that one only to the person you are '
                            'accusing. The jury link is safe to post anywhere '
                            'your friends are. Both expire '
                            '${created!.expiresAt == null ? 'in a few days' : 'soon'}.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// A link card with a coloured edge: blue for the accused, green for the jury.
class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.spine, required this.child});

  final Color spine;
  final Widget child;

  @override
  Widget build(BuildContext context) => SpineCard(spine: spine, child: child);
}
