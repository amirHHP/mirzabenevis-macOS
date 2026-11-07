import Foundation
import SwiftUI

public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case persian = "fa"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .persian: return "فارسی"
        }
    }

    public var shortLabel: String {
        switch self {
        case .english: return "EN"
        case .persian: return "FA"
        }
    }

    public var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .persian: return "🇮🇷"
        }
    }

    public var layoutDirection: LayoutDirection {
        switch self {
        case .english: return .leftToRight
        case .persian: return .rightToLeft
        }
    }

    public var locale: Locale {
        Locale(identifier: rawValue)
    }
}

public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()

    @Published public var currentLanguage: AppLanguage {
        didSet {
            AppSettings.appLanguage = currentLanguage
        }
    }

    public init() {
        self.currentLanguage = AppSettings.appLanguage
    }

    public var isRTL: Bool {
        currentLanguage == .persian
    }

    public var layoutDirection: LayoutDirection {
        currentLanguage.layoutDirection
    }

    public func toggle() {
        currentLanguage = (currentLanguage == .english) ? .persian : .english
    }
}

public enum L10n {
    public static func tr(_ key: Key, _ lang: AppLanguage? = nil) -> String {
        let current = lang ?? AppSettings.appLanguage
        return key.translation(for: current)
    }

    public enum Key {
        // App & Navigation
        case appTitle
        case sessionsTitle
        case searchPlaceholder
        case noSessionSelected
        case noSessionDescription
        case noSessionsFound
        case newSession
        case words
        case today
        case yesterday

        // Details & Header
        case meetingTitlePlaceholder
        case save
        case cancel
        case delete
        case deleteSessionConfirmTitle
        case deleteSessionConfirmMessage(String)
        case calendarEvent

        // Toolbar & Export
        case language
        case shareAndExport
        case exportPDF
        case exportWord
        case copyTranscript
        case copiedToClipboard
        case savedFile(String)

        // Audio Player
        case audioPlayer
        case play
        case pause
        case skipBackward5
        case skipForward5
        case stop
        case playbackSpeed
        case normalSpeed
        case showInFinder
        case openExternal

        // Tabs
        case tabTranscript
        case tabSummary
        case tabActionItems
        case tabChat
        case tabAttendees

        // Transcript & Speakers
        case filterTranscript
        case noTranscript
        case changeSpeakerTo
        case editSpeaker
        case playFromHere
        case attendees
        case attendeesHint
        case attendeePlaceholder
        case add
        case aiDiarization
        case offlineDiarization
        case diarizeSuccess(Int)
        case offlineDiarizeSuccess(Int)
        case offlineDiarizeNoData
        case editSpeakerTitle
        case currentSpeakerName(String)
        case newSpeakerNamePlaceholder
        case quickSelectAttendee
        case applyThisSegmentOnly
        case applyGlobally
        case speakerYou
        case speakerMeeting
        case speakerGeneral

        // Summary
        case aiSummaryTitle
        case template
        case generateSummary
        case regenerateSummary
        case copySummary
        case noSummaryYet
        case apiKeyRequiredBanner
        case openSettings
        case summarizing
        case summaryCopied

        // Summary Templates
        case templateGeneral
        case templateStandup
        case templateOneOnOne
        case templateSales
        case templateTechnical

        // Action Items
        case actionItemsTitle
        case extractActionItems
        case copyActionItems
        case addTaskPlaceholder
        case noActionItemsYet
        case tasksProgress(Int, Int)
        case tasksCopied
        case extracting

        // Chat with Meeting
        case chatTitle
        case chatPlaceholder
        case ask
        case asking
        case suggestedQuestions
        case suggestedQ1
        case suggestedQ2
        case suggestedQ3
        case copyAnswer
        case answerCopied
        case chatEmptySubtitle
        case questionPrefix(String)

        // Menu Bar Popover
        case ready
        case recording
        case startRecording
        case stopRecording
        case audioSource
        case speechLanguage
        case autoLanguage
        case liveTranscript
        case readyToRecord
        case openSessions
        case settings
        case quitApp
        case updateAvailable(String)
        case clickToDownload
        case download
        case speakerDiarizationActive
        case downloadingModel

