import Foundation

enum SummaryTemplate: String, CaseIterable, Identifiable, Codable {
    case general
    case standup
    case oneOnOne
    case sales
    case technical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "عمومی و جامع"
        case .standup: return "جلسه روزانه / اسکرام"
        case .oneOnOne: return "جلسه ۱ به ۱ (1-on-1)"
        case .sales: return "جلسه مشتری و فروش"
        case .technical: return "تصمیم‌گیری فنی و معماری"
        }
    }

    var icon: String {
        switch self {
        case .general: return "doc.text.fill"
        case .standup: return "clock.arrow.circlepath"
        case .oneOnOne: return "person.2.fill"
        case .sales: return "briefcase.fill"
        case .technical: return "cpu"
        }
    }

    func buildPrompt(transcript: String) -> String {
        switch self {
        case .general:
            return """
            متن زیر رونوشت یک جلسه است. لطفاً یک خلاصه ساختاریافته و مفید به زبان فارسی بنویس.
            شامل این بخش‌ها باشد:
            - موضوع اصلی جلسه
            - نکات و بحث‌های کلیدی
            - تصمیمات نهایی گرفته شده
            - اقدامات و وظایف بعدی (Action Items) با ذکر مسئول در صورت مشخص بودن

            رونوشت جلسه:
            \(transcript)
            """

        case .standup:
            return """
            متن زیر رونوشت یک جلسه استندآپ روزانه یا اسکرام است. لطفاً خلاصه را در قالب زیر به زبان فارسی تدوین کن:
            - کارهای انجام شده توسط هر فرد
            - کارهای برنامه‌ریزی شده برای امروز
            - موانع و بلاکرها (Blockers)
            - هماهنگی‌های فوری مورد نیاز

            رونوشت جلسه:
            \(transcript)
            """

        case .oneOnOne:
            return """
            متن زیر رونوشت یک جلسه یک‌به‌یک (1-on-1) است. لطفاً یک خلاصه محرمانه و ساختاریافته به زبان فارسی شامل موارد زیر بنویس:
            - موضوعات و دغدغه‌های مطرح شده
            - بازخوردها و نکات تبادل شده
            - اهداف فردی و مسیر رشد
            - تعهدات طرفین و موارد پیگیری برای جلسه بعد

            رونوشت جلسه:
            \(transcript)
            """

        case .sales:
            return """
            متن زیر رونوشت یک جلسه با مشتری یا جلسه فروش است. لطفاً یک گزارش به زبان فارسی بنویس شامل:
            - نیازمندی‌ها و اهداف اصلی مشتری
            - بودجه، زمان‌بندی و محدودیت‌ها
            - دغدغه‌ها یا سوالات بدون پاسخ مشتری
            - گام‌های بعدی توافق شده جهت پیگیری قرارداد یا فروش

            رونوشت جلسه:
            \(transcript)
            """

        case .technical:
            return """
            متن زیر رونوشت یک جلسه بررسی معماری یا تصمیم‌گیری فنی است. لطفاً گزارش فنی به زبان فارسی شامل این بخش‌ها ارائه کن:
            - مسئله یا نیازمندی فنی
            - گزینه‌ها و راه‌حل‌های مطرح شده و مقایسه مزایا/معایب
            - تصمیم نهایی معماری (Architectural Decision) و دلایل آن
            - ریسک‌ها و نیازمندی‌های پیاده‌سازی

            رونوشت جلسه:
            \(transcript)
            """
        }
    }
}

