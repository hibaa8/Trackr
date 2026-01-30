import SwiftUI
import Combine
import PhotosUI

struct RecipeFinderView: View {
    @StateObject private var viewModel = RecipeFinderViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var searchMode: SearchMode = .smart
    @State private var ingredientsText = ""
    @State private var selectedCuisine = "Cuisine"
    @State private var selectedFlavor = "Flavor"
    @State private var selectedDietary: Set<String> = []
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var selectedRecipe: RecipeItem?
    
    let cuisineOptions = ["Any", "Italian", "Mexican", "Asian", "American", "Mediterranean", "Indian"]
    let flavorOptions = ["Any", "Spicy", "Sweet", "Savory", "Tangy", "Mild"]
    let dietaryOptions = ["Vegetarian", "Vegan", "Gluten-Free", "Low Carb", "High Protein"]
    
    enum SearchMode: String, CaseIterable {
        case smart = "AI Generated"
        case online = "Online Recipes"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color.backgroundGradientStart, Color.backgroundGradientEnd, Color.white.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        modeSelector
                        inputSection
                        
                        if viewModel.isLoading {
                            loadingView
                        } else if !viewModel.recipes.isEmpty {
                            recipesSection
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
        }
        .onChange(of: photoItem) { _ in
            Task {
                if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
        .sheet(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
        }
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recipe Finder")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("Discover healthy meals")
                    .font(.system(size: 15))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
    }
    
    private var modeSelector: some View {
        HStack(spacing: 12) {
            ForEach(SearchMode.allCases, id: \.self) { mode in
                Button(action: { searchMode = mode }) {
                    Text(mode.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(searchMode == mode ? .white : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(searchMode == mode ? Color.blue : Color.white.opacity(0.5))
                        .cornerRadius(12)
                }
            }
        }
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ingredients")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                TextField("e.g. chicken, rice, broccoli", text: $ingredientsText)
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)
            }
            
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                        Text("Photo")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                
                if let data = photoData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipped()
                        .cornerRadius(8)
                }
            }
            
            HStack(spacing: 12) {
                FilterMenu(title: selectedCuisine, icon: "🍝", options: cuisineOptions) {
                    selectedCuisine = $0
                }
                FilterMenu(title: selectedFlavor, icon: "🌶️", options: flavorOptions) {
                    selectedFlavor = $0
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Dietary Preferences")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dietaryOptions, id: \.self) { option in
                            FilterChip(
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
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
            
            Button(action: searchRecipes) {
                Text(searchMode == .smart ? "Generate Recipes" : "Search Recipes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.4))
        .cornerRadius(16)
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(searchMode == .smart ? "Generating recipes..." : "Searching recipes...")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
        }
        .padding(40)
    }
    
    private var recipesSection: some View {
            VStack(alignment: .leading, spacing: 16) {
            Text("\(viewModel.recipes.count) Recipes Found")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            ForEach(viewModel.recipes) { recipe in
                RecipeCard(recipe: recipe) {
                    selectedRecipe = recipe
                }
            }
        }
    }
    
    private func searchRecipes() {
        if searchMode == .smart {
            viewModel.generateRecipes(
                ingredients: ingredientsText,
                cuisine: (selectedCuisine == "Any" || selectedCuisine == "Cuisine") ? nil : selectedCuisine,
                flavor: (selectedFlavor == "Any" || selectedFlavor == "Flavor") ? nil : selectedFlavor,
                dietary: Array(selectedDietary),
                imageData: photoData
            )
        } else {
            viewModel.searchOnlineRecipes(
                ingredients: ingredientsText,
                cuisine: (selectedCuisine == "Any" || selectedCuisine == "Cuisine") ? nil : selectedCuisine,
                flavor: (selectedFlavor == "Any" || selectedFlavor == "Flavor") ? nil : selectedFlavor,
                dietary: Array(selectedDietary)
            )
        }
    }
}

struct FilterMenu: View {
    let title: String
    let icon: String
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    onSelect(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(20)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.white)
                .cornerRadius(18)
        }
    }
}

struct RecipeCard: View {
    let recipe: RecipeItem
    let onViewDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeImageView(primaryURL: recipe.imageURL, fallbackQuery: recipe.name)
                .frame(height: 180)
                .clipped()
            
