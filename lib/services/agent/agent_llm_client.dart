import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:openrc/core/constants/app_constants.dart';
import 'package:openrc/models/agent_preset.dart';
import 'package:openrc/services/agent/agent_settings_store.dart';
import 'package:openrc/services/agent/agent_tool_executor.dart';

class AgentLlmException implements Exception {
  AgentLlmException(this.messageKey, {this.detail});

  final String messageKey;
  final String? detail;

  @override
  String toString() => messageKey;
}

class AgentLlmResponse {
  const AgentLlmResponse({
    this.assistantText,
    this.toolCalls = const [],
  });

  final String? assistantText;
  final List<AgentToolCall> toolCalls;
}

class AgentToolCall {
  const AgentToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;
}

class AgentLlmClient {
  AgentLlmClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 30),
                // Large models with tools can take a while to answer.
                receiveTimeout: const Duration(seconds: 120),
              ),
            );

  final Dio _dio;

  Future<AgentLlmResponse> chat({
    required AgentSettings settings,
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required CancelToken cancelToken,
  }) async {
    if (kIsWeb && settings.providerId == AgentProviderId.custom) {
      throw AgentLlmException('agent.errors.customWeb');
    }
    if (settings.effectiveStyle == AgentApiStyle.anthropic) {
      return _anthropic(
        settings: settings,
        apiKey: apiKey,
        messages: messages,
        cancelToken: cancelToken,
      );
    }
    return _openAiCompatible(
      settings: settings,
      apiKey: apiKey,
      messages: messages,
      cancelToken: cancelToken,
    );
  }

  String _baseUrl(AgentSettings settings) {
    if (kIsWeb && settings.preset.relaySlug != null) {
      return '${AppConstants.relayUrl}/llm/${settings.preset.relaySlug}';
    }
    return settings.effectiveBaseUrl;
  }

  Future<AgentLlmResponse> _openAiCompatible({
    required AgentSettings settings,
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required CancelToken cancelToken,
  }) async {
    final url = '${_baseUrl(settings)}/chat/completions';
    final headers = <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    if (settings.providerId == AgentProviderId.openrouter) {
      headers['HTTP-Referer'] = AppConstants.repoUrl;
      headers['X-Title'] = AppConstants.appName;
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {
          'model': settings.effectiveModel,
          'temperature': 0,
          'messages': messages,
          'tools': agentToolDefinitions(),
        },
        options: Options(headers: headers, responseType: ResponseType.json),
        cancelToken: cancelToken,
      );
      final choice = (response.data?['choices'] as List?)?.firstOrNull;
      if (choice is! Map<String, dynamic>) {
        throw AgentLlmException('agent.errors.empty');
      }
      final message = choice['message'] as Map<String, dynamic>? ?? {};
      final content = message['content'];
      final toolCallsRaw = message['tool_calls'] as List? ?? const [];
      final toolCalls = [
        for (final raw in toolCallsRaw)
          if (raw is Map<String, dynamic>)
            AgentToolCall(
              id: raw['id'] as String? ?? '',
              name: (raw['function'] as Map?)?['name'] as String? ?? '',
              argumentsJson:
                  (raw['function'] as Map?)?['arguments'] as String? ?? '{}',
            ),
      ];
      return AgentLlmResponse(
        assistantText: _openAiText(content),
        toolCalls: toolCalls,
      );
    } on DioException catch (e) {
      throw _mapDio(e);
    }
  }

  Future<AgentLlmResponse> _anthropic({
    required AgentSettings settings,
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    required CancelToken cancelToken,
  }) async {
    final url = '${_baseUrl(settings)}/v1/messages';
    final system = messages
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'])
        .join('\n');
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: {
          'model': settings.effectiveModel,
          'max_tokens': 4096,
          'temperature': 0,
          'system': system,
          'messages': anthropicMessagesFromOpenAi(messages),
          'tools': [
            for (final t in agentToolDefinitions())
              {
                'name': (t['function'] as Map)['name'],
                'description': (t['function'] as Map)['description'],
                'input_schema': (t['function'] as Map)['parameters'],
              },
          ],
        },
        options: Options(
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
        ),
        cancelToken: cancelToken,
      );
      final content = response.data?['content'] as List? ?? const [];
      String? text;
      final toolCalls = <AgentToolCall>[];
      for (final block in content) {
        if (block is! Map<String, dynamic>) continue;
        if (block['type'] == 'text') {
          text = (text ?? '') + (block['text'] as String? ?? '');
        } else if (block['type'] == 'tool_use') {
          toolCalls.add(
            AgentToolCall(
              id: block['id'] as String? ?? '',
              name: block['name'] as String? ?? '',
              argumentsJson: jsonEncode(block['input'] ?? {}),
            ),
          );
        }
      }
      return AgentLlmResponse(assistantText: text, toolCalls: toolCalls);
    } on DioException catch (e) {
      throw _mapDio(e);
    }
  }

  /// `content` is a string, or a list of parts on some compatible hosts.
  static String? _openAiText(Object? content) {
    if (content is String) return content;
    if (content is! List) return null;
    final text = [
      for (final part in content)
        if (part is Map && part['type'] == 'text' && part['text'] is String)
          part['text'] as String,
    ].join();
    return text.isEmpty ? null : text;
  }

  /// OpenAI-shaped messages → Anthropic Messages API (tool_use / tool_result).
  @visibleForTesting
  static List<Map<String, dynamic>> anthropicMessagesFromOpenAi(
    List<Map<String, dynamic>> messages,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      final role = m['role'];
      if (role == 'system') continue;
      if (role == 'tool') {
        final result = {
          'type': 'tool_result',
          'tool_use_id': m['tool_call_id'],
          'content': m['content'] ?? '',
        };
        if (out.isNotEmpty &&
            out.last['role'] == 'user' &&
            out.last['content'] is List) {
          (out.last['content'] as List).add(result);
        } else {
          out.add({
            'role': 'user',
            'content': [result],
          });
        }
        continue;
      }
      if (role == 'assistant' && m['tool_calls'] is List) {
        final content = <Map<String, dynamic>>[];
        final text = m['content'];
        if (text is String && text.isNotEmpty) {
          content.add({'type': 'text', 'text': text});
        }
        for (final raw in m['tool_calls'] as List) {
          if (raw is! Map) continue;
          final fn = raw['function'] as Map? ?? const {};
          Map<String, dynamic> input = const {};
          try {
            final decoded = jsonDecode(fn['arguments'] as String? ?? '{}');
            if (decoded is Map<String, dynamic>) input = decoded;
          } catch (_) {}
          content.add({
            'type': 'tool_use',
            'id': raw['id'],
            'name': fn['name'],
            'input': input,
          });
        }
        out.add({'role': 'assistant', 'content': content});
        continue;
      }
      out.add({
        'role': role == 'assistant' ? 'assistant' : 'user',
        'content': m['content'] ?? '',
      });
    }
    return out;
  }

  AgentLlmException _mapDio(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return AgentLlmException('agent.errors.stopped');
    }
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return AgentLlmException('agent.errors.badKey');
    }
    if (status == 429) return AgentLlmException('agent.errors.quota');
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AgentLlmException('agent.errors.network');
    }
    return AgentLlmException('agent.errors.generic');
  }
}
