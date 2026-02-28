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
                        Button(action: { dismiss() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Capsule())
                        }

                        Text("Community")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding()
                    
                    Text("Connect with others on the same journey")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
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

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Friend Streaks")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.black)
                            Spacer()
                            Button("Add Friend") {}
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal)

                        ForEach(viewModel.friendStreaks) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                    Text("\(item.days) day streak together")
                                        .font(.system(size: 13))
                                        .foregroundColor(.black)
                                }
                                Spacer()
                                Text("🔥 \(item.days)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(14)
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Group Chats")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal)

                        ForEach(viewModel.groupChats) { room in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(room.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                    Text("\(room.members) members • \(room.topic)")
                                        .font(.system(size: 13))
                                        .foregroundColor(.black)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Join Chat") {}
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(18)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(14)
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
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
                .foregroundColor(.black)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.black)
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
                        .foregroundColor(.black)
                        .lineLimit(2)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    
                    Text("\(formatNumber(community.memberCount)) members")
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                }
            }
            
            Spacer()
            
            // Action button
            if isJoined {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
            } else {
                Button(action: {}) {
                    Text("Join Community")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
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
    @Published var friendStreaks: [FriendStreak] = []
    @Published var groupChats: [GroupChatRoom] = []
    
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

        friendStreaks = [
            FriendStreak(id: UUID(), name: "Alex", days: 12),
            FriendStreak(id: UUID(), name: "Jordan", days: 7),
            FriendStreak(id: UUID(), name: "Sam", days: 21)
        ]

        groupChats = [
            GroupChatRoom(id: UUID(), name: "Early Risers 6AM", topic: "Morning workouts", members: 86),
            GroupChatRoom(id: UUID(), name: "High Protein Meal Prep", topic: "Meal planning swaps", members: 143),
            GroupChatRoom(id: UUID(), name: "Weekend Long Run", topic: "Cardio accountability", members: 54)
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

struct FriendStreak: Identifiable {
    let id: UUID
    let name: String
    let days: Int
}

struct GroupChatRoom: Identifiable {
    let id: UUID
    let name: String
    let topic: String
    let members: Int
}

#Preview {
    CommunityView()
}
