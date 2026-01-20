//
//  DesignSystem.swift
//  AITrainer
//
//  Design system for the AI Trainer app
//

import SwiftUI

// MARK: - Color Palette
extension Color {
    // Fitness gradient colors
    static let fitnessGradientStart = Color(red: 255/255, green: 94/255, blue: 77/255)
    static let fitnessGradientEnd = Color(red: 255/255, green: 154/255, blue: 0/255)

    // Macro gradient colors
    static let proteinGradientStart = Color(red: 255/255, green: 59/255, blue: 48/255)
    static let proteinGradientEnd = Color(red: 255/255, green: 149/255, blue: 0/255)

    static let carbsGradientStart = Color(red: 52/255, green: 199/255, blue: 89/255)
    static let carbsGradientEnd = Color(red: 48/255, green: 209/255, blue: 88/255)

    static let fatsGradientStart = Color(red: 90/255, green: 200/255, blue: 250/255)
    static let fatsGradientEnd = Color(red: 0/255, green: 122/255, blue: 255/255)

    // Background colors
    static let backgroundGradientStart = Color(red: 248/255, green: 250/255, blue: 252/255)
    static let backgroundGradientEnd = Color(red: 255/255, green: 255/255, blue: 255/255)

    // Card colors
    static let cardBackground = Color.white
    static let cardShadowColor = Color.black.opacity(0.1)

    // Text colors
    static let textPrimary = Color.black
    static let textSecondary = Color(red: 142/255, green: 142/255, blue: 147/255)
    static let textTertiary = Color(red: 174/255, green: 174/255, blue: 178/255)
}

// MARK: - Gradients
extension LinearGradient {
    static let fitnessGradient = LinearGradient(
        colors: [Color.fitnessGradientStart, Color.fitnessGradientEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let proteinGradient = LinearGradient(
        colors: [Color.proteinGradientStart, Color.proteinGradientEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let carbsGradient = LinearGradient(
        colors: [Color.carbsGradientStart, Color.carbsGradientEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let fatsGradient = LinearGradient(
        colors: [Color.fatsGradientStart, Color.fatsGradientEnd],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [Color.backgroundGradientStart, Color.backgroundGradientEnd],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Typography
extension Font {
    // Display fonts
    static let displayLarge = Font.system(size: 36, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 30, weight: .bold, design: .rounded)

    // Headlines
    static let headlineLarge = Font.system(size: 22, weight: .bold, design: .rounded)
    static let headlineMedium = Font.system(size: 18, weight: .semibold, design: .rounded)

    // Body text
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .rounded)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .rounded)

    // Captions
    static let captionLarge = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let captionMedium = Font.system(size: 10, weight: .regular, design: .rounded)

    // Numeric display
    static let numericLarge = Font.system(size: 48, weight: .bold, design: .rounded)
    static let numericMedium = Font.system(size: 24, weight: .semibold, design: .rounded)
}

// MARK: - Shadow System
extension View {
    // Card shadows
    func modernCardShadow() -> some View {
        self.shadow(color: Color.cardShadowColor, radius: 8, x: 0, y: 4)
    }

    // Button shadows
    func modernButtonShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // Floating shadows
    func modernFloatingShadow() -> some View {
        self.shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
    }

    // Ring shadows
    func modernRingShadow() -> some View {
        self.shadow(color: Color.fitnessGradientStart.opacity(0.3), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Button Styles
struct ModernPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodyLarge)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient.fitnessGradient)
                .cornerRadius(16)
                .modernButtonShadow()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ModernSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.bodyLarge)
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .modernCardShadow()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ModernIconButton: View {
    let icon: String
    let action: () -> Void
    let size: CGFloat
    let gradient: LinearGradient

    init(icon: String, size: CGFloat = 44, gradient: LinearGradient = LinearGradient.fitnessGradient, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.gradient = gradient
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(gradient)
                    .frame(width: size, height: size)

                Image(systemName: icon)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .modernButtonShadow()
    }
}

// MARK: - Card Style
struct ModernCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Color.cardBackground)
            .cornerRadius(20)
            .modernCardShadow()
    }
}