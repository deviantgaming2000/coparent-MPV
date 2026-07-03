import Foundation
import UIKit

enum IncidentPDFExporter {
    static func makeTimelinePDF(for incidents: [Incident]) throws -> URL {
        let fileName = "FactTrail-Timeline-\(Date().timeIntervalSince1970).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        try renderer.writePDF(to: outputURL) { context in
            let writer = PDFPageWriter(context: context, pageBounds: pageBounds)

            writer.startPage()
            writer.addTitle("FactTrail Timeline")
            writer.addText("Exported: \(DateFormatter.factTrailDateTime.string(from: Date()))", font: .systemFont(ofSize: 11), color: .secondaryLabel)
            writer.addText("Number of events: \(incidents.count)", font: .systemFont(ofSize: 11), color: .secondaryLabel)
            writer.addSpacing(12)

            for (index, incident) in incidents.enumerated() {
                writer.addHeading("Event \(index + 1)")
                writer.addText("Date/Time: \(DateFormatter.factTrailDateTime.string(from: incident.incidentDate))")
                writer.addText("Category: \(incident.category)")
                writer.addSection(title: "Original Notes", text: incident.originalNotes)
                if let analysis = incident.aiAnalysis {
                    writer.addSection(title: "AI Understanding", text: analysis.understandingSummary.joined(separator: "\n"))
                }
                writer.addText("People Involved: \(displayValue(incident.peopleInvolved))")
                writer.addText("Location: \(displayValue(incident.location))")
                writer.addText("Child Involved: \(incident.childInvolved ? "Yes" : "No")")
                writer.addSection(title: "Evidence Notes", text: incident.evidenceNotes)
                if let analysis = incident.aiAnalysis, !analysis.evidenceMentioned.isEmpty {
                    writer.addText("Evidence Mentioned: \(analysis.evidenceMentioned.joined(separator: ", "))")
                }

                if !incident.guidedAnswers.isEmpty {
                    writer.addHeading("Follow-Up Questions and Answers")
                    for answer in incident.guidedAnswers {
                        let answerText = answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not answered" : answer.answer
                        writer.addText("\(answer.question)\n\(answerText)")
                    }
                } else if !incident.followUpQuestions.isEmpty {
                    writer.addHeading("Follow-Up Questions")
                    for question in incident.followUpQuestions {
                        writer.addText(question)
                    }
                }

                if !incident.patternTags.isEmpty {
                    writer.addText("Pattern Tags: \(incident.patternTags.map(\.displayName).joined(separator: ", "))")
                }

                writer.addSection(
                    title: incident.finalDocumentationSummary.isEmpty ? "Neutral Summary" : "Final Documentation Summary",
                    text: incident.finalDocumentationSummary.isEmpty ? incident.neutralSummary : incident.finalDocumentationSummary
                )

                if let completeness = incident.documentationCompleteness {
                    writer.addText("Documentation Completeness: \(completeness.score)% - \(completeness.status)")
                    if !completeness.completedItems.isEmpty {
                        writer.addText("Completed: \(completeness.completedItems.joined(separator: ", "))")
                    }
                    if !completeness.missingItems.isEmpty {
                        writer.addText("Still Missing: \(completeness.missingItems.joined(separator: ", "))")
                    }
                }

                writer.addSpacing(16)
            }
        }