            VStack(alignment: .leading, spacing: 12) {
                Text(recipe.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                
                Text(recipe.summary)
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
                    .lineLimit(3)
                
                HStack(spacing: 16) {
                    if recipe.calories > 0 {
                        MacroBadge(icon: "🔥", value: "\(recipe.calories)", label: "cal")
                    }
                    if let protein = recipe.protein, protein > 0 {
                        MacroBadge(icon: "🥩", value: "\(Int(protein))g", label: "protein")
                    }
                    if let carbs = recipe.carbs, carbs > 0 {
                        MacroBadge(icon: "🍞", value: "\(Int(carbs))g", label: "carbs")
                    }
                }
                
                HStack(spacing: 12) {
                    if let url = recipe.url, !url.isEmpty, let link = URL(string: url) {
                        Link(destination: link) {
                            HStack {
                                Text("View Online")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    if recipe.hasDetails {
                        Button(action: onViewDetails) {
                            HStack {
                                Text("View Details")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "book")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct RecipeImageView: View {
    let primaryURL: String?
    let fallbackQuery: String

    var body: some View {
        if let primaryURL = primaryURL, let url = URL(string: primaryURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    fallbackImage
                default:
                    placeholderImage
                }
            }
        } else {
            fallbackImage
        }
    }

    private var fallbackImage: some View {
        let foodImages = [
            "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1565299624946-b28f40a0ca4b?w=800&h=600&fit=crop",
            "https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=800&h=600&fit=crop"
        ]
        let hash = abs(fallbackQuery.hashValue % foodImages.count)
        let url = URL(string: foodImages[hash])

        return AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "fork.knife")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.6))
        )
    }
}

struct MacroBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(icon)
                    .font(.system(size: 12))
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textSecondary)
        }
    }
}

struct RecipeDetailView: View {
    let recipe: RecipeItem

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let urlString = recipe.imageURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        } placeholder: {
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .frame(height: 220)
                        .clipped()
                        .cornerRadius(16)
                    }

                    Text(recipe.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text(recipe.summary)
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)

