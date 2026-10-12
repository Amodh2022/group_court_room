import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/court_people.dart';
import '../../auth/data/auth_providers.dart';

/// Search people by handle (or exact email) and pick one.
Future<UserRef?> pickUser(
  BuildContext context, {
  String title = 'Find someone',
}) {
  return showModalBottomSheet<UserRef>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    builder: (_) => _UserSearch(title: title),
  );
}

class _UserSearch extends ConsumerStatefulWidget {
  const _UserSearch({required this.title});

  final String title;

  @override
  ConsumerState<_UserSearch> createState() => _UserSearchState();
}

class _UserSearchState extends ConsumerState<_UserSearch> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<UserRef> _results = const [];
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() {
      _query = q;
      _error = null;
      if (q.length < 2) _results = const [];
    });
    if (q.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final found = await ref.read(apiClientProvider).searchUsers(q);
      if (!mounted || q != _query) return;
      setState(() {
        _results = found;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SizedBox(
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: context.text.headlineSmall),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Handle or exact email',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: TextStyle(color: CourtColors.guilty)),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _query.length < 2
                          ? 'Type at least 2 characters.'
                          : (_loading ? '' : 'Nobody found.'),
                      style: TextStyle(color: context.palette.inkDim),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final u = _results[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AvatarTile(name: u.displayName, size: 44),
                        title: Text(u.displayName),
                        subtitle: Text('@${u.handle}'),
                        onTap: () => Navigator.of(context).pop(u),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
