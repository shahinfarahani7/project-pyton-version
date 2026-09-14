<div dir="rtl">
# EdgeMint — بررسی ریپو و تطبیق معماری

تاریخ بررسی: 2026-09-13  
Snapshot: `47608d5c9d0c4dffdd7f79430b87a1cf60b3150b`  
نوع کار: بررسی خواندنی؛ هیچ فایل پروژه، برنچ یا کامیتی تغییر نکرد.

## نتیجه

تغییرات معماری واقعی و گسترده‌اند، اما پیاده‌سازی فعلی هنوز یک مسیر Production کامل و قابل اتکا نیست. اجزای متعددی ایجاد شده‌اند که اتصال آن‌ها به ورودی سرویس، چرخه Worker، قرارداد Assignment یا جریان پذیرش نتیجه ناقص است. مهم‌ترین مشکلات به اجرای سرد Qwen، ایمنی دستگاه، رقابت Cancel/Complete، تمدید Lease، ورود فایل و گیت فعال‌سازی مربوط‌اند.

`Phase 0–8 complete (218/218)` در plan/README.md بیانگر بسته‌شدن آیتم‌های پلن است؛ همان فایل گیت Production را CLOSED و شواهد v2 را IMPLEMENTED_DEV_ONLY اعلام می‌کند. این گزارش هیچ قابلیت جدیدی را بدون شواهد عملیاتی IMPLEMENTED_PRODUCTION اعلام نمی‌کند.

## دامنه و حد قطعیت

- هندآف ضمیمه‌شده «Pasted markdown.md» کامل خوانده شد. این فایل جایگزین مبنای انتقال اطلاعات شد؛ دسترسی به متن کامل چت اصلی KVM همچنان اثبات نشده است.
- Clone کامل و غیر shallow دریافت شد: 3,069 فایل tracked، دو برنچ remote و 32 کامیت قابل‌دسترسی؛ هیچ tag از ls-remote برنگشت.
- تمام 32 کامیت از نظر ترتیب، والدها، عنوان، اندازه تغییر و مجموعه مسیرهای تغییرکرده فهرست و بررسی ساختاری شدند. Diffهای اخیر و مسیرهای اصلی مرتبط با معماری عمیق‌تر بررسی شدند.
- این کار ادعای بازبینی دستی تک‌تک خطوط تمام نسخه‌های تاریخی، اثبات همه سناریوها یا تست همه صفحات UI نیست. کامیت‌های حذف‌شده/unreachable و برنچ‌هایی که remote عرضه نمی‌کند در دامنه نیستند.
- آزمایش‌های Python و route-level انجام شدند؛ PostgreSQL زنده، Flutter/Dart، Emulator و دستگاه فیزیکی در این محیط موجود نبودند. نتیجه Native، SQL concurrency و Deployment فقط با اجرای محیط مربوط قابل بسته‌شدن است.
- نسخه Python محیط 3.12.14 است؛ پروژه 3.13 را می‌خواهد. وابستگی‌های اصلی Backend برای اجرای نهایی مطابق نسخه‌های pyproject نصب شدند، اما محیط دقیق lockشده Production بازسازی نشده است. بنابراین نتایج، شواهد تشخیصی معتبر در محیط اعلام‌شده‌اند، نه گیت رسمی Release.

## برنچ‌ها و مبنای جدید

| برنچ | HEAD | اختلاف با master |
|---|---|---|
| master | 47608d5 | — |
| shahin | 47608d5 | صفر؛ همان کامیت و همان محتوا |

Baseline هندآف `2a0d178` در تاریخچه موجود است. بعد از آن 10 کامیت روی تاریخچه فعلی قرار دارد. اختلاف تجمیعی تا HEAD: **784 فایل، 69,585 خط اضافه و 1,092 خط حذف**.

مرجع فعلی در خود ریپو **docs/EDGE-MINT-TARGET-ARCHITECTURE-v2.md** است: نسخه 2.0، تاریخ 2026-09-05، جایگزین صریح v1. بنابراین مقایسه صرفاً با v1 کافی نیست. اصل Server authority، consent محلی و model residency حفظ شده؛ v2 روی TaskRun، physical release، durable inbox، allocation، validation/reward و policy readiness سخت‌گیری بیشتری دارد.

کامیت `c2d9c3d` به‌تنهایی 719 فایل را تغییر داده: 63,045 خط اضافه و 562 خط حذف. عنوان عمومی «architecture details» حجم و ریسک تغییر را منعکس نمی‌کند. دو کامیت آخر نیز فقط اصلاح build نیستند: رفتار Context و ورود فایل را تغییر داده‌اند.

## یافته‌های نیازمند اصلاح

P0 یعنی مانع فعال‌سازی مسیر مربوط؛ P1 یعنی خطای مهم صحت/بازیابی؛ P2 یعنی شکاف شواهد یا نگهداری. یافته‌های static از اجرای Native/SQL تفکیک شده‌اند.

### F01 — P0 — پذیرش نتیجه پس از باختن رقابت وضعیت نهایی

