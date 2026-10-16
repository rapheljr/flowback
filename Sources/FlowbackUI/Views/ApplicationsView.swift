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
                        .accessibilityLabel("Application bundle identifier to protect")
                        .accessibilityIdentifier("applications-bundle-textfield")
                        .onSubmit(addApp)
                    Button("Add", action: addApp)
                        .disabled(viewModel.newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("applications-add-button")
                }
                
                if protectedApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "shield.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No protected applications")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Add bundle identifiers (e.g. us.zoom.xos, com.apple.Keynote) to ensure Flowback never interrupts presentations or meetings.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("applications-empty-state")
                } else {
                    VStack(spacing: 8) {
                        ForEach(protectedApps, id: \.self) { app in
                            HStack {
                                Image(systemName: "shield.fill")
                                    .foregroundColor(.green)
                                    .accessibilityHidden(true)
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
                                .accessibilityLabel("Remove \(app) from protected applications")
                                .help("Remove \(app) from protected applications")
                                .accessibilityIdentifier("applications-remove-\(app)")
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    private func addApp() {
        let trimmed = viewModel.newAppBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !protectedApps.contains(trimmed) {
            protectedApps.append(trimmed)
            viewModel.newAppBundleID = ""
        }
    }
}
