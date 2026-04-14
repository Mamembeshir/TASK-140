import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: AuthViewModel

    init(authService: AuthService, appState: AppState) {
        _viewModel = State(initialValue: AuthViewModel(authService: authService, appState: appState))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Branding
            Image(systemName: "hammer.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color("ForgeBlue"))
                .accessibilityHidden(true)

            Text("ForgeFlow")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color("TextPrimary"))

            Text("Work Orchestration Platform")
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))

            // Form
            VStack(spacing: 16) {
                TextField("Username", text: $viewModel.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color("SurfaceElevated"), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("BorderDefault"), lineWidth: 1))

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .padding()
                    .background(Color("SurfaceElevated"), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("BorderDefault"), lineWidth: 1))

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color("Danger"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await viewModel.login() }
                } label: {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Sign In")
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

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("SurfacePrimary"))
        .onSubmit { Task { await viewModel.login() } }
    }
}
