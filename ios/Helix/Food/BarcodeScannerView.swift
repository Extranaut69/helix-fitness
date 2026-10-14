import SwiftUI
import VisionKit

/// Camera barcode scanning (VisionKit) plus manual entry, looked up on Open Food Facts.
struct BarcodePanel: View {
    @Environment(AppModel.self) private var model
    let profile: UserProfile
    var onLogged: () -> Void

    @State private var code = ""
    @State private var product: OpenFoodFactsClient.Product?
    @State private var servings = 1.0
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    BarcodeScannerView { scanned in
                        guard scanned != code else { return }
                        code = scanned
                        Task { await lookup() }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                HStack(spacing: 8) {
                    TextField("Barcode number", text: $code)
                        .keyboardType(.numberPad)
                        .font(.figure(15, weight: .regular))
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1.5))
                    Button("Look up") { Task { await lookup() } }.buttonStyle(.helix(.primary)).disabled(code.isEmpty || loading)
                }

                if loading { ProgressView().tint(Theme.ink2) }
                if let error { Text(error).font(.subheadline).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading) }

                if let product {
                    let grams = product.servingGrams * servings
                    let m = product.food.macros(grams: grams)
                    Panel {
                        Text(product.food.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        Stepper("\(servings, specifier: "%.1f") × \(Int(product.servingGrams)) g", value: $servings, in: 0.5...10, step: 0.5)
                            .foregroundStyle(Theme.ink)
                        Text("\(Int(m.kcal)) kcal, \(m.protein, specifier: "%.1f") g protein, \(m.carbs, specifier: "%.1f") g carbs, \(m.fat, specifier: "%.1f") g fat")
                            .font(.figure(12.5, weight: .regular)).foregroundStyle(Theme.ink2)
                        Button("Log \(servings == 1 ? "one serving" : String(format: "%.1f servings", servings))") {
                            model.log([(product.food, grams: grams, volume: nil)], name: product.food.name, source: .barcode, for: profile)
                            self.product = nil; code = ""; servings = 1
                            onLogged()
                        }
                        .buttonStyle(.helix(.primary, small: true))
                    }
                }
                Text("Product data comes from Open Food Facts, a free and open database.")
                    .font(.footnote).foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func lookup() async {
        loading = true; error = nil; product = nil
        defer { loading = false }
        do { product = try await OpenFoodFactsClient().lookup(barcode: code.filter(\.isNumber)) }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Lookup failed. Check your connection." }
    }
}

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items {
                if let s = b.payloadStringValue { onCode(s); return }
            }
        }
    }
}