        // Settings Window
        case settingsTitle
        case settingsGeneral
        case settingsModel
        case settingsGemini
        case settingsAudio
        case settingsCalendar
        case interfaceLanguage
        case interfaceLanguageDesc
        case appUpdates
        case currentVersion
        case checkForUpdates
        case checkingForUpdates
        case upToDate
        case downloadUpdate
        case supportAndDonation
        case donationDescription
        case donateButton
        case whisperSectionTitle
        case whisperModel
        case downloadModel
        case cancelDownload
        case downloadFailed
        case modelDownloaded
        case metalToggle
        case metalDescription
        case coreMLTitle
        case coreMLActive
        case metalActive
        case coreMLDesc
        case openModelsFolder
        case coreMLGuide
        case geminiSectionTitle
        case geminiDesc
        case apiKeyLabel
        case apiKeyPlaceholder
        case saveKey
        case keySaved
        case keyMissingNotice
        case customHostLabel
        case customHostPlaceholder
        case proxyTip
        case getKeyHelp
        case audioSourceSection
        case audioSourceDesc
        case speakerProfileSection
        case userNameLabel
        case userNamePlaceholder
        case userNameDesc
        case calendarSectionTitle
        case calendarDesc
        case calendarAccessGranted
        case calendarAccessDenied
        case requestCalendarAccess
        case calendarSyncHint
        case close

