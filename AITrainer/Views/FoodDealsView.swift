//
//  FoodDealsView.swift
//  AITrainer
//
//  Healthy food deals from local restaurants
//

import SwiftUI
import MapKit
import Combine

struct FoodDealsView: View {
    @StateObject private var viewModel = FoodDealsViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: DealCategory = .nearYou
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Healthy Food Deals")
                        .font(.system(size: 24, weight: .bold))
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .padding()
                
                Text("Save money while staying on track")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                
                // Category filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(DealCategory.allCases, id: \.self) { category in
                            CategoryButton(
                                title: category.rawValue,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 16)
                
                // Deals list
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(filteredDeals) { deal in
                            FoodDealCard(deal: deal)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            viewModel.loadDeals()
        }
    }
    
    private var filteredDeals: [FoodDeal] {
        switch selectedCategory {
        case .nearYou:
            return viewModel.deals
        case .highProtein:
            return viewModel.deals.filter { $0.tags.contains(.highProtein) }
        case .lowCalorie:
            return viewModel.deals.filter { $0.calories < 500 }
        case .vegetarian:
            return viewModel.deals.filter { $0.tags.contains(.vegetarian) }
        }
    }
}

// MARK: - Category Button

private struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .black)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.1))
                .cornerRadius(20)
        }
    }
}

// MARK: - Food Deal Card

private struct FoodDealCard: View {
    let deal: FoodDeal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with restaurant and discount
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deal.itemName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(deal.restaurantName)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("%")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(deal.discountPercent)% OFF")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.yellow)
                .cornerRadius(20)
            }
            .padding()
            .background(Color.blue)
            
            // Deal details
            VStack(alignment: .leading, spacing: 12) {
                // Price
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(String(format: "%.2f", deal.discountedPrice))")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("$\(String(format: "%.2f", deal.originalPrice))")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                        .strikethrough()
                }
                
                // Macros
                HStack(spacing: 20) {
                    MacroInfo(icon: "🔥", label: "Calories", value: "\(deal.calories)")
                    MacroInfo(icon: "🥩", label: "Protein", value: "\(deal.protein)g")
                    MacroInfo(icon: "🍞", label: "Carbs", value: "\(deal.carbs)g")
                    MacroInfo(icon: "🥑", label: "Fat", value: "\(deal.fat)g")
                }
                
                // Tags
                HStack(spacing: 8) {
                    ForEach(deal.tags, id: \.self) { tag in
                        TagView(tag: tag)
                    }
                }
                
                // Location and expiration
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f mi", deal.distanceMiles))
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("Expires in \(deal.expiresInHours) hours")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                    }
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {}) {
                        Text("Claim Deal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {}) {
                        Text("Directions")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                            .frame(width: 120)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            .padding()
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Macro Info

private struct MacroInfo: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}

// MARK: - Tag View

private struct TagView: View {
    let tag: DealTag
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
            
            Text(tag.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - View Model

class FoodDealsViewModel: ObservableObject {
    @Published var deals: [FoodDeal] = []
    
    func loadDeals() {
        // Mock data
        deals = [
            FoodDeal(
                id: UUID(),
                itemName: "Harvest Bowl",
                restaurantName: "Sweetgreen",
                originalPrice: 14.95,
                discountedPrice: 10.46,
                discountPercent: 30,
                calories: 450,
                protein: 28,
                carbs: 52,
                fat: 18,
                tags: [.vegetarian, .highProtein],
                distanceMiles: 0.3,
                expiresInHours: 2
            ),
            FoodDeal(
                id: UUID(),
                itemName: "Chicken Bowl (Light)",
                restaurantName: "Chipotle",
                originalPrice: 12.50,
                discountedPrice: 8.75,
                discountPercent: 30,
                calories: 520,
                protein: 45,
                carbs: 48,
                fat: 16,
                tags: [.highProtein, .lowFat],
                distanceMiles: 0.5,
                expiresInHours: 1
            ),
            FoodDeal(
                id: UUID(),
                itemName: "Protein Power Bowl",
                restaurantName: "Cava",
                originalPrice: 13.25,
                discountedPrice: 9.95,
                discountPercent: 25,
                calories: 480,
                protein: 38,
                carbs: 45,
                fat: 19,
                tags: [.highProtein],
                distanceMiles: 0.7,
                expiresInHours: 3
            )
        ]
    }
}

// MARK: - Models

struct FoodDeal: Identifiable {
    let id: UUID
    let itemName: String
    let restaurantName: String
    let originalPrice: Double
    let discountedPrice: Double
    let discountPercent: Int
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let tags: [DealTag]
    let distanceMiles: Double
    let expiresInHours: Int
}

enum DealTag: String {
    case vegetarian = "Vegetarian"
    case highProtein = "High Protein"
    case lowFat = "Low Fat"
    case lowCarb = "Low Carb"
    case vegan = "Vegan"
}

enum DealCategory: String, CaseIterable {
    case nearYou = "Near You"
    case highProtein = "High Protein"
    case lowCalorie = "Low Calorie"
    case vegetarian = "Vegetarian"
}

#Preview {
    FoodDealsView()
}
