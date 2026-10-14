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
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Scan a meal", subtitle: subtitle)
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
                .padding(.horizontal, Theme.gutter)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.fog)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: mode) { _, m in m == .lidar ? scan.start() : scan.stop() }
            .onAppear { if mode == .lidar { scan.start() } }
            .onDisappear { scan.stop() }
        }
    }

    private var subtitle: String {
        switch mode {
        case .lidar: ScanSession.supportsLiDAR ? "LiDAR measures how much is on the plate." : "The camera recognises what is on the plate."
        case .photo: "The camera recognises what is on the plate."
        case .barcode: "Look up packaged food by its barcode."
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
                            Image(systemName: "viewfinder").font(.system(size: 34, weight: .light))
                            Text("Choose a meal photo").font(.system(size: 16, weight: .semibold))
                            Text("Recognition runs on this iPhone.").font(.footnote).opacity(0.7)
                        }
                        .foregroundStyle(Theme.lensInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Reticle()
                if case .analyzing = scan.phase {
                    Text("Measuring…").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.lens)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.lensInk, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3 / 4, contentMode: .fit)
            .background(Theme.lens)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                Button(ScanSession.supportsLiDAR ? "Scan plate" : "Capture") {
                    Task { await scan.capture() }
                }
                .buttonStyle(.helix(.primary, fill: true))
                Text(ScanSession.supportsLiDAR
                     ? "Hold the phone 30 to 50 cm above the plate, angled slightly. LiDAR measures the height of each item above the plate."
                     : "This iPhone has no LiDAR, so portions start at a typical serving. Adjust them before logging.")
                    .font(.footnote).foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .buttonStyle(.helix(.primary))
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
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().aspectRatio(contentMode: .fit)
                        .overlay {
                            GeometryReader { geo in
                                ForEach(items.filter { $0.box != .zero }) { it in
                                    let r = it.box
                                    RoundedRectangle(cornerRadius: 10).stroke(Theme.lensInk, lineWidth: 2)
                                        .frame(width: r.width * geo.size.width, height: r.height * geo.size.height)
                                        .overlay(alignment: .topLeading) {
                                            Text("\(it.food.name), \(Int(it.grams)) g").font(.system(size: 12, weight: .semibold).width(.condensed))
                                                .padding(.horizontal, 7).padding(.vertical, 3)
                                                .background(Theme.lensInk, in: RoundedRectangle(cornerRadius: 5))
                                                .foregroundStyle(Theme.lens)
                                                .offset(y: -24)
                                        }
                                        .position(x: r.midX * geo.size.width, y: r.midY * geo.size.height)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                SectionHeader(title: "Check the portions") {
                    Text(measured ? "Grams from volume" : "Typical servings").font(.footnote).foregroundStyle(Theme.ink2)
                }
                VStack(spacing: 0) {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Menu {
                                    if !item.alternatives.isEmpty {
                                        Section("Also likely") { ForEach(item.alternatives) { f in Button(f.name) { item.food = f } } }
                                    }
                                    Section("All foods") { ForEach(FoodDatabase.shared.foods) { f in Button(f.name) { item.food = f } } }
                                } label: {
                                    Label(item.food.name, systemImage: "chevron.up.chevron.down")
                                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                                }
                                Spacer()
                                Text("\(Int(item.grams)) g").font(.figure(15)).foregroundStyle(Theme.ink)
                            }
                            Slider(value: $item.grams, in: 0...500, step: 5).tint(Theme.action)
                            let m = item.food.macros(grams: item.grams)
                            let volume = item.volumeCm3.map { ". Volume \(Int($0)) cm³" } ?? ""
                            let match = item.confidence.map { ". \(Int($0 * 100))% match" } ?? ""
                            Text(String(format: "%d kcal, %.1f g protein, %.1f g carbs, %.1f g fat", Int(m.kcal), m.protein, m.carbs, m.fat) + volume + match)
                                .font(.figure(12.5, weight: .regular)).foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { if item.id != items.first?.id { Rectangle().fill(Theme.rule).frame(height: 1) } }
                    }
                }
                Menu {
                    ForEach(FoodDatabase.shared.foods) { f in
                        Button(f.name) { items.append(DetectedFood(food: f, grams: f.serving)) }
                    }
                } label: {
                    Text("Add an item")
                }
                .buttonStyle(.helix(.quiet, small: true))

                Panel {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Meal total").font(.footnote).foregroundStyle(Theme.ink2)
                            (Text(Int(total.kcal), format: .number).font(.display(30, weight: .heavy).monospacedDigit())
                                + Text(" kcal").font(.system(size: 14)))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(total.protein)) g protein")
                            Text("\(Int(total.carbs)) g carbs, \(Int(total.fat)) g fat")
                        }
                        .font(.figure(13, weight: .regular))
                    }
                    .foregroundStyle(Theme.ink)
                }

                HStack(spacing: 10) {
                    Button("Scan again", action: onRescan).buttonStyle(.helix(.quiet, fill: true))
                    Button("Log meal") { onLog(items) }.buttonStyle(.helix(.primary, fill: true))
                }
            }
            .padding(.bottom, 24)
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
            let inset = geo.size.width * 0.13
            Path { p in
                let r = CGRect(origin: .zero, size: geo.size).insetBy(dx: inset, dy: inset)
                let l: CGFloat = 26
                for (c, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                    (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
                    p.move(to: CGPoint(x: c.x + l * dx, y: c.y)); p.addLine(to: c); p.addLine(to: CGPoint(x: c.x, y: c.y + l * dy))
                }
            }
            .stroke(Theme.lensInk, style: StrokeStyle(lineWidth: 2))
        }
        .allowsHitTesting(false)
    }
}
