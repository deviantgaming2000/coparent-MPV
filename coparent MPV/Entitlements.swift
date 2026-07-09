import SwiftUI
import Observation

/// Tracks access to Coparo's premium features (AI insights, neutral rewriting, and
/// Court Mode) via a 14-day free trial that starts on first launch.
///
/// There is no App Store product wired yet: `subscribe()` unlocks locally so the flow
/// is fully testable now. Before release, replace the body of `subscribe()`/`restore()`
/// with StoreKit 2 purchase/restore against an App Store Connect auto-renewable
/// subscription (with a 14-day introductory free-trial offer). Everything else — the
/// trial clock, the gating, and the paywall — stays the same.
@Observable
final class EntitlementManager {
    static let trialLengthDays = 14

    private let trialStartKey = "coparoTrialStartDate"
    private let subscribedKey = "coparoIsSubscribed"

    /// Local stand-in for an active App Store subscription.
    var isSubscribed: Bool {
        didSet { UserDefaults.standard.set(isSubscribed, forKey: subscribedKey) }
    }

    init() {
        isSubscribed = UserDefaults.standard.bool(forKey: subscribedKey)
        startTrialIfNeeded()
    }

    /// Stamps the trial start the first time the app runs, so the 14 days are counted
    /// from first launch.
    func startTrialIfNeeded() {
        if UserDefaults.standard.object(forKey: trialStartKey) == nil {
            UserDefaults.standard.set(Date(), forKey: trialStartKey)
        }
    }

    var trialStartDate: Date {
        UserDefaults.standard.object(forKey: trialStartKey) as? Date ?? Date()
    }

    var trialEndDate: Date {
        Calendar.current.date(byAdding: .day, value: Self.trialLengthDays, to: trialStartDate) ?? trialStartDate
    }

    /// Whole days left in the trial (0 once it has ended).
    var trialDaysRemaining: Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEndDate).day ?? 0
        return max(0, days)
    }

    var isTrialActive: Bool { Date() < trialEndDate }

    /// Whether premium features are currently available — during the free trial or with
    /// an active subscription.
    var isPremium: Bool { isSubscribed || isTrialActive }

    /// A short status line for the paywall / settings row.
    var statusLine: String {
        if isSubscribed { return "Coparo Plus is active." }
        if isTrialActive {
            let d = trialDaysRemaining
            return d <= 0 ? "Your free trial ends today." : "Free trial - \(d) day\(d == 1 ? "" : "s") left."
        }
        return "Your free trial has ended."
    }

    // MARK: Purchase (placeholder until StoreKit is wired to App Store Connect)

    func subscribe() { isSubscribed = true }
    func restore() { /* StoreKit restore goes here */ }

    #if DEBUG
    /// Testing helper: reset the trial clock to now.
    func resetTrialForTesting() {
        UserDefaults.standard.removeObject(forKey: trialStartKey)
        isSubscribed = false
        startTrialIfNeeded()
    }
    #endif
}

// MARK: - Paywall

/// "Coparo Plus" paywall. Explains what the subscription unlocks and starts the trial /
/// (placeholder) purchase. Shown when a premium feature is used after the trial ends,
/// or from the menu.
struct CoparoPlusView: View {
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let features: [(icon: String, title: String, sub: String)] = [
        ("sparkles", "Smart summaries", "Neutral, court-ready write-ups of what you logged."),
        ("chart.line.uptrend.xyaxis", "Pattern insights", "Coparo quietly surfaces trends worth noticing."),
        ("building.columns", "Court Mode", "Prepare your records so they're ready if you ever need them.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coparo Plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Text("The smart features that help make sense of your record - free to try for 14 days.")
                        .font(.system(size: 14))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    ForEach(features, id: \.title) { f in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: f.icon)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                                .frame(width: 34, height: 34)
                                .background(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                                Text(f.sub)
                                    .font(.system(size: 13))
                                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
                    }
                }

                Text(entitlements.statusLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))

                VStack(spacing: 10) {
                    if entitlements.isSubscribed {
                        Text("You're all set - Coparo Plus is active.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            .frame(maxWidth: .infinity)
                    } else {
                        Button {
                            entitlements.subscribe()
                            dismiss()
                        } label: {
                            Text(entitlements.isTrialActive ? "Continue - 14-day free trial" : "Start your 14-day free trial")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FactTrailPrimaryButtonStyle())

                        Text("Free for 14 days, then $2.99/month. Cancel anytime.")
                            .font(.system(size: 12))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            .frame(maxWidth: .infinity)

                        Button("Restore purchases") { entitlements.restore() }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Coparo Plus")
        .navigationBarTitleDisplayMode(.inline)
    }
}