        return outputURL
    }

    static func makePDF(for incident: Incident) throws -> URL {
        var draft = IncidentDraft()
        draft.originalNotes = incident.originalNotes
        draft.incidentDate = incident.incidentDate
        draft.peopleInvolved = incident.peopleInvolved
        draft.location = incident.location
        draft.childInvolved = incident.childInvolved
        draft.evidenceNotes = incident.evidenceNotes
        draft.evidenceAttachments = incident.evidenceAttachments
        draft.evidenceTypes = incident.evidenceTypes
        draft.guidedAnswers = incident.guidedAnswers
        draft.patternTags = incident.patternTags
        draft.aiAnalysis = incident.aiAnalysis
        if !incident.finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.finalDocumentation = FinalDocumentationSummary(
                summary: incident.finalDocumentationSummary,
                completeness: incident.documentationCompleteness ?? DocumentationCompletenessCalculator.calculate(draft: draft, analysis: incident.aiAnalysis)
            )
        }
        draft.category = IncidentCategory(rawValue: incident.category) ?? .other

        let summaryDraft = IncidentSummaryDraft(
            draft: draft,
            neutralSummary: incident.neutralSummary,
            followUpQuestions: incident.followUpQuestions
        )

        return try makePDF(for: summaryDraft)
    }

    static func makePDF(for summaryDraft: IncidentSummaryDraft) throws -> URL {
        let fileName = "FactTrail-Summary-\(summaryDraft.draft.incidentDate.timeIntervalSince1970).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        try renderer.writePDF(to: outputURL) { context in
            let writer = PDFPageWriter(context: context, pageBounds: pageBounds)

            writer.startPage()
            writer.addTitle("FactTrail Summary")
            writer.addText("Created: \(DateFormatter.factTrailDateTime.string(from: Date()))", font: .systemFont(ofSize: 11), color: .secondaryLabel)
            writer.addSpacing(12)

            writer.addSection(title: "Original Notes", text: summaryDraft.draft.originalNotes)
            if let analysis = summaryDraft.draft.aiAnalysis {
                writer.addSection(title: "AI Understanding", text: analysis.understandingSummary.joined(separator: "\n"))
                if !analysis.evidenceMentioned.isEmpty {
                    writer.addText("Evidence Mentioned: \(analysis.evidenceMentioned.joined(separator: ", "))")
                }
            }
            writer.addSection(
                title: summaryDraft.draft.finalDocumentation == nil ? "Neutral Summary" : "Final Documentation Summary",
                text: summaryDraft.draft.finalDocumentation?.summary ?? summaryDraft.neutralSummary
            )

            if !summaryDraft.draft.evidenceAttachments.isEmpty {
                writer.addHeading("Attached Photos and Screenshots")
                writer.addText("\(summaryDraft.draft.evidenceAttachments.count) attachment\(summaryDraft.draft.evidenceAttachments.count == 1 ? "" : "s") included below.")
                writer.addSpacing(8)

                for attachment in summaryDraft.draft.evidenceAttachments {
                    writer.addImageAttachment(attachment)
                }
            }

            writer.addHeading("Follow-Up Questions")
            for (index, question) in summaryDraft.followUpQuestions.enumerated() {
                writer.addText("\(index + 1). \(question)")
            }

            if let completeness = summaryDraft.draft.finalDocumentation?.completeness {
                writer.addHeading("Documentation Completeness")
                writer.addText("\(completeness.score)% - \(completeness.status)")
                if !completeness.completedItems.isEmpty {
                    writer.addText("Completed: \(completeness.completedItems.joined(separator: ", "))")
                }
                if !completeness.missingItems.isEmpty {
                    writer.addText("Still Missing: \(completeness.missingItems.joined(separator: ", "))")
                }
            }
        }

        return outputURL
    }

    private static func displayValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not specified" : trimmed
    }
}

private final class PDFPageWriter {
    private let context: UIGraphicsPDFRendererContext
    private let pageBounds: CGRect
    private let inset: CGFloat = 42
    private let bottomInset: CGFloat = 42
    private var cursorY: CGFloat = 42

    init(context: UIGraphicsPDFRendererContext, pageBounds: CGRect) {
        self.context = context
        self.pageBounds = pageBounds
    }

    func startPage() {
        context.beginPage()
        cursorY = inset
    }

    func addTitle(_ text: String) {
        addText(text, font: .boldSystemFont(ofSize: 24), color: .label, spacingAfter: 8)
    }

    func addHeading(_ text: String) {
        addSpacing(10)
        addText(text, font: .boldSystemFont(ofSize: 15), color: .label, spacingAfter: 6)
    }

    func addSection(title: String, text: String) {
        addHeading(title)
        addText(text.isEmpty ? "Not specified" : text)
    }

    func addText(
        _ text: String,
        font: UIFont = .systemFont(ofSize: 12),
        color: UIColor = .label,
        spacingAfter: CGFloat = 8
    ) {
        let maxWidth = pageBounds.width - (inset * 2)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textBounds = attributedText.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        ensureSpace(for: ceil(textBounds.height) + spacingAfter)
        attributedText.draw(in: CGRect(x: inset, y: cursorY, width: maxWidth, height: ceil(textBounds.height)))
        cursorY += ceil(textBounds.height) + spacingAfter
    }

    func addImageAttachment(_ attachment: EvidenceAttachment) {
        guard let image = UIImage(data: attachment.data) else {
            addText("Attachment could not be rendered: \(attachment.fileName)")
            return
        }

        let maxWidth = pageBounds.width - (inset * 2)
        let maxHeight: CGFloat = 260
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height, 1)
        let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        ensureSpace(for: imageSize.height + 28)
        addText(attachment.fileName, font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 4)
        image.draw(in: CGRect(x: inset, y: cursorY, width: imageSize.width, height: imageSize.height))
        cursorY += imageSize.height + 12
    }

    func addSpacing(_ amount: CGFloat) {
        ensureSpace(for: amount)
        cursorY += amount
    }

    private func ensureSpace(for height: CGFloat) {
        if cursorY + height > pageBounds.height - bottomInset {
            startPage()
        }
    }
}
