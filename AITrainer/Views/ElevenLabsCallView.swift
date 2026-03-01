import SwiftUI
import Combine
import ElevenLabs

@MainActor
final class ElevenLabsCallViewModel: ObservableObject {
    @Published var conversation: Conversation?
    @Published var isConnecting = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    var isActive: Bool {
        if let conversation {
            if case .active = conversation.state {
                return true
            }
        }
        return false
    }

    func start(agentId: String) {
        guard !agentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Missing ElevenLabs agent id."
            return
        }
        guard !isConnecting, conversation == nil else { return }
        isConnecting = true
        errorMessage = nil

        APIService.shared.fetchElevenLabsConversationToken(agentId: agentId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    if case .failure(let error) = completion {
                        Task { await self.startPublicConversation(agentId: agentId, tokenError: error) }
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self else { return }
                    Task { await self.startConversation(token: response.token, fallbackAgentId: agentId) }
                }
            )
            .store(in: &cancellables)
    }

    func end() {
        let current = conversation
        Task {
            await current?.endConversation()
            await MainActor.run {
                self.conversation = nil
                self.isConnecting = false
            }
        }
    }

    private func startConversation(token: String, fallbackAgentId: String) async {
        do {
            let session = try await ElevenLabs.startConversation(conversationToken: token)
            conversation = session
            isConnecting = false
        } catch {
            await startPublicConversation(agentId: fallbackAgentId, tokenError: error)
        }
    }

    private func startPublicConversation(agentId: String, tokenError: Error) async {
        do {
            // Fallback for public agents if token exchange fails.
            let session = try await ElevenLabs.startConversation(agentId: agentId)
            conversation = session
            isConnecting = false
            errorMessage = nil
        } catch {
            isConnecting = false
            errorMessage = "Token flow failed (\(tokenError.localizedDescription)). Public fallback failed too: \(error.localizedDescription)"
        }
    }
}

struct ElevenLabsCallView: View {
    let agentId: String
    @StateObject private var viewModel = ElevenLabsCallViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("ElevenLabs Live Voice")
                    .font(.headline)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let error = viewModel.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                if let conversation = viewModel.conversation {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(conversation.messages.suffix(30))) { msg in
                                Text("\(msg.role): \(msg.content)")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.gray.opacity(0.12))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else {
                    Spacer()
                }

                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.start(agentId: agentId)
                    }) {
                        Text(viewModel.isConnecting ? "Connecting..." : "Start Live Call")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isConnecting || viewModel.conversation != nil)

                    Button(action: {
                        viewModel.end()
                    }) {
                        Text("End")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.conversation == nil)
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 16)
            .navigationTitle("Call AI Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.end()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.start(agentId: agentId)
        }
        .onDisappear {
            viewModel.end()
        }
    }

    private var statusText: String {
        guard let conversation = viewModel.conversation else {
            return viewModel.isConnecting ? "Connecting..." : "Disconnected"
        }
        switch conversation.state {
        case .idle:
            return "Idle"
        case .connecting:
            return "Connecting..."
        case .active(_):
            if String(describing: conversation.agentState).lowercased().contains("speak") {
                return "Agent speaking"
            }
            return "Listening"
        case .ended(_):
            return "Ended"
        case .error(let error):
            return "Error: \(error)"
        }
    }
}

