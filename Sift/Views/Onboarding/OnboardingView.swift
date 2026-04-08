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
                    illustrationName: "Onboarding_Writing",
                    page: 0
                )
                .tag(0)

                // Page 2: Signal
                FeaturePage(
                    headline: "Embrace noise,\nboost signal",
                    subtitle: "Entries live for seven days. Actions live until you complete them. Gems live forever.",
                    illustrationName: "Onboarding_Signal",
                    page: 1
                )
                .tag(1)

                // Page 3: Focus
                FeaturePage(
                    headline: "Maintain focus\non what matters",
                    subtitle: "Choose themes & habits to guide your thoughts and progress over time.",
                    illustrationName: "Onboarding_Focus",
                    page: 2
                )
                .tag(2)

                // Page 4: Auth
                AuthPage()
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
    let page: Int

    var body: some View {
        VStack(spacing: 0) {
            // Top spacing
            Spacer()
                .frame(height: 48)

            // Headline
            Text(headline)
                .font(.custom("Newsreader", size: 24).italic())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 20)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundColor(Color(white: 0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(1.5)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            // Illustration area
            Spacer()

            if let image = UIImage(named: illustrationName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .padding(.horizontal, 32)
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(white: 0.2), lineWidth: 1)
                    .frame(height: 240)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Page indicator
            PageIndicator(currentPage: page, totalPages: 4)
                .padding(.bottom, 40)
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
            Spacer()

            // Logo
            Text("sift")
                .font(.custom("Newsreader", size: 56).italic())
                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.75))

            // Subtitle
            Text("by APORIAC")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(Color(white: 0.4))
                .tracking(1.2)
                .padding(.top, 8)

            Spacer()

            // Error message
            if let error = authError {
                Text(error)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(Color(white: 0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            // Sign in button
            if isLoading {
                ProgressView()
                    .tint(Color(red: 0.4, green: 0.9, blue: 0.75))
                    .frame(height: 52)
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
                .frame(height: 52)
                .cornerRadius(8)
            }

            Spacer()
                .frame(height: 32)

            // Page indicator
            PageIndicator(currentPage: 3, totalPages: 4)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 20)
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

// MARK: - Page Indicator

private struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { page in
                Circle()
                    .fill(page == currentPage ? Color(white: 0.9) : Color(white: 0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
