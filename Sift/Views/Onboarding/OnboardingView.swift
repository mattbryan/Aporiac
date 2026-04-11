import SwiftUI
import AuthenticationServices
import CryptoKit

struct OnboardingView: View {
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            // Dark background
            Color(red: 0.11, green: 0.11, blue: 0.11).ignoresSafeArea()

            TabView(selection: $currentPage) {
                // Page 1: Writing
                FeaturePage(
                    headline: "Writing is thinking,\nit's meant to be messy",
                    subtitle: "Sift is a place to think out loud. Write freely. Highlight the gems and let everything else fade.",
                    illustrationName: "Onboarding_Writing"
                )
                .tag(0)

                // Page 2: Signal
                FeaturePage(
                    headline: "Embrace noise,\nboost signal",
                    subtitle: "Entries live for seven days. Actions live until you complete them. Gems live forever.",
                    illustrationName: "Onboarding_Signal"
                )
                .tag(1)

                // Page 3: Focus
                FeaturePage(
                    headline: "Maintain focus\non what matters",
                    subtitle: "Choose themes & habits to guide your thoughts and progress over time.",
                    illustrationName: "Onboarding_Focus"
                )
                .tag(2)

                // Page 4: Auth
                AuthPage()
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Feature Page

private struct FeaturePage: View {
    let headline: String
    let subtitle: String
    let illustrationName: String

    var body: some View {
        VStack(spacing: 0) {
            // Top spacing
            Spacer()
                .frame(height: DS.Spacing.pageTop)

            // Headline — H1 Bold italic
            Text(headline)
                .font(.siftH1Bold)
                .tracking(SiftTracking.h1Bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
                .padding(.horizontal, DS.Spacing.screenEdge)

            // Subtitle — P2 Regular
            Text(subtitle)
                .font(.siftP2Regular)
                .tracking(SiftTracking.p2Regular)
                .foregroundColor(Color.siftSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1.5)
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.md)

            // Flexible space
            Spacer()

            // Illustration — proportional to available space
            if let image = UIImage(named: illustrationName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, DS.Spacing.xl)
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(Color(white: 0.2), lineWidth: 1)
                    .padding(.horizontal, DS.Spacing.xl)
            }

            // Space before page dots
            Spacer()
                .frame(height: DS.Spacing.lg)
        }
    }
}

// MARK: - Auth Page

private struct AuthPage: View {
    @State private var currentNonce: String?
    @State private var authError: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Top flexible space
            Spacer()

            // Logo — Newsreader Italic 188px
            Text("sift")
                .font(.custom("Newsreader", size: 188).italic())
                .foregroundColor(Color.siftAccent)

            // Subtitle — Newsreader Medium 20px with 75px line height
            Text("by APORIAC")
                .font(.custom("Newsreader", size: 20).weight(.medium))
                .foregroundColor(Color.siftSecondary)
                .lineSpacing(55)  // 75 - 20 = 55 additional spacing
                .multilineTextAlignment(.center)
                .frame(maxWidth: 366)

            // Large middle space
            Spacer()

            // Error message
            if let error = authError {
                Text(error)
                    .font(.siftCaption)
                    .foregroundStyle(Color.siftSubtle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .padding(.bottom, DS.Spacing.md)
            }

            // Sign in button
            if isLoading {
                ProgressView()
                    .tint(Color.siftAccent)
                    .frame(height: DS.ButtonHeight.large)
            } else {
                SignInWithAppleButton(.continue) { request in
                    let nonce = generateNonce()
                    currentNonce = nonce
                    request.requestedScopes = [.email]
                    request.nonce = sha256(nonce)
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: DS.ButtonHeight.large)
                .cornerRadius(DS.Radius.sm)
            }

            Spacer()
                .frame(height: DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                authError = "Sign in failed. Please try again."
                return
            }
            isLoading = true
            authError = nil
            Task {
                do {
                    try await SupabaseService.shared.signInWithApple(idToken: idToken, nonce: nonce)
                } catch {
                    isLoading = false
                    authError = "Sign in failed. Please try again."
                    print("[Onboarding] Apple sign-in failed: \(error)")
                }
            }

        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                authError = "Sign in failed. Please try again."
                print("[Onboarding] Apple sign-in error: \(error)")
            }
        }
    }

    private func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Failed to generate nonce")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    OnboardingView()
}
