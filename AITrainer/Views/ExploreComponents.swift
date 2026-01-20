//
//  ExploreComponents.swift
//  AITrainer
//
//  Shared components for Explore section
//

import SwiftUI

struct ModernExploreCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var action: (() -> Void)? = nil

    var body: some View {
        ModernCard {
            Button(action: {
                action?()
            }) {
                VStack(alignment: .leading, spacing: 18) {
                    // Modern icon container with glassmorphism
                    ZStack {
                        // Outer glow effect
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [iconColor.opacity(0.3), iconColor.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 70, height: 70)
                            .blur(radius: 8)

                        // Main icon container
                        Text(icon)
                            .font(.system(size: 28))
                            .frame(width: 64, height: 64)
                            .background(
                                LinearGradient(
                                    colors: [iconColor.opacity(0.15), iconColor.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }

                    // Modern typography
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headlineMedium)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .scaleEffect(1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: false)
    }
}

struct EnhancedExploreCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String
    var action: (() -> Void)? = nil

    @State private var isPressed = false

    var body: some View {
        ModernCard {
            Button(action: {
                action?()
            }) {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with icon and badge
                    HStack {
                        ZStack {
                            // Multi-layer icon background
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            iconColor.opacity(0.3),
                                            iconColor.opacity(0.1)
                                        ],
                                        center: .center,
                                        startRadius: 10,
                                        endRadius: 35
                                    )
                                )
                                .frame(width: 56, height: 56)
                                .blur(radius: 8)

                            // Main icon container
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [iconColor.opacity(0.2), iconColor.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.6), Color.white.opacity(0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )

                            Text(icon)
                                .font(.system(size: 20))
                        }

                        Spacer()

                        // Badge
                        Text(badge)
                            .font(.captionMedium)
                            .foregroundColor(iconColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(iconColor.opacity(0.15))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(iconColor.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.headlineMedium)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    // Call to action
                    HStack {
                        Text("Explore")
                            .font(.bodyMedium)
                            .foregroundColor(iconColor)
                            .fontWeight(.semibold)

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.captionLarge)
                            .foregroundColor(iconColor.opacity(0.8))
                    }
                }
                .padding(20)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

struct CalorieRemainingMessage: View {
    let remaining: Int

    var body: some View {
        ModernCard {
            HStack(spacing: 16) {
                // Modern icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.fitnessGradientStart.opacity(0.2), Color.fitnessGradientStart.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Text("💡")
                        .font(.system(size: 20))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Text("You have ")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)

                        Text("\(remaining) calories")
                            .font(.bodyLarge)
                            .foregroundColor(.textPrimary)

                        Text(" remaining")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }

                    Text("for today")
                        .font(.bodyMedium)
                        .foregroundColor(.textSecondary)
                }

                Spacer()
            }
            .padding(20)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [Color.fitnessGradientStart.opacity(0.3), Color.fitnessGradientEnd.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

#Preview("Explore Cards") {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            ModernExploreCard(
                icon: "📍",
                iconColor: Color.blue,
                title: "Gym Classes",
                subtitle: "Find local sessions"
            )

            ModernExploreCard(
                icon: "💵",
                iconColor: Color.green,
                title: "Food Deals",
                subtitle: "Save on healthy meals"
            )
        }

        CalorieRemainingMessage(remaining: 650)
    }
    .padding()
}