[database/sql/032_result_candidates_reward_entitlements.sql:216](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/database/sql/032_result_candidates_reward_entitlements.sql#L216)

[src/backend/edgemint/results/result_acceptance.py:123](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/results/result_acceptance.py#L123)

[src/backend/edgemint/workers/assignments.py:779](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/workers/assignments.py#L779)

تابع `accept_task_run_with_entitlement` نتیجه CAS را در `v_committed` می‌گیرد، ولی حتی اگر false باشد، ساخت entitlement و تغییر Candidate به accepted ادامه دارد. `accept_outcome` مقدار false را برمی‌گرداند و caller در complete آن را بررسی نمی‌کند؛ سپس Task/Attempt را completed می‌کند.

سناریوی قابل استنتاج از کد: Cancel ابتدا TaskRun را terminal می‌کند؛ Complete بعدی CAS را می‌بازد، ولی Candidate/Entitlement و وضعیت Task هنوز می‌توانند به مسیر موفقیت بروند. Unique entitlement فقط جلوی تکرار کلید را می‌گیرد، نه پذیرش نتیجه بازنده. در caller فعلی amount پیش‌فرض صفر است؛ این یافته ادعای پرداخت واقعی وجه نیست. SQL race در این محیط اجرا نشده است.

**اصلاح لازم:** در همان تراکنش، نتیجه terminal و هویت Candidate برنده را قطعی کنید؛ باخت به Cancel/Failure باید پیش از هر اثر پذیرش متوقف شود. Replay فقط برای همان نتیجه پذیرفته‌شده معتبر باشد.

**معیار پذیرش:** Cancel-first، Complete-first، دو Candidate متفاوت، replay یکسان و crash در مرز entitlement روی PostgreSQL واقعی؛ یک نتیجه نهایی و entitlement متعلق به برنده.

### F02 — P0 — اجرای سرد Qwen قبل از بارگذاری مدل وارد Session guard می‌شود

[src/apps/worker/lib/tasks/task_execution_engine.dart:328](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/tasks/task_execution_engine.dart#L328)

[src/apps/worker/lib/runtime/execution_plan_runner.dart:326](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/execution_plan_runner.dart#L326)

[src/apps/worker/lib/runtime/gemma_model_runtime_manager.dart:153](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/gemma_model_runtime_manager.dart#L153)

[src/apps/worker/lib/inference/llm/qwen_task_processor.dart:174](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/inference/llm/qwen_task_processor.dart#L174)

مسیر پیش‌فرض TaskEngine برای LLM، plan را اجرا می‌کند. runStage قبل از invokeHandler وارد withFreshSession می‌شود؛ این تابع مدل resident می‌خواهد. اما ensureLoaded داخل `_runPrompt` و پس از ورود به Handler است. Installer نیز عمداً فقط registration انجام می‌دهد و Native model نمی‌سازد. بنابراین مسیر شروع سرد به شرط `Primary model is not resident` می‌رسد. این یک نتیجه call-graph است؛ اجرای Flutter اینجا انجام نشده.

همچنین Session scope بیرونی plan و scope داخلی adapter جداگانه شمارنده را افزایش می‌دهند؛ شمارنده فعلی الزاماً شمار Native session واقعی نیست.

**اصلاح لازم:** پس از احراز grant/safety و پیش از stage نیازمند مدل، resident شدن همان runtime owner را انجام دهید؛ ownership Session را در یک لایه قطعی کنید.

**معیار پذیرش:** از App cold start، سه Task واقعی متوالی بدون demo/warmup دستی اجرا شوند؛ Native model یک بار load و برای هر inference فقط یک session ایجاد/بسته شود.

### F03 — P0 — رضایت و سیگنال‌های ایمنی Android واقعی نیستند

[src/apps/worker/android/app/src/main/kotlin/io/edgemint/edgemint_worker/WorkerRuntimePlugin.kt:104](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/android/app/src/main/kotlin/io/edgemint/edgemint_worker/WorkerRuntimePlugin.kt#L104)

[src/apps/worker/lib/platform/worker_runtime_channel.dart:46](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/platform/worker_runtime_channel.dart#L46)

snapshot Android، consentها را ثابت، thermal را normal، network را wifi و withinSchedule را true برمی‌گرداند. بدتر اینکه دستگاهی که Emulator تشخیص داده نشده ولی باتری‌اش 0 تا 19 درصد است به Emulator تبدیل و battery=100 و charging=true گزارش می‌شود. این شرط فقط به debug build محدود نشده است. DeviceConstraints سپس برای Emulator شرط باتری را دور می‌زند.

وجود RuntimeSafetyController این داده جعلی را اصلاح نمی‌کند؛ گزارش availability/consent باید از تنظیم واقعی کاربر و سیستم بیاید.

**اصلاح لازم:** شاخه‌های شبیه‌ساز را محدود به build/profile توسعه کنید؛ consent پایدار و قابل لغو، thermal/network/battery واقعی و رفتار fail-closed برای داده نامعلوم وصل شوند.

**معیار پذیرش:** روی گوشی واقعی باتری 15٪، thermal critical، اینترنت قطع و consent revoked اجرا مسدود/متوقف شود؛ هیچ‌کدام Emulator یا consent granted گزارش نشود.

### F04 — P0 — Worker از توکن ثبت‌نام‌شده برای Coordinator استفاده نمی‌کند

[src/apps/worker/lib/worker_app_controller.dart:97](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/worker_app_controller.dart#L97)

[src/apps/worker/lib/runtime/assignment_coordinator.dart:86](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/assignment_coordinator.dart#L86)

[src/apps/worker/lib/api/worker_api_client.dart:399](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/api/worker_api_client.dart#L399)

Controller هنگام ساخت Coordinator پارامتر accessToken نمی‌دهد. Coordinator مقدار ثابت `token` را انتخاب می‌کند و همان را برای poll/start/progress/complete می‌فرستد. در مقابل heartbeat از `_workerAccessToken` استفاده می‌کند. توکن Coordinator final است و refresh نیز به آن وصل نیست. این تفاوت در dev پنهان می‌ماند ولی احراز هویت مسیر production را خراب می‌کند.

**اصلاح لازم:** یک token provider مشترک و قابل refresh برای heartbeat و تمام assignment commands استفاده شود؛ fallback ثابت در مسیر غیرتست حذف شود.

**معیار پذیرش:** پس از enrollment و سپس token rotation همه درخواست‌ها توکن جاری بفرستند؛ توکن قدیمی/ثابت رد شود.

### F05 — P0 — Assignment Production نشانی فایل‌هایی را می‌دهد که route ندارند

[src/backend/edgemint/workers/assignments.py:150](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/workers/assignments.py#L150)

[src/backend/edgemint/services/worker_gateway.py:53](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/services/worker_gateway.py#L53)

[src/apps/worker/lib/worker_app_controller.dart:1370](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/worker_app_controller.dart#L1370)

bootstrap نشانی `/assignments/{id}/input-manifest` و `/assignments/{id}/output` می‌سازد. در سورس Backend route متناظر پیدا نشد؛ worker-gateway هم این مسیرها را به worker-registry هدایت می‌کند. probe با FastAPI TestClient در environment=production برای GET manifest و POST output هر دو **404 Not Found** برگرداند. مسیر dev با `/v1/dev/worker/tasks/...` جداست و این نقص را ثابتاً رفع نمی‌کند.

**اصلاح لازم:** دریافت manifest و upload واقعی با tenant/device/assignment authorization و digest/size/expiry تعریف و در gateway وصل شود.

**معیار پذیرش:** یک assignment واقعی بدون هیچ endpoint از dev، input بگیرد، نتیجه آپلود کند و receipt معتبر دریافت کند.

### F06 — P1 — آپلود فایل پورتال در آخرین کامیت شکسته است

[src/apps/customer-portal/src/api/client.js:159](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/customer-portal/src/api/client.js#L159)

[src/backend/edgemint/dev/portal_api.py:185](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/dev/portal_api.py#L185)

کامیت 47608d5 هم شاخه multipart و هم route اختصاصی upload را حذف کرده، اما client همچنان در صورت inputFile، FormData به همان tasks endpoint می‌فرستد. Backend فقط request.json می‌خواند. probe مستقیم parser با auth stubbed نتیجه **500 TASK_CREATE_FAILED** داد؛ این آزمایش خطای parsing را اثبات می‌کند و تست auth/DB نیست.

همان commit فراخوانی validate_queue_admission را از مسیر dev حذف کرده است؛ اعتبارسنجی عمومی input هنوز باقی است و نباید گفت تمام validation حذف شده.

**اصلاح لازم:** قرارداد multipart فرانت/بک‌اند را هماهنگ و کنترل admission لازم را بازگردانید؛ JSON و multipart هر دو تست شوند.

**معیار پذیرش:** ایجاد text task و task دارای تصویر/PDF از UI؛ خطای فرمت باید 4xx مناسب باشد و upload معتبر موفق شود.

### F07 — P0 — manifest اپ به asset مدلِ غایب وابسته شده است

[src/apps/worker/pubspec.yaml:28](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/pubspec.yaml#L28)

در dcdada3 یک asset الزامی Qwen به pubspec اضافه شده، اما فایل در clean checkout وجود ندارد و tracked نیست. پس clone به‌تنهایی برای asset bundling قابل‌بازتولید کافی نیست. Flutter build اینجا اجرا نشده؛ فقدان فایل مستقیماً بررسی شد.

**اصلاح لازم:** اگر مدل download/sideload است dependency به asset حذف شود؛ اگر bundled است مرحله provisioning مستند با digest و قبل از build اضافه شود.

**معیار پذیرش:** Build از clean clone بدون فایل دستی توسعه‌دهنده؛ روش تامین مدل و checksum مشخص باشد.

### F08 — P1 — Lease تمدید نمی‌شود و توقف حین inference محدود نشده است

[src/apps/worker/lib/api/worker_api_client.dart:218](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/api/worker_api_client.dart#L218)

[src/apps/worker/lib/runtime/assignment_receiver.dart:134](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/assignment_receiver.dart#L134)

[src/apps/worker/lib/runtime/gemma_inference_adapter.dart:100](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/gemma_inference_adapter.dart#L100)

[dsl/policies/routing/smart-router-v2.yaml:82](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/dsl/policies/routing/smart-router-v2.yaml#L82)

renewAssignment فقط در API client تعریف شده و caller در lib ندارد. expiry در پذیرش اولیه بررسی می‌شود؛ هنگام انتظار Native generation، watchdog مستقل برای Lease expiry و توقف قطعی دیده نشد. بنابراین کار بیش از TTL فعلی 120 ثانیه می‌تواند پس از انقضای مجوز همچنان محلی مصرف منابع داشته باشد و submission آن رد شود. Heartbeat جای تمدید Lease نیست.

**اصلاح لازم:** renewal زمان‌بندی‌شده مستقل از پیشرفت inference و local bounded grant/stop deadline اضافه شود؛ ازسرگیری مجوز منقضی مجاز نباشد.

**معیار پذیرش:** Task طولانی‌تر از دو TTL، قطع شبکه، pause اپ و Native طولانی؛ expiry محلی مانع کار جدید و stop bound اندازه‌گیری شود.

### F09 — P1 — Inbox پایدار نیست و نتیجه dedup در مسیر واقعی نادیده گرفته می‌شود

[src/apps/worker/lib/worker_app_controller.dart:71](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/worker_app_controller.dart#L71)

[src/apps/worker/lib/runtime/assignment_coordinator.dart:155](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/assignment_coordinator.dart#L155)

[src/apps/worker/lib/runtime/assignment_coordinator.dart:157](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/assignment_coordinator.dart#L157)

[src/apps/worker/lib/runtime/encrypted_store.dart:18](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/encrypted_store.dart#L18)

اپ store حافظه‌ای می‌سازد؛ Inbox و Checkpoint پس از process death از دست می‌روند. در executeAssignment، recordBeforeProcess فراخوانی می‌شود اما disposition بررسی نمی‌شود. متد acceptPolledAssignment که duplicate را رد می‌کند caller ندارد. علاوه بر این، آن متد ابتدا bootstrap را merge می‌کند و سپس همان رکورد را duplicate تشخیص می‌دهد؛ wired کردن ساده آن هم کافی نیست. در bootstrap نیز attemptId اشتباهاً از assignmentId پر می‌شود.

`InMemoryEncryptedStore._seal` داده را رمز نمی‌کند؛ HMAC را جلوی plaintext قرار می‌دهد. این توضیح درباره همان store است، نه ادعای اینکه تمام platform encryption پروژه چنین است.

**اصلاح لازم:** Durable store با encryption واقعی، Inbox stateهای received/started/completed، reconciliation صحیح و dedup قبل از side effect؛ attemptId واقعی در قرارداد.

**معیار پذیرش:** Crash بعد از دریافت و قبل از start، ACK گم‌شده، replay پس از complete، reboot و stale fence؛ هیچ اجرای اضافی بدون grant تازه.

### F10 — P1 — Server Plan و Allocation تا Worker حمل نمی‌شوند

[src/backend/edgemint/routing/execution_allocation.py:64](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/routing/execution_allocation.py#L64)

[src/backend/edgemint/workers/assignments.py:153](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/workers/assignments.py#L153)

[src/apps/worker/lib/api/worker_assignment_models.dart:1](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/api/worker_assignment_models.dart#L1)

[src/apps/worker/lib/tasks/task_execution_engine.dart:324](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/tasks/task_execution_engine.dart#L324)

Backend allocation و plan دارد، اما payload bootstrap و WorkerAssignment شامل plan/version/hash، allocation resource vector یا maxInferenceCalls نیستند. Worker براساس taskType plan محلی می‌سازد. در RunContext نیز فقط onProgress داده می‌شود، نه snapshot/resourceEnforcer/stageResourceRequest. Coordinator هم از Controller، resourceEnforcer و taskResourceRequest دریافت نمی‌کند.

این به معنای انتخاب Worker توسط دستگاه نیست؛ انتخاب execution plan/budget از قرارداد سرور هنوز مستقل نشده است.

**اصلاح لازم:** یک grant نسخه‌دار و immutable شامل plan و allocation به Worker برسد؛ اجرای stageها و chunk bounds فقط در همان محدوده باشد.

**معیار پذیرش:** برای یک taskType با دو input متفاوت، بودجه و plan سروری متفاوت تا اجرای Worker قابل ردیابی باشند؛ تغییر محلی حد مجاز رد شود.

### F11 — P1 — Scheduler stack و readiness gate به entrypoint عملیاتی وصل نیستند

[src/backend/edgemint/services/router.py:60](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/services/router.py#L60)

[src/backend/edgemint/routing/service.py:287](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/routing/service.py#L287)

[src/backend/edgemint/governance/policy_readiness_gate.py:113](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/governance/policy_readiness_gate.py#L113)

در جستجوی کل سورس، callerِ assign_attempt_with_scheduler_stack در تست‌ها دیده می‌شود؛ سرویس router فقط policy/evaluate/rank expose می‌کند. evaluate_activation_gate نیز caller عملیاتی در edgemint ندارد. پس وجود ماژول یا عبارت «gate wired» در سند، اعمال گیت در admission/dispatch/start را اثبات نمی‌کند. امکان orchestration بیرون از این ریپو را نمی‌توان با این بررسی نفی کرد؛ در خود ریپو مسیر کامل پیدا نشد.

**اصلاح لازم:** Consumer/loop عملیاتی queue→scheduler→atomic assignment و گیت readiness را در مرز واقعی admission/dispatch برقرار کنید.

**معیار پذیرش:** با policy/evidence ناقص، درخواست واقعی assignment ایجاد نکند؛ با policy معتبر بدون فراخوانی دستی تست، صف تخلیه شود.

### F12 — P1 — رزرو منابع اتمیک از نظر درج است، ولی تمام کنترل ظرفیت زیر lock نیست

[src/backend/edgemint/routing/atomic_assignment.py:98](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/routing/atomic_assignment.py#L98)

[database/sql/019_atomic_assignment_transaction.sql:38](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/database/sql/019_atomic_assignment_transaction.sql#L38)

[database/sql/008_auto_assignment_protocol.sql:125](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/database/sql/008_auto_assignment_protocol.sql#L125)

[src/backend/edgemint/routing/resource_reservations.py:143](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/routing/resource_reservations.py#L143)

کنترل exclusive group و resource budget پیش از ورود به تابع SQL و lock روی Worker انجام می‌شود. تابع SQL هنوز ظرفیت T4=2 و دیگران=1 را می‌سنجد؛ create reservation سقف منابع را مجدداً محاسبه نمی‌کند. اگر caller با READ COMMITTED اجرا کند، دو بررسی قبلی می‌توانند ظرفیت خالی مشترک ببینند و بعد از lock هر دو درج شوند. SERIALIZABLE با retry درست می‌تواند بعضی raceها را دفع کند، اما خود coordinator isolation/lock/recheck را تضمین نمی‌کند. نبود capability نیز به return بدون منع منجر می‌شود.

درج assignment/reservation/credential در تراکنش caller نکته مثبت است؛ این یافته منکر rollback اتمیک نیست.

**اصلاح لازم:** Lock Worker، سپس recheck تمام منابع/consent/runtime و بعد رزرو؛ ظرفیت ناشناخته fail-closed، isolation و retry serialization صریح شوند.

**معیار پذیرش:** دو scheduler واقعی هم‌زمان روی یک Worker؛ مجموع رزرو از بودجه عبور نکند و دو heavy session غیرمجاز ایجاد نشود.

### F13 — P1 — Fence و retry budget هنوز به دامنه TaskRun متصل نیستند

[database/sql/008_auto_assignment_protocol.sql:140](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/database/sql/008_auto_assignment_protocol.sql#L140)

[database/sql/035_task_run_budgets.sql:19](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/database/sql/035_task_run_budgets.sql#L19)

[src/backend/edgemint/routing/service.py:309](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/routing/service.py#L309)

تولید fence در acquire_assignment_lease از max داخل همان Attempt + 1 استفاده می‌کند؛ Attempt تازه می‌تواند دوباره fence=1 داشته باشد. شرط v2 monotonic در سطح TaskRun است. در عین حال تابع SQL reserve_task_run_budget تعریف شده ولی caller در Python/SQL دیگر دیده نشد؛ scheduler در نبود usage مقادیر 1/0/0 فرض می‌کند. پس budget مدل‌سازی شده اما مصرف اتمیکِ پایدار هنگام assignment/fallback برقرار نیست.

**اصلاح لازم:** Counter fence و مصرف budget در همان تراکنش، تحت TaskRun و بدون reset در Attempt جدید؛ usage دلخواه caller مرجع نهایی نباشد.

**معیار پذیرش:** دو Attempt یک Run fence افزایشی داشته باشند؛ ایجاد Attempt جدید و cloud نتواند سقف تجمعی assignment/calls/cost را دور بزند.

### F14 — P1 — Context/output guard با Native contract یکی نیست

[src/apps/worker/lib/inference/llm/context_budget_manager.dart:30](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/inference/llm/context_budget_manager.dart#L30)

[src/apps/worker/lib/inference/llm/context_budget_manager.dart:39](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/inference/llm/context_budget_manager.dart#L39)

[src/apps/worker/lib/inference/llm/qwen_task_processor.dart:172](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/inference/llm/qwen_task_processor.dart#L172)

[src/apps/worker/lib/runtime/gemma_inference_adapter.dart:88](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/gemma_inference_adapter.dart#L88)

dcdada3 بدون عنوان سیاستی، input budget را 600→900، reserve را 300→256 و safety را 180→32 تغییر داده است. شمارش همچنان length/3.5 است و برای فارسی/JSON tokenizer دقیق نیست. processor متن شامل systemInstruction می‌سازد و adapter دوباره systemInstruction جدا به createChat می‌دهد؛ template واقعی Native فراتر از رشته شمارش‌شده است.

maxOutputTokens در processor بررسی می‌شود، اما API adapter چنین پارامتری نمی‌گیرد و output limit پس از پایان generateChatResponse اعمال می‌شود؛ این «جلوگیری Native از تولید بیش از حد» نیست. تست context موجود هنوز fixture مبتنی بر budget=600 دارد.

**اصلاح لازم:** پروفایل واحد artifact/tokenizer/template/policy؛ شمارش ورودی نهایی و سقف خروجی قابل اعمال حین generation. کاهش safety نیازمند benchmark ثبت‌شده است.

**معیار پذیرش:** فارسی/انگلیسی/mixed/JSON در مرز ظرفیت؛ overflow پیش از Native رد شود، خروجی در cap متوقف و truncation شکست صریح باشد.

### F15 — P1 — Result با status=failed می‌تواند از مسیر success پذیرفته شود

[src/backend/edgemint/results/validator.py:112](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/results/validator.py#L112)

[src/backend/edgemint/workers/assignments.py:748](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/edgemint/workers/assignments.py#L748)

probe واقعی validator برای `{"status":"failed","data":{"summary":"x","keyPoints":["x"]},"metrics":{}}` با taskType=text.summarize مقدار valid=True برگرداند. Complete فقط valid را می‌سنجد و سپس accept_outcome با terminal_status پیش‌فرض SUCCEEDED فراخوانی می‌شود. failed/partial باید از موفقیت نهایی تفکیک شوند. همچنین task_input به validator داده نمی‌شود؛ کنترل کیفیت وابسته به حقیقت ورودی در این مسیر انجام نمی‌شود.

**اصلاح لازم:** وضعیت خروجی را صریح normalize و برای failed مسیر failure و برای partial سیاست entitlement مستقل اعمال کنید؛ ورودی immutable را به validator بدهید.

**معیار پذیرش:** JSON معتبر با status failed هرگز SUCCEEDED نسازد؛ نتیجه semantic نادرست نسبت به input و partial بدون مجوز پذیرفته نشود.

### F16 — P1 — چرخه مدل دو owner دارد و dispose مسیر Qwen اصلی را پوشش نمی‌دهد

[src/apps/worker/lib/worker_app_controller.dart:63](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/worker_app_controller.dart#L63)

[src/apps/worker/lib/worker_app_controller.dart:73](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/worker_app_controller.dart#L73)

[src/apps/worker/lib/worker_app_controller.dart:94](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/worker_app_controller.dart#L94)

[src/apps/worker/lib/runtime/worker_model_installer.dart:75](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/worker_model_installer.dart#L75)

Controller دو Gemma adapter/runtime manager می‌سازد؛ callback process lifecycle فقط `_inference` را dispose می‌کند، در حالی‌که pipeline از adapter داخل `_qwenProcessor` استفاده می‌کند. `_qwenProcessor.dispose()` در Controller فراخوانی ندارد. Installer در بعضی مسیرها وجود هر active identity را کافی می‌گیرد، بدون تطبیق identity فعال با مدل مورد انتظار.

بنابراین guard/tracer جدید پیشرفت است، اما رفع کامل Active Identity Loop و شمار واقعی handleها ثابت نشده؛ لاگ registration معادل Native load نیست.

**اصلاح لازم:** یک owner مشترک برای مدل اصلی؛ invalidation/upgrade/dispose همان owner واقعی pipeline را پوشش دهد و active identity دقیقاً مقایسه شود.

**معیار پذیرش:** Idle طولانی، سه Task متوالی، missing/corrupt artifact، lifecycle stop/restart و regression سابق GATHER_ND روی build/device مشخص.

### F17 — P1 — بازیابی transport و physical stop قابل اتکا نیست

[src/apps/worker/lib/runtime/assignment_coordinator.dart:426](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/assignment_coordinator.dart#L426)

[src/apps/worker/lib/runtime/assignment_coordinator.dart:587](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/assignment_coordinator.dart#L587)

[src/apps/worker/lib/runtime/assignment_event_reporter.dart:27](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/runtime/assignment_event_reporter.dart#L27)

[src/apps/worker/lib/inference/llm/qwen_task_processor.dart:113](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/apps/worker/lib/inference/llm/qwen_task_processor.dart#L113)

Complete مستقیماً ارسال می‌شود و receipt/result durable ندارد؛ خطای ACK می‌تواند به failure path برود. خطای confirmPhysicalStop نادیده گرفته می‌شود و tracker reset می‌شود، با اینکه Server ممکن است physical hold را هنوز نگه داشته باشد. journal جدید عمدتاً برای progress/checkpoint است؛ caller بازیابی آن از اپ دیده نشد. ResumeGrant نیز در scope پیش‌فرض Qwen تزریق نمی‌شود. داشتن کلاس ResumeGrant و checkpoint محلی مساوی بازیابی بین Workerها نیست.

**اصلاح لازم:** Result و stop proof در outbox محلی durable با replay همان payload؛ resume فقط با grant تازه و artifact واقعی قابل‌دریافت از Server.

**معیار پذیرش:** گم‌شدن ACK نتیجه یا stop، restart و cross-Worker resume؛ بدون inference دوباره، بدون نشت ظرفیت و بدون reuse غیرمجاز.

### F18 — P2 — شمار Catalog اصلاح شده ولی اثبات اجرای 56/56 نیست

[src/shared/task-types/catalog.json:2](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/shared/task-types/catalog.json#L2)

[src/backend/tests/routing/test_retry_policy_matrix.py:18](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/src/backend/tests/routing/test_retry_policy_matrix.py#L18)

شمار مستقیم snapshot: 56 رکورد و 56 ID یکتا؛ document=10، text=20، image=17، flex=9؛ هر 56 در shared catalog executable=true هستند. DSL دارای 63 فایل TaskType است؛ این جمع را با 56 یکی نباید گرفت و موارد بیرون از shared catalog باید explicit باشند. InputMode با taxonomy مدل (Qwen/Vision/OCR) یک محور نیست.

Flex نسبت به هندآف تغییر کرده؛ تست‌ها هنوز انتظار non-executable/no-retry دارند و شکست می‌خورند. نمی‌توان صرف فعال‌شدن flag یا بودن handler را موفقیت Native تمام 56 کار دانست.

**اصلاح لازم:** یک ماتریس واحد ID→input contract→runtime→handler→validator→retry→checkpoint→runtime evidence و توضیح موارد DSL خارج از catalog.

**معیار پذیرش:** تمام IDها در همان snapshot reconciliation شوند؛ هر enabled path golden مثبت/منفی و اجرای واقعی روی runtime مجاز داشته باشد.

### F19 — P2 — گیت‌های متنی و شواهد قدیمی قابلیت بسته‌شدن را بیش‌برآورد می‌کنند

[tools/verify_production_auto_assignment_source.py:38](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/tools/verify_production_auto_assignment_source.py#L38)

[plan/evidence/phase-03-p3-t19-integration-smoke.json:25](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/plan/evidence/phase-03-p3-t19-integration-smoke.json#L25)

[tests/database/test_postgresql_contract.py:34](https://github.com/shahinfarahani7/project-pyton-version/blob/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b/tests/database/test_postgresql_contract.py#L34)

verify_production_auto_assignment_source.py اجرا شد و همه 16 check را passed اعلام کرد، در حالی‌که check تمدید فقط وجود تعریف متد را می‌سنجد و caller واقعی ندارد. شواهد P3-T19 صریحاً می‌گوید smoke test نوشته شده ولی Flutter اجرا نشده است. تست‌های SQL هنوز 9 فایل انتظار دارند در حالی‌که اکنون 38 migration وجود دارد. این‌ها با آمادگی Production یا «همه‌چیز پاس» سازگار نیستند.

**اصلاح لازم:** شواهد به commit/build/runtime دقیق متصل شوند؛ authored/NOT_RUN/static-pass/runtime-pass جدا؛ تست‌های stale اصلاح شوند بدون تضعیف invariant.

**معیار پذیرش:** Fresh clone روی Python 3.13 و Flutter pinned؛ همه تست‌های مربوط اجرا و gate با سناریوی معیوب واقعی fail شود.

## ماتریس وضعیت فعلی

| حوزه | وضعیت این Audit | توضیح |
|---|---|---|
| سند معماری v2 و traceability | DOC_ONLY برای ادعای اجرا | سند موجود و مرجع فعلی است |
| مدل Qwen resident و fresh session | PARTIAL | کد واقعی دارد؛ F02/F16 و Native proof باز |
| Context و hierarchical chunk/reduce | PARTIAL | ماژول و تست دارد؛ محدودیت Native/plan binding باز |
| consent و safety محلی | PARTIAL | controllerها هست؛ platform signals و enforcement ناقص |
| TaskRun / allocation / reservation | PARTIAL | SQL و service موجود؛ اتصال و raceها باز |
| Queue / scoring / scheduler | PARTIAL | الگوریتم و unit tests؛ consumer عملیاتی پیدا نشد |
| Lease bootstrap و credentials | PARTIAL | مسیر auth/SQL موجود؛ endpoint فایل و Worker token/renew باز |
| Inbox / checkpoint / resume | PARTIAL | persistence واقعی و reconciliation ناقص |
| validation / terminal acceptance / reward | PARTIAL | CAS و uniqueness موجود؛ F01/F15 مانع بسته‌شدن |
| Catalog inventory | IMPLEMENTED_DEV_ONLY | 56 ID موجود؛ اجرای Native کامل اثبات نشده |
| readiness gate | PARTIAL | تابع و policy موجود؛ اعمال در runtime پیدا نشد |
| 20 Worker / chaos / physical device | TEST_ONLY یا NOT_RUN طبق شواهد هر مورد | این Audit هیچ load واقعی اجرا نکرد |

## نقشه مسیرها

مسیر توسعه‌ای قابل مشاهده:

`Customer Portal → api-gateway dev/portal_api → fixtures/assignment_bridge → worker-registry dev assignments → Worker controller → TaskExecutionEngine → handler → Qwen/OCR → dev complete/output`

مسیر هدف Production در سورس:

`TaskAdmissionService → TaskRun + ExecutionAllocation + queue → [consumer/scheduler wiring gap] → AtomicAssignmentTransaction → lease credential/outbox → bootstrap → [manifest route + token gap] → Worker → [resident/renew/safety gaps] → AssignmentCommandService.complete → validator → acceptance SQL → [terminal race gap]`

این دو مسیر را نباید با تست موفق یکی به جای دیگری گواهی کرد. compose.backend.yaml به‌صورت پیش‌فرض development است؛ تست محلی آن production routing را اثبات نمی‌کند.

## نتایج تست و بازتولید

| بررسی | نتیجه | تفسیر |
|---|---|---|
| Backend موجود، اجرای نهایی با registry محلی غیرقابل‌دسترسی | 635 passed / 10 failed / 9 skipped | 654 تست؛ PostgreSQL موجود نیست |
| tests/database | 7 passed / 2 failed / 2 skipped | 11 تست؛ پاس‌ها عمدتاً static SQL contract هستند |
| مجموع دو مجموعه | 642 passed / 12 failed / 11 skipped | 665 تست؛ معادل E2E نیست |
| production source verifier | 16/16 passed | وجود نمادها، نه اثبات فراخوانی/اجرای کامل |
| production manifest GET | 404 | FastAPI TestClient، بدون DB |
| production output POST | 404 | FastAPI TestClient، بدون DB |
| multipart parser | 500 TASK_CREATE_FAILED | auth stubbed؛ parsing واقعی |
| status=failed با schema معتبر | validator valid=True | نمونه دقیق در F15 |
| asset Qwen در clone | غایب | build عملی اجرا نشده |
| Flutter / Android / model inference | NOT_RUN | ابزار/دستگاه موجود نیست |
| PostgreSQL race / migration execution | NOT_RUN | DB زنده موجود نیست |

اجرای نخست دو خطای محیطی اضافه به علت نبود socksio داشت. بعد از نصب dependency، این دو حذف شدند. اجرای نهایی registry را `http://127.0.0.1:1` قرار داد تا fallback توسعه‌ای بدون وابستگی به DNS سرویس Docker اجرا شود. خطاهای باقی‌مانده را نباید یک‌به‌یک runtime defect تلقی کرد: KeyErrorهای mock و تعداد execute قدیمی عمدتاً نشان می‌دهند تست با service جدید همگام نشده است.

### خطاهای باقی‌مانده Backend

- `src/backend/tests/dev/test_fixtures.py::test_dev_tasks_vary_by_workspace`
- `src/backend/tests/routing/test_atomic_assignment_transaction.py::test_acquire_with_reservation_returns_reservation_id_and_persists_credentials`
- `src/backend/tests/routing/test_resource_reservations.py::test_release_for_assignment_is_idempotent`
- `src/backend/tests/routing/test_retry_policy_matrix.py::test_flex_tasks_are_non_executable_with_no_retry`
- `src/backend/tests/routing/test_retry_policy_matrix.py::test_flex_task_retry_blocked_even_for_retryable_failure`
- `src/backend/tests/routing/test_retry_policy_matrix.py::test_catalog_json_has_retry_class_on_every_type`
- `src/backend/tests/routing/test_retry_policy_matrix.py::test_router_service_uses_task_retry_matrix`
- `src/backend/tests/routing/test_retry_policy_matrix.py::test_export_snapshot_matches_matrix`
- `src/backend/tests/workers/test_assignment_credential_bootstrap.py::test_bootstrap_returns_same_raw_credential_on_replay_without_rotation`
- `src/backend/tests/workers/test_assignment_fail.py::test_fail_accepts_leased_assignment_for_pre_execution_rejection`

دسته‌بندی: یک اختلاف fixture status، سه mock قدیمی مربوط به allocation/bootstrap/task_run، یک انتظار قدیمی تعداد query، پنج انتظار قدیمی Flex/retry. دو خطای SQL هم انتظار 9 migration به جای 38 هستند. اصلاح تست‌ها لازم است، اما green شدن آن‌ها به‌تنهایی F01–F17 را حل نمی‌کند.

دستور اجرای نهایی Backend:

```bash
EDGEMINT_WORKER_REGISTRY_URL=http://127.0.0.1:1 PYTHONPATH=src/backend python -m pytest src/backend/tests -q --disable-warnings
```

## ترتیب اصلاح پیشنهادی بدون بازطراحی معماری

1. **قابل ساخت و قابل اجرا کردن مسیر پایه:** asset گمشده، قرارداد multipart، token provider و مسیر manifest/output؛ سپس cold-start Qwen و ownership واحد مدل.
2. **پیش از مصرف واقعی روی دستگاه کاربران:** سیگنال‌های واقعی consent/thermal/battery، local grant deadline، تمدید Lease، interruption/cancellation محدود و enforcement منابع از allocation سرور.
3. **پیش از اعتبار نهایی و reward:** F01 رقابت terminal، F15 failed/partial، validation متصل به input و receipt/entitlement متعلق به Candidate برنده.
4. **بازیابی و ظرفیت:** Inbox/checkpoint/result/stop journal پایدار؛ bootstrap درست؛ atomic lock/recheck؛ TaskRun fence و budget counters.
5. **اتصال کنترل‌پلین:** consumer واقعی صف، plan/allocation قراردادشده و readiness gate در admission/dispatch؛ مصرف failure evidence برای retry/reassign مجاز.
6. **همگام‌سازی تست و Catalog:** 56 ID یکتا با وضعیت واقعی runtime؛ تفکیک DSL-only؛ اصلاح mockها و حذف ادعاهای runtime ناشی از check متنی.
7. **گیت نهایی:** سه inference متوالی + idle trace؛ سپس سناریوهای v2 T01–T24، PostgreSQL race tests، دستگاه فیزیکی و 20-Worker load/chaos.

### برنامه فایل، دیتابیس و قرارداد

| بسته اصلاح | فایل‌ها/مرز اصلی | تغییر مورد انتظار |
|---|---|---|
| Worker lifecycle | worker_app_controller، task_execution_engine، execution_plan_runner، gemma_model_runtime_manager | یک owner، load-before-session، dispose واقعی و counter دقیق |
| Device safety | WorkerRuntimePlugin.kt، worker_runtime_channel، contribution/resource enforcers | سیگنال واقعی + opt-in پایدار + enforce budget |
| Assignment contract | workers/assignments.py، worker_assignment_models.dart، OpenAPI | TaskRun/plan/allocation/model digest/policy/grant bounds و version/hash |
| Durable recovery | encrypted_store، assignment_inbox/coordinator، checkpoint و transport journal | persistence واقعی، crash-safe dedup، replay نتیجه/stop |
| Acceptance migration | SQL بعد از 037 با شماره آزاد بررسی‌شده + result_acceptance/assignments | اصلاح تابع acceptance به صورت migration جدید؛ عدم بازنویسی بی‌صدای تاریخچه |
| Reservation migration | atomic_assignment، SQL acquire/reservation | lock/recheck و fence/budget در دامنه Run |
| Scheduler activation | router service/consumer، policy_readiness_gate | فراخوانی gate در مرز side effect و stop-on-missing evidence |

برای migrationهای موجود در محیط‌های نصب‌شده، همان فایل تاریخی را بی‌صدا اصلاح نکنید؛ migration افزایشی، سازگاری mixed-version و rollback معنایی باید همراه باشد. هیچ migration در این Audit اجرا نشده است.

### Event و State لازم برای closure

- Commandهای progress/checkpoint/renew/failure/result/stop باید هویت Run/Attempt/Assignment، fence و payload identity سازگار داشته باشند.
- دریافت و ACK حمل‌ونقل از مجوز اجرای Task و از تکمیل آن جدا باشد؛ replay پیام حق inference تازه ایجاد نکند.
- Candidate pinned → validation passed → terminal winner → entitlement/outbox فقط برای نتیجه مجاز؛ Cancel-first یا terminal باخته هیچ اثر success نسازد.
- Logical release ظرفیت فعال را تا physical proof آزاد نکند؛ stop receipt گم‌شده باید قابل ارسال مجدد باشد.
- Rollout با گیت بسته آغاز شود، Workerهای قدیمی drain شوند، سپس subset دارای protocol/policy سازگار فعال شود. Rollback نباید fence/receipt/holdهای durable را reset کند.

## تاریخچه همه کامیت‌های قابل‌دسترسی

این جدول inventory تاریخی است؛ عنوان commit ادعای نویسنده است و گواهی این Audit نیست. عدد فایل برای merge صفر یعنی تغییرات از والدها بررسی می‌شوند، نه اینکه merge بی‌اثر بوده است.

| کامیت | تاریخ | فایل تغییرکرده | عنوان |
|---|---|---:|---|
| [7d54402](https://github.com/shahinfarahani7/project-pyton-version/commit/7d5440299e52ca2fc284170bd1d84b82b65f4ccc) | 2026-07-26 | 1505 | Initialize EdgeMint v5.0 Python/PostgreSQL execution pack with contract generation and database harness. |
| [0368a8c](https://github.com/shahinfarahani7/project-pyton-version/commit/0368a8c6dd2cf2997f23d7e6508f61374c14f8f4) | 2026-07-26 | 12 | Add contract generation, persistence layer, database tests, and WP-000/010/020 evidence. |
| [e52b44c](https://github.com/shahinfarahani7/project-pyton-version/commit/e52b44cd82da882271a5586ef540e810cdaa2ff6) | 2026-07-26 | 18 | Implement WP-030 persistence harness and WP-040 identity/security foundation. |
| [e579582](https://github.com/shahinfarahani7/project-pyton-version/commit/e5795823b976a62250e8bce9fdea2af0208ee336) | 2026-07-27 | 745 | Complete WP-045 through WP-250 and pass the production release gate. |
| [212e41c](https://github.com/shahinfarahani7/project-pyton-version/commit/212e41c65f1e8035cca091069f776c6a9c7fb851) | 2026-07-27 | 192 | Rebind release evidence to HEAD and ignore signing keys. |
| [346ce5d](https://github.com/shahinfarahani7/project-pyton-version/commit/346ce5df0ad5f2d4e2cf8d9bae68591dadcfc974) | 2026-07-27 | 190 | Refresh signed release evidence for commit 212e41c. |
| [dbeb7ce](https://github.com/shahinfarahani7/project-pyton-version/commit/dbeb7ceda52db2a6d2ed72eae37a0dc195a6f3c8) | 2026-07-27 | 101 | Migrate web portals from React and TypeScript to Vue 3 and JavaScript. |
| [c322b08](https://github.com/shahinfarahani7/project-pyton-version/commit/c322b08bd101efb88db8304d378480d2d81eaed1) | 2026-07-27 | 14 | Add local Docker compose stack and refresh package metadata for Vue portals. |
| [685bce0](https://github.com/shahinfarahani7/project-pyton-version/commit/685bce01ef8c50026ea87c7f9e7034477bf19f61) | 2026-07-27 | 193 | Rebind production release evidence after Vue portal migration and Docker stack. |
| [2251b9e](https://github.com/shahinfarahani7/project-pyton-version/commit/2251b9eb75a9610555257e2df67081f77e2903df) | 2026-07-28 | 98 | Add mobile worker Gemma download, portal fixes, and dev stack improvements. |
| [6c51720](https://github.com/shahinfarahani7/project-pyton-version/commit/6c5172004dd5ffa4760ce9d87bb01ffbf280d2dd) | 2026-08-01 | 29 | change model |
| [39a083f](https://github.com/shahinfarahani7/project-pyton-version/commit/39a083f74f4f827c6dd7d7c21857f1fdc6698894) | 2026-08-15 | 92 | Add PaddleOCR + Qwen3 worker pipeline with dev E2E tooling. |
| [a6bde94](https://github.com/shahinfarahani7/project-pyton-version/commit/a6bde94325bca033426200a70d6d443fed1d2773) | 2026-08-22 | 67 | remove poll btn |
| [e2f6fe9](https://github.com/shahinfarahani7/project-pyton-version/commit/e2f6fe96ac34889e15b6075d862ed42bbd5074a5) | 2026-08-23 | 105 | Integrate EdgeMint final package from ChatGPT zip (2026-08-22). |
| [37c7311](https://github.com/shahinfarahani7/project-pyton-version/commit/37c731117106a8a78fe66b4659810faea706ff27) | 2026-08-23 | 18 | Fix post-import validation failures across DSL, vectors, and language policy. |
| [24fb4b7](https://github.com/shahinfarahani7/project-pyton-version/commit/24fb4b7d116347ec704eac42e46b98758838e99e) | 2026-08-23 | 0 | Merge import/chatgpt-edgemint-final: EdgeMint final package integration |
| [7adc2e1](https://github.com/shahinfarahani7/project-pyton-version/commit/7adc2e1840b0070edab00bf8af1c1afc6c8cc083) | 2026-08-23 | 3 | Finalize integration branch setup: docker env pins and package metadata. |
| [2a434c6](https://github.com/shahinfarahani7/project-pyton-version/commit/2a434c668c29942e3eb1737bb79fdf2b82ec0964) | 2026-08-23 | 1 | Fix lease credential persistence test to assert hash on acquire call. |
| [497054d](https://github.com/shahinfarahani7/project-pyton-version/commit/497054df37675a46a41d95f362f77f2b0b9ae013) | 2026-08-23 | 3 | Regenerate package metadata after lease credential test fix. |
| [8707d2b](https://github.com/shahinfarahani7/project-pyton-version/commit/8707d2bf0a29512e9751017723ebeb5fd5744a44) | 2026-08-23 | 0 | Merge integrate/edgemint-final: EdgeMint final package with validation fixes |
| [596ab8c](https://github.com/shahinfarahani7/project-pyton-version/commit/596ab8c5f82407bb377d5b1bcee944c500d78a97) | 2026-08-23 | 3 | Fix local Docker startup: portal build args, SQL LF endings, gitattributes. |
| [2a0d178](https://github.com/shahinfarahani7/project-pyton-version/commit/2a0d17875e88c36659b0e063e75727033e51bfbd) | 2026-08-24 | 27 | Improve portal task UX with SSE updates, detail view, and dev tooling. |
| [401f47d](https://github.com/shahinfarahani7/project-pyton-version/commit/401f47d3c728826fab256b08c51608a46ef985d5) | 2026-08-26 | 5 | edit task page |
| [3df7dec](https://github.com/shahinfarahani7/project-pyton-version/commit/3df7dec689685f1d3715a7506446e15e38243956) | 2026-09-01 | 32 | create landing page |
| [83e26d4](https://github.com/shahinfarahani7/project-pyton-version/commit/83e26d40a42fcf7698713488f0934e55bd0166e7) | 2026-09-01 | 13 | create landing page |
| [22d7e25](https://github.com/shahinfarahani7/project-pyton-version/commit/22d7e2580e15cbae715b3d94f3e2c12bfbec0cb5) | 2026-09-01 | 1 | fix app |
| [e47a340](https://github.com/shahinfarahani7/project-pyton-version/commit/e47a3406653b152e306db1e326e262297cc1a3e4) | 2026-09-01 | 20 | fix android app |
| [c2d9c3d](https://github.com/shahinfarahani7/project-pyton-version/commit/c2d9c3d66387dcd592ade133729c7c94f992bb2a) | 2026-09-07 | 719 | architecture details |
| [5135c4b](https://github.com/shahinfarahani7/project-pyton-version/commit/5135c4bf39c90de1776ebe3707b9b433dda281c9) | 2026-09-09 | 1 | fix build error |
| [3eb575a](https://github.com/shahinfarahani7/project-pyton-version/commit/3eb575a61917734c5f72a6c98b7c176756f467ef) | 2026-09-09 | 1 | git ignore |
| [dcdada3](https://github.com/shahinfarahani7/project-pyton-version/commit/dcdada3169f13de015b8e15e5f47b32083d4edd8) | 2026-09-09 | 19 | fix build error |
| [47608d5](https://github.com/shahinfarahani7/project-pyton-version/commit/47608d5c9d0c4dffdd7f79430b87a1cf60b3150b) | 2026-09-09 | 16 | fix task |

## چک‌لیست بسته‌شدن

- [ ] Clean clone و build بدون asset دستی.
- [ ] text و multipart از UI تا Worker بدون dev-only shortcut.
- [ ] cold-start و سه Task واقعی؛ یک resident owner، session مستقل و بدون loop.
- [ ] رضایت لغوشده و battery/thermal واقعی مانع مصرف شوند.
- [ ] Lease طولانی، partition، restart و stale fence بدون مصرف یا اثر غیرمجاز.
- [ ] Server-issued plan/allocation با نسخه/hash و محدودیت واقعی حین اجرا.
- [ ] Inbox/result/checkpoint/stop durable و replay دقیق.
- [ ] Cancel/Complete race و failed/partial status درست و entitlement متعلق به برنده.
- [ ] بودجه و fence در دامنه TaskRun و رزرو اتمیک تحت concurrency.
- [ ] readiness gate با درخواست واقعی و policy ناقص مانع side effect شود.
- [ ] تست‌های موجود سبز روی ابزارهای pinned؛ Runtime/SQL/physical/load proof جدا ثبت شوند.

**تصمیم این Audit:** معماری هدف حفظ شود؛ تمرکز روی اتصال و تصحیح همین پیاده‌سازی باشد. آماده‌سازی Production تا رفع blockerهای بالا و ثبت شواهد واقعی بسته بماند. هیچ تضمین 100٪ یا closure عملیاتی از این Snapshot صادر نمی‌شود.
</div>