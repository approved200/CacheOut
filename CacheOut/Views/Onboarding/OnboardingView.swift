import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenTour")            private var hasSeenTour = false
    @State private var page: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Pages 0-2: standard onboarding screens
            // Page 3: the feature tour (embedded, not a sheet)
            if page < 3 {
                Group {
                    switch page {
                    case 0:  welcomePage
                    case 1:  permissionsPage
                    default: prefsPage
                    }
                }
                .frame(width: 480, height: 400)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                // Tour as the final onboarding step — user sees flow without interruption
                EmbeddedTourView {
                    // On "Get started" — mark both complete
                    hasSeenTour            = true
                    hasCompletedOnboarding = true
                }
                .frame(width: 560, height: 500)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .animation(
            reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8),
            value: page
        )
    }

    // MARK: — Page 1: Welcome
    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to Cache Out")
                .font(.system(size: 28, weight: .bold))

            Text("The free, open-source Mac cleaner\nbuilt for developers.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)

            Spacer()

            Button("Continue") {
                withAnimation { page = 1 }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.bottom, 32)
        }
    }

    // MARK: — Page 2: Permissions
    private var permissionsPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Full disk access")
                .font(.system(size: 22, weight: .semibold))

            Text("Cache Out needs Full Disk Access to scan all\ncache folders, logs, and app remnants.\nWithout it, some items may not appear.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Spacer()

            HStack(spacing: 12) {
                Button("Skip for now") { withAnimation { page = 2 } }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    withAnimation { page = 2 }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: — Page 3: Tour prompt
    private var prefsPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("One last thing")
                .font(.system(size: 22, weight: .semibold))

            Text("Take a quick tour to see what each\ntool does — takes about 30 seconds.")
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)

            Spacer()

            HStack(spacing: 12) {
                Button("Skip tour") {
                    hasSeenTour            = true
                    hasCompletedOnboarding = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Take the tour →") { withAnimation { page = 3 } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.bottom, 32)
        }
    }
}
