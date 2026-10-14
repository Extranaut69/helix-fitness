import SwiftUI

struct CoachView: View {
    @Environment(AppModel.self) private var model
    let profile: UserProfile

    struct Message: Identifiable { let id = UUID(); var fromUser: Bool; var text: String }

    @State private var coach = CoachService()
    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var thinking = false

    private let suggestions = ["What should I eat next?", "Should I train hard today?", "How is my progress?", "How did I sleep?", "How much protein is left?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ScreenHeader(title: "Coach", subtitle: coach.engine == .onDevice
                                         ? "Answers from your own data, on this iPhone."
                                         : "Answers from your own data, using fixed rules on this iPhone.")
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(messages) { m in
                                    Group {
                                        if m.fromUser {
                                            Text(m.text)
                                                .padding(.horizontal, 13).padding(.vertical, 9)
                                                .foregroundStyle(Theme.onAction)
                                                .background(Theme.action, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16,
                                                                                                     bottomTrailingRadius: 4, topTrailingRadius: 16,
                                                                                                     style: .continuous))
                                                .frame(maxWidth: 300, alignment: .trailing)
                                                .frame(maxWidth: .infinity, alignment: .trailing)
                                        } else {
                                            Text(m.text)
                                                .foregroundStyle(Theme.ink)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .font(.system(size: 15))
                                    .id(m.id)
                                }
                                if thinking { ProgressView().tint(Theme.ink2) }
                            }
                            .padding(.horizontal, Theme.gutter)
                        }
                        .padding(.bottom, 16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { Task { await ask(s) } }.buttonStyle(ChipButtonStyle())
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                HStack(spacing: 8) {
                    TextField("Ask about food, training or sleep", text: $draft)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1.5))
                        .onSubmit { send() }
                    Button("Send", action: send)
                        .buttonStyle(.helix(.primary))
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
            }
            .background(Theme.fog)
            .toolbar(.hidden, for: .navigationBar)
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
