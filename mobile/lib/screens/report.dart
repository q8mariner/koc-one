// Report to 160: type + description + in-app camera photos, encrypted on the phone before upload.
// Photos are never written to the gallery; temporary files are deleted right after sending.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/live.dart';
import '../services/secure_report.dart';
import '../i18n.dart';
import '../ui.dart';

const reportTypes = {
  'fire': ('حريق', 'Fire', Icons.local_fire_department),
  'leak': ('تسرب غاز/نفط', 'Gas/oil leak', Icons.water_drop),
  'injury': ('إصابة', 'Injury', Icons.medical_services),
  'road': ('حادث طريق', 'Road accident', Icons.car_crash),
  'suspicious': ('نشاط مشبوه', 'Suspicious activity', Icons.visibility),
  'hazard': ('خطر سلامة', 'Safety hazard', Icons.warning_amber),
  'sos': ('نداء استغاثة', 'SOS', Icons.sos),
};

class ReportScreen extends StatefulWidget {
  final String initialType;
  const ReportScreen({super.key, this.initialType = 'fire'});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late String _type = widget.initialType;
  final _desc = TextEditingController();
  final List<XFile> _photos = [];
  bool _sending = false;
  String? _err;

  Future<void> _snap() async {
    if (_photos.length >= 4) return;
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    if (x != null) setState(() => _photos.add(x));
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _err = null;
    });
    final sb = Supabase.instance.client;
    final live = LiveService.I;
    try {
      final keyRow = await sb.from('org_public_key').select('jwk').maybeSingle();
      if (keyRow == null) throw tr('لم يفعّل فريق ORT مفتاح التشفير بعد — اتصل بـ 160 مباشرة.', 'ORT hasn’t set up the encryption key yet — call 160 directly.');
      final sealer = SecureReport.forJwk(Map<String, dynamic>.from(keyRow['jwk'] as Map));
      final uid = sb.auth.currentUser!.id;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final paths = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final bytes = await _photos[i].readAsBytes();
        final blob = base64Encode(sealer.sealBytes(bytes));
        final path = '$uid/$stamp-$i.enc';
        await sb.storage.from('reports').uploadBinary(path, Uint8List.fromList(utf8.encode(blob)),
            fileOptions: const FileOptions(contentType: 'text/plain', upsert: false));
        paths.add(path);
      }
      await sb.from('reports').insert({
        'user_id': uid,
        'type': _type,
        'enc_payload': sealer.sealJson({'description': _desc.text.trim(), 'area': live.areaLabel()}),
        'wrapped_key': sealer.wrappedKey(),
        'photo_paths': paths,
        'lat': live.pos?.latitude,
        'lng': live.pos?.longitude,
        'building_id': live.where.buildingId,
        'zone_id': live.where.zoneId,
      });
      await _wipe();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('وصل بلاغك إلى 160 مشفّرًا، وحُذفت الصور من هاتفك.', 'Your report reached 160 encrypted, and the photos were removed from your phone.'))));
    } catch (e) {
      setState(() => _err = e is String ? e : tr('تعذّر الإرسال: تحقق من الشبكة وأعد المحاولة.', 'Couldn’t send: check the network and try again.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _wipe() async {
    for (final p in _photos) {
      try {
        await File(p.path).delete();
      } catch (_) {}
    }
    _photos.clear();
  }

  @override
  void dispose() {
    _wipe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = LiveService.I;
    return Scaffold(
      appBar: AppBar(title: Text(tr('بلاغ إلى 160', 'Report to 160'), style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.bad, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Text('160', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(tr('يصل بلاغك مباشرة إلى فريق ORT في مركز 160، مشفّرًا من هاتفك.', 'Your report goes straight to ORT at the 160 centre, encrypted on your phone.'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.4)),
            ),
          ]),
        ),
        SectionTitle(tr('نوع البلاغ', 'Report type')),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
          children: [
            for (final e in reportTypes.entries)
              Material(
                color: _type == e.key ? C.navy : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: _type == e.key ? C.navy : C.line)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _type = e.key),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(e.value.$3, color: _type == e.key ? Colors.white : (e.key == 'sos' || e.key == 'fire' ? C.bad : C.navy), size: 28),
                    const SizedBox(height: 6),
                    Text(tr(e.value.$1, e.value.$2), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: _type == e.key ? Colors.white : C.fg)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        OneCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            const Icon(Icons.my_location, color: C.navy),
            const SizedBox(width: 10),
            Expanded(child: Text(live.areaLabel(), style: const TextStyle(fontWeight: FontWeight.w700, color: C.fg))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFE6F4EC), borderRadius: BorderRadius.circular(10)),
              child: Text(live.pos == null ? tr('غير متاح', 'Unavailable') : tr('تلقائي', 'Automatic'), style: const TextStyle(color: Color(0xFF1F7A45), fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
        ),
        TextField(controller: _desc, maxLines: 4, decoration: InputDecoration(labelText: tr('ماذا ترى؟ (اختياري)', 'What do you see? (optional)'))),
        const SizedBox(height: 6),
        Row(children: [
          SectionTitle(tr('صور البلاغ', 'Report photos')),
          Text('  (${_photos.length}/4)', style: const TextStyle(color: C.muted)),
          const Spacer(),
          const Icon(Icons.lock, size: 16, color: C.ok),
          Text(tr(' مشفّرة', ' Encrypted'), style: const TextStyle(color: C.ok, fontWeight: FontWeight.w700)),
        ]),
        SizedBox(
          height: 96,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < _photos.length; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_photos[i].path), width: 96, height: 96, fit: BoxFit.cover)),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: InkWell(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            if (_photos.length < 4)
              InkWell(
                onTap: _snap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: C.navy.withValues(alpha: .35), width: 1.5), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.add_a_photo_outlined, color: C.navy),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(tr('تُلتقط بكاميرا التطبيق فقط · لا تُحفظ في المعرض · تُرسل إلى 160 فقط', 'In-app camera only · not saved to the gallery · sent to 160 only'), style: const TextStyle(color: C.muted, fontSize: 12)),
        ),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: C.bad))),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send),
          label: Text(_sending ? tr('جارٍ التشفير والإرسال…', 'Encrypting and sending…') : tr('إرسال البلاغ إلى 160', 'Send report to 160')),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: C.bad, foregroundColor: Colors.white),
        ),
      ]),
    );
  }
}
