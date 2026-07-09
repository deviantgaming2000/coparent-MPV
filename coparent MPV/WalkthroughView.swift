import SwiftUI

/// The launch / loading splash. Blue-to-teal gradient with a glass ring around the
/// Coparo mark, wordmark, and tagline — matches the design prototype. Shared by the
/// app launch screen and the first-run onboarding splash so they're identical.
struct CoparoSplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x2F5D8C), location: 0),
                    .init(color: Color(hex: 0x3D7A8C), location: 0.55),
                    .init(color: Color(hex: 0x4F8F8B), location: 1)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .offset(x: 90, y: -80)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 320, height: 320)
                    .blur(radius: 70)
                    .offset(x: -90, y: 90)
            }

            VStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 84, height: 84)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    }
                    .overlay {
                        Image("coparo-mark-white")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 46, height: 46)
                    }
                    .padding(.bottom, 22)

                Text("Coparo")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                Text("A clear record, quietly kept.")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(i == 0 ? 1 : 0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 60)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { appeared = true }
        }
    }
}

/// The little illustrative mock shown under each walkthrough card.
enum WalkthroughPreview {
    case compose, checkins, locked, insights
}

/// One concept page in the intro walkthrough. Shared by first-run onboarding and the
/// "replay" entry point in Help & FAQ so the explanation lives in exactly one place.
struct WalkthroughPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
    let preview: WalkthroughPreview
}

enum CoparoWalkthroughContent {
    static let pages: [WalkthroughPage] = [
        WalkthroughPage(
            icon: "square.and.pencil",
            title: "Log an entry",
            body: "Everything starts here. Tap the + and describe what happened. Voice-to-text works anywhere you see the microphone.",
            preview: .compose
        ),
        WalkthroughPage(
            icon: "clock",
            title: "Check-ins track the schedule",
            body: "After each handoff, confirm who has the kids - a consistent, timestamped record of where they were and when.",
            preview: .checkins
        ),
        WalkthroughPage(
            icon: "lock",
            title: "Entries lock after 5 minutes",
            body: "After five minutes, entries are sealed - no edits, no deletions. That's what makes this a record worth keeping.",
            preview: .locked
        ),
        WalkthroughPage(
            icon: "waveform.path.ecg",
            title: "Patterns surface over time",
            body: "Coparo quietly watches for things worth noticing and surfaces them for you. That's all there is to it.",
            preview: .insights
        )
    ]
}

/// A brief, skippable paged explainer of the core concepts. `onFinish` is called when
/// the user reaches the end or taps Skip; the host decides what that means (advance
/// onboarding, or dismiss the replay sheet).
struct CoparoWalkthrough: View {
    var pages: [WalkthroughPage] = CoparoWalkthroughContent.pages
    let onFinish: () -> Void
    /// Text of the final-page button (e.g. "Get started" in onboarding, "Done" on replay).
    var finishTitle: String = "Get started"

