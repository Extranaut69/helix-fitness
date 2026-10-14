import Foundation

/// Barcode lookups against Open Food Facts: free, open data (ODbL), no API key.
/// https://openfoodfacts.github.io/openfoodfacts-server/api/
struct OpenFoodFactsClient {
    struct Product: Sendable {
        var food: FoodInfo
        var servingGrams: Double
    }

    enum LookupError: LocalizedError {
        case notFound, missingNutrition
        var errorDescription: String? {
            switch self {
            case .notFound: "This barcode isn't in Open Food Facts yet. You can add it at openfoodfacts.org."
            case .missingNutrition: "Open Food Facts has this product but no nutrition values for it."
            }
        }
    }

    private struct Response: Decodable {
        var status: Int
        var product: P?
        struct P: Decodable {
            var product_name: String?
            var brands: String?
            var serving_quantity: Double?
            var nutriments: [String: Double]?

            enum CodingKeys: String, CodingKey { case product_name, brands, serving_quantity, nutriments }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                product_name = try? c.decode(String.self, forKey: .product_name)
                brands = try? c.decode(String.self, forKey: .brands)
                // OFF sometimes sends numbers as strings.
                serving_quantity = (try? c.decode(Double.self, forKey: .serving_quantity))
                    ?? (try? c.decode(String.self, forKey: .serving_quantity)).flatMap(Double.init)
                nutriments = (try? c.decode(LossyNumbers.self, forKey: .nutriments))?.values
            }
        }
    }

    /// Decodes a dictionary keeping only numeric values.
    private struct LossyNumbers: Decodable {
        var values: [String: Double] = [:]
        struct Key: CodingKey {
            var stringValue: String; var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            for k in c.allKeys {
                if let d = try? c.decode(Double.self, forKey: k) { values[k.stringValue] = d }
                else if let s = try? c.decode(String.self, forKey: k), let d = Double(s) { values[k.stringValue] = d }
            }
        }
    }

    func lookup(barcode: String) async throws -> Product {
        let fields = "product_name,brands,serving_quantity,nutriments"
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)")!
        var request = URLRequest(url: url)
        // OFF asks every app to identify itself.
        request.setValue("Helix/0.1 (iOS; personal fitness app)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.status == 1, let p = response.product else { throw LookupError.notFound }
        guard let n = p.nutriments, let kcal = n["energy-kcal_100g"] ?? n["energy_100g"].map({ $0 / 4.184 }) else {
            throw LookupError.missingNutrition
        }
        let name = [p.brands?.split(separator: ",").first.map(String.init), p.product_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        let food = FoodInfo(
            id: "off:\(barcode)",
            name: name.isEmpty ? "Product \(barcode)" : name,
            per100g: Macros(kcal: kcal, protein: n["proteins_100g"] ?? 0, carbs: n["carbohydrates_100g"] ?? 0, fat: n["fat_100g"] ?? 0),
            density: 1, serving: p.serving_quantity ?? 100, role: .mixed, diet: .omnivore)
        return Product(food: food, servingGrams: p.serving_quantity ?? 100)
    }
}
