# Marine Operations · تطبيق العمليات البحرية

فرع مستقل (`marine-ops`) لا علاقة له بكود KOC ONE في `main`.

| الجزء | المكان |
|---|---|
| تطبيق Android (Flutter) | `app/` — يُبنى تلقائيًا في Actions وينشر `MarineOps.apk` في Release باسم `marine-ops-latest` |
| قاعدة البيانات | Supabase مشروع `marine-ops` (جداول: operations, weather, news, duty, contacts + bucket `news`) |
| لوحة الإدخال | صفحة HTML في `dashboard/index.html` (منشورة أيضًا كـ Artifact) |

الكتابة في الجداول مسموحة فقط للبريد الموجود في جدول `admins`. القراءة مفتوحة للتطبيق.
