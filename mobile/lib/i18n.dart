// Arabic / English. The choice is saved on the device; switching rebuilds the whole app.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Lang extends ValueNotifier<String> {
  static final Lang I = Lang._();
  Lang._() : super('ar');

  bool get isEn => value == 'en';

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      value = p.getString('one.lang') ?? 'ar';
    } catch (_) {}
  }

  Future<void> toggle() async {
    value = isEn ? 'ar' : 'en';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('one.lang', value);
    } catch (_) {}
  }
}

/// Pick the Arabic or English text for the current language.
String tr(String ar, String en) => Lang.I.isEn ? en : ar;

/// Alarm text in the employee's language (English fields fall back to Arabic).
String alarmTitle(Map<String, dynamic> a) {
  final en = a['title_en'] as String?;
  return Lang.I.isEn && en != null && en.trim().isNotEmpty ? en : (a['title'] as String? ?? '');
}

String alarmBody(Map<String, dynamic> a) {
  final en = a['body_en'] as String?;
  return Lang.I.isEn && en != null && en.trim().isNotEmpty ? en : (a['body'] as String? ?? '');
}

String kindLabelOf(String? k) => switch (k) {
      'signal1' => tr('الإشارة 1 · طوارئ', 'Signal 1 · Emergency'),
      'signal2' => tr('الإشارة 2 · إخلاء', 'Signal 2 · Evacuate'),
      'signal3' => tr('الإشارة 3 · زوال الخطر', 'Signal 3 · All clear'),
      'message' => tr('تنبيه', 'Message'),
      _ => '',
    };

String statusLabelOf(String? s) => switch (s) {
      'received' => tr('استُلم', 'Received'),
      'safe' => tr('آمن', 'Safe'),
      'need_help' => tr('يحتاج مساعدة', 'Needs help'),
      'injured' => tr('مصاب', 'Injured'),
      'trapped' => tr('محتجز', 'Trapped'),
      _ => '',
    };
