import Foundation

struct AIBackendService: AIService {
    private let endpointURL: URL
    private let authToken: String
    private let session: URLSession

    init?(bundle: Bundle = .main, session: URLSession = .shared) {
        guard let baseURLString = bundle.object(forInfoDictionaryKey: "AI_BACKEND_URL") as? String,
              let baseURL = URL(string: baseURLString),
              let authToken = bundle.object(forInfoDictionaryKey: "AI_BACKEND_AUTH_TOKEN") as? String,
              !authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.endpointURL = baseURL.appendingPathComponent("generate-incident-summary")
        self.authToken = authToken
        self.session = session
    }

    func analyzeIncident(draft: IncidentDraft) async throws -> AIIncidentAnalysis {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let backendRequest = AIBackendRequest(draft: draft)
        let requestBody = try JSONEncoder().encode(backendRequest)
        request.httpBody = requestBody

        AIDebugLogger.log("User incident text", draft.originalNotes)
        AIDebugLogger.log("AIBackendService request URL", endpointURL.absoluteString)
        AIDebugLogger.log("Prompt/input sent to AIService", String(data: requestBody, encoding: .utf8) ?? "<unreadable request>")

        let (data, response) = try await session.data(for: request)
        AIDebugLogger.log("Raw AIService response", String(data: data, encoding: .utf8) ?? "<unreadable response>")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIBackendServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(AIBackendErrorResponse.self, from: data)
            throw AIBackendServiceError.server(errorResponse?.error ?? "AI request failed.")
        }

        let backendResponse = try JSONDecoder().decode(AIBackendResponse.self, from: data)
        let analysis = backendResponse.analysis
        AIDebugLogger.log("Parsed response", analysis.debugSummary)
        return analysis
    }

    func generateFinalDocumentation(draft: IncidentDraft, analysis: AIIncidentAnalysis?) async throws -> FinalDocumentationSummary {
        let finalEndpointURL = endpointURL.deletingLastPathComponent().appendingPathComponent("generate-final-documentation-summary")
        var request = URLRequest(url: finalEndpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let requestBody = try JSONEncoder().encode(AIFinalDocumentationRequest(draft: draft, analysis: analysis))
        request.httpBody = requestBody

        AIDebugLogger.log("Final documentation request URL", finalEndpointURL.absoluteString)
        AIDebugLogger.log("Final documentation input", String(data: requestBody, encoding: .utf8) ?? "<unreadable request>")

        let (data, response) = try await session.data(for: request)
        AIDebugLogger.log("Raw final documentation response", String(data: data, encoding: .utf8) ?? "<unreadable response>")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIBackendServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(AIBackendErrorResponse.self, from: data)
            throw AIBackendServiceError.server(errorResponse?.error ?? "Final documentation could not be generated.")
        }

        return try JSONDecoder().decode(FinalDocumentationSummary.self, from: data)
    }

    func analyzeTimeline(entries: [TimelineEntryInput]) async throws -> TimelineAnalysis {
        // Try the backend; fall back to the on-device engine on any failure so the app
        // always has insights even when the backend is unreachable or not yet configured.
        do {
            return try await requestTimelineAnalysis(entries: entries)
        } catch {
            AIDebugLogger.log("analyzeTimeline backend failed; using local engine", "\(error)")
            return TimelineInsightEngine.analyze(entries: entries)
        }
    }

    private func requestTimelineAnalysis(entries: [TimelineEntryInput]) async throws -> TimelineAnalysis {
        let url = endpointURL.deletingLastPathComponent().appendingPathComponent("analyze-timeline")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(TimelineAnalysisRequest(entries: entries))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIBackendServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(AIBackendErrorResponse.self, from: data)
            throw AIBackendServiceError.server(errorResponse?.error ?? "Timeline insights could not be generated.")
        }
        return try JSONDecoder().decode(TimelineAnalysisResponse.self, from: data).model
    }
}

