import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/text/search_text.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';

void main() {
  test('Arabic letters match whichever form was written', () {
    expect(matchesSearch('الصلاة', ['فضل الصلاه في المسجد']), isTrue);
    expect(matchesSearch('احمد', ['محاضرة الشيخ أحمد']), isTrue);
    expect(matchesSearch('مُحَمَّد', ['قصة محمد']), isTrue);
    expect(matchesSearch('على', ['هدية الي علي']), isTrue);
  });

  test('every word must appear, in any field and any case', () {
    expect(
      matchesSearch('Chicken recipe', ['#viral', 'easy RECIPE with chicken']),
      isTrue,
    );
    expect(
      matchesSearch('chicken soup', ['easy recipe with chicken']),
      isFalse,
    );
    expect(matchesSearch('  ', ['anything']), isTrue);
    expect(matchesSearch('x', [null, 'box']), isTrue);
  });

  test('a download keeps its post text and date', () {
    final task = DownloadTask.fromMap({
      'id': 'a',
      'url': 'https://x.com/a/status/1',
      'title': '#viral',
      'platform': 'x',
      'createdAt': 0,
      'caption': 'Easy chicken recipe',
      'postedAt': DateTime(2026, 11, 20).millisecondsSinceEpoch,
    });
    final again = DownloadTask.fromMap(task.toMap());
    expect(again.caption, 'Easy chicken recipe');
    expect(again.postedAt, DateTime(2026, 11, 20));
  });
}
