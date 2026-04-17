class RcErrorResponse {
  final int? code;
  final String? message;

  const RcErrorResponse({this.code, this.message});

  factory RcErrorResponse.fromJson(Map<String, dynamic> json) =>
      RcErrorResponse(
        code: json['code'] as int?,
        message: json['message'] as String?,
      );
}
