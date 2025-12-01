class BannerModel {
  BannerModel({
    required this.id,
    required this.imageUrl,
    this.linkUrl,
    required this.order,
    required this.isActive,
  });

  factory BannerModel.fromFirestore(Map<String, dynamic> data, String id) {
    return BannerModel(
      id: id,
      imageUrl: data['imageUrl'] as String? ?? '',
      linkUrl: data['linkUrl'] as String?,
      order: data['order'] as int? ?? 0,
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  final String id;
  final String imageUrl;
  final String? linkUrl;
  final int order;
  final bool isActive;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'imageUrl': imageUrl,
      'linkUrl': linkUrl,
      'order': order,
      'isActive': isActive,
    };
  }
}