enum GeminiService {
    enum GeminiError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "کلید API جمینای تنظیم نشده است"
            case .invalidResponse:
                return "پاسخ نامعتبر از سرور جمینای"
            case .apiError(let msg):
                return msg
            }
        }
    }

    private static let apiModel = "gemini-2.0-flash"

    private static func callGemini(prompt: String, apiKey: String, temperature: Double = 0.3) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }

        var baseHost = AppSettings.geminiCustomHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseHost.isEmpty {
            baseHost = "https://generativelanguage.googleapis.com"
        }
        if baseHost.hasSuffix("/") {
            baseHost.removeLast()
        }

        let url = URL(
            string: "\(baseHost)/v1beta/models/\(apiModel):generateContent?key=\(apiKey)"
        )!

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": 3000
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if http.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                if message.contains("User location is not supported") {
                    throw GeminiError.apiError("تحریم منطقه‌ای گوگل (User location not supported): اتصال مستقیم به هوش مصنوعی جمینای از موقعیت مکانی شما (ایران) توسط گوگل مسدود است. لطفاً VPN خود را روشن کنید یا در تنظیمات آدرس پروکسی/هاست اختصاصی وارد نمایید.")
                }
                throw GeminiError.apiError(message)
            }
            throw GeminiError.apiError("HTTP \(http.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let result = parts.first?["text"] as? String else {
            throw GeminiError.invalidResponse
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func summarize(
        text: String,
        apiKey: String,
        template: SummaryTemplate = .general,
        language: String = "fa"
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "متنی برای خلاصه‌سازی وجود ندارد."
        }

        let prompt = template.buildPrompt(transcript: text)
        return try await callGemini(prompt: prompt, apiKey: apiKey)
    }

    /// Extract actionable tasks / next steps as interactive items.
    static func extractActionItems(
        text: String,
        apiKey: String
    ) async throws -> [MeetingActionItem] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let prompt = """
        متن زیر رونوشت یک جلسه است. لطفاً فقط و فقط تمام وظایف، اقدامات بعدی (Action Items) و تعهداتی که باید انجام شوند را استخراج کن.
        هر اقدام را در یک خط جداگانه بنویس و با علامت - شروع کن.
        اگر مسئول مشخص است، در ابتدای پرانتز بنویس (مثلاً: - (علی) آماده کردن داکیومنت معماری).
        هیچ توضیح اضافه، مقدمه یا موخره‌ای ننویس.

        رونوشت:
        \(text)
        """

        let response = try await callGemini(prompt: prompt, apiKey: apiKey, temperature: 0.2)
        let lines = response.components(separatedBy: .newlines)

        var items: [MeetingActionItem] = []
        for line in lines {
            var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("-") || cleaned.hasPrefix("*") || cleaned.hasPrefix("•") {
                cleaned.removeFirst()
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !cleaned.isEmpty else { continue }

            var assignee: String?
            if cleaned.hasPrefix("(") {
                if let closeIdx = cleaned.firstIndex(of: ")") {
                    let name = String(cleaned[cleaned.index(after: cleaned.startIndex)..<closeIdx])
                    assignee = name
                    cleaned = String(cleaned[cleaned.index(after: closeIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            items.append(MeetingActionItem(text: cleaned, isCompleted: false, assignee: assignee))
        }

        return items
    }

    /// Chat with the meeting context (Ask questions about decisions, attendees, topics).
    static func chatWithMeeting(
        question: String,
        transcript: String,
        summary: String?,
        apiKey: String
    ) async throws -> String {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "لطفاً سوال خود را بنویسید."
        }

        let summaryContext = summary.map { "خلاصه قبلی جلسه:\n\($0)\n" } ?? ""
        let prompt = """
        تو دستیار هوشمند جلسه (میرزا بنویس) هستی. به سوال کاربر با دقت کامل و منحصراً بر اساس متن و اطلاعات این جلسه پاسخ بده.
        پاسخ باید دقیق، ساختاریافته و به زبان فارسی سلیس باشد. اگر اطلاعاتی در جلسه وجود ندارد، صادقانه بگو در متن جلسه مطرح نشده است.

        \(summaryContext)
        رونوشت کامل جلسه:
        \(transcript)

        سوال کاربر:
        \(question)
        """

        return try await callGemini(prompt: prompt, apiKey: apiKey, temperature: 0.3)
    }
}
