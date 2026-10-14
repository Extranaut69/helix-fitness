import SwiftUI
import SwiftData

/// Switch between people on this device, add someone, or edit the active profile.
struct ProfilesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var adding = false
    @State private var confirmDelete: UserProfile?

    var body: some View {
        NavigationStack {
            List {
                Section("People") {
                    ForEach(profiles) { p in
                        Button {
                            model.activeProfileID = p.id
                        } label: {
                            HStack {
                                Text(p.initials).font(.footnote.weight(.bold)).frame(width: 32, height: 32)
                                    .background(Theme.panel, in: Circle())
                                VStack(alignment: .leading) {
                                    Text(p.name).foregroundStyle(.primary)
                                    Text("\(p.spec.goal.title) · \(p.usesHealthKit ? "Apple Watch linked" : "estimated energy")")
                                        .font(.caption).foregroundStyle(Theme.mute)
                                }
                                Spacer()
                                if p.id == model.activeProfile(in: profiles)?.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ice)
                                }
                            }
                        }
                        .swipeActions {
                            if profiles.count > 1 {
                                Button("Remove", role: .destructive) { confirmDelete = p }
                            }
                        }
                    }
                    Button("Add person", systemImage: "person.badge.plus") { adding = true }
                }

                if let p = model.activeProfile(in: profiles) {
                    Section("\(p.name)'s profile") {
                        ProfileForm(profile: p)
                    }
                }
            }
            .navigationTitle("People")
            .toolbar { Button("Done") { dismiss() } }
            .sheet(isPresented: $adding) {
                OnboardingView(isFirstProfile: false) { new in model.activeProfileID = new.id; adding = false }
            }
            .confirmationDialog("Remove \(confirmDelete?.name ?? "")?", isPresented: .init(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
                Button("Remove person and their logs", role: .destructive) {
                    if let p = confirmDelete { context.delete(p); try? context.save() }
                    confirmDelete = nil
                }
            } message: {
                Text("Their meals and workouts on this iPhone are deleted. Data already saved to the Health app stays there.")
            }
        }
    }
}

struct ProfileForm: View {
    @Environment(AppModel.self) private var model
    @Bindable var profile: UserProfile
    @Query private var profiles: [UserProfile]

    var body: some View {
        TextField("Name", text: $profile.name)
        Picker("Sex (for BMR)", selection: Binding(get: { profile.spec.sex }, set: { profile.spec.sex = $0 })) {
            ForEach(Sex.allCases) { Text($0.label).tag($0) }
        }
        Stepper("Age \(profile.age)", value: $profile.age, in: 13...100)
        Stepper("Height \(Int(profile.heightCm)) cm", value: $profile.heightCm, in: 120...230)
        Stepper(String(format: "Weight %.1f kg", profile.weightKg), value: $profile.weightKg, in: 30...250, step: 0.5)
        Picker("Goal", selection: Binding(get: { profile.spec.goal }, set: { profile.spec.goal = $0 })) {
            ForEach(Goal.allCases) { Text($0.title).tag($0) }
        }
        Picker("Diet", selection: Binding(get: { profile.spec.diet }, set: { profile.spec.diet = $0 })) {
            ForEach(Diet.allCases) { Text($0.label).tag($0) }
        }
        Picker("Daily activity", selection: Binding(get: { profile.spec.activity }, set: { profile.spec.activity = $0 })) {
            ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
        }
        Stepper("Training \(profile.trainDaysPerWeek) days / week", value: $profile.trainDaysPerWeek, in: 0...7)
        Toggle("Use this iPhone's Apple Watch data", isOn: Binding(
            get: { profile.usesHealthKit },
            set: { on in
                // HealthKit belongs to the phone's owner, so only one profile can be linked.
                if on { profiles.forEach { $0.usesHealthKit = false } }
                profile.usesHealthKit = on
                Task { await model.refresh(profile) }
            }))
    }
}

/// First-run and "add person" flow.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    var isFirstProfile: Bool
    var onCreated: (UserProfile) -> Void

    @State private var name = ""
    @State private var spec = ProfileSpec(sex: .male, age: 30, heightCm: 175, weightKg: 75, goal: .recomp,
                                          diet: .omnivore, activity: .moderate, trainDaysPerWeek: 4)
    @State private var linkWatch = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(isFirstProfile ? "Helix builds a plan for you from your body, your goal and your Apple Watch data." :
                            "Add a family member or friend. Each person gets their own targets, meals and training.")
                        .font(.subheadline).foregroundStyle(Theme.mute)
                }
                Section("About") {
                    TextField("Name", text: $name)
                    Picker("Sex (for BMR)", selection: $spec.sex) { ForEach(Sex.allCases) { Text($0.label).tag($0) } }
                    Stepper("Age \(spec.age)", value: $spec.age, in: 13...100)
                    Stepper("Height \(Int(spec.heightCm)) cm", value: $spec.heightCm, in: 120...230)
                    Stepper(String(format: "Weight %.1f kg", spec.weightKg), value: $spec.weightKg, in: 30...250, step: 0.5)
                }
                Section("Goal") {
                    Picker("Goal", selection: $spec.goal) { ForEach(Goal.allCases) { Text($0.title).tag($0) } }
                    Picker("Diet", selection: $spec.diet) { ForEach(Diet.allCases) { Text($0.label).tag($0) } }
                    Picker("Daily activity", selection: $spec.activity) { ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) } }
                    Stepper("Training \(spec.trainDaysPerWeek) days / week", value: $spec.trainDaysPerWeek, in: 0...7)
                }
                if isFirstProfile {
                    Section {
                        Toggle("Use my Apple Watch data", isOn: $linkWatch)
                    } footer: {
                        Text("Reads energy, HRV, resting heart rate, sleep and weight from the Health app. Nothing leaves your iPhone.")
                    }
                }
                let preview = NutritionEngine.targets(for: spec, energy: NutritionEngine.estimatedEnergy(for: spec))
                Section("Starting targets") {
                    LabeledContent("Calories", value: "\(Int(preview.macros.kcal)) kcal")
                    LabeledContent("Protein · carbs · fat", value: "\(Int(preview.macros.protein)) · \(Int(preview.macros.carbs)) · \(Int(preview.macros.fat)) g")
                }
            }
            .navigationTitle(isFirstProfile ? "Welcome to Helix" : "Add person")
            .toolbar {
                Button("Save") {
                    let p = UserProfile(name: name.isEmpty ? "Me" : name, spec: spec, usesHealthKit: isFirstProfile && linkWatch)
                    context.insert(p)
                    try? context.save()
                    model.activeProfileID = p.id
                    onCreated(p)
                }
            }
        }
    }
}
