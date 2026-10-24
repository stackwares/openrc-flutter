/// How a URL or notification wants Ask or a sale opened.
class AskLaunch {
  const AskLaunch({
    this.prompt,
    this.transactionId,
    this.openAsk = false,
  });

  /// Prefill for the Ask composer. Never includes the RevenueCat session.
  final String? prompt;

  /// Store transaction id, already sent in the notification payload.
  final String? transactionId;

  /// Jump to the Ask tab instead of (or before) opening the sale.
  final bool openAsk;

  bool get isEmpty =>
      (prompt == null || prompt!.isEmpty) &&
      (transactionId == null || transactionId!.isEmpty) &&
      !openAsk;

  static const maxPromptChars = 400;
  static const maxTransactionIdChars = 200;

  /// `?ask=how+was+today`, `?ask=1&transaction=…`, or `?transaction=…`.
  static AskLaunch fromQuery(Map<String, String> query) {
    final rawAsk = query['ask']?.trim();
    final transaction = boundedId(query['transaction']);
    if (rawAsk == null || rawAsk.isEmpty) {
      return AskLaunch(transactionId: transaction);
    }
    final flag = rawAsk == '1' || rawAsk.toLowerCase() == 'true';
    if (flag) {
      return AskLaunch(transactionId: transaction, openAsk: true);
    }
    return AskLaunch(
      prompt: sanitizePrompt(rawAsk),
      transactionId: transaction,
      openAsk: true,
    );
  }

  static String? sanitizePrompt(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return null;
    return collapsed.length <= maxPromptChars
        ? collapsed
        : collapsed.substring(0, maxPromptChars);
  }

  static String? boundedId(String? raw) {
    final id = raw?.trim();
    if (id == null || id.isEmpty) return null;
    return id.length <= maxTransactionIdChars
        ? id
        : id.substring(0, maxTransactionIdChars);
  }
}
