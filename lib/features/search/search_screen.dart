import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/core/utils/api_error_message.dart';
import 'package:openrc/features/search/transaction_search.dart';
import 'package:openrc/features/transactions/transaction_detail_screen.dart';
import 'package:openrc/features/transactions/widgets/transaction_item.dart';
import 'package:openrc/models/rc_project.dart';
import 'package:openrc/models/rc_transaction.dart';
import 'package:openrc/services/product_labels_store.dart';
import 'package:openrc/services/rc_account_projects_provider.dart';
import 'package:openrc/services/rc_api_service.dart';
import 'package:openrc/services/telemetry.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/search_field_decoration.dart';
import 'package:openrc/widgets/side_panel.dart';

/// Opens search full screen, over the tabs.
Future<void> openSearch(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const SearchScreen()));

/// Finds loaded transactions by transaction id, customer, product, project,
/// store or country, and looks a customer up on RevenueCat by id.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );

  /// Project picked for the customer lookup; null follows the default.
  String? _lookupProjectId;
  bool _lookupBusy = false;
  String? _lookupError;

  @override
  void initState() {
    super.initState();
    Telemetry.screen('Search');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _query => _controller.text.trim();

  void _onChanged(String _) => setState(() => _lookupError = null);

  /// The picked project, else the one a loaded sale of this customer is in,
  /// else the first project.
  RcProject? _lookupProject(
    List<RcProject> projects,
    List<RcTransaction> pool,
  ) {
    if (projects.isEmpty) return null;
    RcProject? byId(String? id) {
      for (final p in projects) {
        if (p.id != null && p.id == id) return p;
      }
      return null;
    }

    final picked = byId(_lookupProjectId);
    if (picked != null) return picked;
    for (final tx in pool) {
      if (tx.subscriberId == _query) {
        final p = byId(tx.app?.id);
        if (p != null) return p;
      }
    }
    return projects.first;
  }

  Future<void> _lookUp(RcProject project, List<RcTransaction> pool) async {
    final id = _query;
    final projectId = project.id;
    if (projectId == null || id.isEmpty || _lookupBusy) return;

    // A sale already loaded opens with its full details, no request needed.
    final loaded = newestLoadedForCustomer(
      pool,
      projectId: projectId,
      subscriberId: id,
    );
    if (loaded != null) {
      _open(loaded);
      return;
    }

    setState(() {
      _lookupBusy = true;
      _lookupError = null;
    });
    try {
      await ref
          .read(rcApiServiceProvider)
          .transactionDetail(projectId: projectId, subscriberId: id);
      if (!mounted) return;
      setState(() => _lookupBusy = false);
      _open(
        RcTransaction(
          app: RcTransactionApp(id: projectId, name: project.name),
          subscriberId: id,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final notFound = e.response?.statusCode == 404;
      setState(() {
        _lookupBusy = false;
        _lookupError = notFound
            ? 'search.customerNotFound'.tr(
                namedArgs: {'project': project.name ?? ''},
              )
            : friendlyApiErrorMessage(
                e,
                serverMessage: ref
                    .read(rcApiServiceProvider)
                    .parseError(e)
                    ?.message,
              );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lookupBusy = false;
        _lookupError = friendlyApiErrorMessage(e);
      });
    }
  }

  void _open(RcTransaction tx) =>
      openDetail(context, (_) => TransactionDetailScreen(transaction: tx));

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final pool = ref.watch(searchPoolProvider);
    final labels = ref.watch(productLabelsProvider);
    final projects =
        ref.watch(rcAccountProjectsProvider).asData?.value ?? const [];
    final query = _query;
    final result = searchTransactions(pool, query, labels: labels);
    final project = _lookupProject(projects, pool);
    final showLookup = canLookUpCustomer(query) && project != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (_) {
              if (result.total == 0 && showLookup) _lookUp(project, pool);
            },
            decoration: searchFieldDecoration(scheme, 'search.hint'.tr())
                .copyWith(
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'search.clear'.tr(),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              top: 8,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              if (query.isEmpty)
                _Hint(loadedCount: pool.length)
              else ...[
                if (showLookup)
                  _CustomerLookupCard(
                    customerId: query,
                    project: project,
                    projects: projects,
                    busy: _lookupBusy,
                    error: _lookupError,
                    onProjectChanged: (p) => setState(() {
                      _lookupProjectId = p.id;
                      _lookupError = null;
                    }),
                    onLookUp: () => _lookUp(project, pool),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    result.total == 0
                        ? 'search.noMatches'.tr()
                        : result.total > result.matches.length
                        ? 'search.matchesCapped'.tr(
                            namedArgs: {
                              'shown': '${result.matches.length}',
                              'total': '${result.total}',
                            },
                          )
                        : 'search.matches'.plural(result.total),
                    style: context.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (result.matches.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpace.gutter,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, tx) in result.matches.indexed) ...[
                          if (i > 0)
                            const Divider(indent: kTransactionRowDividerIndent),
                          TransactionItem(
                            transaction: tx,
                            onTap: () => _open(tx),
                          ),
                        ],
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    'search.scopeNote'.tr(),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.loadedCount});

  final int loadedCount;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final muted = context.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.manage_search_rounded, size: 40, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'search.emptyTitle'.tr(),
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text('search.emptyBody'.tr(), style: muted),
          const SizedBox(height: 12),
          Text(
            'search.loadedCount'.plural(loadedCount),
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerLookupCard extends StatelessWidget {
  const _CustomerLookupCard({
    required this.customerId,
    required this.project,
    required this.projects,
    required this.busy,
    required this.error,
    required this.onProjectChanged,
    required this.onLookUp,
  });

  final String customerId;
  final RcProject project;
  final List<RcProject> projects;
  final bool busy;
  final String? error;
  final ValueChanged<RcProject> onProjectChanged;
  final VoidCallback onLookUp;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final projectName = project.name ?? project.id ?? '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: busy ? null : onLookUp,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Icon(Icons.person_search_rounded, color: scheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'search.lookUpCustomer'.tr(),
                          style: context.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          customerId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            child: Row(
              children: [
                Text(
                  'search.inProject'.tr(),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: projects.length < 2
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            projectName,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : PopupMenuButton<RcProject>(
                          tooltip: 'search.pickProject'.tr(),
                          onSelected: onProjectChanged,
                          itemBuilder: (_) => [
                            for (final p in projects)
                              CheckedPopupMenuItem(
                                value: p,
                                checked: p.id == project.id,
                                child: Text(p.name ?? p.id ?? ''),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    projectName,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textTheme.bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: scheme.primary,
                                        ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down_rounded,
                                  color: scheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                error!,
                style: context.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
