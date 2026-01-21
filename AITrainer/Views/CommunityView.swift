//
//  CommunityView.swift
//  AITrainer
//
//  Community and social features
//

import SwiftUI
import Combine

struct CommunityView: View {
    @StateObject private var viewModel = CommunityViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Community")
                            .font(.system(size: 24, weight: .bold))
                        
                        Spacer()
                        
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .padding()
                    
                    Text("Connect with others on the same journey")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    
                    // Stats banner
                    HStack(spacing: 0) {
                        StatItem(
                            value: "42K+",
                            label: "Active Members"
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        StatItem(
                            value: "1.2M",
                            label: "Messages"
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        StatItem(
                            value: "85%",
                            label: "Success Rate"
                        )
                    }
                    .padding(.vertical, 20)
                    .background(Color.blue)
                    .cornerRadius(16)
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                    
                    // Your Communities
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Communities")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal)
                        
                        ForEach(viewModel.joinedCommunities) { community in
                            CommunityCard(community: community, isJoined: true)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 24)
                    
                    // Discover Communities
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Discover Communities")
                            .font(.system(size: 20, weight: .bold))
                            .padding(.horizontal)
                        
                        ForEach(viewModel.discoverCommunities) { community in
                            CommunityCard(community: community, isJoined: false)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            viewModel.loadCommunities()
        }
    }
}

// MARK: - Stat Item

private struct StatItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Community Card

private struct CommunityCard: View {
    let community: Community
    let isJoined: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(community.iconColor.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Text(community.icon)
                    .font(.system(size: 28))
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(community.name)
                    .font(.system(size: 18, weight: .semibold))
                
                if let description = community.description {
                    Text(description)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    
                    Text("\(formatNumber(community.memberCount)) members")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            // Action button
            if isJoined {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.gray)
            } else {
                Button(action: {}) {
                    Text("Join Community")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(20)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1000 {
            let thousands = Double(number) / 1000.0
            return String(format: "%.1fK", thousands).replacingOccurrences(of: ".0", with: "")
        }
        return "\(number)"
    }
}

// MARK: - View Model

class CommunityViewModel: ObservableObject {
    @Published var joinedCommunities: [Community] = []
    @Published var discoverCommunities: [Community] = []
    
    func loadCommunities() {
        // Mock data for joined communities
        joinedCommunities = [
            Community(
                id: UUID(),
                name: "Weight Loss Warriors",
                description: nil,
                icon: "🎯",
                iconColor: .red,
                memberCount: 12543
            ),
            Community(
                id: UUID(),
                name: "HIIT Enthusiasts",
                description: nil,
                icon: "🔥",
                iconColor: .orange,
                memberCount: 8721
            )
        ]
        
        // Mock data for discover communities
        discoverCommunities = [
            Community(
                id: UUID(),
                name: "Plant-Based Athletes",
                description: "Vegan and vegetarian fitness community",
                icon: "🌱",
                iconColor: .green,
                memberCount: 5436
            ),
            Community(
                id: UUID(),
                name: "Morning Workout Crew",
                description: "Early birds crushing their fitness goals",
                icon: "🌅",
                iconColor: .orange,
                memberCount: 15234
            ),
            Community(
                id: UUID(),
                name: "Strength Training Club",
                description: "Building muscle and getting stronger together",
                icon: "💪",
                iconColor: .blue,
                memberCount: 9876
            ),
            Community(
                id: UUID(),
                name: "Running Buddies",
                description: "From 5K to marathons, we run together",
                icon: "🏃",
                iconColor: .purple,
                memberCount: 11234
            ),
            Community(
                id: UUID(),
                name: "Yoga & Mindfulness",
                description: "Balance body and mind through yoga practice",
                icon: "🧘",
                iconColor: .indigo,
                memberCount: 7890
            ),
            Community(
                id: UUID(),
                name: "Postpartum Fitness",
                description: "Supporting new moms on their fitness journey",
                icon: "👶",
                iconColor: .pink,
                memberCount: 4567
            )
        ]
    }
}

// MARK: - Models

struct Community: Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let icon: String
    let iconColor: Color
    let memberCount: Int
}

#Preview {
    CommunityView()
}
