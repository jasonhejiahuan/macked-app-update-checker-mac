import SwiftData
import SwiftUI

struct TrackedAppsWindowView: View {
    @EnvironmentObject private var controller: AppController
    @Query(sort: [
        SortDescriptor(\TrackedApp.displayName),
        SortDescriptor(\TrackedApp.createdAt),
    ]) private var trackedApps: [TrackedApp]
    @State private var isPresentingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if trackedApps.isEmpty {
                    ContentUnavailableView(
                        "还没有追踪任何应用",
                        systemImage: "plus.app",
                        description: Text("添加 source page 与本地 .app 路径后，应用会自动周期检查更新。")
                    )
                } else {
                    List {
                        ForEach(trackedApps) { app in
                            TrackedAppRowView(app: app)
                        }
                        .onDelete(perform: deleteRows)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Tracked Apps")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isPresentingAddSheet = true
                    } label: {
                        Label("添加应用", systemImage: "plus")
                    }

                    Button {
                        Task {
                            await controller.checkAllNow()
                        }
                    } label: {
                        Label("检查全部", systemImage: "arrow.clockwise")
                    }
                    .disabled(controller.isCheckingAll)
                }
            }
        }
        .sheet(isPresented: $isPresentingAddSheet) {
            AddTrackedAppSheet(isPresented: $isPresentingAddSheet)
                .environmentObject(controller)
                .frame(width: 520)
                .padding(24)
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        let ids = offsets.map { trackedApps[$0].id }
        controller.deleteTrackedApps(ids: ids)
    }
}
