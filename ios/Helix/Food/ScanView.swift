import SwiftUI
import ARKit
import PhotosUI

struct ScanView: View {
    @Environment(AppModel.self) private var model
    let profile: UserProfile
    var onLogged: () -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case lidar = "LiDAR", photo = "Photo", barcode = "Barcode"
        var id: String { rawValue }
    }

    @State private var mode: Mode = ScanSession.supportsLiDAR ? .lidar : .photo
    @State private var scan = ScanSession()
    @State private var pickedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0 == .lidar && !ScanSession.supportsLiDAR ? "Camera" : $0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .barcode:
                    BarcodePanel(profile: profile, onLogged: onLogged)
                case .lidar, .photo:
                    cameraOrPhoto
                }
            }
            .padding(.horizontal, 16)
            .navigationTitle("Scan a meal")
            .onChange(of: mode) { _, m in m == .lidar ? scan.start() : scan.stop() }
            .onAppear { if mode == .lidar { scan.start() } }
            .onDisappear { scan.stop() }
        }
    }

    @ViewBuilder private var cameraOrPhoto: some View {
        switch scan.phase {
        case .live, .analyzing:
            ZStack {
                if mode == .lidar {
                    ARCameraView(session: scan.session)
                } else {
                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                            Text("Choose a meal photo").font(.headline)
                            Text("Recognition runs on this iPhone.").font(.caption).foregroundStyle(Theme.mute)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Reticle()
                if case .analyzing = scan.phase {
                    ProgressView("Measuring…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3 / 4, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await scan.analyze(photo: img)
                    }
                    pickedItem = nil
                }
            }

            if mode == .lidar {
                Button {
                    Task { await scan.capture() }
                } label: {
                    Label(ScanSession.supportsLiDAR ? "Scan plate with LiDAR" : "Capture", systemImage: "camera.metering.matrix")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text(ScanSession.supportsLiDAR
                     ? "Hold the phone 30–50 cm above the plate, angled slightly. LiDAR measures each item's height above the plate."
                     : "This iPhone has no LiDAR, so portions start at a typical serving. Adjust them before logging.")
                    .font(.caption).foregroundStyle(Theme.mute)
            }
            Spacer(minLength: 0)

        case .results(let foods, let snapshot):
            ResultsEditor(initial: foods, snapshot: snapshot, measured: foods.contains { $0.volumeCm3 != nil },
                          onRescan: { if mode == .lidar { scan.reset() } else { scan = ScanSession() } },
                          onLog: { items in
                              model.log(items.map { ($0.food, grams: $0.grams, volume: $0.volumeCm3) },
                                        name: mealName(), source: mode == .lidar ? .lidar : .photo, for: profile)
                              scan = ScanSession()
                              onLogged()
                          })

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't read that", systemImage: "exclamationmark.triangle")
            } description: { Text(message) } actions: {
                Button("Try again") { if mode == .lidar { scan.reset() } else { scan = ScanSession() } }
            }
        }
    }

    private func mealName() -> String {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<11: "Breakfast"
        case 11..<15: "Lunch"
        case 15..<18: "Snack"
        default: "Dinner"
        }
    }
}

/// Edit what was detected: swap foods, adjust grams, add missing items.
struct ResultsEditor: View {
    @State var items: [DetectedFood]
    var snapshot: UIImage?
    var measured: Bool
    var onRescan: () -> Void
    var onLog: ([DetectedFood]) -> Void

    init(initial: [DetectedFood], snapshot: UIImage?, measured: Bool, onRescan: @escaping () -> Void, onLog: @escaping ([DetectedFood]) -> Void) {
        _items = State(initialValue: initial)
        self.snapshot = snapshot; self.measured = measured; self.onRescan = onRescan; self.onLog = onLog
    }

    var body: some View {
        let total = items.reduce(Macros.zero) { $0 + $1.food.macros(grams: $1.grams) }
        ScrollView {
            VStack(spacing: 12) {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().aspectRatio(contentMode: .fit)
                        .overlay {
                            GeometryReader { geo in
                                ForEach(items.filter { $0.box != .zero }) { it in
                                    let r = it.box
                                    RoundedRectangle(cornerRadius: 10).stroke(Theme.ice, lineWidth: 1.5)
                                        .frame(width: r.width * geo.size.width, height: r.height * geo.size.height)
                                        .overlay(alignment: .topLeading) {
                                            Text("\(it.food.name) · \(Int(it.grams)) g").font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6).padding(.vertical, 3)
                                                .background(Theme.ice, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.black)
                                                .offset(y: -22)
                                        }
                                        .position(x: r.midX * geo.size.width, y: r.midY * geo.size.height)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                Card {
                    HStack {
                        Eyebrow("Detected · edit anything")
                        Spacer()
                        Text(measured ? "grams from volume" : "typical servings").font(.data(11)).foregroundStyle(Theme.mute)
                    }
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Menu {
                                    if !item.alternatives.isEmpty {
                                        Section("Also likely") { ForEach(item.alternatives) { f in Button(f.name) { item.food = f } } }
                                    }
                                    Section("All foods") { ForEach(FoodDatabase.shared.foods) { f in Button(f.name) { item.food = f } } }
                                } label: {
                                    Label(item.food.name, systemImage: "chevron.up.chevron.down").font(.subheadline.weight(.semibold))
                                }
                                Spacer()
                                Text("\(Int(item.grams)) g").font(.data(13))
                                if let v = item.volumeCm3 { Text("· \(Int(v)) cm³").font(.data(11)).foregroundStyle(Theme.mute) }
                            }
                            Slider(value: $item.grams, in: 0...500, step: 5)
                            let m = item.food.macros(grams: item.grams)
                            let match = item.confidence.map { " · \(Int($0 * 100))% match" } ?? ""
                            Text(String(format: "%d kcal · %.1f P · %.1f C · %.1f F", Int(m.kcal), m.protein, m.carbs, m.fat) + match)
                                .font(.data(11)).foregroundStyle(Theme.mute)
                        }
                        .padding(.vertical, 4)
                    }
                    Menu("Add item", systemImage: "plus") {
                        ForEach(FoodDatabase.shared.foods) { f in
                            Button(f.name) { items.append(DetectedFood(food: f, grams: f.serving)) }
                        }
                    }
                    .font(.subheadline)
                }

                Card {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Meal total").font(.caption).foregroundStyle(Theme.mute)
                            Text("\(Int(total.kcal)) kcal").font(.data(22))
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(Int(total.protein)) g protein").foregroundStyle(Theme.protein)
                            Text("\(Int(total.carbs)) g carbs · \(Int(total.fat)) g fat").foregroundStyle(Theme.mute)
                        }
                        .font(.data(12))
                    }
                }

                HStack {
                    Button("Rescan", action: onRescan).buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Button("Log meal") { onLog(items) }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
    }
}

struct ARCameraView: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = false
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct Reticle: View {
    var body: some View {
        GeometryReader { geo in
            let inset = geo.size.width * 0.14
            Path { p in
                let r = CGRect(origin: .zero, size: geo.size).insetBy(dx: inset, dy: inset)
                let l: CGFloat = 22
                for (c, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                    (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
                    p.move(to: CGPoint(x: c.x + l * dx, y: c.y)); p.addLine(to: c); p.addLine(to: CGPoint(x: c.x, y: c.y + l * dy))
                }
            }
            .stroke(Theme.ice, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}
