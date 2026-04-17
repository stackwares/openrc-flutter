class RcProject {
  final String? iconUrl;
  final String? id;
  final String? name;

  const RcProject({this.iconUrl, this.id, this.name});

  factory RcProject.fromJson(Map<String, dynamic> json) => RcProject(
    iconUrl: json['icon_url'] as String?,
    id: json['id'] as String?,
    name: json['name'] as String?,
  );
}
