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

const reportTypes = {
  'fire': ('حريق', Icons.local_fire_department),
  'leak': ('تسرب غاز/نفط', Icons.water_drop),
  'injury': ('إصابة', Icons.medical_services),
  'road': ('حادث طريق', Icons.car_crash),
  'suspicious': ('نشاط مشبوه', Icons.visibility),
  'hazard': ('خطر سلامة', Icons.warning_amber),
  'sos': ('نداء استغاثة', Icons.sos),
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
      if (keyRow == null) throw 'لم يفعّل فريق ORT مفتاح التشفير بعد — اتصل بـ 160 مباشرة.';
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وصل بلاغك إلى 160 مشفّرًا، وحُذفت الصور من هاتفك.')));
    } catch (e) {
      setState(() => _err = e is String ? e : 'تعذّر الإرسال: تحقق من الشبكة وأعد المحاولة.');
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
      appBar: AppBar(title: const Text('بلاغ إلى 160')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('نوع البلاغ', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in reportTypes.entries)
            ChoiceChip(
              avatar: Icon(e.value.$2, size: 18),
              label: Text(e.value.$1),
              selected: _type == e.key,
              onSelected: (_) => setState(() => _type = e.key),
            ),
        ]),
        const SizedBox(height: 16),
        Card(child: ListTile(leading: const Icon(Icons.my_location), title: Text(live.areaLabel()), subtitle: Text(live.pos == null ? 'الموقع غير متاح' : 'يُرفق الموقع تلقائيًا'))),
        const SizedBox(height: 12),
        TextField(controller: _desc, maxLines: 4, decoration: const InputDecoration(labelText: 'ماذا ترى؟ (اختياري)')),
        const SizedBox(height: 16),
        Row(children: [
          Text('صور البلاغ (${_photos.length}/4)', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          const Icon(Icons.lock, size: 16, color: Color(0xFF22C55E)),
          const Text(' مشفّرة', style: TextStyle(color: Color(0xFF22C55E))),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < _photos.length; i++)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_photos[i].path), width: 96, height: 96, fit: BoxFit.cover)),
                  Positioned(top: 0, left: 0, child: IconButton(onPressed: () => setState(() => _photos.removeAt(i)), icon: const Icon(Icons.close, size: 18))),
                ]),
              ),
            if (_photos.length < 4)
              InkWell(
                onTap: _snap,
                child: Container(width: 96, height: 96, decoration: BoxDecoration(border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add_a_photo)),
              ),
          ]),
        ),
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('تُلتقط بكاميرا التطبيق فقط · لا تُحفظ في المعرض · تُرسل إلى 160 فقط', style: TextStyle(color: Colors.white54, fontSize: 12))),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: Color(0xFFFCA5A5)))),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send),
          label: Text(_sending ? 'جارٍ التشفير والإرسال…' : 'إرسال البلاغ إلى 160'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
        ),
      ]),
    );
  }
}