    @Environment(\.colorScheme) private var colorScheme
    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    pageView(page)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: index)

            dots

            OBPrimaryButton(title: index == pages.count - 1 ? finishTitle : "Next") {
                if index == pages.count - 1 {
                    onFinish()
                } else {
                    withAnimation { index += 1 }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
    }

    private func pageView(_ page: WalkthroughPage) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.12))
                .frame(width: 66, height: 66)
                .overlay(
                    Image(systemName: page.icon)
                        .font(.system(size: 27, weight: .regular))
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                )
                .padding(.bottom, 22)

            Text(page.title)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            Text(page.body)
                .font(.system(size: 15))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)

            previewMock(page.preview)
                .frame(height: 190)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }

    // MARK: Preview mocks (decorative, echo the prototype's tour illustrations)

    private var accent: Color { FactTrailTheme.aiAccent(for: colorScheme) }
    private var line: Color { FactTrailTheme.border(for: colorScheme) }

    private func previewShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(line, lineWidth: 1) }
    }

    private func bar(_ widthFraction: CGFloat, color: Color? = nil, height: CGFloat = 9) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color ?? line.opacity(0.9))
            .frame(width: nil, height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: widthFraction, y: 1, anchor: .leading)
    }

    @ViewBuilder
    private func previewMock(_ kind: WalkthroughPreview) -> some View {
        switch kind {
        case .compose:
            previewShell {
                bar(0.5, color: accent.opacity(0.5))
                bar(0.9)
                bar(0.7)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FactTrailTheme.primaryAction(for: colorScheme))
                    .frame(height: 30)
            }
        case .checkins:
            previewShell {
                bar(0.4, color: line.opacity(0.6), height: 7)
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 5) {
                        bar(0.55, color: accent.opacity(0.4), height: 7)
                        bar(0.8, height: 7)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.06)))
                }
                Spacer(minLength: 0)
            }
        case .locked:
            previewShell {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(i == 2 ? accent : FactTrailTheme.mutedText(for: colorScheme))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(i == 2 ? accent.opacity(0.12) : line.opacity(0.5))
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            bar(i == 2 ? 0.8 : 0.7, height: 7)
                            if i != 2 { bar(0.5, height: 7) }
                        }
                    }
                    .opacity(i == 2 ? 1 : 0.85)
                }
                Spacer(minLength: 0)
            }
        case .insights:
            previewShell {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent.opacity(0.5))
                        .frame(width: 46, height: 12)
                    bar(0.85, height: 8)
                    bar(0.65, height: 8)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(accent.opacity(0.08)))
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent.opacity(0.4))
                        .frame(width: 36, height: 11)
                    bar(0.7, height: 7)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(accent.opacity(0.05)))
                .opacity(0.6)
                Spacer(minLength: 0)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<pages.count, id: \.self) { i in
                Circle()
                    .fill(i == index ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.border(for: colorScheme))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.vertical, 16)
    }
}

// MARK: - FAQ

private struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

/// Help & FAQ screen, reachable from the menu. Carries the same explanations as the
/// walkthrough (immutability, Court Mode) plus a button to replay the intro.
struct FAQView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingWalkthrough = false
    @State private var expandedID: UUID?

    private let items: [FAQItem] = [
        FAQItem(
            question: "Why do entries lock after a few minutes?",
            answer: "So your record is credible. Once an entry locks, the original can't be edited or deleted - which means no one can claim you changed it after the fact. It protects you."
        ),
        FAQItem(
            question: "Can I still add information later?",
            answer: "Yes. You can add follow-up notes to any entry at any time. Each note is timestamped on its own, so it's clear what you knew and when - the original just stays as first written."
        ),
        FAQItem(
            question: "What is Court Mode?",
            answer: "It tells Coparo to quietly prepare neutral, court-ready summaries of your entries, so they're organized and ready if you ever need them. Everything stays timestamped and preserved either way."
        ),
        FAQItem(
            question: "Where is my data stored?",
            answer: "On your device. Coparo doesn't send your records to a server on its own. You decide if and when to export or share anything."
        ),
        FAQItem(
            question: "What does the AI actually do?",
            answer: "It helps organize and phrase what you logged - suggesting a category or a neutral summary. It never adds facts or draws conclusions, and you review everything before it's part of your record."
        ),
        FAQItem(
            question: "What are check-ins?",
            answer: "A one-tap way to save where you are and when - handy at exchanges or pickups. You can add a note or start a full entry right after."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The short version of how Coparo works, and why.")
                    .font(.system(size: 13))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

                Button {
                    isShowingWalkthrough = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replay the intro")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            Text("Take the quick walkthrough again")
                                .font(.system(size: 12))
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.6))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
                }
                .buttonStyle(.plain)

                VStack(spacing: 10) {
                    ForEach(items) { item in
                        faqRow(item)
                    }
                }
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingWalkthrough) {
            CoparoWalkthrough(onFinish: { isShowingWalkthrough = false }, finishTitle: "Done")
                .presentationDragIndicator(.visible)
        }
    }

    private func faqRow(_ item: FAQItem) -> some View {
        let isExpanded = expandedID == item.id
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                expandedID = isExpanded ? nil : item.id
            }
        } label: {
            VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(item.question)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                if isExpanded {
                    Text(item.answer)
                        .font(.system(size: 13.5))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
