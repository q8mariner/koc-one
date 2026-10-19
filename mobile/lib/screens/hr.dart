// HR services, in the four groups of the HR portal. Easy to reach without clutter:
// search, one-tap group filter, the services you used recently on top, then compact 3-per-row tiles.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';
import '../ui.dart';

class HrService {
  final String id, ar, en, descAr, descEn;
  final IconData icon;
  const HrService(this.id, this.icon, this.ar, this.en, this.descAr, this.descEn);
  String get name => tr(ar, en);
}

class HrGroup {
  final String id, ar, en;
  final List<HrService> items;
  const HrGroup(this.id, this.ar, this.en, this.items);
  String get name => tr(ar, en);
}

const hrGroups = <HrGroup>[
  HrGroup('employment', 'بيانات التوظيف', 'Employment details', [
    HrService('payslip', Icons.receipt_long_outlined, 'كشف الراتب', 'Payslip', 'عرض كشوف الراتب الشهرية وتنزيلها.', 'View and download your monthly payslips.'),
    HrService('dependents', Icons.family_restroom, 'المعالون', 'Employee dependents', 'بيانات أفراد الأسرة المسجلين على ملفك.', 'Family members registered on your file.'),
    HrService('leaves', Icons.flight_takeoff, 'الإجازات', 'Leaves', 'رصيد الإجازات وتقديم طلب إجازة.', 'Leave balance and leave requests.'),
    HrService('sop', Icons.description_outlined, 'إجراءات العمل (SOP)', 'SOP', 'إجراءات التشغيل القياسية الخاصة بعملك.', 'Standard operating procedures for your job.'),
    HrService('ecert', Icons.workspace_premium_outlined, 'الشهادات الإلكترونية', 'e-Certificates', 'طلب شهادات الراتب وإثبات العمل.', 'Request salary and employment certificates.'),
    HrService('jobdesc', Icons.assignment_ind_outlined, 'الوصف الوظيفي', 'Job description', 'الوصف الوظيفي المعتمد لوظيفتك.', 'The approved description of your job.'),
    HrService('prevemp', Icons.work_history_outlined, 'الخبرات السابقة', 'Previous employment', 'جهات العمل السابقة المسجلة.', 'Your recorded previous employers.'),
    HrService('quals', Icons.card_membership, 'المؤهلات', 'Qualifications', 'المؤهلات العلمية والمهنية المسجلة.', 'Your recorded academic and professional qualifications.'),
    HrService('assign', Icons.edit_note, 'سجل التكليفات', 'Assignment history', 'التكليفات والانتدابات السابقة والحالية.', 'Your past and current assignments.'),
    HrService('approvals', Icons.how_to_reg_outlined, 'الموافقات', 'Approvals', 'الطلبات بانتظار موافقتك أو المرفوعة منك.', 'Requests awaiting your approval or raised by you.'),
    HrService('social', Icons.people_outline, 'تحديث الحالة الاجتماعية', 'Social status update', 'تحديث الحالة الاجتماعية وبيانات الأسرة.', 'Update your marital status and family details.'),
  ]),
  HrGroup('benefits', 'البدلات والمزايا', 'Allowance & benefits', [
    HrService('edu', Icons.school_outlined, 'بدل التعليم', 'Education allowance', 'طلب بدل تعليم الأبناء ومتابعته.', 'Request and track children’s education allowance.'),
    HrService('marriage', Icons.favorite_border, 'منحة الزواج', 'Marriage grant', 'تقديم طلب منحة الزواج.', 'Apply for the marriage grant.'),
    HrService('furniture', Icons.chair_outlined, 'منحة الأثاث', 'Furniture grant', 'تقديم طلب منحة الأثاث.', 'Apply for the furniture grant.'),
    HrService('housinggrant', Icons.home_outlined, 'منحة السكن', 'Housing grant', 'تقديم طلب منحة السكن.', 'Apply for the housing grant.'),
    HrService('loans', Icons.account_balance_wallet_outlined, 'القروض الشخصية', 'Personal loans', 'طلب قرض شخصي ومتابعة الأقساط.', 'Request a personal loan and track repayments.'),
    HrService('special', Icons.payments_outlined, 'مدفوعات خاصة', 'Special payments', 'المدفوعات والمستحقات الخاصة.', 'Special payments and entitlements.'),
    HrService('longservice', Icons.military_tech_outlined, 'مكافأة الخدمة الطويلة', 'Long service award', 'استحقاق مكافأة سنوات الخدمة.', 'Your long-service award entitlement.'),
    HrService('rewards', Icons.card_giftcard, 'المكافآت', 'Rewards', 'المكافآت والحوافز المستحقة.', 'Rewards and incentives.'),
  ]),
  HrGroup('relations', 'علاقات الموظفين', 'Employee relations', [
    HrService('grievance', Icons.feedback_outlined, 'التظلم الفردي', 'Individual grievance', 'تقديم تظلم ومتابعة حالته.', 'Submit a grievance and track it.'),
    HrService('disciplinary', Icons.gavel, 'الإجراءات التأديبية', 'Disciplinary action', 'الإجراءات التأديبية المسجلة إن وجدت.', 'Recorded disciplinary actions, if any.'),
  ]),
  HrGroup('housing', 'السكن', 'Housing', [
    HrService('accom', Icons.house_outlined, 'السكن الوظيفي', 'Housing accommodation', 'طلب سكن وظيفي ومتابعته.', 'Request and track company housing.'),
    HrService('housingcert', Icons.home_work_outlined, 'شهادات السكن', 'Housing certificates', 'طلب شهادات السكن.', 'Request housing certificates.'),
    HrService('awareness', Icons.play_circle_outline, 'التوعية', 'Awareness', 'مواد توعوية خاصة بالسكن.', 'Housing awareness material.'),
    HrService('faq', Icons.help_outline, 'الأسئلة الشائعة', 'FAQ', 'إجابات أكثر الأسئلة شيوعًا عن السكن.', 'Answers to common housing questions.'),
    HrService('waiting', Icons.hourglass_top, 'رقم الانتظار', 'Waiting number', 'رقمك في قائمة انتظار السكن.', 'Your place on the housing waiting list.'),
  ]),
];

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});
  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> {
  final _q = TextEditingController();
  String _group = 'all';
  List<String> _recent = [];

  static final Map<String, HrService> _byId = {for (final g in hrGroups) for (final s in g.items) s.id: s};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _recent = (p.getStringList('one.hr.recent') ?? []).where(_byId.containsKey).toList());
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _open(HrService s, HrGroup g) async {
    setState(() => _recent = [s.id, ..._recent.where((x) => x != s.id)].take(4).toList());
    try {
      (await SharedPreferences.getInstance()).setStringList('one.hr.recent', _recent);
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _iconBox(s.icon, 52),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.navy)),
                const SizedBox(height: 2),
                Text(g.name, style: const TextStyle(color: C.muted, fontSize: 12.5)),
              ])),
            ]),
            const SizedBox(height: 14),
            Text(tr(s.descAr, s.descEn), style: const TextStyle(fontSize: 15, height: 1.5)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.yellow)),
              child: Row(children: [
                const Icon(Icons.link, color: Color(0xFF8A6400)),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('هذه الخدمة جاهزة في التطبيق وستُفعّل بعد ربطها بنظام الموارد البشرية.', 'This service is ready in the app and will go live once it is linked to the HR system.'),
                    style: const TextStyle(color: Color(0xFF6B5200), fontWeight: FontWeight.w600))),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('حسنًا', 'OK')))),
          ]),
        ),
      ),
    );
  }

  static Widget _iconBox(IconData icon, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: const Color(0xFFE3EAF8), borderRadius: BorderRadius.circular(size * .28)),
        child: Icon(icon, color: C.navy, size: size * .52),
      );

  Widget _tile(HrService s, HrGroup g) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: C.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(s, g),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              _iconBox(s.icon, 42),
              const SizedBox(height: 8),
              Text(s.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.fg, height: 1.25)),
            ]),
          ),
        ),
      );

  Widget _grid(List<HrService> items, HrGroup Function(HrService) groupOf) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: .98,
        children: [for (final s in items) _tile(s, groupOf(s))],
      );

  HrGroup _groupOf(HrService s) => hrGroups.firstWhere((g) => g.items.contains(s));

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final groups = hrGroups.where((g) => _group == 'all' || g.id == _group).map((g) {
      final items = q.isEmpty ? g.items : g.items.where((s) => s.ar.contains(q) || s.en.toLowerCase().contains(q)).toList();
      return (g, items);
    }).where((e) => e.$2.isNotEmpty).toList();
    final showRecent = q.isEmpty && _group == 'all' && _recent.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(tr('الموارد البشرية', 'HR'), style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        // search
        TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: tr('ابحث عن خدمة…', 'Search a service…'),
            prefixIcon: const Icon(Icons.search, color: C.muted),
            suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.line)),
          ),
        ),
        const SizedBox(height: 10),
        // group filter
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final g in [('all', tr('الكل', 'All')), for (final h in hrGroups) (h.id, h.name)])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(g.$2),
                  selected: _group == g.$1,
                  showCheckmark: false,
                  selectedColor: C.navy,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: _group == g.$1 ? C.navy : C.line),
                  labelStyle: TextStyle(color: _group == g.$1 ? Colors.white : C.navy, fontWeight: FontWeight.w700, fontSize: 13),
                  onSelected: (_) => setState(() => _group = g.$1),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        if (showRecent) ...[
          SectionTitle(tr('استخدمتها مؤخرًا', 'Recently used')),
          _grid([for (final id in _recent.take(3)) _byId[id]!], _groupOf),
          const SizedBox(height: 6),
        ],
        for (final (g, items) in groups) ...[
          SectionTitle(g.name),
          _grid(items, (_) => g),
          const SizedBox(height: 6),
        ],
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: Text(tr('لا توجد خدمة بهذا الاسم.', 'No service with that name.'), textAlign: TextAlign.center, style: const TextStyle(color: C.muted)),
          ),
      ]),
    );
  }
}
