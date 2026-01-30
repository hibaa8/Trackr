//
//  PlaceholderViews.swift
//  AITrainer
//
//  Placeholder views for remaining screens
//

import SwiftUI


struct ProgressTabView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Progress tracking coming soon")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            .navigationTitle("Progress")
        }
    }
}


struct AICoachView: View {
    @Environment(\.dismiss) var dismiss
    @State private var messageText = ""
    @State private var messages: [WireframeChatMessage] = [
        WireframeChatMessage(
            text: "Hi! I'm your AI fitness coach. I've been analyzing your progress. How can I help you today?",
            isFromUser: false,
            timestamp: Date()
        )
    ]
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(messages) { message in
                            EnhancedMessageBubble(message: message)
                        }
                    }
                    .padding()
                }
                
                HStack(spacing: 12) {
                    TextField("Ask your coach...", text: $messageText)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(messageText.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Vaylo Fitness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func sendMessage() {
        let userMessage = WireframeChatMessage(
            text: messageText,
            isFromUser: true,
            timestamp: Date()
        )
        messages.append(userMessage)
        messageText = ""

        // Simulate AI response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let aiResponse = WireframeChatMessage(
                text: "I understand. Based on your recent activity, I have some suggestions for you.",
                isFromUser: false,
                timestamp: Date()
            )
            messages.append(aiResponse)
        }
    }
}



#Preview("AI Coach") {
    AICoachView()
}
