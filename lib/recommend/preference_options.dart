import '../account/user.dart';

/// 偏好设置页上可选的语言（面向菲律宾和全球用户）。
const languageOptions = [
  'English', 'Filipino', 'Korean', 'Japanese', 'Spanish', 'Mandarin',
];

/// 可选的风格。
const genreOptions = [
  'Pop', 'Rock', 'Hip-Hop', 'R&B', 'Indie', 'Acoustic', 'Electronic',
  'Jazz', 'Lo-fi', 'Country', 'Latin',
];

/// 按语言分组的歌手候选。没选语言时展示全部。
const artistOptionsByLanguage = <String, List<String>>{
  'English': [
    'Taylor Swift', 'Olivia Rodrigo', 'Sabrina Carpenter', 'The Weeknd',
    'Billie Eilish', 'Bruno Mars', 'Ed Sheeran', 'Dua Lipa', 'Ariana Grande',
    'Coldplay',
  ],
  'Filipino': [
    'Ben&Ben', 'SB19', 'BINI', 'Moira Dela Torre', 'Zack Tabudlo',
    'December Avenue', 'Arthur Nery', 'Adie', 'Cup of Joe', 'Juan Karlos',
  ],
  'Korean': ['NewJeans', 'BLACKPINK', 'BTS', 'IU', 'aespa', 'SEVENTEEN', 'Stray Kids'],
  'Japanese': ['YOASOBI', 'Kenshi Yonezu', 'Aimer', 'King Gnu', 'Official HIGE DANDism'],
  'Spanish': ['Bad Bunny', 'Shakira', 'Karol G', 'Rosalía', 'Peso Pluma'],
  'Mandarin': ['Jay Chou', 'JJ Lin', 'G.E.M.', 'Eason Chan', 'Mayday'],
};

/// 热歌榜拉不到时的兜底：短视频平台上常见的走红歌手。
const viralFallbackArtists = [
  'Sabrina Carpenter', 'Benson Boone', 'Chappell Roan', 'Tate McRae',
  'Gracie Abrams', 'Alex Warren', 'Cup of Joe', 'Dionela', 'Arthur Nery',
];

/// 按已选语言列出歌手候选，去重并保持顺序。
List<String> artistOptionsFor(Set<String> languages) {
  final groups = languages.isEmpty
      ? artistOptionsByLanguage.values
      : [
          for (final l in languageOptions)
            if (languages.contains(l)) artistOptionsByLanguage[l]!,
        ];
  final seen = <String>{};
  return [for (final g in groups) for (final a in g) if (seen.add(a)) a];
}

/// 每种语言没有选风格时的默认搜索词。
const _languageDefaultTerm = {
  'English': 'pop hits',
  'Filipino': 'OPM',
  'Korean': 'K-Pop',
  'Japanese': 'J-Pop',
  'Spanish': 'latin pop',
  'Mandarin': 'Mandopop',
};

/// 「语言 + 风格」在曲库里的搜索说法。
String _phrase(String language, String genre) {
  final g = genre.toLowerCase();
  return switch (language) {
    'English' => g,
    'Filipino' => 'OPM $g',
    'Korean' => 'K-$g',
    'Japanese' => 'J-$g',
    'Spanish' => 'latin $g',
    'Mandarin' => 'Mandarin $g',
    _ => g,
  };
}

/// 把偏好翻译成推荐器用的搜索词：歌手名、「语言 + 风格」组合、语言默认词。
List<String> preferenceSeeds(UserPreferences p) {
  final terms = <String>{...p.artists};
  final langs = [for (final l in languageOptions) if (p.languages.contains(l)) l];
  final genres = [for (final g in genreOptions) if (p.genres.contains(g)) g];
  if (langs.isEmpty) {
    terms.addAll(genres.map((g) => g.toLowerCase()));
  } else {
    for (final l in langs) {
      if (genres.isEmpty) {
        terms.add(_languageDefaultTerm[l]!);
      } else {
        terms.addAll(genres.map((g) => _phrase(l, g)));
      }
    }
  }
  return terms.toList();
}