                    if let ingredients = recipe.ingredients, !ingredients.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ingredients")
                                .font(.system(size: 16, weight: .semibold))
                            ForEach(ingredients, id: \.self) { item in
                                Text("• \(item)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ingredients")
                                .font(.system(size: 16, weight: .semibold))
                            Text("No ingredients provided for this recipe.")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    if let steps = recipe.steps, !steps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Steps")
                                .font(.system(size: 16, weight: .semibold))
                            ForEach(steps.indices, id: \.self) { idx in
                                Text("\(idx + 1). \(steps[idx])")
                                    .font(.system(size: 13))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Steps")
                                .font(.system(size: 16, weight: .semibold))
                            Text("No steps provided for this recipe.")
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Recipe Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct RecipeItem: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let calories: Int
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    var imageURL: String?
    let url: String?
    let ingredients: [String]?
    let steps: [String]?
    let tags: [String]?

    var hasDetails: Bool {
        // Always show details button for AI-generated recipes (they have ingredients/steps)
        // Online recipes (with url) might not have detailed steps
        if url == nil || url?.isEmpty == true {
            // AI-generated recipe - always has details
            return true
        }
        // Online recipe - check if we have ingredients or steps
        return (ingredients?.isEmpty == false) || (steps?.isEmpty == false)
    }
}

class RecipeFinderViewModel: ObservableObject {
    @Published var recipes: [RecipeItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var baseURL: String { BackendConfig.baseURL }
    
    func requestGeminiImage(for recipe: RecipeItem) {
        RecipeImageService.shared.fetchImageURL(prompt: "\(recipe.name) food photography") { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, let index = self.recipes.firstIndex(where: { $0.id == recipe.id }) else {
                    return
                }
                switch result {
                case .success(let url):
                    self.recipes[index].imageURL = url
                case .failure:
                    let encoded = recipe.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "healthy%20meal"
                    self.recipes[index].imageURL = "https://source.unsplash.com/800x600/?\(encoded)"
                }
            }
        }
    }
    
    func generateRecipes(ingredients: String, cuisine: String?, flavor: String?, dietary: [String], imageData: Data?) {
        isLoading = true
        errorMessage = nil
        recipes = []
        
        var payload: [String: Any] = [
            "user_id": 1,
            "ingredients": ingredients,
            "dietary": dietary
        ]
        if let cuisine = cuisine { payload["cuisine"] = cuisine }
        if let flavor = flavor { payload["flavor"] = flavor }
        if let data = imageData {
            payload["image_base64"] = data.base64EncodedString()
        }
        
        guard let url = URL(string: "\(baseURL)/recipes/suggest") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }

                // Check if response is an error
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    if let errorString = String(data: data, encoding: .utf8), errorString.contains("quota") {
                        self?.errorMessage = "API quota exceeded. Please try again later."
                    } else {
                        self?.errorMessage = "Server error (code: \(httpResponse.statusCode))"
                    }
                    return
                }

                do {
                    let result = try JSONDecoder().decode(RecipeSuggestionResponse.self, from: data)
                    self?.recipes = result.recipes.enumerated().map { (index, item) in
                        // Use curated Unsplash food photos with better distribution
                        let foodPhotos = [
                            "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=800&h=600&fit=crop",
                            "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&h=600&fit=crop"
                        ]
                        // Use index + name hash to ensure different images for each recipe
                        let hash = abs((item.name.hashValue + index * 7) % foodPhotos.count)
                        let imageURL = foodPhotos[hash]
                        
                        return RecipeItem(
                            id: item.id,
                            name: item.name,
                            summary: item.summary,
                            calories: item.calories,
                            protein: item.protein_g,
                            carbs: item.carbs_g,
                            fat: item.fat_g,
                            imageURL: imageURL,
                            url: nil,
                            ingredients: item.ingredients,
                            steps: item.steps,
                            tags: item.tags
                        )
                    }
                } catch {
                    self?.errorMessage = "Failed to parse recipes: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func searchOnlineRecipes(ingredients: String, cuisine: String?, flavor: String?, dietary: [String]) {
        isLoading = true
        errorMessage = nil
        recipes = []
        
        var payload: [String: Any] = [
            "query": ingredients.isEmpty ? "healthy meal" : ingredients,
            "ingredients": ingredients,
            "dietary": dietary,
            "max_results": 6
        ]
        if let cuisine = cuisine { payload["cuisine"] = cuisine }
        if let flavor = flavor { payload["flavor"] = flavor }
        
        guard let url = URL(string: "\(baseURL)/recipes/search") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else { return }
                
                do {
                    let result = try JSONDecoder().decode(RecipeSearchResponse.self, from: data)
                    self?.recipes = result.results.map { item in
                        RecipeItem(
                            id: item.id,
                            name: item.title,
                            summary: item.summary,
                            calories: 0,
                            protein: nil,
                            carbs: nil,
                            fat: nil,
                            imageURL: (item.image_url?.isEmpty == false) ? item.image_url : nil,
                            url: item.url,
                            ingredients: nil,
                            steps: nil,
                            tags: nil
                        )
                    }
                } catch {
                    self?.errorMessage = "Failed to parse recipes: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func fallbackImageURL(for name: String) -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "healthy%20meal"
        return "https://source.unsplash.com/800x600/?\(encoded)"
    }
}

#Preview {
    RecipeFinderView()
}
