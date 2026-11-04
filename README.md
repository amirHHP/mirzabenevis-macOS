# Mirza Benevis (میرزا بنویس)

اپ منوبار macOS برای تبدیل گفتار جلسات به متن — **کاملاً Native** با Swift + whisper.cpp + ScreenCaptureKit.

[![Latest Release](https://img.shields.io/github/v/release/amirHHP/mirzabenevis-recorder3?label=Release&color=blue)](https://github.com/amirHHP/mirzabenevis-recorder3/releases/latest)

## دانلود سریع (Ready-to-Use)

می‌توانید آخرین نسخه برنامه را بدون نیاز به کامپایل، مستقیماً از بخش Releases گیت‌هاب دریافت کنید:
- 📦 **[دانلود مستقیم MirzaBenevis-v1.0.0.dmg](https://github.com/amirHHP/mirzabenevis-recorder3/releases/download/v1.0.0/MirzaBenevis-v1.0.0.dmg)** (توصیه شده)
- 🗜️ **[دانلود نسخه فشرده MirzaBenevis-v1.0.0.zip](https://github.com/amirHHP/mirzabenevis-recorder3/releases/download/v1.0.0/MirzaBenevis-v1.0.0.zip)**
- 🔗 **[صفحه تمام نسخه‌ها (GitHub Releases)](https://github.com/amirHHP/mirzabenevis-recorder3/releases)**

## چرا Swift + whisper.cpp؟

### ۱. دسترسی بومی به صدای سیستم (ScreenCaptureKit)

بزرگ‌ترین چالش ابزار صورت‌جلسه: ضبط هم‌زمان صدای **میکروفون شما** و **افراد جلسه** (از اسپیکر/هدفون).

| رویکرد | مشکل |
|--------|------|
| **Python** | بدون درایور مجازی مثل BlackHole نمی‌تواند صدای خروجی سیستم را بگیرد — UX خراب |
| **Swift Native** | از macOS 13+ با **ScreenCaptureKit** صدای Zoom/Meet/Slack بدون درایور اضافه |

### ۲. بهینه برای Apple Silicon (M-series)

**whisper.cpp** نسخه C/C++ مدل Whisper است:

- اجرا روی **Neural Engine** و **Metal**
- سرعت پردازش زنده بالا
- بدون روشن شدن فن و هدر رفتن باتری (برخلاف Python/faster-whisper)

### ۳. منوبار مینیمال

با `MenuBarExtra` در SwiftUI:

- آیکون در نوار منو
- پاپ‌آور کوچک برای شروع/توقف
- کپی متن در کلیپ‌بورد
- بدون پکیج سنگین Electron/PyInstaller

## معماری

```
┌─────────────────────────────────────────────────────────┐
│  MenuBarExtra (SwiftUI)                                 │
│  ├─ ScreenCaptureKit → صدای سیستم (Zoom/Meet)           │
│  ├─ AVAudioEngine    → میکروفون                         │
│  ├─ AudioMixer       → ترکیب (اختیاری)                  │
│  ├─ whisper.cpp      → تبدیل on-device (Metal/CoreML)   │
│  ├─ TranscriptStore  → ذخیره کلمه‌به‌کلمه                │
│  └─ Gemini API       → خلاصه‌سازی (اختیاری)              │
└─────────────────────────────────────────────────────────┘
```

## پیش‌نیازها

- macOS 14+
- **Xcode 15+** (نه فقط Command Line Tools)
- **CMake 3.28+** (`brew install cmake`)
- کلید Gemini ([Google AI Studio](https://aistudio.google.com/apikey)) — فقط برای خلاصه

## نصب

```bash
git clone https://github.com/amirHHP/mirzabenevis-recorder3.git
cd mirzabenevis-recorder3
chmod +x scripts/setup.sh
./scripts/setup.sh
```

یا دستی:

```bash
# 1. ساخت whisper.xcframework (~چند دقیقه)
./scripts/build_whisper.sh

# 2. تولید Xcode project
python3 scripts/generate_xcode_project.py

# 3. باز کردن در Xcode
open MacApp/MirzaBenevis.xcodeproj
```

## استفاده

1. اپ را با `⌘R` اجرا کنید — آیکون در **منوبار** ظاهر می‌شود
2. اولین بار مدل `ggml-base.bin` (~142 MB) دانلود می‌شود
3. **منبع صدا** را انتخاب کنید (پیش‌فرض: صدای سیستم)
4. **شروع ضبط** — متن زنده در پاپ‌آور
5. **توقف** — جلسه ذخیره می‌شود
6. **کپی** — متن در کلیپ‌بورد
7. **جلسات** — export PDF/Word + خلاصه Gemini

## مدل‌های whisper.cpp

| مدل | حجم | کاربرد |
|-----|-----|--------|
| tiny | ~75 MB | سریع، جلسات کوتاه |
| base | ~142 MB | متعادل (پیش‌فرض) |
| small | ~466 MB | دقت بالاتر |
| medium | ~1.5 GB | بسیار دقیق |
| turbo | ~1.6 GB | **Large v3 Turbo** — بهترین دقت برای زبان فارسی با سرعت بالا |

مدل‌ها از Hugging Face دانلود و در `~/Library/Application Support/MirzaBenevis/models/` ذخیره می‌شوند.

## ویژگی‌های نسخه جدید

- **تشخیص فعالیت صوتی (VAD هوشمند):** تقطیع جملات با مکث طبیعی گوینده به جای قطعات ثابت ۳ ثانیه‌ای.
- **تفکیک خودکار گویندگان (Speaker Diarization):** برچسب‌گذاری مجزای صحبت‌های «شما» و «جلسه / همکاران».
- **یکپارچگی با تقویم مک (Calendar Integration):** نام‌گذاری هوشمند خودکار جلسات از روی تقویم با فریم‌ورک بومی EventKit.
- **قالب‌های تخصصی خلاصه (Summary Templates):** خلاصه عمومی، استندآپ روزانه/اسکرام، جلسات ۱ به ۱، جلسات فروش و جلسات معماری فنی.
- **استخراج تعاملی وظایف (Action Items):** استخراج خودکار تسک‌ها با چک‌باکس و قابلیت کپی برای Notion و Slack.
- **پرسش و پاسخ از جلسه (Chat with Meeting):** امکان پرسیدن سوال از تصمیمات و محتوای جلسه با هوش مصنوعی Gemini.

## مجوزها

- **میکروفون** — صدای شما
- **Screen Recording** — صدای سیستم (ScreenCaptureKit)
- **تقویم (Calendar)** — خواندن خودکار عنوان جلسه از رویداد تقویم

## ساختار پروژه

```
mirzabenevis-recorder3/
├── MacApp/MirzaBenevis/       # اپ منوبار SwiftUI
│   ├── Whisper/LibWhisper.swift
│   ├── Services/               # ScreenCaptureKit, whisper engine
│   └── Views/                  # MenuBarExtra popover
├── vendor/whisper.cpp/         # whisper.cpp + build-apple/
├── scripts/
│   ├── build_whisper.sh
│   └── generate_xcode_project.py
```

## مقایسه با Python + BlackHole

| | Swift + whisper.cpp | Python + faster-whisper |
|--|---------------------|-------------------------|
| صدای سیستم | ScreenCaptureKit (بومی) | BlackHole (دستی) |
| پردازش | Neural Engine / Metal | CPU (گرم، پرمصرف) |
| حجم اپ | ~20 MB + مدل | PyInstaller >400 MB |
| UI | MenuBarExtra | پیچیده‌تر |
| سرور | ندارد | FastAPI لازم |

## لایسنس

MIT
