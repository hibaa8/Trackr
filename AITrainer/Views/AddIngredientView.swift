//
//  AddIngredientView.swift
//  AITrainer
//
//  View for manually adding ingredients to meals
//

import SwiftUI
import Combine

struct AddIngredientView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = AddIngredientViewModel()
    let onIngredientAdded: (FoodIngredient) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color.backgroundGradientStart,
                        Color.backgroundGradientEnd,
                        Color.white.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Search section
                        searchSection
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        if viewModel.isSearching {
                            // Loading state
                            loadingSection
                        } else if !viewModel.searchResults.isEmpty {
                            // Search results
                            searchResultsSection
                                .padding(.horizontal, 20)
                        } else if !viewModel.searchQuery.isEmpty {
                            // No results
                            noResultsSection
                        } else {
                            // Manual input
                            manualInputSection
                                .padding(.horizontal, 20)
                        }

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        viewModel.addIngredient()
                        onIngredientAdded(viewModel.createIngredient())
                        dismiss()
                    }
                    .disabled(!viewModel.canAddIngredient)
                }
            }
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(spacing: 16) {
            Text("Search for an ingredient or add manually")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)

            ModernCard {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.textSecondary)

                    TextField("Search ingredients...", text: $viewModel.searchQuery)
                        .font(.bodyLarge)
                        .onSubmit {
                            viewModel.searchIngredients()
                        }

                    if !viewModel.searchQuery.isEmpty {
                        Button(action: {
                            viewModel.searchQuery = ""
                            viewModel.clearSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .fitnessGradientStart))
                .scaleEffect(1.2)

            Text("Searching ingredients...")
                .font(.bodyMedium)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Search Results Section

    private var searchResultsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Search Results")
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)

                Spacer()
            }

            LazyVStack(spacing: 12) {
                ForEach(viewModel.searchResults) { ingredient in
                    IngredientSearchCard(ingredient: ingredient) {
                        viewModel.selectIngredient(ingredient)
                    }
                }
            }
        }
    }

    // MARK: - No Results Section

    private var noResultsSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary)

            VStack(spacing: 8) {
                Text("No ingredients found")
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)

                Text("Try a different search term or add manually below")
                    .font(.bodyMedium)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Add manually instead") {
                viewModel.searchQuery = ""
                viewModel.clearSearch()
            }
            .font(.bodyMedium)
            .foregroundColor(.fitnessGradientStart)
        }
        .padding(40)
    }

    // MARK: - Manual Input Section

    private var manualInputSection: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Add Manually")
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)

                Spacer()
            }

            ModernCard {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredient Name")
                            .font(.bodyMedium)
                            .foregroundColor(.textPrimary)

                        TextField("e.g., Olive Oil", text: $viewModel.ingredientName)
                            .font(.bodyLarge)
                            .padding(12)
                            .background(Color.backgroundGradientStart)
                            .cornerRadius(12)
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Amount")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)

                            TextField("e.g., 2 tbsp", text: $viewModel.amount)
                                .font(.bodyLarge)
                                .padding(12)
                                .background(Color.backgroundGradientStart)
                                .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Calories")
                                .font(.bodyMedium)
                                .foregroundColor(.textPrimary)

                            TextField("e.g., 120", text: $viewModel.calories)
                                .font(.bodyLarge)
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(Color.backgroundGradientStart)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(24)
            }

            // Quick suggestions
            if !viewModel.quickSuggestions.isEmpty {
                quickSuggestionsSection
            }
        }
    }

    // MARK: - Quick Suggestions Section

    private var quickSuggestionsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Quick Add")
                    .font(.headlineMedium)
                    .foregroundColor(.textPrimary)

                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(viewModel.quickSuggestions) { suggestion in
                    QuickIngredientCard(ingredient: suggestion) {
                        viewModel.selectQuickIngredient(suggestion)
                    }
                }
            }
        }
    }
}

// MARK: - Add Ingredient ViewModel

class AddIngredientViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var isSearching = false
    @Published var searchResults: [IngredientSearchResult] = []

    @Published var ingredientName = ""
    @Published var amount = ""
    @Published var calories = ""

    @Published var selectedIngredient: IngredientSearchResult?

    var canAddIngredient: Bool {
        if let _ = selectedIngredient {
            return true
        }
        return !ingredientName.isEmpty && !amount.isEmpty && !calories.isEmpty
    }

    var quickSuggestions: [QuickIngredient] = [
        QuickIngredient(name: "Olive Oil", amount: "1 tbsp", calories: 120),
        QuickIngredient(name: "Salt", amount: "1 tsp", calories: 0),
        QuickIngredient(name: "Butter", amount: "1 tbsp", calories: 100),
        QuickIngredient(name: "Garlic", amount: "1 clove", calories: 4),
        QuickIngredient(name: "Lemon Juice", amount: "1 tbsp", calories: 4),
        QuickIngredient(name: "Black Pepper", amount: "1/4 tsp", calories: 1)
    ]

    func searchIngredients() {
        guard !searchQuery.isEmpty else { return }

        isSearching = true

        // Simulate API call - in production, call USDA Food Data API or similar
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isSearching = false
            self?.searchResults = self?.mockSearchResults() ?? []
        }
    }

    private func mockSearchResults() -> [IngredientSearchResult] {
        let query = searchQuery.lowercased()
        let allIngredients = [
            IngredientSearchResult(name: "Chicken Breast", caloriesPer100g: 165, commonServing: "100g"),
            IngredientSearchResult(name: "Brown Rice", caloriesPer100g: 112, commonServing: "1 cup"),
            IngredientSearchResult(name: "Broccoli", caloriesPer100g: 34, commonServing: "1 cup"),
            IngredientSearchResult(name: "Salmon Fillet", caloriesPer100g: 208, commonServing: "100g"),
            IngredientSearchResult(name: "Avocado", caloriesPer100g: 160, commonServing: "1 medium"),
            IngredientSearchResult(name: "Sweet Potato", caloriesPer100g: 86, commonServing: "1 medium"),
            IngredientSearchResult(name: "Spinach", caloriesPer100g: 23, commonServing: "1 cup"),
            IngredientSearchResult(name: "Greek Yogurt", caloriesPer100g: 59, commonServing: "1 cup"),
        ]

        return allIngredients.filter { $0.name.lowercased().contains(query) }
    }

    func clearSearch() {
        searchResults = []
        selectedIngredient = nil
    }

    func selectIngredient(_ ingredient: IngredientSearchResult) {
        selectedIngredient = ingredient
        ingredientName = ingredient.name
        amount = ingredient.commonServing
        calories = String(ingredient.estimatedCalories)
    }

    func selectQuickIngredient(_ ingredient: QuickIngredient) {
        ingredientName = ingredient.name
        amount = ingredient.amount
        calories = String(ingredient.calories)
    }

    func addIngredient() {
        // Logic handled by parent view
    }

    func createIngredient() -> FoodIngredient {
        return FoodIngredient(
            name: ingredientName,
            calories: Int(calories) ?? 0,
            amount: amount,
            confidence: selectedIngredient != nil ? 0.9 : 1.0
        )
    }
}

// MARK: - Ingredient Search Card

struct IngredientSearchCard: View {
    let ingredient: IngredientSearchResult
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ModernCard {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ingredient.name)
                            .font(.bodyLarge)
                            .foregroundColor(.textPrimary)

                        Text("\(ingredient.estimatedCalories) cal per \(ingredient.commonServing)")
                            .font(.captionLarge)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.fitnessGradientStart)
                }
                .padding(16)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Quick Ingredient Card

struct QuickIngredientCard: View {
    let ingredient: QuickIngredient
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ModernCard {
                VStack(spacing: 8) {
                    Text(ingredient.name)
                        .font(.bodyMedium)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("\(ingredient.amount)")
                        .font(.captionLarge)
                        .foregroundColor(.textSecondary)

                    Text("\(ingredient.calories) cal")
                        .font(.captionMedium)
                        .foregroundColor(.fitnessGradientStart)
                        .fontWeight(.semibold)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Supporting Models

struct IngredientSearchResult: Identifiable {
    let id = UUID()
    let name: String
    let caloriesPer100g: Int
    let commonServing: String

    var estimatedCalories: Int {
        // Simplified calculation - in real app, would be more precise
        return caloriesPer100g
    }
}

struct QuickIngredient: Identifiable {
    let id = UUID()
    let name: String
    let amount: String
    let calories: Int
}

#Preview {
    AddIngredientView { ingredient in
        print("Added ingredient: \(ingredient.name)")
    }
}