// MARK: - Timeline analysis DTOs (map backend JSON <-> the Color-free domain types)

private struct TimelineAnalysisRequest: Encodable {
    struct Entry: Encodable {
        let id: String
        let date: String
        let kind: String
        let title: String
        let text: String
        let tags: [String]
        let flagged: Bool
        let location: String
    }
    let entries: [Entry]

    init(entries: [TimelineEntryInput]) {
        let formatter = ISO8601DateFormatter()
        self.entries = entries.map { entry in
            Entry(
                id: entry.id,
                date: formatter.string(from: entry.date),
                kind: entry.kind.rawValue,
                title: entry.title,
                text: entry.text,
                tags: entry.tags,
                flagged: entry.flagged,
                location: entry.location
            )
        }
    }
}

private struct TimelineAnalysisResponse: Decodable {
    let insights: [InsightDTO]
    let annotations: [AnnotationDTO]

    var model: TimelineAnalysis {
        TimelineAnalysis(
            insights: insights.map { $0.model },
            annotations: annotations.compactMap { $0.model }
        )
    }
}

private struct InsightDTO: Decodable {
    let type: String
    let iconSystemName: String?
    let eyebrow: String?
    let headline: String
    let body: String?
    let tag: String?
    let firstSeen: String?
    let lastSeen: String?
    let occurrences: Int?
    let visual: VisualDTO?
    let supporting: [SupportDTO]?

    var model: Insight {
        Insight(
            type: type == "affirm" ? .affirm : .concern,
            visual: visual?.model ?? .none,
            iconSystemName: iconSystemName ?? "chart.bar",
            eyebrow: eyebrow ?? "Pattern",
            headline: headline,
            body: body ?? "",
            tag: tag ?? "",
            firstSeen: firstSeen ?? "",
            lastSeen: lastSeen ?? "",
            occurrences: occurrences ?? 0,
            supporting: (supporting ?? []).map { $0.model }
        )
    }
}

private struct VisualDTO: Decodable {
    let type: String
    let dates: [String]?
    let values: [Int]?
    let labels: [String]?

    var model: InsightVisual {
        switch type {
        case "strip": return .strip(dates: dates ?? [])
        case "tally": return .tally(values: values ?? [], labels: labels ?? [])
        default: return .none
        }
    }
}

private struct SupportDTO: Decodable {
    let text: String
    let date: String?
    let kind: String?

    var model: InsightSupport {
        InsightSupport(text: text, date: date ?? "", kind: EntryKind(rawValue: kind ?? "entry") ?? .entry)
    }
}

private struct AnnotationDTO: Decodable {
    let text: String
    let anchorDate: String

    var model: TimelineAnnotation? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: anchorDate) else { return nil }
        return TimelineAnnotation(text: text, anchorDate: date)
    }
}

extension AIBackendService: AIServiceStatusProviding {
    var serviceMode: AIServiceMode {
        .backend(endpointURL.deletingLastPathComponent())
    }
}

enum AIServiceMode {
    case mock
    case backend(URL)

    var displayName: String {
        switch self {
        case .mock:
            return "Mock AI"
        case .backend:
            return "Backend AI"
        }
    }
}

protocol AIServiceStatusProviding {
    var serviceMode: AIServiceMode { get }
}

enum AIServiceFactory {
    static func makeService() -> any AIService {
        if let backendService = AIBackendService() {
            return backendService
        }

        return MockAIService()
    }
}

private struct AIBackendRequest: Encodable {
    let systemInstructions: String
    let incidentText: String
    let currentCategory: String
    let peopleInvolved: String
    let location: String
    let childInvolved: Bool
    let evidenceNotes: String
    let existingFollowUpAnswers: [AIBackendFollowUpAnswer]

