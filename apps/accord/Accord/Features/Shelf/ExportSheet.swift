import SwiftUI
import UIKit

struct ExportSheet: View {
    let formula: Formula
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: ShareItem?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            do { shareURL = ShareItem(url: try Exporter.export(formula, as: format)) }
                            catch { self.error = error.localizedDescription }
                        } label: {
                            Label {
                                Text(verbatim: format.title).foregroundStyle(Theme.ink)
                            } icon: {
                                Image(systemName: format.symbol).foregroundStyle(Theme.amberInk)
                            }
                        }
                        .accessibilityIdentifier("export-\(format.rawValue)")
                    }
                } footer: {
                    Text("CSV files open in Numbers, Excel and Google Sheets, and import back into Accord.")
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle(Text("Export “\(formula.name)”"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $shareURL) { item in ActivityView(items: [item.url]).ignoresSafeArea() }
            .alert(Text("Export failed"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(verbatim: error ?? "") }
        }
        .presentationDetents([.medium])
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
