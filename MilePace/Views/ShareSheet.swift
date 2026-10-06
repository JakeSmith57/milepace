import SwiftUI
import UIKit

/// The system share sheet for one file, shown in a `.sheet`.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The file the share sheet offers. `Identifiable` so `.sheet(item:)` shows a fresh sheet per export.
struct ShareFile: Identifiable {
    let url: URL
    let id = UUID()
}
