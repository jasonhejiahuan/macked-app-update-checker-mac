import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AddTrackedAppSheet: View {
    @EnvironmentObject private var controller: AppController

    @Binding var isPresented: Bool
    @State private var displayName = ""
    @State private var sourcePageURL = ""
    @State private var localAppPath = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加追踪应用")
                .font(.title2.weight(.semibold))

            Text("首次添加时会加载 source page，提取最新发布时间，并把它作为当前已安装版本的基线。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Form {
                TextField("显示名称（可选）", text: $displayName)
                TextField("Source page URL", text: $sourcePageURL)
                HStack {
                    TextField("本地 .app 路径", text: $localAppPath)
                    Button("选择…") {
                        chooseLocalApp()
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    isPresented = false
                }
                .disabled(isSubmitting)

                Button {
                    Task {
                        await submit()
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("添加并建立基线")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || sourcePageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || localAppPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func chooseLocalApp() {
        let panel = NSOpenPanel()
        panel.title = "选择本地 App"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]

        if panel.runModal() == .OK, let url = panel.url {
            localAppPath = url.path
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await controller.addTrackedApp(
                displayName: displayName,
                sourcePageURLString: sourcePageURL,
                localAppPath: localAppPath
            )
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