        func translation(for lang: AppLanguage) -> String {
            switch lang {
            case .english:
                switch self {
                case .appTitle: return "Mirza Benevis"
                case .sessionsTitle: return "Meetings & Notes"
                case .searchPlaceholder: return "Search meetings..."
                case .noSessionSelected: return "No Meeting Selected"
                case .noSessionDescription: return "Select a meeting from the sidebar to view details."
                case .noSessionsFound: return "No Meetings Found"
                case .newSession: return "New Meeting"
                case .words: return "words"
                case .today: return "Today"
                case .yesterday: return "Yesterday"

                case .meetingTitlePlaceholder: return "Meeting Title"
                case .save: return "Save"
                case .cancel: return "Cancel"
                case .delete: return "Delete"
                case .deleteSessionConfirmTitle: return "Delete Meeting"
                case .deleteSessionConfirmMessage(let title):
                    return "Are you sure you want to delete \"\(title)\"? This action cannot be undone."
                case .calendarEvent: return "Calendar Event"

                case .language: return "Language"
                case .shareAndExport: return "Share & Export"
                case .exportPDF: return "PDF Document"
                case .exportWord: return "Word Document (.docx)"
                case .copyTranscript: return "Copy Full Text"
                case .copiedToClipboard: return "Copied to clipboard"
                case .savedFile(let name): return "Saved: \(name)"

                case .audioPlayer: return "Meeting Recording"
                case .play: return "Play"
                case .pause: return "Pause"
                case .skipBackward5: return "5s Backward"
                case .skipForward5: return "5s Forward"
                case .stop: return "Stop"
                case .playbackSpeed: return "Speed"
                case .normalSpeed: return "1.0× (Normal)"
                case .showInFinder: return "Show in Finder"
                case .openExternal: return "Open in External App"

                case .tabTranscript: return "Transcript"
                case .tabSummary: return "AI Summary"
                case .tabActionItems: return "Action Items"
                case .tabChat: return "Ask AI"
                case .tabAttendees: return "Speakers"

                case .filterTranscript: return "Search in dialogue..."
                case .noTranscript: return "No transcript content in this meeting."
                case .changeSpeakerTo: return "Change speaker to:"
                case .editSpeaker: return "Edit speaker / rename..."
                case .playFromHere: return "Play from here"
                case .attendees: return "Meeting Attendees"
                case .attendeesHint: return "Attendees list (helps AI diarization and quick tagging):"
                case .attendeePlaceholder: return "Attendee name (e.g. Sarah, Alex)..."
                case .add: return "Add"
                case .aiDiarization: return "AI Diarization (Gemini)"
                case .offlineDiarization: return "Acoustic Clustering (Offline)"
                case .diarizeSuccess(let count):
                    return "Speakers successfully identified (\(count) segments updated)."
                case .offlineDiarizeSuccess(let count):
                    return "Offline voice clustering completed: \(count) distinct acoustic groups identified."
                case .offlineDiarizeNoData:
                    return "Audio data not available or segment duration too short for voice clustering."
                case .editSpeakerTitle: return "Edit Speaker Name"
                case .currentSpeakerName(let name): return "Current Name: \(name)"
                case .newSpeakerNamePlaceholder: return "New speaker name..."
                case .quickSelectAttendee: return "Quick select from attendees:"
                case .applyThisSegmentOnly: return "This Segment Only"
                case .applyGlobally: return "All Segments in Meeting"
                case .speakerYou: return "You"
                case .speakerMeeting: return "Meeting / Others"
                case .speakerGeneral: return "Speaker"

                case .aiSummaryTitle: return "AI Meeting Summary"
                case .template: return "Template"
                case .generateSummary: return "Generate Summary"
                case .regenerateSummary: return "Regenerate"
                case .copySummary: return "Copy Summary"
                case .noSummaryYet: return "No summary generated yet. Select a template and click Generate."
                case .apiKeyRequiredBanner:
                    return "Gemini API key is required for AI features. Please configure it in Settings."
                case .openSettings: return "Open Settings"
                case .summarizing: return "Generating..."
                case .summaryCopied: return "Summary copied"

                case .templateGeneral: return "General & Comprehensive"
                case .templateStandup: return "Daily Standup / Scrum"
                case .templateOneOnOne: return "1-on-1 Meeting"
                case .templateSales: return "Sales & Client Meeting"
                case .templateTechnical: return "Technical Architecture"

                case .actionItemsTitle: return "Action Items & Tasks"
                case .extractActionItems: return "Extract with AI"
                case .copyActionItems: return "Copy Tasks"
                case .addTaskPlaceholder: return "Add a new task..."
                case .noActionItemsYet:
                    return "No action items recorded. Click 'Extract with AI' or add tasks manually."
                case .tasksProgress(let done, let total): return "\(done) of \(total) completed"
                case .tasksCopied: return "Tasks copied to clipboard"
                case .extracting: return "Extracting..."

                case .chatTitle: return "Ask About This Meeting"
                case .chatPlaceholder: return "e.g., What were the final decisions on timeline?"
                case .ask: return "Ask"
                case .asking: return "Thinking..."
                case .suggestedQuestions: return "Suggested questions:"
                case .suggestedQ1: return "What were the main conclusions?"
                case .suggestedQ2: return "Who was assigned which tasks?"
                case .suggestedQ3: return "Summarize the key discussion points"
                case .copyAnswer: return "Copy Answer"
                case .answerCopied: return "Answer copied"
                case .chatEmptySubtitle:
                    return "Ask any question about the discussion, decisions, or attendees in this meeting."
                case .questionPrefix(let q): return "Q: \(q)"

                // Menu Bar Popover
                case .ready: return "Ready"
                case .recording: return "Recording..."
                case .startRecording: return "Start Recording"
                case .stopRecording: return "Stop Recording"
                case .audioSource: return "Audio Source"
                case .speechLanguage: return "Speech Language"
                case .autoLanguage: return "Auto"
                case .liveTranscript: return "Live Transcript"
                case .readyToRecord: return "Ready to record. Live transcript will stream here..."
                case .openSessions: return "Meetings"
                case .settings: return "Settings"
                case .quitApp: return "Quit"
                case .updateAvailable(let v): return "Version \(v) Available"
                case .clickToDownload: return "Click to download update"
                case .download: return "Update"
                case .speakerDiarizationActive: return "Speaker Diarization Active"
                case .downloadingModel: return "Downloading model..."

                // Settings Window
                case .settingsTitle: return "Settings"
                case .settingsGeneral: return "General"
                case .settingsModel: return "Whisper Model"
                case .settingsGemini: return "Gemini AI"
                case .settingsAudio: return "Audio & Voice"
                case .settingsCalendar: return "Calendar"
                case .interfaceLanguage: return "Interface Language"
                case .interfaceLanguageDesc: return "Choose the application display and interface language."
                case .appUpdates: return "Software Updates"
                case .currentVersion: return "Current Version"
                case .checkForUpdates: return "Check for Updates"
                case .checkingForUpdates: return "Checking for updates on GitHub..."
                case .upToDate: return "Mirza Benevis is up to date"
                case .downloadUpdate: return "Download Update (DMG)"
                case .supportAndDonation: return "Support & Donation"
                case .donationDescription: return "Mirza Benevis is free and open-source. If it helps keep your meetings organized and saves you time, consider supporting its ongoing development and maintenance."
                case .donateButton: return "Donate & Support"
                case .whisperSectionTitle: return "Whisper On-Device Model"
                case .whisperModel: return "Model Size"
                case .downloadModel: return "Download / Update Model"
                case .cancelDownload: return "Cancel Download"
                case .downloadFailed: return "Download Error"
                case .modelDownloaded: return "Downloaded & Ready"
                case .metalToggle: return "Metal GPU Acceleration (Apple Silicon)"
                case .metalDescription: return "Runs directly on your Mac GPU via Metal for instant transcription with zero internet dependency and minimal battery consumption."
                case .coreMLTitle: return "Apple Neural Engine / Core ML (Optional)"
                case .coreMLActive: return "Neural Engine Active"
                case .metalActive: return "Metal GPU Active (Default)"
                case .coreMLDesc: return "Mirza Benevis automatically runs on your Mac's GPU (Metal) at high performance. Core ML is an optional enhancement for advanced users wishing to run the encoder on the Apple Neural Engine."
                case .openModelsFolder: return "Open Models in Finder"
                case .coreMLGuide: return "Core ML Guide"
                case .geminiSectionTitle: return "Gemini AI API Configuration"
                case .geminiDesc: return "Google Gemini powers intelligent meeting summaries, action item extraction, speaker diarization, and Q&A chat."
                case .apiKeyLabel: return "Gemini API Key"
                case .apiKeyPlaceholder: return "AIzaSy..."
                case .saveKey: return "Save Key"
                case .keySaved: return "Key saved securely to macOS Keychain"
                case .keyMissingNotice: return "No API key configured. AI summaries and chat are disabled."
                case .customHostLabel: return "Custom Host / Reverse Proxy (Optional)"
                case .customHostPlaceholder: return "https://generativelanguage.googleapis.com"
                case .proxyTip: return "Tip: If connecting from Iran or restricted regions, turn on a VPN or enter your reverse proxy domain."
                case .getKeyHelp: return "Get a free Gemini API key from Google AI Studio"
                case .audioSourceSection: return "Default Audio Source"
                case .audioSourceDesc: return "In 'Both (Mic + System)' mode, the app automatically attributes dialogue turns between you and other participants by acoustic energy analysis."
                case .speakerProfileSection: return "Speaker Profile"
                case .userNameLabel: return "Your Name (Microphone)"
                case .userNamePlaceholder: return "e.g., Alex or You"
                case .userNameDesc: return "This name is used as the speaker label for microphone speech instead of the generic 'You'."
                case .calendarSectionTitle: return "macOS Calendar Integration"
                case .calendarDesc: return "Automatically detects meeting titles and participant details from your Calendar when recording starts."
                case .calendarAccessGranted: return "Calendar Access Active"
                case .calendarAccessDenied: return "Access Permission Needed"
                case .requestCalendarAccess: return "Grant Calendar Access"
                case .calendarSyncHint: return "Compatible with iCloud, Google Calendar, Exchange, and local calendar accounts."
                case .close: return "Done"
                }

            case .persian:
                switch self {
                case .appTitle: return "میرزا بنویس"
                case .sessionsTitle: return "جلسات و یادداشت‌ها"
                case .searchPlaceholder: return "جستجو در جلسات..."
                case .noSessionSelected: return "جلسه‌ای انتخاب نشده"
                case .noSessionDescription: return "یک جلسه را از ستون کناری انتخاب کنید."
                case .noSessionsFound: return "هیچ جلسه‌ای یافت نشد"
                case .newSession: return "جلسه جدید"
                case .words: return "کلمه"
                case .today: return "امروز"
                case .yesterday: return "دیروز"

                case .meetingTitlePlaceholder: return "عنوان جلسه"
                case .save: return "ذخیره"
                case .cancel: return "انصراف"
                case .delete: return "حذف"
                case .deleteSessionConfirmTitle: return "حذف جلسه"
                case .deleteSessionConfirmMessage(let title):
                    return "آیا از حذف «\(title)» اطمینان دارید؟ این عمل غیرقابل بازگشت است."
                case .calendarEvent: return "رویداد تقویم"

                case .language: return "زبان"
                case .shareAndExport: return "اشتراک‌گذاری و خروجی"
                case .exportPDF: return "سند PDF"
                case .exportWord: return "سند Word (.docx)"
                case .copyTranscript: return "کپی متن کامل"
                case .copiedToClipboard: return "در کلیپ‌بورد کپی شد"
                case .savedFile(let name): return "ذخیره شد: \(name)"

                case .audioPlayer: return "پخش‌کننده صوتی جلسه"
                case .play: return "پخش"
                case .pause: return "توقف موقت"
                case .skipBackward5: return "۵ ثانیه به عقب"
                case .skipForward5: return "۵ ثانیه به جلو"
                case .stop: return "توقف"
                case .playbackSpeed: return "سرعت پخش"
                case .normalSpeed: return "1.0× (عادی)"
                case .showInFinder: return "نمایش در Finder"
                case .openExternal: return "باز کردن در برنامه جانبی"

                case .tabTranscript: return "رونوشت"
                case .tabSummary: return "خلاصه هوشمند"
                case .tabActionItems: return "وظایف"
                case .tabChat: return "پرسش و پاسخ"
                case .tabAttendees: return "حاضران"

                case .filterTranscript: return "جستجو در متن گفتگو..."
                case .noTranscript: return "متنی در این جلسه وجود ندارد."
                case .changeSpeakerTo: return "تغییر گوینده به:"
                case .editSpeaker: return "ویرایش نام / تغییر سراسری..."
                case .playFromHere: return "پخش از اینجا"
                case .attendees: return "حاضران در جلسه"
                case .attendeesHint: return "حاضران در جلسه (برای کمک به دقت تفکیک و نام‌گذاری سریع):"
                case .attendeePlaceholder: return "نام فرد حاضر (مثلاً: رضا، سارا، مهندس تقوی)..."
                case .add: return "افزودن"
                case .aiDiarization: return "تفکیک هوشمند با Gemini"
                case .offlineDiarization: return "تفکیک صوتی آفلاین"
                case .diarizeSuccess(let count):
                    return "گویندگان جلسه با موفقیت تفکیک و نام‌گذاری شدند (\(count) بخش به‌روزرسانی شد)."
                case .offlineDiarizeSuccess(let count):
                    return "تفکیک صوتی آفلاین انجام شد: \(count) گروه صوتی بر اساس تن و ویژگی‌های آکوستیک شناسایی شدند."
                case .offlineDiarizeNoData:
                    return "داده‌های صوتی برای این جلسه موجود نیست یا مدت زمان دیالوگ‌ها برای تفکیک کافی نبوده است."
                case .editSpeakerTitle: return "ویرایش نام گوینده"
                case .currentSpeakerName(let name): return "نام فعلی: \(name)"
                case .newSpeakerNamePlaceholder: return "نام جدید گوینده..."
                case .quickSelectAttendee: return "انتخاب سریع از میان حاضران:"
                case .applyThisSegmentOnly: return "فقط این بخش"
                case .applyGlobally: return "تغییر در کل جلسه"
                case .speakerYou: return "شما"
                case .speakerMeeting: return "جلسه / طرف مقابل"
                case .speakerGeneral: return "گوینده"

                case .aiSummaryTitle: return "خلاصه هوشمند با Gemini"
                case .template: return "قالب"
                case .generateSummary: return "خلاصه‌سازی"
                case .regenerateSummary: return "تولید مجدد"
                case .copySummary: return "کپی خلاصه"
                case .noSummaryYet: return "هنوز خلاصه‌ای تولید نشده است. قالب مورد نظر را انتخاب و دکمه خلاصه‌سازی را بزنید."
                case .apiKeyRequiredBanner:
                    return "برای استفاده از قابلیت‌های هوشمند، ابتدا کلید API جمینای را در بخش تنظیمات وارد کنید."
                case .openSettings: return "تنظیمات"
                case .summarizing: return "در حال خلاصه‌سازی..."
                case .summaryCopied: return "خلاصه کپی شد"

                case .templateGeneral: return "عمومی و جامع"
                case .templateStandup: return "جلسه روزانه / اسکرام"
                case .templateOneOnOne: return "جلسه ۱ به ۱ (1-on-1)"
                case .templateSales: return "جلسه مشتری و فروش"
                case .templateTechnical: return "تصمیم‌گیری فنی و معماری"

                case .actionItemsTitle: return "اقدامات بعدی و وظایف (Action Items)"
                case .extractActionItems: return "استخراج خودکار"
                case .copyActionItems: return "کپی وظایف"
                case .addTaskPlaceholder: return "افزودن کار جدید..."
                case .noActionItemsYet:
                    return "هیچ اقدامی ثبت نشده است. می‌توانید با دکمه «استخراج خودکار» وظایف را توسط هوش مصنوعی استخراج کنید."
                case .tasksProgress(let done, let total): return "\(done) از \(total) انجام شده"
                case .tasksCopied: return "وظایف در کلیپ‌بورد کپی شد"
                case .extracting: return "در حال استخراج..."

                case .chatTitle: return "پرسش و پاسخ از این جلسه"
                case .chatPlaceholder: return "مثلاً: درباره زمان تحویل چه تصمیمی گرفته شد؟"
                case .ask: return "بپرس"
                case .asking: return "در حال پردازش..."
                case .suggestedQuestions: return "پرسش‌های پیشنهادی:"
                case .suggestedQ1: return "تصمیمات نهایی جلسه چه بود؟"
                case .suggestedQ2: return "چه تعهدات و وظایفی برای چه کسانی تعیین شد؟"
                case .suggestedQ3: return "مهم‌ترین نکات بحث شده را خلاصه کن"
                case .copyAnswer: return "کپی پاسخ"
                case .answerCopied: return "پاسخ کپی شد"
                case .chatEmptySubtitle:
                    return "می‌توانید هر سوالی درباره روند گفتگوها، تصمیمات یا افراد حاضر در این جلسه مطرح کنید."
                case .questionPrefix(let q): return "پرسش: \(q)"

                // Menu Bar Popover
                case .ready: return "آماده"
                case .recording: return "در حال ضبط..."
                case .startRecording: return "شروع ضبط"
                case .stopRecording: return "توقف ضبط"
                case .audioSource: return "منبع صدا"
                case .speechLanguage: return "زبان گفتار"
                case .autoLanguage: return "خودکار"
                case .liveTranscript: return "رونوشت زنده"
                case .readyToRecord: return "آماده ضبط. متن گفتگو در این قسمت ظاهر می‌شود..."
                case .openSessions: return "جلسات"
                case .settings: return "تنظیمات"
                case .quitApp: return "خروج"
                case .updateAvailable(let v): return "نسخه جدید \(v) موجود است"
                case .clickToDownload: return "برای دانلود نسخه جدید کلیک کنید"
                case .download: return "دریافت"
                case .speakerDiarizationActive: return "تفکیک هوشمند گوینده فعال"
                case .downloadingModel: return "در حال دانلود مدل..."

                // Settings Window
                case .settingsTitle: return "تنظیمات"
                case .settingsGeneral: return "عمومی"
                case .settingsModel: return "مدل و هوش محلی"
                case .settingsGemini: return "هوش مصنوعی جمینای"
                case .settingsAudio: return "صدا و گوینده"
                case .settingsCalendar: return "تقویم"
                case .interfaceLanguage: return "زبان رابط کاربری"
                case .interfaceLanguageDesc: return "زبان نمایش و منوهای مختلف برنامه را تعیین کنید."
                case .appUpdates: return "به‌روزرسانی برنامه"
                case .currentVersion: return "نسخه فعلی"
                case .checkForUpdates: return "بررسی نسخه جدید"
                case .checkingForUpdates: return "در حال بررسی نسخه جدید در گیت‌هاب..."
                case .upToDate: return "میرزا بنویس به‌روز است"
                case .downloadUpdate: return "دانلود نسخه جدید (DMG)"
                case .supportAndDonation: return "حمایت مالی از میرزا بنویس"
                case .donationDescription: return "میرزا بنویس یک ابزار کاملاً رایگان و متن‌باز است. اگر این برنامه به منظم‌تر شدن جلسات و صرفه‌جویی در وقت شما کمک کرده است، با دونیت کردن می‌توانید به توسعه و نگهداری مداوم آن کمک کنید."
                case .donateButton: return "حمایت مالی (دونیت)"
                case .whisperSectionTitle: return "مدل whisper.cpp (پردازش روی دستگاه)"
                case .whisperModel: return "اندازه مدل"
                case .downloadModel: return "دانلود / به‌روزرسانی مدل"
                case .cancelDownload: return "لغو دانلود"
                case .downloadFailed: return "خطا در دانلود"
                case .modelDownloaded: return "دانلود شده و آماده"
                case .metalToggle: return "شتاب‌دهنده سخت‌افزاری Metal (اپل سیلیکون)"
                case .metalDescription: return "مدل با شتاب‌دهنده گرافیکی Metal مستقیماً روی پردازنده مک اجرا می‌شود — سریع، بدون نیاز به اینترنت و با کمترین مصرف باتری."
                case .coreMLTitle: return "موتور عصبی اپل / Core ML (اختیاری)"
                case .coreMLActive: return "موتور عصبی فعال است"
                case .metalActive: return "شتاب‌دهنده گرافیکی Metal فعال است (پیش‌فرض)"
                case .coreMLDesc: return "برنامه به‌طور پیش‌فرض با سرعت بسیار بالا روی شتاب‌دهنده گرافیکی مک (Metal) اجرا می‌شود. این گزینه کاملاً اختیاری است و برای استفاده عادی نیازی به فایل اضافه ندارید."
                case .openModelsFolder: return "باز کردن پوشه مدل‌ها در Finder"
                case .coreMLGuide: return "راهنمای فنی Core ML"
                case .geminiSectionTitle: return "تنظیمات کلید API جمینای"
                case .geminiDesc: return "کلید API جمینای برای خلاصه‌سازی هوشمند، تفکیک گویندگان، استخراج وظایف و پرسش‌وپاسخ استفاده می‌شود."
                case .apiKeyLabel: return "کلید API جمینای"
                case .apiKeyPlaceholder: return "AIzaSy..."
                case .saveKey: return "ذخیره کلید"
                case .keySaved: return "کلید با موفقیت در Keychain مک ذخیره شد"
                case .keyMissingNotice: return "کلید وارد نشده است. قابلیت‌های هوش مصنوعی غیرفعال خواهند بود."
                case .customHostLabel: return "آدرس هاست / پروکسی معکوس (اختیاری)"
                case .customHostPlaceholder: return "https://generativelanguage.googleapis.com"
                case .proxyTip: return "نکته: در صورت استفاده از داخل ایران، VPN را فعال کنید یا از آدرس پروکسی معتبر استفاده کنید."
                case .getKeyHelp: return "دریافت کلید رایگان جمینای از Google AI Studio"
                case .audioSourceSection: return "منبع صدای پیش‌فرض"
                case .audioSourceDesc: return "در حالت «میک + سیستم»، برنامه با مقایسه انرژی صداها گویندگان را به صورت «شما» و «جلسه» تفکیک می‌کند."
                case .speakerProfileSection: return "مشخصات گوینده پیش‌فرض"
                case .userNameLabel: return "نام شما (میکروفون)"
                case .userNamePlaceholder: return "مثلاً: رضا یا شما"
                case .userNameDesc: return "این نام هنگام ضبط مکالمه با میکروفون، به عنوان برچسب گوینده به جای «شما» استفاده می‌شود."
                case .calendarSectionTitle: return "یکپارچگی با تقویم مک (Calendar Integration)"
                case .calendarDesc: return "نام جلسه و موضوع به‌طور خودکار هنگام شروع ضبط از تقویم برداشته می‌شود."
                case .calendarAccessGranted: return "دسترسی به تقویم فعال است"
                case .calendarAccessDenied: return "نیاز به مجوز دسترسی"
                case .requestCalendarAccess: return "درخواست دسترسی به تقویم"
                case .calendarSyncHint: return "از حساب‌های تقویم iCloud، گوگل، Exchange و تقویم محلی مک پشتیبانی می‌شود."
                case .close: return "بستن"
                }
            }
        }
    }
}
