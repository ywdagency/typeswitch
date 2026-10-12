import SwiftUI

struct LearnedWordsView: View {
    let appModel: AppModel
    let coordinator: LayoutCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learned Words")
                .font(.title2.weight(.semibold))

            Text("These corrections are stored only on this Mac.")
                .foregroundStyle(.secondary)

            if appModel.learnedCorrections.isEmpty {
                ContentUnavailableView(
                    "No Learned Words",
                    systemImage: "text.badge.plus",
                    description: Text("A confirmed missed correction will appear here.")
                )
            } else {
                List(appModel.learnedCorrections) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(entry.wrongToken) → \(entry.correctToken)")
                                .font(.body.monospaced())
                            Text(entry.language.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            coordinator.removeLearnedCorrection(id: entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove learned correction")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(width: 500, height: 340)
    }
}
