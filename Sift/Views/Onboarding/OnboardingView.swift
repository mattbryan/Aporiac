import SwiftUI
import AuthenticationServices
import CryptoKit

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentNonce: String?
    @State private var authError: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.siftSurface.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Wordmark + tagline
                VStack(spacing: DS.Spacing.sm) {
                    Text("Sift")
                        .font(.system(size: 48, weight: .medium, design: .default))
                        .foregroundStyle(Color.siftInk)

                    Text("Say everything. Keep what matters.")
                        .font(.siftCallout)
                        .foregroundStyle(Color.siftSubtle)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Sign in CTA
                VStack(spacing: DS.Spacing.md) {
                    if let error = authError {
                        Text(error)
                            .font(.siftCaption)
                            .foregroundStyle(Color.siftSubtle)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.xl)
                    }

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
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: DS.ButtonHeight.large)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.bottom, DS.Spacing.xl)
            }
        }
    }

    // MARK: - Sign In Handler

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
            // ASAuthorizationError.canceled means the user dismissed — no message needed
            if (error as? ASAuthorizationError)?.code != .canceled {
                authError = "Sign in failed. Please try again."
                print("[Onboarding] Apple sign-in error: \(error)")
            }
        }
    }

    // MARK: - Nonce Helpers

    /// Generates a cryptographically random 32-byte hex string.
    private func generateNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Failed to generate nonce")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 hex digest of the given string.
    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    OnboardingView()
}