    init(draft: IncidentDraft) {
        systemInstructions = FactTrailAIInstructions.fullPrompt
        incidentText = draft.originalNotes
        currentCategory = draft.category.rawValue
        peopleInvolved = draft.peopleInvolved
        location = draft.location
        childInvolved = draft.childInvolved
        evidenceNotes = draft.evidenceNotes
        existingFollowUpAnswers = draft.guidedAnswers.map {
            AIBackendFollowUpAnswer(question: $0.question, answer: $0.answer)
        }
    }
}

private struct AIBackendFollowUpAnswer: Codable {
    let question: String
    let answer: String
}

private struct AIFinalDocumentationRequest: Encodable {
    let systemInstructions: String
    let originalNotes: String
    let incidentDate: Date
    let category: String
    let peopleInvolved: String
    let location: String
    let childInvolved: Bool
    let evidenceNotes: String
    let evidenceTypes: [String]
    let patternTags: [String]
    let followUpAnswers: [AIBackendFollowUpAnswer]
    let initialAnalysis: AIIncidentAnalysis?

    init(draft: IncidentDraft, analysis: AIIncidentAnalysis?) {
        systemInstructions = FactTrailAIInstructions.fullPrompt
        originalNotes = draft.originalNotes
        incidentDate = draft.incidentDate
        category = draft.category.rawValue
        peopleInvolved = draft.peopleInvolved
        location = draft.location
        childInvolved = draft.childInvolved
        evidenceNotes = draft.evidenceNotes
        evidenceTypes = draft.evidenceTypes.map(\.rawValue)
        patternTags = draft.patternTags.map(\.rawValue)
        followUpAnswers = draft.guidedAnswers.map {
            AIBackendFollowUpAnswer(question: $0.question, answer: $0.answer)
        }
        initialAnalysis = analysis
    }
}

private struct AIBackendResponse: Decodable {
    let understandingSummary: [String]?
    let suggestedCategory: String
    let categoryReason: String?
    let categoryRationale: String?
    let neutralSummary: String
    let missingInformation: [String]?
    let missingInformationFields: [String]?
    let evidenceMentioned: [String]?
    let patternTags: [String]
    let followUpQuestions: [AIBackendFollowUpQuestion]
    let disclaimer: String

    var analysis: AIIncidentAnalysis {
        let category = IncidentCategory(rawValue: suggestedCategory) ?? .other
        let reason = categoryReason ?? categoryRationale ?? "Suggested by the backend AI service based on the incident details."
        let missing = missingInformation ?? missingInformationFields ?? []
        let evidence = evidenceMentioned ?? []
        let tags = patternTags.compactMap { PatternTag(rawValue: $0) }
        let questions = followUpQuestions.map { $0.model }

        return AIIncidentAnalysis(
            understandingSummary: understandingSummary ?? [],
            suggestedCategory: category,
            categoryReason: reason,
            neutralSummary: neutralSummary,
            missingInformation: missing,
            evidenceMentioned: evidence,
            patternTags: tags,
            followUpQuestions: questions,
            disclaimer: disclaimer,
            debugSnapshot: nil
        )
    }
}

private struct AIBackendFollowUpQuestion: Decodable {
    let priority: String?
    let question: String
    let whyItMatters: String?

    private enum CodingKeys: String, CodingKey {
        case priority
        case question
        case whyItMatters
    }

    init(from decoder: Decoder) throws {
        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            priority = FollowUpPriority.helpfulContext.rawValue
            question = stringValue
            whyItMatters = "This may help make the documentation more complete and specific."
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        question = try container.decode(String.self, forKey: .question)
        whyItMatters = try container.decodeIfPresent(String.self, forKey: .whyItMatters)
    }

    var model: AIFollowUpQuestion {
        AIFollowUpQuestion(
            priority: FollowUpPriority(rawValue: priority ?? "") ?? .helpfulContext,
            question: question,
            whyItMatters: whyItMatters ?? "This may help make the documentation more complete and specific."
        )
    }
}

private struct AIBackendErrorResponse: Decodable {
    let error: String
}

enum AIBackendServiceError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The AI service returned an unexpected response."
        case .server(let message):
            return message
        }
    }
}
