import 'dart:ui' show Color;

class Chapter {
  final String title;
  final double start;
  final double end;
  const Chapter(this.title, this.start, this.end);

  double get length => end - start;

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        (j['title'] ?? '') as String,
        (j['start'] as num).toDouble(),
        (j['end'] as num).toDouble(),
      );
}

class AudioFileInfo {
  final int index;
  final int size;
  final double duration;
  final String mime;
  final String ext;
  const AudioFileInfo(this.index, this.size, this.duration, this.mime, this.ext);

  factory AudioFileInfo.fromJson(Map<String, dynamic> j) => AudioFileInfo(
        j['index'] as int,
        j['size'] as int,
        (j['duration'] as num).toDouble(),
        (j['mime'] ?? 'audio/mpeg') as String,
        (j['ext'] ?? 'mp3') as String,
      );
}

class Book {
  final String id;
  final String title;
  final String author;
  final String? narrator;
  final String? series;
  final String? seriesPart;
  final String? description;
  final String? genre;
  final String? year;
  final String? language;
  final String? publisher;
  final double duration;
  final List<AudioFileInfo> files;
  final List<Chapter> chapters;
  final bool hasCover;
  final Color? coverColor;
  final int addedAt;

  Book({
    required this.id,
    required this.title,
    required this.author,
    this.narrator,
    this.series,
    this.seriesPart,
    this.description,
    this.genre,
    this.year,
    this.language,
    this.publisher,
    required this.duration,
    required this.files,
    required this.chapters,
    required this.hasCover,
    this.coverColor,
    required this.addedAt,
  });

  int get totalSize => files.fold(0, (a, f) => a + f.size);

  /// Series number as a sortable value ("2", "2.5", "Band 3" → 3).
  double get seriesIndex {
    final m = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(seriesPart ?? '');
    return m == null ? 9999 : double.parse(m.group(1)!.replaceAll(',', '.'));
  }

  /// Series name without a trailing number some taggers append ("Ilium & Olympos 1").
  String? get seriesName {
    if (series == null) return null;
    final s = series!.replaceFirst(RegExp(r'\s+\d+$'), '').trim();
    return s.isEmpty ? series : s;
  }

  String? get seriesLabel {
    if (seriesName == null) return null;
    final part = seriesPart ?? RegExp(r'\s(\d+)$').firstMatch(series!)?.group(1);
    return part == null ? seriesName : '$seriesName · Band $part';
  }

  int chapterIndexAt(double pos) {
    for (var i = chapters.length - 1; i >= 0; i--) {
      if (pos >= chapters[i].start - 0.5) return i;
    }
    return 0;
  }

  /// Maps a global position to (file index, offset inside file).
  (int, double) locate(double pos) {
    var acc = 0.0;
    for (var i = 0; i < files.length; i++) {
      if (pos < acc + files[i].duration || i == files.length - 1) {
        return (i, (pos - acc).clamp(0, files[i].duration));
      }
      acc += files[i].duration;
    }
    return (0, 0);
  }

  double fileOffset(int index) {
    var acc = 0.0;
    for (var i = 0; i < index && i < files.length; i++) {
      acc += files[i].duration;
    }
    return acc;
  }

  factory Book.fromJson(Map<String, dynamic> j) {
    Color? color;
    final c = j['cover_color'] as String?;
    if (c != null && c.length == 7) {
      color = Color(int.parse('FF${c.substring(1)}', radix: 16));
    }
    return Book(
      id: j['id'] as String,
      title: (j['title'] ?? '') as String,
      author: (j['author'] ?? 'Unbekannt') as String,
      narrator: j['narrator'] as String?,
      series: j['series'] as String?,
      seriesPart: j['series_part'] as String?,
      description: j['description'] as String?,
      genre: j['genre'] as String?,
      year: j['year'] as String?,
      language: j['language'] as String?,
      publisher: j['publisher'] as String?,
      duration: (j['duration'] as num).toDouble(),
      files: (j['files'] as List).map((e) => AudioFileInfo.fromJson(e)).toList(),
      chapters: (j['chapters'] as List).map((e) => Chapter.fromJson(e)).toList(),
      hasCover: (j['has_cover'] ?? false) as bool,
      coverColor: color,
      addedAt: (j['added_at'] ?? 0) as int,
    );
  }
}

class Progress {
  final String bookId;
  final double position;
  final bool finished;
  final int updatedAt; // ms
  final String? device;
  const Progress(this.bookId, this.position, this.finished, this.updatedAt, [this.device]);

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        j['book_id'] as String,
        (j['position'] as num).toDouble(),
        (j['finished'] ?? false) as bool,
        j['updated_at'] as int,
        j['device'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'book_id': bookId,
        'position': position,
        'finished': finished,
        'updated_at': updatedAt,
        'device': device,
      };
}

class UserInfo {
  final int id;
  final String username;
  final String displayName;
  final bool isAdmin;
  final int? lastSeen;
  final int? avatarVersion;
  const UserInfo(this.id, this.username, this.displayName, this.isAdmin, [this.lastSeen, this.avatarVersion]);

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        j['id'] as int,
        j['username'] as String,
        (j['display_name'] ?? j['username']) as String,
        (j['is_admin'] ?? false) as bool,
        j['last_seen'] as int?,
        j['avatar_version'] as int?,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'username': username, 'display_name': displayName, 'is_admin': isAdmin, 'avatar_version': avatarVersion};
}
