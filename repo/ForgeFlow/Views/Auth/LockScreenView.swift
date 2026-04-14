import SwiftUI

struct LockScreenView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: AuthViewModel
    @State private var showPasswordField = false

    init(authService: AuthService, appState: AppState) {
        _viewModel = State(initialValue: AuthViewModel(authService: authService, appState: appState))
    }

    private var canUseBiometric: Bool {
        viewModel.biometricType != .none
            && !viewModel.showPasswordFallback
            && appState.hasPasswordAuthenticatedThisSession
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color("ForgeBlue"))
                .accessibilityHidden(true)

            Text("Session Locked")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color("TextPrimary"))

            Text("Your session was locked due to inactivity.")
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Biometric button
            if canUseBiometric && !showPasswordField {
                Button {
                    Task { await viewModel.biometricUnlock() }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: viewModel.biometricType.systemImageName)
                            .font(.system(size: 44))
                        Text("Unlock with \(viewModel.biometricType.displayName)")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color("ForgeBlue"))
                    .padding()
                }
                .accessibilityLabel("Unlock with \(viewModel.biometricType.displayName)")

                Button("Use Password Instead") {
                    showPasswordField = true
                }
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
            }

            // Password field
            if showPasswordField || !canUseBiometric {
                VStack(spacing: 16) {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .padding()
                        .background(Color("SurfaceElevated"), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("BorderDefault"), lineWidth: 1))

                    Button {
                        Task { await viewModel.passwordUnlock() }
                    } label: {
                        Group {
                            if viewModel.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Unlock")
                            }
                        }
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color("ForgeBlue"), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(viewModel.isLoading)
                    .opacity(viewModel.isLoading ? 0.6 : 1)
                }
                .padding(.horizontal, 40)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color("Danger"))
                    .padding(.horizontal)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("SurfacePrimary"))
        .onAppear {
            viewModel.checkBiometricAvailability()
            if canUseBiometric {
                Task { await viewModel.biometricUnlock() }
            }
        }
        .onSubmit { Task { await viewModel.passwordUnlock() } }
    }
}
