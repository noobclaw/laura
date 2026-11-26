import SwiftUI
import SwiftData

struct LabScreen: View {
    @Environment(AppState.self) private var state
    @Environment(ProStore.self) private var store
    @Query(sort: \Batch.madeAt, order: .reverse) private var batches: [Batch]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Batches").font(Theme.display(38, relativeTo: .largeTitle)).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Perfume changes as it rests. Smell each batch on the days you planned and write down what moved.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if batches.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        MaturationDemo()
                        if store.isPro {
                            ActionEmpty(title: "No batches yet",
                                        message: "Open a formula, tap Weigh and follow the sheet. When you finish, save it here and Accord reminds you to smell it on day 7, 14 and 28.",
                                        action: "Go to the bench") { state.tab = .bench }
                        } else {
                            ActionEmpty(title: "Keep a maturation diary",
                                        message: "Save what you actually weighed, rate it as it matures and get a reminder on day 7, 14 and 28.",
                                        action: "Unlock batches") { state.proReason = .batches }
                        }
                    }
                } else {
                    VStack(spacing: Theme.Space.s) {
                        ForEach(batches) { b in
                            NavigationLink { BatchDetailScreen(batch: b) } label: { BatchRow(batch: b) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .screenPadding()
            .padding(.top, Theme.Space.m)
            .padding(.bottom, 100)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Ring showing days rested out of a 28-day maceration.
struct MaturationRing: View {
    let days: Int
    var target = 28

    var body: some View {
        let p = min(Double(days) / Double(target), 1)
        ZStack {
            Circle().stroke(Theme.sunken, lineWidth: 5)
            Circle().trim(from: 0, to: p).stroke(p >= 1 ? Theme.ok : Theme.amber, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text(verbatim: "\(days)").font(Theme.figure(.headline))
                Text("days").font(.system(size: 9)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(width: 52, height: 52)
        .accessibilityElement()
        .accessibilityLabel(Text("\(days) days resting"))
    }
}

struct BatchRow: View {
    let batch: Batch

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            MaturationRing(days: batch.ageDays)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: batch.formulaName).font(Theme.display(19, relativeTo: .headline)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(verbatim: "\(Fmt.date(batch.madeAt)) · \(batch.product.name)").font(.caption).foregroundStyle(Theme.inkSoft)
                if let last = batch.sortedNotes.first {
                    Text(verbatim: last.text).font(.caption).foregroundStyle(Theme.ink).lineLimit(1)
                }
            }
            Spacer()
            if batch.rating > 0 { Stars(value: batch.rating, size: 10) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.hair))
        .contentShape(Rectangle())
    }
}

struct Stars: View {
    let value: Int
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star").font(.system(size: size)).foregroundStyle(i <= value ? Theme.amber : Theme.inkSoft.opacity(0.5))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(value) of 5 stars"))
    }
}

/// Illustration of the maturation timeline, shown before the first batch.
private struct MaturationDemo: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach([0, 7, 14, 28], id: \.self) { day in
                VStack(spacing: 6) {
                    Circle().fill(day == 0 ? Theme.amber : Theme.card).overlay(Circle().strokeBorder(Theme.ink.opacity(0.6), lineWidth: 1))
                        .frame(width: 14, height: 14)
                    Text("Day \(day)").font(.caption2).foregroundStyle(Theme.inkSoft)
                }
                if day != 28 { Rectangle().fill(Theme.hair).frame(height: 1).padding(.bottom, 18) }
            }
        }
        .padding(Theme.Space.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct BatchDetailScreen: View {
    @Bindable var batch: Batch
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @Query private var formulas: [Formula]
    @State private var noteText = ""
    @State private var noteRating = 0
    @State private var confirmDelete = false
    @State private var notificationsDenied = false
    @FocusState private var noteFocused: Bool

    private var formula: Formula? { formulas.first { $0.id == batch.formulaID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(alignment: .center, spacing: Theme.Space.m) {
                    MaturationRing(days: batch.ageDays)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: batch.formulaName).font(Theme.display(28, relativeTo: .title)).foregroundStyle(Theme.ink)
                        Text(verbatim: "\(String(localized: "v\(batch.formulaVersion)", bundle: .l10n)) · \(Fmt.date(batch.madeAt))")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                }
                HStack {
                    Text("Overall")
                    Spacer()
                    StarPicker(value: $batch.rating)
                }
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))

                timeline
                weighed
                reminders

                if let f = formula {
                    Button { state.open(f) } label: { Label("Open the formula", systemImage: "flask") }
                        .buttonStyle(QuietButtonStyle())
                }
                Button(role: .destructive) { confirmDelete = true } label: { Text("Delete batch record") }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Space.s)
            }
            .screenPadding()
            .padding(.bottom, 100)
        }
        .background(PaperBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog(Text("Delete this batch record?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete record and its notes", role: .destructive) {
                Reminders.cancel(batch)
                dismiss()
                let ctx = context, b = batch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    ctx.delete(b)
                    try? ctx.save()
                }
            }
        } message: { Text("The formula itself is not affected.") }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Maturation diary").font(Theme.display(20, italic: true, relativeTo: .title3))
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                TextField(text: $noteText, axis: .vertical) { Text("Day \(batch.ageDays): how does it smell now?") }
                    .lineLimit(2...5)
                    .focused($noteFocused)
                    .accessibilityIdentifier("aging-note")
                HStack {
                    StarPicker(value: $noteRating)
                    Spacer()
                    Button("Add note") { addNote() }
                        .buttonStyle(PrimaryButtonStyle(wide: false))
                        .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))

            ForEach(batch.sortedNotes) { note in
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    VStack(spacing: 0) {
                        Circle().fill(Theme.amber).frame(width: 10, height: 10)
                        Rectangle().fill(Theme.hair).frame(width: 1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(verbatim: dayLabel(note.date)).font(.caption.weight(.semibold)).foregroundStyle(Theme.amberInk)
                            if note.rating > 0 { Stars(value: note.rating, size: 9) }
                            Spacer()
                            Text(verbatim: Fmt.date(note.date)).font(.caption2).foregroundStyle(Theme.inkSoft)
                        }
                        Text(verbatim: note.text).font(.subheadline).foregroundStyle(Theme.ink)
                    }
                    .padding(.bottom, Theme.Space.m)
                }
                .contextMenu {
                    Button(role: .destructive) { context.delete(note) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    private var weighed: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("What went in").font(Theme.display(20, italic: true, relativeTo: .title3))
            VStack(spacing: 0) {
                ForEach(Array(batch.entries.enumerated()), id: \.offset) { _, e in
                    HStack {
                        Text(verbatim: e.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(verbatim: Fmt.grams(e.actual)).font(Theme.figure(.subheadline))
                        if e.target > 0, abs(e.actual - e.target) / e.target > 0.05 {
                            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warn)
                                .accessibilityLabel(Text("Off target"))
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .hairDivider()
                }
                if batch.ethanolGrams > 0 {
                    HStack {
                        Text(verbatim: batch.product.diluentName).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text(verbatim: Fmt.grams(batch.ethanolGrams)).font(Theme.figure(.body, weight: .medium))
                    }
                    .padding(.vertical, 6).padding(.horizontal, 12)
                }
                if batch.waterGrams > 0 { InfoRow(label: "Distilled water", value: Fmt.grams(batch.waterGrams)).padding(.horizontal, 12) }
                if batch.bottleML > 0 { InfoRow(label: "Bottle", value: Fmt.number(batch.bottleML) + " " + String(localized: "ml", bundle: .l10n)).padding(.horizontal, 12) }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Reminders").font(Theme.display(20, italic: true, relativeTo: .title3))
            HStack(spacing: 6) {
                ForEach([3, 7, 14, 28, 42], id: \.self) { d in
                    let on = batch.reminderDays.contains(d)
                    Button {
                        Haptics.select()
                        if on { batch.reminderDays.removeAll { $0 == d } } else { batch.reminderDays.append(d); batch.reminderDays.sort() }
                        Reminders.schedule(batch)
                        Reminders.status { notificationsDenied = $0 == .denied }
                    } label: {
                        Text("Day \(d)").font(.footnote.weight(.semibold))
                            .foregroundStyle(on ? Theme.onAmber : Theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(on ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Theme.card), in: RoundedRectangle(cornerRadius: Theme.Radius.row))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if notificationsDenied {
                HStack {
                    Text("Notifications are off for Accord.").font(.footnote).foregroundStyle(Theme.warn)
                    Spacer()
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
        .onAppear { Reminders.status { notificationsDenied = $0 == .denied } }
    }

    private func dayLabel(_ date: Date) -> String {
        let d = max(0, Calendar.current.dateComponents([.day], from: batch.madeAt, to: date).day ?? 0)
        return String(localized: "Day \(d)", bundle: .l10n)
    }

    private func addNote() {
        let n = AgingNote(text: noteText.trimmingCharacters(in: .whitespacesAndNewlines), rating: noteRating)
        context.insert(n)
        n.batch = batch
        if noteRating > 0 { batch.rating = noteRating }
        try? context.save()
        noteText = ""
        noteRating = 0
        noteFocused = false
        Haptics.success()
    }
}

struct StarPicker: View {
    @Binding var value: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    Haptics.select()
                    value = value == i ? 0 : i
                } label: {
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .font(.system(size: 20))
                        .foregroundStyle(i <= value ? Theme.amber : Theme.inkSoft.opacity(0.6))
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Rating"))
        .accessibilityValue(Text("\(value) of 5 stars"))
        .accessibilityAdjustableAction { dir in
            value = dir == .increment ? min(5, value + 1) : max(0, value - 1)
        }
    }
}
