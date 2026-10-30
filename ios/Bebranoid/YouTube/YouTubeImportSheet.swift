import SwiftUI

/// Модальное окно импорта и синхронизации плейлистов / видео YouTube (`src/views/PlaylistsView.jsx`).
public struct YouTubeImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appState: BebranoidAppState

    @State private var urlInput: String = ""
    @State private var customTitleInput: String = ""
    @State private var isImporting: Bool = false
    @State private var errorMessage: String?

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.11).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ссылка на плейлист или видео YouTube")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))

                            TextField("https://www.youtube.com/playlist?list=...", text: $urlInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Название плейлиста (необязательно)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))

                            TextField("Оставьте пустым для автоопределения", text: $customTitleInput)
                                .padding(14)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Label("Поддерживаются плейлисты YouTube, YouTube Music, одиночные видео и Shorts (до 5000 треков).", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.65))
                            Label("По умолчанию в общий шаффл медиатеки берутся первые 15 треков плейлиста (настраивается кнопками ±10).", systemImage: "shuffle")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            Task {
                                await performImport()
                            }
                        } label: {
                            HStack {
                                if isImporting {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "arrow.down.doc.fill")
                                    Text("Импортировать из YouTube")
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(appState.accentSwiftUIColor, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Импорт YouTube")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func performImport() async {
        errorMessage = nil
        isImporting = true
        defer { isImporting = false }

        do {
            try await appState.importYouTubeURL(urlInput, customTitle: customTitleInput)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
