import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openrc/core/utils/plan_display.dart';
import 'package:openrc/core/utils/product_label_suggest.dart';
import 'package:openrc/services/agent/agent_conversation_runner.dart';
import 'package:openrc/services/agent/agent_llm_client.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';

/// How many products one run may name.
const kProductLabelSuggestionMax = 200;

/// How many ids travel in one model request.
const kProductLabelSuggestionChunk = 40;

/// A name for one product, from the model or the built-in parser.
class ProductLabelSuggestion {
  const ProductLabelSuggestion({
    required this.productId,
    this.name,
    this.plan,
    this.fromAi = false,
  });

  final String productId;
  final String? name;
  final String? plan;

  /// True when the model named it, false for the parser.
  final bool fromAi;
}

final productLabelSuggesterProvider = Provider<ProductLabelSuggester>(
  (ref) => ProductLabelSuggester(ref),
);

/// Names product ids with the connected model, falling back to the built-in
/// parser for ids the model skips or when its answer isn't usable.
class ProductLabelSuggester {
  ProductLabelSuggester(this._ref);

  final Ref _ref;

  /// Names that need no model: offline, instant, and the fallback. Only the
  /// billing period the id names (`Monthly`, `1 Year`, ...), never a guess at
  /// the product's own name. That period doubles as the plan family, so
  /// every monthly product counts as one plan rather than several rows
  /// labelled `Monthly`.
  static List<ProductLabelSuggestion> local(Iterable<String> productIds) {
    final out = <ProductLabelSuggestion>[];
    for (final id in _unique(productIds)) {
      final period = suggestProductPeriod(id);
      final label = period == null ? null : productPeriodName(period);
      out.add(
        ProductLabelSuggestion(productId: id, name: label, plan: label),
      );
    }
    return out;
  }

  Future<List<ProductLabelSuggestion>> suggest({
    required Iterable<String> productIds,
    required CancelToken cancelToken,
    void Function(int done, int total)? onProgress,
  }) async {
    final settings = await _ref.read(agentSettingsProvider.future);
    final apiKey = await _ref
        .read(agentSettingsProvider.notifier)
        .readApiKey(settings.providerId);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw AgentLlmException('agent.errors.noKey');
    }

    final ids = _unique(productIds).take(kProductLabelSuggestionMax).toList();
    if (ids.isEmpty) return const [];

    // Start from the parser so every id has a name even if the model fails.
    final byId = {
      for (final s in local(ids)) s.productId: s,
    };

    final client = _ref.read(agentLlmClientProvider);
    var done = 0;
    onProgress?.call(done, ids.length);
    for (var i = 0; i < ids.length; i += kProductLabelSuggestionChunk) {
      if (cancelToken.isCancelled) {
        throw AgentLlmException('agent.errors.stopped');
      }
      final chunk = ids.sublist(
        i,
        (i + kProductLabelSuggestionChunk).clamp(0, ids.length),
      );
      final parsed = await _askChunk(
        client: client,
        settings: settings,
        apiKey: apiKey.trim(),
        chunk: chunk,
        cancelToken: cancelToken,
      );
      for (final entry in parsed.entries) {
        final fallback = byId[entry.key];
        byId[entry.key] = ProductLabelSuggestion(
          productId: entry.key,
          name: entry.value.name ?? fallback?.name,
          plan: entry.value.plan,
          fromAi: entry.value.name != null || entry.value.plan != null,
        );
      }
      done += chunk.length;
      onProgress?.call(done, ids.length);
    }

    return [for (final id in ids) byId[id]!];
  }

  /// One model request; an unusable answer falls back to the parser's names
  /// rather than failing the whole run.
  Future<Map<String, ProductLabelSuggestionDraft>> _askChunk({
    required AgentLlmClient client,
    required AgentSettings settings,
    required String apiKey,
    required List<String> chunk,
    required CancelToken cancelToken,
  }) async {
    final response = await client.complete(
      settings: settings,
      apiKey: apiKey,
      cancelToken: cancelToken,
      messages: [
        {'role': 'system', 'content': _systemPrompt},
        {
          'role': 'user',
          'content': jsonEncode({'products': chunk}),
        },
      ],
    );
    final text = response.assistantText ?? '';
    try {
      return parseProductLabelSuggestions(text, chunk.toSet());
    } on FormatException {
      return const {};
    }
  }

  static const _systemPrompt =
      'You name in-app purchase products for a RevenueCat dashboard. '
      'The developer of this app sees the names you give, not end customers.\n'
      'Answer with JSON only, no prose and no code fence: '
      '{"labels":[{"id":"<exact id>","name":"<name>","plan":"<plan>"}]}\n'
      'Rules:\n'
      '- Echo every id exactly as given, once.\n'
      '- name: 1 to 3 words, Title Case, at most 24 characters. Name the plan, '
      'not the billing period, so "pro.sub.annual" is "Pro", not '
      '"Pro Annual"; the app already shows the period.\n'
      '- plan: the plan family shared by variants, so a monthly and an annual '
      'product get the same plan, at most 24 characters. Use null when unsure.\n'
      '- Never use emoji, quotes, prices, store names, or technical tokens '
      '(sub, product, false), and drop the app or bundle prefix.\n'
      '- Use null for a name you cannot read; do not invent features.';

  static Iterable<String> _unique(Iterable<String> ids) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(id);
    }
    return out;
  }
}
