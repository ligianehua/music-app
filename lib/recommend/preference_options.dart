import '../account/user.dart';

/// 偏好设置页上可选的语言。
const languageOptions = ['华语', '粤语', '欧美', '日语', '韩语'];

/// 可选的风格。
const genreOptions = [
  '流行', '摇滚', '民谣', '电子', 'R&B', '说唱', '古风', '爵士', '轻音乐', 'City Pop', 'Lo-fi',
];

/// 按语言分组的歌手候选。没选语言时展示全部。
const artistOptionsByLanguage = <String, List<String>>{
  '华语': [
    '周杰伦', '林俊杰', '陈奕迅', '邓紫棋', '五月天', '孙燕姿', '王菲', '毛不易',
    '李荣浩', '薛之谦', '告五人', '陶喆', '蔡依林', '方大同', '张惠妹', '汪苏泷',
  ],
  '粤语': ['张学友', 'Beyond', '杨千嬅', '容祖儿', '张天赋', 'Dear Jane', '谢安琪'],
  '欧美': [
    'Taylor Swift', 'The Weeknd', 'Billie Eilish', 'Coldplay', 'Bruno Mars',
    'Ed Sheeran', 'Olivia Rodrigo', 'Dua Lipa',
  ],
  '日语': ['米津玄師', 'YOASOBI', 'Aimer', 'King Gnu', '宇多田ヒカル', 'Official髭男dism'],
  '韩语': ['NewJeans', 'IU', 'BLACKPINK', 'BTS', 'aespa', 'SEVENTEEN'],
};

/// 网红热歌榜拉不到时的兜底：短视频平台上常见的网络歌手。
const viralFallbackArtists = [
  '王贰浪', '阿冗', '海来阿木', '任然', '承桓', '刘大壮', '颜人中', '小阿七', '半吨兄弟',
];

/// 按已选语言列出歌手候选，去重并保持顺序。
List<String> artistOptionsFor(Set<String> languages) {
  final groups = languages.isEmpty
      ? artistOptionsByLanguage.values
      : [for (final l in languageOptions) if (languages.contains(l)) artistOptionsByLanguage[l]!];
  final seen = <String>{};
  return [for (final g in groups) for (final a in g) if (seen.add(a)) a];
}

/// 每种语言没有选风格时的默认搜索词。
const _languageDefaultTerm = {
  '华语': '华语流行',
  '粤语': '粤语流行',
  '欧美': 'pop hits',
  '日语': 'J-Pop',
  '韩语': 'K-Pop',
};

/// 风格在欧美曲库里的英文说法。
const _genreEnglish = {
  '流行': 'pop', '摇滚': 'rock', '民谣': 'folk', '电子': 'electronic',
  'R&B': 'R&B', '说唱': 'hip hop', '古风': '古风', '爵士': 'jazz',
  '轻音乐': 'piano', 'City Pop': 'city pop', 'Lo-fi': 'lofi',
};

/// 把偏好翻译成推荐器用的搜索词：歌手名、「语言 + 风格」组合、语言默认词。
List<String> preferenceSeeds(UserPreferences p) {
  final terms = <String>{...p.artists};
  final langs = [for (final l in languageOptions) if (p.languages.contains(l)) l];
  final genres = [for (final g in genreOptions) if (p.genres.contains(g)) g];
  if (langs.isEmpty) {
    terms.addAll(genres);
  } else {
    for (final l in langs) {
      if (genres.isEmpty) {
        terms.add(_languageDefaultTerm[l]!);
        continue;
      }
      for (final g in genres) {
        terms.add(switch (l) {
          '欧美' => _genreEnglish[g]!,
          '日语' => 'J-${_genreEnglish[g]}',
          '韩语' => 'K-${_genreEnglish[g]}',
          _ => '$l$g',
        });
      }
    }
  }
  return terms.toList();
}
