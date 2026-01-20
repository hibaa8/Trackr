//
//  NutritionDetailsView.swift
//  AITrainer
//
//  Nutrition details and confirmation screen
//

import SwiftUI

struct NutritionDetailsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: NutritionDetailsViewModel
    
    init(recognition: FoodRecognitionResponse) {
        _viewModel = StateObject(wrappedValue: NutritionDetailsViewModel(recognition: recognition))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Food image
                    if let image = viewModel.foodImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 300)
                            .clipped()
                            .cornerRadius(16)
                            .padding(.horizontal)
                    }
                    
                    // Meal info card
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(viewModel.foodName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                // Meal type selection
                                Button(action: {
                                    viewModel.showMealTypeSelection = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: viewModel.selectedMealType.icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(.fitnessGradientStart)

                                        Text(viewModel.selectedMealType.rawValue)
                                            .font(.bodyMedium)
                                            .foregroundColor(.fitnessGradientStart)

                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 12))
                                            .foregroundColor(.fitnessGradientStart)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.fitnessGradientStart.opacity(0.1))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.fitnessGradientStart.opacity(0.3), lineWidth: 1)
                                    )
                                }

                                Text(viewModel.currentTime)
                                    .font(.captionLarge)
                                    .foregroundColor(.textSecondary)
                            }
                            
                            Spacer()
                            
                            // Quantity controls
                            HStack(spacing: 16) {
                                Button(action: { viewModel.decreaseQuantity() }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.gray)
                                }
                                
                                Text("\(viewModel.quantity)")
                                    .font(.headline)
                                    .frame(minWidth: 30)
                                
                                Button(action: { viewModel.increaseQuantity() }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Calories
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("Calories")
                                .font(.headline)
                            
                            Spacer()
                            
                            Text("\(viewModel.totalCalories)")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        
                        // Macros
                        HStack(spacing: 24) {
                            MacroInfo(icon: "p", label: "Protein", value: viewModel.protein, color: .red)
                            MacroInfo(icon: "c", label: "Carbs", value: viewModel.carbs, color: .orange)
                            MacroInfo(icon: "f", label: "Fats", value: viewModel.fat, color: .blue)
                        }
                        .padding(.vertical, 8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // Ingredients section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Ingredients")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button(action: { viewModel.showAddIngredient = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("Add more")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        ForEach(viewModel.ingredients) { ingredient in
                            IngredientRow(ingredient: ingredient)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button(action: { viewModel.showEditMode = true }) {
                            HStack {
                                Image(systemName: "pencil")
                                Text("Fix Results")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        Button(action: {
                            viewModel.saveFoodLog()
                            dismiss()
                        }) {
                            Text("Done")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.black)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("See the calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .foregroundColor(.primary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {}) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button(action: {}) {
                            Label("Save to favorites", systemImage: "star")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddIngredient) {
            AddIngredientView { ingredient in
                viewModel.addIngredient(ingredient)
            }
        }
        .sheet(isPresented: $viewModel.showMealTypeSelection) {
            MealTypeSelectionView(selection: $viewModel.selectedMealType)
        }
    }
}

private struct MacroInfo: View {
    let icon: String
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Text("\(value)g")
                .font(.headline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IngredientRow: View {
    let ingredient: FoodIngredient
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(ingredient.calories) cal")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(ingredient.amount)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NutritionDetailsView(
        recognition: FoodRecognitionResponse(
            foodName: "Caesar Salad with Cherry Tomatoes",
            totalCalories: 330,
            macros: Macros(protein: 8, carbs: 20, fat: 18),
            ingredients: [
                FoodIngredient(name: "Lettuce", calories: 20, amount: "1.5 cups", confidence: 0.95),
                FoodIngredient(name: "Parmesan", calories: 110, amount: "2 tbsp", confidence: 0.90),
                FoodIngredient(name: "Cherry Tomatoes", calories: 30, amount: "10 pieces", confidence: 0.92),
                FoodIngredient(name: "Croutons", calories: 120, amount: "1/2 cup", confidence: 0.88)
            ],
            confidence: 0.91
        )
    )
}
