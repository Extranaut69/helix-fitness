import SwiftUI

struct CoachView: View {
    @Environment(AppModel.self) private var model
    let profile: UserProfile

    struct Message: Identifiable { let id = UUID(); var fromUser: Bool; var text: String }

    @State private var coach = CoachService()
    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var thinking = false

    private let suggestions = ["What should I eat next?", "Should I train hard today?", "How is my progress?", "How did I sleep?", "Protein left?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { m in
                                Text(m.text)
                                    .padding(.horizontal, 13).padding(.vertical, 10)
                                    .background(m.fromUser ? Theme.ice : Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .foregroundStyle(m.fromUser ? Color.black : .primary)
                                    .frame(maxWidth: 300, alignment: m.fromUser ? .trailing : .leading)
                                    .frame(maxWidth: .infinity, alignment: m.fromUser ? .trailing : .leading)
                                    .id(m.id)
                            }
                            if thinking { ProgressView().padding(.leading, 8) }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { Task { await ask(s) } }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                HStack {
                    TextField("Ask your coach…", text: $draft).textFieldStyle(.roundedBorder).onSubmit { send() }
                    Button("Send", action: send).buttonStyle(.borderedProminent).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)
            }
            .navigationTitle("Coach")
            .toolbar {
                Text(coach.engine == .onDevice ? "On-device AI" : "Rules").font(.caption).foregroundStyle(Theme.mute)
            }
            .task(id: profile.id) {
                messages = [Message(fromUser: false, text: CoachService.ruleBased("", context()))]
            }
        }
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        draft = ""
        Task { await ask(q) }
    }

    private func ask(_ q: String) async {
        messages.append(Message(fromUser: true, text: q))
        thinking = true
        let answer = await coach.reply(to: q, context: context())
        thinking = false
        messages.append(Message(fromUser: false, text: answer))
    }

    private func context() -> CoachService.Context {
        let rem = model.remaining(for: profile)
        let want = Macros(kcal: max(0, rem.kcal), protein: max(0, rem.protein), carbs: max(0, rem.carbs), fat: max(0, rem.fat)).scaled(by: 0.55)
        return CoachService.Context(
            name: profile.name, spec: profile.spec, targets: model.targets(for: profile), eaten: profile.eaten(on: .now),
            readiness: model.readiness(for: profile), recovery: model.recovery(for: profile), session: model.session(for: profile),
            weeklyWeightChange: profile.usesHealthKit ? model.snapshot?.weeklyWeightChange : nil,
            nextMeal: MealPlanner.meal(for: want, diet: profile.spec.diet, rotation: Calendar.current.component(.hour, from: .now)))
    }
}
