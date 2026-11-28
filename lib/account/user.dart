/// 听歌偏好：注册后选，之后可在「我的」里修改。推荐器用它做冷启动。
class UserPreferences {
  const UserPreferences({
    this.languages = const {},
    this.genres = const {},
    this.artists = const {},
    this.viral = false,
  });

  /// 语言，取值见 `preference_options.dart` 的 [languageOptions]。
  final Set<String> languages;

  /// 风格。
  final Set<String> genres;

  /// 喜欢的歌手。
  final Set<String> artists;

  /// 是否多推网红热歌。
  final bool viral;

  bool get isEmpty =>
      languages.isEmpty && genres.isEmpty && artists.isEmpty && !viral;

  UserPreferences copyWith({
    Set<String>? languages,
    Set<String>? genres,
    Set<String>? artists,
    bool? viral,
  }) =>
      UserPreferences(
        languages: languages ?? this.languages,
        genres: genres ?? this.genres,
        artists: artists ?? this.artists,
        viral: viral ?? this.viral,
      );

  Map<String, dynamic> toJson() => {
        'languages': languages.toList(),
        'genres': genres.toList(),
        'artists': artists.toList(),
        'viral': viral,
      };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    Set<String> set(Object? v) =>
        {...((v as List?) ?? const []).map((e) => '$e')};
    return UserPreferences(
      languages: set(json['languages']),
      genres: set(json['genres']),
      artists: set(json['artists']),
      viral: json['viral'] == true,
    );
  }
}

/// 一个会员账号。
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.createdAt,
    this.preferences = const UserPreferences(),
  });

  final String id;
  final String username;
  final DateTime createdAt;
  final UserPreferences preferences;

  /// 注册后还没选过偏好：要先进偏好设置页。
  bool get needsOnboarding => preferences.isEmpty;

  AppUser copyWith({UserPreferences? preferences}) => AppUser(
        id: id,
        username: username,
        createdAt: createdAt,
        preferences: preferences ?? this.preferences,
      );
}
