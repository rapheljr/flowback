import SwiftUI
import AppKit
import FlowbackCore

public final class ApplicationsViewModel: ObservableObject {
    @Published public var newAppBundleID: String = ""
    public init() {}
}

public struct ApplicationsView: View {
    @Binding var protectedApps: [String]
    @StateObject private var viewModel = ApplicationsViewModel()
    
    public init(protectedApps: Binding<[String]>) {
        self._protectedApps = protectedApps
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Protected Applications")
                        .font(.title2.bold())
                    Text("Flowback will NEVER steal focus when any of these applications are frontmost. Notifications will be displayed instead.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    TextField("Add bundle identifier (e.g. us.zoom.xos)", text: $viewModel.newAppBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = viewModel.newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !protectedApps.contains(trimmed) {
                            protectedApps.append(trimmed)
                            viewModel.newAppBundleID = ""
                        }
                    }
                    .disabled(viewModel.newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                VStack(spacing: 8) {
                    ForEach(protectedApps, id: \.self) { app in
                        HStack {
                            Image(systemName: "shield.fill")
                                .foregroundColor(.green)
                            Text(app)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(action: {
                                protectedApps.removeAll { $0 == app }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(24)
        }
    }
}
