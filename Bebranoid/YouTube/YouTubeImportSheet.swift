import SwiftUI

/// Модальное окно импорта и синхронизации плейлистов / видео YouTube (`src/views/PlaylistsView.jsx`) в стиле Liquid Glass (iOS 26 / iOS 27).
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
                LiquidGlassSheetBackdrop(accentColor: appState.accentSwiftUIColor)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ссылка на плейлист или видео YouTube")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.84))

                                TextField("https://www.youtube.com/playlist?list=...", text: $urlInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(14)
                                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.9)
                                    )
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Название плейлиста (необязательно)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.84))

                                TextField("Оставьте пустым для автоопределения", text: $customTitleInput)
                                    .padding(14)
                                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.9)
                                    )
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(16)
                        .liquidGlassCard(cornerRadius: 22, tint: appState.accentSwiftUIColor, tintOpacity: 0.08)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Поддерживаются плейлисты YouTube, YouTube Music, одиночные видео и Shorts (до 5000 треков).", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.white.opacity(0.74))
                            Label("По умолчанию в общий шаффл медиатеки берутся первые 15 треков плейлиста (настраивается кнопками ±10).", systemImage: "shuffle")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.white.opacity(0.74))
                        }
                        .padding(15)
                        .liquidGlassCard(cornerRadius: 20, tint: .white, tintOpacity: 0.04)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 1.0, green: 0.50, blue: 0.50))
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .liquidGlassCard(cornerRadius: 16, tint: .red, tintOpacity: 0.16)
                        }

                        Button {
                            Task {
                                await performImport()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isImporting {
                                    ProgressView().tint(Color(red: 0.08, green: 0.06, blue: 0.14))
                                } else {
                                    Image(systemName: "arrow.down.doc.fill")
                                    Text("Импортировать из YouTube")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                            }
                            .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .liquidGlassCapsule(tint: appState.accentSwiftUIColor, isProminent: true)
                        }
                        .buttonStyle(.plain)
                        .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Импорт YouTube")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .liquidGlassSheetPresentation()
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
