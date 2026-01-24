import SwiftUI
import Combine

struct RecipesView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = RecipesViewModel()

    @State private var query = ""
    @State private var ingredientsText = ""
    @State private var selectedCuisine = "Any"
    @State private var selectedFlavor = "Any"
    @State private var selectedDietary: Set<String> = []

    private let cuisineOptions = ["Any", "Italian", "Mexican", "Japanese", "Mediterranean", "Indian", "Thai", "American"]
    private let flavorOptions = ["Any", "Savory", "Spicy", "Sweet", "Tangy", "Smoky", "Herby"]
    private let dietaryOptions = ["High Protein", "Low Carb", "Vegetarian", "Vegan", "Gluten Free", "Dairy Free"]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        searchSection
                        resultsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recipes")
                    .font(.system(size: 24, weight: .bold))
                Text("Find healthy recipes from the web")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What do you want to cook?")
                    .font(.system(size: 14, weight: .semibold))
                TextField("e.g. chicken bowl, salmon salad", text: $query)
                    .padding(12)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Ingredients you have")
                    .font(.system(size: 14, weight: .semibold))
                TextField("e.g. chicken, rice, spinach", text: $ingredientsText)
                    .padding(12)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(12)
            }

            filterRow(title: "Cuisine", options: cuisineOptions, selected: $selectedCuisine)
            filterRow(title: "Flavor", options: flavorOptions, selected: $selectedFlavor)

            VStack(alignment: .leading, spacing: 8) {
                Text("Dietary")
                    .font(.system(size: 14, weight: .semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dietaryOptions, id: \.self) { option in
                            RecipesFilterChip(
                                title: option,
                                isSelected: selectedDietary.contains(option),
                                action: {
                                    if selectedDietary.contains(option) {
                                        selectedDietary.remove(option)
                                    } else {
                                        selectedDietary.insert(option)
                                    }
                                }
                            )
                        }
                    }
                }
            }

            Button(action: runSearch) {
                Text("Search Recipes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
            }

            if viewModel.isLoading {
                HStack {
                    ProgressView()
                    Text("Searching recipes...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private var resultsSection: some View {
        VStack(spacing: 14) {
            if viewModel.results.isEmpty && !viewModel.isLoading {
                EmptyResultsView()
            } else {
                ForEach(viewModel.results) { recipe in
                    RecipeSearchCard(recipe: recipe)
                }
            }
        }
    }

    private func filterRow(title: String, options: [String], selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        FilterChip(
                            title: option,
                            isSelected: selected.wrappedValue == option,
                            action: { selected.wrappedValue = option }
                        )
                    }
                }
            }
        }
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            viewModel.errorMessage = "Please enter what you want to cook."
            return
        }
        viewModel.search(
            query: trimmed,
            ingredients: ingredientsText,
            cuisine: selectedCuisine == "Any" ? nil : selectedCuisine,
            flavor: selectedFlavor == "Any" ? nil : selectedFlavor,
            dietary: Array(selectedDietary)
        )
    }
}

final class RecipesViewModel: ObservableObject {
    @Published var results: [RecipeSearchResultItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func search(
        query: String,
        ingredients: String?,
        cuisine: String?,
        flavor: String?,
        dietary: [String]
    ) {
        errorMessage = nil
        isLoading = true
        RecipeSearchService.shared.searchRecipes(
            query: query,
            ingredients: ingredients,
            cuisine: cuisine,
            flavor: flavor,
            dietary: dietary
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                switch result {
                case .success(let response):
                    self.results = response.results
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.results = []
                }
            }
        }
    }
}

private struct RecipesFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.12))
                .cornerRadius(16)
        }
    }
}

private struct EmptyResultsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.gray.opacity(0.7))
            Text("No recipes yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.gray)
            Text("Search above to find recipes online.")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

private struct RecipeSearchCard: View {
    let recipe: RecipeSearchResultItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnlineRecipeImageView(urlString: recipe.image_url)

            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                if let source = recipe.source, !source.isEmpty {
                    Text(source)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)
                }
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(3)
                }
            }

            if let url = URL(string: recipe.url), !recipe.url.isEmpty {
                Link(destination: url) {
                    Text("Open Recipe")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

private struct OnlineRecipeImageView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString = urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(height: 160)
        .clipped()
        .cornerRadius(12)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.2), Color.green.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "leaf")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.green.opacity(0.6))
        )
    }
}

#Preview {
    RecipesView()
}
