import SwiftUI

/// Полноэкранный плеер Bebranoid iOS (`src/views/NowPlaying.jsx` + `src/components/Player.jsx`) в стиле Liquid Glass (iOS 26 / iOS 27).
/// Включает:
/// - Живой фон `HarmonoidMeshView`, синхронизированный с реальной палитрой обложки, предзагруженным следующим треком и свайпом диска
/// - Верхнюю панель с кнопкой сворачивания `⌄` и меню трека `•••`
/// - Карусель обложек с полноценным улётом диска за край экрана при свайпе влево/вправо, 3D-вращением гироскопом и 3D Touch / долгим нажатием для увеличения обложки и просмотра сведений о треке
/// - Название трека, исполнителя/альбома и круглые стеклянные кнопки `Избранное` и `Очередь` (без лишней кнопки `Инфо`)
/// - Капсульную панель быстрого доступа (`Текст`, `Звук / FX`)
/// - Крупные кнопки управления воспроизведением (`Shuffle`, `Prev`, круглая акцентная `Play/Pause`, `Next`, `Repeat`)
/// - Абсолютно плавный 120 Гц слайдер прогресса без рывков при отпускании пальца и смене трека
public struct FullScreenPlayerView: View {
    @ObservedObject var appState: BebranoidAppState
    @Environment(\.dismiss) private var dismiss

    @State private var isDraggingSlider: Bool = false
    @State private var draggedTime: Double = 0.0
    @State private var dragDismissOffset: CGFloat = 0.0
    @State private var coverHorizontalOffset: CGFloat = 0.0
    @State private var lockedGestureAxis: Axis? = nil
    @State private var isCompletingDiscSwipe: Bool = false
    @State private var trackChangeSettleScale: CGFloat = 1.0

    // Состояние 3D Touch / долгого удержания обложки для увеличения и открытия сведений
    @State private var isPressingCover: Bool = false
    @State private var isCover3DPreviewPresented: Bool = false
    @State private var coverLongPressTask: Task<Void, Never>? = nil

    // Слоты обложек исходного максимального качества (`.originalSource`) без мигания при свайпе и переключении трека
    @State private var prevCoverTrackId: String? = nil
    @State private var prevCoverImage: CGImage? = nil
    @State private var activeCoverTrackId: String? = nil
    @State private var activeCoverImage: CGImage? = nil
    @State private var nextCoverTrackId: String? = nil
    @State private var nextCoverImage: CGImage? = nil
    @State private var crossfadeOutgoingImage: CGImage? = nil
    @State private var crossfadeIncomingAlpha: Double = 1.0
    @State private var crossfadeCleanupTask: Task<Void, Never>? = nil

    @StateObject private var gyro = GyroscopeMotionManager()

    public init(appState: BebranoidAppState) {
        self.appState = appState
    }

    private var track: Track? {
        appState.currentTrack
    }

    private var activeDownloadPercent: Int? {
        appState.downloadProgress(for: track)
    }

    public var body: some View {
        GeometryReader { geo in
            let discStride = max(320.0, geo.size.width * 0.94)
            let forwardSwipeProgress = coverHorizontalOffset < 0
                ? min(1.0, max(0.0, Double(-coverHorizontalOffset / discStride)))
                : 0.0
            let effectiveCrossfade = max(appState.crossfadeProgress, forwardSwipeProgress)
            let liveAccentRGB = appState.effectiveAccentRGB(extraProgress: forwardSwipeProgress)
            let liveAccentNorm = liveAccentRGB.normalizedDouble
            let liveAccentColor = Color(red: liveAccentNorm.r, green: liveAccentNorm.g, blue: liveAccentNorm.b)

            ZStack {
                #if DEBUG
                let fixedTime = appState.demoFixedMeshTime
                #else
                let fixedTime: Double? = nil
                #endif
                HarmonoidMeshView(
                    currentPalette: appState.currentPalette,
                    nextPalette: appState.nextTrackPalette,
                    crossfadeProgress: effectiveCrossfade,
                    isReducedMotion: appState.isReducedMotionEnabled || dragDismissOffset > 2,
                    isOccluded: appState.isLyricsScreenPresented,
                    fixedAnimationTime: fixedTime
                )

                VStack(spacing: 0) {
                    topHeaderBar
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                        .contentShape(Rectangle())
                        .gesture(headerDismissGesture)

                    // Отдельная плавающая плашка фонового скачивания выбранного трека, пока текущий трек продолжает играть
                    if let pending = appState.pendingDownloadTrack, pending.id != track?.id {
                        DownloadingTrackGlassBanner(appState: appState, downloadingTrack: pending)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer(minLength: 10)

                    // Карусель 3D-обложек с полноценным пролистыванием диска до конца и 3D Touch увеличением
                    let coverSide = min(geo.size.width - 48, geo.size.height * 0.425)
                    coverCarouselSection(
                        coverSide: coverSide,
                        discStride: discStride,
                        liveAccentRGB: liveAccentRGB,
                        liveAccentColor: liveAccentColor
                    )
                    .frame(width: geo.size.width, height: coverSide)

                    Spacer(minLength: 18)

                    // Блок названия трека, исполнителя и 2 круглых стеклянных кнопок справа (Heart, Queue)
                    trackMetadataAndQuickActionsRow(accentColor: liveAccentColor)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 14)

                    // Центральная капсула переключения в Текст / FX
                    centerModePillRow(accentColor: liveAccentColor)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 18)

                    // Крупные центральные кнопки управления воспроизведением
                    transportControlsRow(accentColor: liveAccentColor)
                        .padding(.horizontal, 28)

                    Spacer(minLength: 20)

                    // Плавный 120 Гц слайдер прогресса + время + кодек/частота/битрейт
                    progressAndTechnicalFooter(accentColor: liveAccentColor)
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(18, geo.safeAreaInsets.bottom > 0 ? 12 : 22))
                }
                .scaleEffect(max(0.92, 1.0 - (dragDismissOffset / 1800.0)))
                .offset(y: dragDismissOffset)
                .blur(radius: isCover3DPreviewPresented ? 12 : 0)

                // 3D Touch оверлей увеличенной обложки и сведений о треке в стиле Liquid Glass
                if isCover3DPreviewPresented, let current = track {
                    Cover3DTouchPreviewOverlay(
                        track: current,
                        localCoverPath: appState.libraryState.customAlbumCovers[current.album] ?? current.coverPath,
                        formatInfo: appState.audioEngine.currentFormatInfo ?? current.formatInfo,
                        accentRGB: liveAccentRGB,
                        accentColor: liveAccentColor,
                        viewportSize: geo.size,
                        onDismiss: {
                            appState.haptics.softSelection()
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                isCover3DPreviewPresented = false
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .zIndex(20)
                }
            }
        }
        .sheet(isPresented: $appState.isQueueSheetPresented) {
            QueueSheetView(appState: appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .liquidGlassSheetPresentation()
        }
        .sheet(isPresented: $appState.isAudioFXSheetPresented) {
            AudioFXSheetView(appState: appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .liquidGlassSheetPresentation()
        }
        .sheet(item: $appState.inspectedTrackForInfo) { targetTrack in
            TrackInfoSheetView(
                track: targetTrack,
                formatInfo: appState.audioEngine.currentFormatInfo ?? targetTrack.formatInfo,
                accentColor: appState.accentSwiftUIColor
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .liquidGlassSheetPresentation()
        }
        .fullScreenCover(isPresented: $appState.isLyricsScreenPresented) {
            LyricsScreenView(appState: appState)
        }
        .onAppear {
            syncAndPreloadCarouselCovers(initialMount: true)
            gyro.setActive(appState.isGyroscope3DCoverEnabled && !appState.isLyricsScreenPresented && !isCover3DPreviewPresented)
        }
        .onDisappear {
            coverLongPressTask?.cancel()
            crossfadeCleanupTask?.cancel()
            gyro.stop()
        }
        .onChange(of: appState.isGyroscope3DCoverEnabled) { _, enabled in
            gyro.setActive(enabled && !appState.isLyricsScreenPresented && !isCover3DPreviewPresented)
        }
        .onChange(of: appState.isLyricsScreenPresented) { _, lyricsOpen in
            gyro.setActive(appState.isGyroscope3DCoverEnabled && !lyricsOpen && !isCover3DPreviewPresented)
        }
        .onChange(of: isCover3DPreviewPresented) { _, previewOpen in
            gyro.setActive(appState.isGyroscope3DCoverEnabled && !appState.isLyricsScreenPresented && !previewOpen)
        }
        .onChange(of: track?.id) { _, _ in
            isDraggingSlider = false
            draggedTime = 0.0
            handleTrackChangedForCarousel()
            if !isCompletingDiscSwipe {
                trackChangeSettleScale = 0.978
                withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.46)) {
                    trackChangeSettleScale = 1.0
                }
            }
        }
        .onChange(of: appState.upcomingNextTrack?.id) { _, _ in
            preloadAdjacentSlotsAsync()
        }
        .onChange(of: appState.adjacentPreviousTrack?.id) { _, _ in
            preloadAdjacentSlotsAsync()
        }
        .onReceive(NotificationCenter.default.publisher(for: .artworkDidResolve)) { note in
            let resolvedId = note.userInfo?["trackId"] as? String
            if let cur = track, resolvedId == cur.id {
                reloadActiveOriginalCoverAsync(for: cur, upgradeSmoothly: true)
            } else {
                preloadAdjacentSlotsAsync(forceReloadId: resolvedId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackDownloadProgressDidChange)) { note in
            guard note.userInfo?["percent"] == nil,
                  let key = note.userInfo?["cacheKey"] as? String else { return }
            if let cur = track, cur.cacheKey == key {
                ArtworkService.shared.invalidateCachedSyncPath(forTrackId: cur.id, cacheKey: cur.cacheKey)
                reloadActiveOriginalCoverAsync(for: cur, upgradeSmoothly: true)
            } else {
                preloadAdjacentSlotsAsync()
            }
        }
    }

    // MARK: - Zero-Blink Native Original-Quality Cover Slot Management

    private func syncLookupOriginalCover(for targetTrack: Track?) -> CGImage? {
        guard let targetTrack else { return nil }
        if let customPath = appState.libraryState.customAlbumCovers[targetTrack.album],
           !customPath.isEmpty,
           ArtworkService.shared.isValidImageFile(atPath: customPath) {
            if let mem = ArtworkService.shared.memoryCachedImage(forKey: customPath, tier: .originalSource) {
                return mem
            }
            if let cg = ArtworkService.shared.loadCGImage(from: URL(fileURLWithPath: customPath), tier: .originalSource) {
                ArtworkService.shared.storeMemoryCachedImage(cg, forKey: customPath, tier: .originalSource)
                return cg
            }
        }
        if let mem = ArtworkService.shared.memoryCachedImage(forKey: targetTrack.id, tier: .originalSource) {
            return mem
        }
        if let syncHit = ArtworkService.shared.resolveLocalCoverURLSync(
            for: targetTrack,
            customAlbumCovers: appState.libraryState.customAlbumCovers,
            siblingTracks: appState.libraryState.tracks
        ), let cg = ArtworkService.shared.loadCGImage(from: syncHit.url, tier: .originalSource) {
            ArtworkService.shared.storeMemoryCachedImage(cg, forKey: targetTrack.id, tier: .originalSource)
            return cg
        }
        return nil
    }

    private func syncAndPreloadCarouselCovers(initialMount: Bool) {
        if let cur = track {
            if initialMount || activeCoverTrackId != cur.id {
                activeCoverTrackId = cur.id
                activeCoverImage = syncLookupOriginalCover(for: cur)
                crossfadeOutgoingImage = nil
                crossfadeIncomingAlpha = 1.0
                if activeCoverImage == nil {
                    reloadActiveOriginalCoverAsync(for: cur, upgradeSmoothly: false)
                } else if appState.cacheIndex.isCached(cur) {
                    // Убеждаемся, что загружена 100% исходная встроенная обложка максимального качества
                    reloadActiveOriginalCoverAsync(for: cur, upgradeSmoothly: true)
                }
            }
        } else {
            activeCoverTrackId = nil
            activeCoverImage = nil
        }
        preloadAdjacentSlotsAsync()
    }

    private func handleTrackChangedForCarousel() {
        guard let newTrack = track else {
            activeCoverTrackId = nil
            activeCoverImage = nil
            crossfadeOutgoingImage = nil
            return
        }

        // Если трек уже синхронно продвинут свайпом пальца (`completeDiscFlick`) — НЕ трогаем `activeCoverImage`,
        // чтобы не было ни малейшего мигания или повторного фейда!
        if activeCoverTrackId == newTrack.id {
            if activeCoverImage == nil {
                reloadActiveOriginalCoverAsync(for: newTrack, upgradeSmoothly: true)
            }
            preloadAdjacentSlotsAsync()
            return
        }

        let previousDisplayed = activeCoverImage
        let preloadedCandidate: CGImage? = {
            if newTrack.id == nextCoverTrackId, let nxt = nextCoverImage { return nxt }
            if newTrack.id == prevCoverTrackId, let prv = prevCoverImage { return prv }
            return syncLookupOriginalCover(for: newTrack)
        }()

        crossfadeCleanupTask?.cancel()
        crossfadeOutgoingImage = previousDisplayed
        activeCoverTrackId = newTrack.id
        activeCoverImage = preloadedCandidate

        if previousDisplayed != nil || preloadedCandidate != nil {
            crossfadeIncomingAlpha = 0.0
            withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.38)) {
                crossfadeIncomingAlpha = 1.0
            }
            crossfadeCleanupTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 410_000_000)
                guard !Task.isCancelled else { return }
                crossfadeOutgoingImage = nil
            }
        } else {
            crossfadeOutgoingImage = nil
            crossfadeIncomingAlpha = 1.0
        }

        if preloadedCandidate == nil || appState.cacheIndex.isCached(newTrack) {
            reloadActiveOriginalCoverAsync(for: newTrack, upgradeSmoothly: true)
        }
        preloadAdjacentSlotsAsync()
    }

    private func reloadActiveOriginalCoverAsync(for targetTrack: Track, upgradeSmoothly: Bool) {
        let customCovers = appState.libraryState.customAlbumCovers
        let siblings = appState.libraryState.tracks
        Task {
            let decoded: CGImage? = await Task.detached(priority: .userInitiated) {
                if let customPath = customCovers[targetTrack.album],
                   !customPath.isEmpty,
                   ArtworkService.shared.isValidImageFile(atPath: customPath),
                   let cg = ArtworkService.shared.loadCGImage(from: URL(fileURLWithPath: customPath), tier: .originalSource) {
                    ArtworkService.shared.storeMemoryCachedImage(cg, forKey: customPath, tier: .originalSource)
                    return cg
                }
                if let syncHit = ArtworkService.shared.resolveLocalCoverURLSync(
                    for: targetTrack,
                    customAlbumCovers: customCovers,
                    siblingTracks: siblings
                ), let cg = ArtworkService.shared.loadCGImage(from: syncHit.url, tier: .originalSource) {
                    ArtworkService.shared.storeMemoryCachedImage(cg, forKey: targetTrack.id, tier: .originalSource)
                    return cg
                }
                if let resolved = await ArtworkService.shared.resolveArtwork(
                    for: targetTrack,
                    customAlbumCovers: customCovers,
                    siblingTracks: siblings
                ), let fileURL = resolved.fileURL,
                   let cg = ArtworkService.shared.loadCGImage(from: fileURL, tier: .originalSource) {
                    ArtworkService.shared.storeMemoryCachedImage(cg, forKey: targetTrack.id, tier: .originalSource)
                    return cg
                }
                return nil
            }.value

            await MainActor.run {
                guard self.track?.id == targetTrack.id else { return }
                guard let decoded else { return }
                if let curImg = self.activeCoverImage,
                   curImg === decoded || (curImg.width >= decoded.width && curImg.height >= decoded.height && self.activeCoverTrackId == targetTrack.id) {
                    return
                }
                if upgradeSmoothly, let existing = self.activeCoverImage {
                    self.crossfadeCleanupTask?.cancel()
                    self.crossfadeOutgoingImage = existing
                    self.activeCoverImage = decoded
                    self.crossfadeIncomingAlpha = 0.0
                    withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.34)) {
                        self.crossfadeIncomingAlpha = 1.0
                    }
                    self.crossfadeCleanupTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 360_000_000)
                        guard !Task.isCancelled else { return }
                        self.crossfadeOutgoingImage = nil
                    }
                } else {
                    self.activeCoverImage = decoded
                }
            }
        }
    }

    private func preloadAdjacentSlotsAsync(forceReloadId: String? = nil) {
        let prevTrack = appState.adjacentPreviousTrack
        let nextTrack = appState.upcomingNextTrack
        let customCovers = appState.libraryState.customAlbumCovers
        let siblings = appState.libraryState.tracks

        if let prevTrack {
            if prevCoverTrackId != prevTrack.id || forceReloadId == prevTrack.id {
                prevCoverTrackId = prevTrack.id
                prevCoverImage = syncLookupOriginalCover(for: prevTrack)
                if prevCoverImage == nil || forceReloadId == prevTrack.id {
                    Task {
                        let cg = await Self.resolveOriginalCGImageOffMain(for: prevTrack, customCovers: customCovers, siblings: siblings)
                        await MainActor.run {
                            if self.appState.adjacentPreviousTrack?.id == prevTrack.id {
                                self.prevCoverTrackId = prevTrack.id
                                self.prevCoverImage = cg
                            }
                        }
                    }
                }
            }
        } else {
            prevCoverTrackId = nil
            prevCoverImage = nil
        }

        if let nextTrack {
            if nextCoverTrackId != nextTrack.id || forceReloadId == nextTrack.id {
                nextCoverTrackId = nextTrack.id
                nextCoverImage = syncLookupOriginalCover(for: nextTrack)
                if nextCoverImage == nil || forceReloadId == nextTrack.id {
                    Task {
                        let cg = await Self.resolveOriginalCGImageOffMain(for: nextTrack, customCovers: customCovers, siblings: siblings)
                        await MainActor.run {
                            if self.appState.upcomingNextTrack?.id == nextTrack.id {
                                self.nextCoverTrackId = nextTrack.id
                                self.nextCoverImage = cg
                            }
                        }
                    }
                }
            }
        } else {
            nextCoverTrackId = nil
            nextCoverImage = nil
        }
    }

    nonisolated private static func resolveOriginalCGImageOffMain(
        for targetTrack: Track,
        customCovers: [String: String],
        siblings: [Track]
    ) async -> CGImage? {
        if let customPath = customCovers[targetTrack.album],
           !customPath.isEmpty,
           ArtworkService.shared.isValidImageFile(atPath: customPath),
           let cg = ArtworkService.shared.loadCGImage(from: URL(fileURLWithPath: customPath), tier: .originalSource) {
            ArtworkService.shared.storeMemoryCachedImage(cg, forKey: customPath, tier: .originalSource)
            return cg
        }
        if let syncHit = ArtworkService.shared.resolveLocalCoverURLSync(
            for: targetTrack,
            customAlbumCovers: customCovers,
            siblingTracks: siblings
        ), let cg = ArtworkService.shared.loadCGImage(from: syncHit.url, tier: .originalSource) {
            ArtworkService.shared.storeMemoryCachedImage(cg, forKey: targetTrack.id, tier: .originalSource)
            return cg
        }
        if let resolved = await ArtworkService.shared.resolveArtwork(
            for: targetTrack,
            customAlbumCovers: customCovers,
            siblingTracks: siblings
        ), let fileURL = resolved.fileURL,
           let cg = ArtworkService.shared.loadCGImage(from: fileURL, tier: .originalSource) {
            ArtworkService.shared.storeMemoryCachedImage(cg, forKey: targetTrack.id, tier: .originalSource)
            return cg
        }
        return nil
    }

    // MARK: - Cover Carousel & 3D Touch

    @ViewBuilder
    private func coverCarouselSection(
        coverSide: CGFloat,
        discStride: CGFloat,
        liveAccentRGB: MeshRGB,
        liveAccentColor: Color
    ) -> some View {
        let tiltX = (appState.isGyroscope3DCoverEnabled && abs(coverHorizontalOffset) < 2) ? gyro.tiltXDegrees : 0.0
        let tiltY = (appState.isGyroscope3DCoverEnabled && abs(coverHorizontalOffset) < 2) ? gyro.tiltYDegrees : 0.0
        let swipeRatio = min(1.0, abs(coverHorizontalOffset) / max(1.0, discStride))
        let outgoingScale = 1.0 - 0.10 * swipeRatio
        let outgoingOpacity = 1.0 - 0.30 * swipeRatio
        let isRimPaused = appState.isReducedMotionEnabled
            || appState.isLyricsScreenPresented
            || isCover3DPreviewPresented
            || dragDismissOffset > 1

        ZStack {
            // Соседний предыдущий диск слева (плавно въезжает при свайпе вправо без мигания)
            if coverHorizontalOffset > 1, appState.adjacentPreviousTrack != nil {
                let incomingProgress = min(1.0, coverHorizontalOffset / discStride)
                Sculpted3DCoverSlabView(
                    primaryImage: prevCoverImage,
                    outgoingImage: nil,
                    incomingAlpha: 1.0,
                    accentRGB: liveAccentRGB,
                    cornerRadius: 28,
                    coverSide: coverSide,
                    tiltX: 0,
                    tiltY: 0,
                    specularOffset: .zero,
                    isRimPaused: true
                )
                .frame(width: coverSide, height: coverSide)
                .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 14)
                .scaleEffect((appState.isPlaying ? 1.0 : 0.93) * (0.88 + 0.12 * incomingProgress))
                .opacity(0.48 + 0.52 * incomingProgress)
                .offset(x: -discStride + coverHorizontalOffset)
                .allowsHitTesting(false)
            }

            // Соседний следующий диск справа (плавно въезжает при свайпе влево без мигания)
            if coverHorizontalOffset < -1, appState.upcomingNextTrack != nil {
                let incomingProgress = min(1.0, -coverHorizontalOffset / discStride)
                let nextAccent = appState.nextTrackAccent ?? liveAccentRGB
                Sculpted3DCoverSlabView(
                    primaryImage: nextCoverImage,
                    outgoingImage: nil,
                    incomingAlpha: 1.0,
                    accentRGB: nextAccent,
                    cornerRadius: 28,
                    coverSide: coverSide,
                    tiltX: 0,
                    tiltY: 0,
                    specularOffset: .zero,
                    isRimPaused: true
                )
                .frame(width: coverSide, height: coverSide)
                .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 14)
                .scaleEffect((appState.isPlaying ? 1.0 : 0.93) * (0.88 + 0.12 * incomingProgress))
                .opacity(0.48 + 0.52 * incomingProgress)
                .offset(x: discStride + coverHorizontalOffset)
                .allowsHitTesting(false)
            }

            // Центральный 3D-диск с исходным качеством и единой живой обводкой по всему 3D-объёму
            let pressScale: CGFloat = isPressingCover ? 0.972 : 1.0

            ZStack(alignment: .bottom) {
                Sculpted3DCoverSlabView(
                    primaryImage: activeCoverImage,
                    outgoingImage: crossfadeOutgoingImage,
                    incomingAlpha: crossfadeIncomingAlpha,
                    accentRGB: liveAccentRGB,
                    cornerRadius: 28,
                    coverSide: coverSide,
                    tiltX: tiltX,
                    tiltY: tiltY,
                    specularOffset: gyro.specularUnitOffset,
                    isRimPaused: isRimPaused || abs(coverHorizontalOffset) > 2
                )
                .frame(width: coverSide, height: coverSide)

                if let pct = activeDownloadPercent {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("Загрузка трека: \(pct)%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        ProgressView(value: Double(max(1, min(100, pct))), total: 100.0)
                            .tint(liveAccentColor)
                            .frame(width: coverSide * 0.68)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .liquidGlassCard(cornerRadius: 16, tint: liveAccentColor, tintOpacity: 0.10)
                    .padding(.bottom, 14)
                }
            }
            .frame(width: coverSide, height: coverSide)
            .contentShape(Rectangle())
            .rotation3DEffect(
                .degrees(tiltX),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.50
            )
            .rotation3DEffect(
                .degrees(tiltY),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.50
            )
            .scaleEffect((appState.isPlaying ? 1.0 : 0.93) * trackChangeSettleScale * outgoingScale * pressScale)
            .opacity(outgoingOpacity)
            .rotationEffect(.degrees(Double(coverHorizontalOffset) * 0.026))
            .offset(x: coverHorizontalOffset)
            .shadow(
                color: Color.black.opacity(0.48),
                radius: 26,
                x: CGFloat(-tiltY * 0.80),
                y: 15 + CGFloat(tiltX * 0.70)
            )
            .animation(.spring(response: 0.34, dampingFraction: 0.80), value: appState.isPlaying)
            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: isPressingCover)
            .highPriorityGesture(coverInteractiveAnd3DTouchGesture(discStride: discStride))
        }
    }

    private var headerDismissGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let dy = value.translation.height
                let dx = abs(value.translation.width)
                if dy > 0 && dy > dx * 0.8 {
                    dragDismissOffset = dy * 0.88
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let predictedY = value.predictedEndTranslation.height
                if dy > 42 || predictedY > 95 {
                    dragDismissOffset = 0
                    appState.haptics.softSelection()
                    appState.isFullScreenPlayerPresented = false
                    dismiss()
                } else {
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.84)) {
                        dragDismissOffset = 0
                    }
                }
            }
    }

    /// Единый жест обложки:
    /// - Удержание пальца без сдвига (`0.36 с`) -> 3D Touch увеличение обложки и сведений о треке с тактильным откликом
    /// - Горизонтальный свайп -> полноценное перелистывание диска до конца за экран и бесшовная подстановка нового трека
    /// - Вертикальный свайп вниз -> плавное сворачивание плеера
    private func coverInteractiveAnd3DTouchGesture(discStride: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard !isDraggingSlider, !isCompletingDiscSwipe, !isCover3DPreviewPresented else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                let distance = hypot(dx, dy)

                if lockedGestureAxis == nil && distance < 8.5 {
                    if !isPressingCover && coverLongPressTask == nil && track != nil {
                        isPressingCover = true
                        coverLongPressTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 360_000_000)
                            guard !Task.isCancelled, lockedGestureAxis == nil, !isCompletingDiscSwipe else { return }
                            isPressingCover = false
                            appState.haptics.mediumImpact()
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                isCover3DPreviewPresented = true
                            }
                        }
                    }
                    return
                }

                if coverLongPressTask != nil || isPressingCover {
                    coverLongPressTask?.cancel()
                    coverLongPressTask = nil
                    isPressingCover = false
                }

                if lockedGestureAxis == nil {
                    if dy > 7 && dy >= abs(dx) * 0.88 {
                        lockedGestureAxis = .vertical
                    } else if abs(dx) > abs(dy) * 1.08 {
                        lockedGestureAxis = .horizontal
                    }
                }

                switch lockedGestureAxis {
                case .horizontal:
                    // Если соседнего трека нет, даём мягкое упругое сопротивление
                    if dx < 0 && appState.upcomingNextTrack == nil {
                        coverHorizontalOffset = dx * 0.28
                    } else if dx > 0 && appState.adjacentPreviousTrack == nil {
                        coverHorizontalOffset = dx * 0.28
                    } else {
                        coverHorizontalOffset = dx * 0.94
                    }
                case .vertical:
                    dragDismissOffset = max(0, dy * 0.88)
                case .none:
                    break
                }
            }
            .onEnded { value in
                coverLongPressTask?.cancel()
                coverLongPressTask = nil
                isPressingCover = false

                let finishedAxis = lockedGestureAxis
                lockedGestureAxis = nil

                guard !isDraggingSlider, !isCompletingDiscSwipe, !isCover3DPreviewPresented else {
                    if !isCompletingDiscSwipe {
                        dragDismissOffset = 0
                        coverHorizontalOffset = 0
                    }
                    return
                }

                let dx = value.translation.width
                let dy = value.translation.height
                let predictedX = value.predictedEndTranslation.width
                let predictedY = value.predictedEndTranslation.height

                switch finishedAxis {
                case .horizontal:
                    if (dx < -46 || predictedX < -105), appState.upcomingNextTrack != nil {
                        completeDiscFlick(toNext: true, discStride: discStride)
                    } else if (dx > 46 || predictedX > 105), appState.adjacentPreviousTrack != nil {
                        completeDiscFlick(toNext: false, discStride: discStride)
                    } else {
                        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.84)) {
                            coverHorizontalOffset = 0
                        }
                    }

                case .vertical:
                    if dy > 42 || predictedY > 95 {
                        dragDismissOffset = 0
                        appState.haptics.softSelection()
                        appState.isFullScreenPlayerPresented = false
                        dismiss()
                    } else {
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.84)) {
                            dragDismissOffset = 0
                        }
                    }

                case .none:
                    if dy > 42 || predictedY > 95 {
                        dragDismissOffset = 0
                        appState.haptics.softSelection()
                        appState.isFullScreenPlayerPresented = false
                        dismiss()
                    } else {
                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
                            dragDismissOffset = 0
                            coverHorizontalOffset = 0
                        }
                    }
                }
            }
    }

    private func completeDiscFlick(toNext: Bool, discStride: CGFloat) {
        isCompletingDiscSwipe = true
        let targetOffset = toNext ? -discStride : discStride
        let promotedTrack = toNext ? appState.upcomingNextTrack : appState.adjacentPreviousTrack
        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.23)) {
            coverHorizontalOffset = targetOffset
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 232_000_000)
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                // Синхронно перекладываем уже отрисованную на экране обложку соседнего трека в центральный слот
                // ДО обнуления `coverHorizontalOffset = 0`, чтобы в кадре x=0 осталась та же самая текстура CGImage без мигания!
                crossfadeCleanupTask?.cancel()
                crossfadeOutgoingImage = nil
                crossfadeIncomingAlpha = 1.0
                if toNext {
                    prevCoverTrackId = activeCoverTrackId
                    prevCoverImage = activeCoverImage
                    activeCoverTrackId = promotedTrack?.id
                    activeCoverImage = nextCoverImage ?? syncLookupOriginalCover(for: promotedTrack)
                    appState.skipToNext(isManualUserAction: true)
                } else {
                    nextCoverTrackId = activeCoverTrackId
                    nextCoverImage = activeCoverImage
                    activeCoverTrackId = promotedTrack?.id
                    activeCoverImage = prevCoverImage ?? syncLookupOriginalCover(for: promotedTrack)
                    appState.skipToPreviousTrackForced()
                }
                coverHorizontalOffset = 0
                isCompletingDiscSwipe = false
            }
            preloadAdjacentSlotsAsync()
        }
    }

    // MARK: - Subviews

    private var topHeaderBar: some View {
        HStack {
            Button {
                appState.isFullScreenPlayerPresented = false
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.90))
                    .frame(width: 42, height: 42)
                    .liquidGlassCircle(tint: .white)
            }
            .buttonStyle(.plain)

            Spacer()

            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 38, height: 5)

            Spacer()

            Menu {
                if let current = track {
                    Button {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                            isCover3DPreviewPresented = true
                        }
                    } label: {
                        Label("Обложка и сведения (3D Touch)", systemImage: "viewfinder")
                    }

                    Button {
                        appState.isAudioFXSheetPresented = true
                    } label: {
                        Label("Звуковые эффекты и скорость", systemImage: "slider.horizontal.3")
                    }

                    Button {
                        appState.toggleLyricsDisabled(for: current)
                    } label: {
                        Label(
                            appState.isLyricsDisabled(for: current) ? "Включить текст для трека" : "Отключить текст для трека",
                            systemImage: appState.isLyricsDisabled(for: current) ? "text.quote" : "eye.slash"
                        )
                    }

                    Divider()

                    Button {
                        appState.haptics.softSelection()
                        appState.isGyroscope3DCoverEnabled.toggle()
                    } label: {
                        Label(
                            appState.isGyroscope3DCoverEnabled ? "Выключить 3D-гироскоп обложки" : "Включить 3D-гироскоп обложки",
                            systemImage: appState.isGyroscope3DCoverEnabled ? "gyroscope" : "cube.transparent"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.90))
                    .frame(width: 42, height: 42)
                    .liquidGlassCircle(tint: .white)
            }
        }
    }

    private func trackMetadataAndQuickActionsRow(accentColor: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(track?.title ?? "Трек не выбран")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // 2 круглые стеклянные кнопки: Избранное и Очередь (кнопка Инфо убрана — сведения открываются по 3D Touch на обложке!)
            HStack(spacing: 10) {
                let isLiked = track.map { appState.isFavorite($0) } ?? false
                Button {
                    if let current = track {
                        appState.toggleFavorite(track: current)
                    }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isLiked ? Color(red: 1.0, green: 0.34, blue: 0.52) : .white.opacity(0.88))
                        .frame(width: 42, height: 42)
                        .liquidGlassCircle(tint: isLiked ? Color(red: 1.0, green: 0.34, blue: 0.52) : .white)
                }
                .buttonStyle(.plain)

                Button {
                    appState.isQueueSheetPresented = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(width: 42, height: 42)
                        .liquidGlassCircle(tint: accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func centerModePillRow(accentColor: Color) -> some View {
        let hasAvailableLyrics = !appState.currentLyricsDocument.lines.isEmpty && !(track.map { appState.isLyricsDisabled(for: $0) } ?? false)
        return HStack(spacing: 10) {
            if hasAvailableLyrics {
                Button {
                    appState.haptics.lightTap()
                    appState.isLyricsScreenPresented = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "music.note")
                            .font(.system(size: 14, weight: .bold))
                        Text("Текст")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .liquidGlassCapsule(tint: accentColor, isProminent: false)
                }
                .buttonStyle(.plain)
            }

            Button {
                appState.haptics.lightTap()
                appState.isAudioFXSheetPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text(fxPillTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(isAnyFXActive ? accentColor : .white.opacity(0.86))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .liquidGlassCapsule(tint: accentColor, isProminent: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func transportControlsRow(accentColor: Color) -> some View {
        HStack(alignment: .center, spacing: 26) {
            Button {
                appState.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(appState.isShuffleEnabled ? accentColor : .white.opacity(0.55))
            }

            Button {
                appState.skipToPrevious()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            Button {
                appState.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 72, height: 72)
                        .shadow(color: accentColor.opacity(0.50), radius: 18, x: 0, y: 8)

                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                        .offset(x: appState.isPlaying ? 0 : 2)
                }
            }

            Button {
                appState.skipToNext(isManualUserAction: true)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }

            Button {
                appState.cycleRepeatMode()
            } label: {
                Image(systemName: appState.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(appState.repeatMode != .none ? accentColor : .white.opacity(0.55))
            }
        }
    }

    private func progressAndTechnicalFooter(accentColor: Color) -> some View {
        let effectiveDuration = appState.duration > 0 ? appState.duration : (track?.duration ?? 0.0)
        let maxDur = max(1.0, effectiveDuration)

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: (!appState.isPlaying && !isDraggingSlider) || appState.isLyricsScreenPresented)) { context in
            let _ = context.date
            let liveTime = appState.isPlaying ? appState.audioEngine.livePlaybackTime : appState.currentTime
            let rawPos = isDraggingSlider ? draggedTime : liveTime
            let clampedPos = min(maxDur, max(0.0, rawPos))

            VStack(spacing: 8) {
                InteractiveSeekBarView(
                    trackId: track?.id,
                    currentTime: clampedPos,
                    duration: maxDur,
                    accentColor: accentColor,
                    isDragging: $isDraggingSlider,
                    draggedTime: $draggedTime,
                    onCommitSeek: { targetSec in
                        appState.haptics.softSelection()
                        appState.seek(to: targetSec)
                    }
                )

                HStack(alignment: .center) {
                    Text(Self.formatSeconds(clampedPos))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.64))

                    Spacer()

                    // Центральная техническая плашка: нажатие также открывает 3D-превью сведений о файле
                    Button {
                        appState.haptics.lightTap()
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                            isCover3DPreviewPresented = true
                        }
                    } label: {
                        let badge = appState.currentQualityBadge
                        HStack(spacing: 5) {
                            if badge.tier == .hiRes {
                                Circle()
                                    .fill(Color(red: 1.0, green: 0.78, blue: 0.35))
                                    .frame(width: 6, height: 6)
                            } else if badge.tier == .lossless {
                                Circle()
                                    .fill(Color(red: 0.82, green: 0.55, blue: 1.0))
                                    .frame(width: 6, height: 6)
                            }
                            Text(badge.tooltipText)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .liquidGlassCapsule(tint: accentColor, isProminent: false, isInteractive: false)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(Self.formatSeconds(effectiveDuration))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
        }
    }

    private var subtitleText: String {
        guard let track else { return "Bebranoid iOS" }
        if !track.album.isEmpty && track.album != "Без альбома" {
            return "\(track.artist) — \(track.album)"
        }
        return track.artist
    }

    private var isAnyFXActive: Bool {
        appState.audioFXMode != .normal || appState.bassBoostEnabled || abs(appState.playbackSpeed - 1.0) > 0.01
    }

    private var fxPillTitle: String {
        var items: [String] = []
        if appState.audioFXMode != .normal {
            items.append(appState.audioFXMode.shortBadgeName)
        }
        if appState.bassBoostEnabled {
            items.append("Bass+")
        }
        if abs(appState.playbackSpeed - 1.0) > 0.01 {
            items.append(String(format: "%.2gx", appState.playbackSpeed))
        }
        return items.isEmpty ? "Звук / FX" : items.joined(separator: " • ")
    }

    public static func formatSeconds(_ totalSeconds: Double) -> String {
        guard totalSeconds.isFinite && totalSeconds > 0 else { return "0:00" }
        let whole = Int(floor(totalSeconds))
        let mins = whole / 60
        let secs = whole % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// 3D Touch / Haptic Touch полноэкранный Liquid Glass просмотр увеличенной обложки и сведений о треке
private struct Cover3DTouchPreviewOverlay: View {
    let track: Track
    let localCoverPath: String?
    let formatInfo: AudioFormatInfo?
    let accentRGB: MeshRGB
    let accentColor: Color
    let viewportSize: CGSize
    let onDismiss: () -> Void

    @State private var dragDownOffset: CGFloat = 0

    var body: some View {
        let resolvedFormat = formatInfo ?? AudioFormatInfo.fallbackFromFilename(track.filename, fileSize: track.fileSize, duration: track.duration)
        let badge = resolvedFormat.computeQualityBadge()
        let enlargedSide = min(viewportSize.width - 36, viewportSize.height * 0.48)

        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.10))
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Spacer(minLength: 20)

                    CoverLivingRimShellView(
                        accentRGB: accentRGB,
                        cornerRadius: 32,
                        isPaused: false
                    ) {
                        ArtworkThumbnailView(
                            track: track,
                            localPath: localCoverPath,
                            remoteURL: track.remoteArtworkURL,
                            fallbackSeed: "\(track.album)|\(track.artist)",
                            cornerRadius: 29.5,
                            sizeTier: .originalSource,
                            enableSmoothTransition: true,
                            showBorder: false
                        )
                    }
                    .frame(width: enlargedSide, height: enlargedSide)
                    .shadow(color: Color.black.opacity(0.55), radius: 32, x: 0, y: 18)

                    VStack(alignment: .leading, spacing: 11) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("\(track.artist) • \(track.album)")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.74))
                            }
                            Spacer()
                            Text(badge.label)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 0.08, green: 0.06, blue: 0.14))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .liquidGlassCapsule(tint: accentColor, isProminent: true, isInteractive: false)
                        }

                        Divider().overlay(Color.white.opacity(0.14))

                        detailRow("Кодек", resolvedFormat.codec)
                        if let sr = resolvedFormat.sampleRateHz {
                            detailRow("Частота", "\(sr) Hz")
                        }
                        if let bps = resolvedFormat.bitsPerSample {
                            detailRow("Разрядность", "\(bps)-bit")
                        }
                        if let br = resolvedFormat.bitrateKbps {
                            detailRow("Битрейт", "\(br) kbps")
                        }
                        if let size = track.fileSize, size > 0 {
                            detailRow("Размер файла", String(format: "%.2f МБ", Double(size) / (1024.0 * 1024.0)))
                        }
                        if let year = track.year {
                            detailRow("Год", "\(year)")
                        }
                        detailRow("Длительность", FullScreenPlayerView.formatSeconds(track.duration))
                        detailRow("Источник", track.sourceKind.rawValue.uppercased())
                        detailRow("Файл", track.filename)
                    }
                    .padding(18)
                    .frame(width: enlargedSide)
                    .liquidGlassCard(cornerRadius: 24, tint: accentColor, tintOpacity: 0.10)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Закрыть")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .liquidGlassCapsule(tint: accentColor, isProminent: false)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 28)
                }
                .frame(maxWidth: .infinity)
                .offset(y: dragDownOffset)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragDownOffset = value.translation.height * 0.78
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 55 || value.predictedEndTranslation.height > 120 {
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                dragDownOffset = 0
                            }
                        }
                    }
            )
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

/// Плавная 120 Гц полоса перемотки без рывков при отпускании пальца и при переключении трека.
public struct InteractiveSeekBarView: View {
    public var trackId: String?
    public let currentTime: Double
    public let duration: Double
    public let accentColor: Color
    @Binding public var isDragging: Bool
    @Binding public var draggedTime: Double
    public let onCommitSeek: (Double) -> Void

    @State private var committedSeekTarget: Double? = nil
    @State private var clearCommittedSeekTask: Task<Void, Never>? = nil

    public init(
        trackId: String? = nil,
        currentTime: Double,
        duration: Double,
        accentColor: Color,
        isDragging: Binding<Bool>,
        draggedTime: Binding<Double>,
        onCommitSeek: @escaping (Double) -> Void
    ) {
        self.trackId = trackId
        self.currentTime = currentTime
        self.duration = duration
        self.accentColor = accentColor
        self._isDragging = isDragging
        self._draggedTime = draggedTime
        self.onCommitSeek = onCommitSeek
    }

    public var body: some View {
        GeometryReader { geo in
            let width = max(1.0, geo.size.width)
            let safeDur = max(1.0, duration)
            let activeTime: Double = {
                if isDragging {
                    return draggedTime
                }
                if let locked = committedSeekTarget {
                    return locked
                }
                return currentTime
            }()
            let progress = min(1.0, max(0.0, activeTime / safeDur))
            let barHeight: CGFloat = isDragging ? 9.0 : 6.0
            let thumbSize: CGFloat = isDragging ? 18.0 : 13.0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: width, height: barHeight)

                Capsule()
                    .fill(accentColor)
                    .frame(width: max(barHeight, width * progress), height: barHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: accentColor.opacity(0.65), radius: isDragging ? 8 : 4, x: 0, y: 2)
                    .offset(x: min(width - thumbSize, max(0, width * progress - thumbSize * 0.5)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        clearCommittedSeekTask?.cancel()
                        committedSeekTarget = nil
                        let ratio = min(1.0, max(0.0, Double(value.location.x / width)))
                        let target = ratio * safeDur
                        if !isDragging {
                            isDragging = true
                        }
                        draggedTime = target
                    }
                    .onEnded { value in
                        let ratio = min(1.0, max(0.0, Double(value.location.x / width)))
                        let target = ratio * safeDur
                        // Фиксируем целевую позицию ДО снятия `isDragging`, чтобы исключить обратный скачок кадра!
                        committedSeekTarget = target
                        draggedTime = target
                        onCommitSeek(target)
                        isDragging = false

                        clearCommittedSeekTask?.cancel()
                        clearCommittedSeekTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 380_000_000)
                            guard !Task.isCancelled else { return }
                            committedSeekTarget = nil
                        }
                    }
            )
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.82), value: isDragging)
            .onChange(of: trackId) { _, _ in
                clearCommittedSeekTask?.cancel()
                committedSeekTarget = nil
                isDragging = false
                draggedTime = 0.0
            }
        }
        .frame(height: 32)
    }
}

/// Монолитная 3D-плита обложки (`Sculpted3DCoverSlabView`), объединяющая:
/// - Исходное разрешение обложки (`.originalSource`, 1 общий `CGImage` буфер без дублирования декодера)
/// - Плавный бесшовный кроссфейд при переключении кнопками и мгновенную подстановку при свайпе пальцем
/// - Синхронную бегущую световую обводку (`AngularGradient`), проходящую как по передней грани, так и по всему продлённому 3D-торцу!
private struct Sculpted3DCoverSlabView: View {
    let primaryImage: CGImage?
    let outgoingImage: CGImage?
    let incomingAlpha: Double
    let accentRGB: MeshRGB
    let cornerRadius: CGFloat
    let coverSide: CGFloat
    let tiltX: Double
    let tiltY: Double
    let specularOffset: CGSize
    let isRimPaused: Bool

    var body: some View {
        let isMonochrome = HarmonoidMeshEngine.chroma(accentRGB.r, accentRGB.g, accentRGB.b) < 0.09
        let norm = accentRGB.normalizedDouble
        let pureAccent = isMonochrome
            ? Color(red: 0.90, green: 0.91, blue: 0.94)
            : Color(red: norm.r, green: norm.g, blue: norm.b)
        let stops = CoverLivingRimGradientBuilder.buildStops(accentRGB: accentRGB, isMonochrome: isMonochrome)
        let tiltMagnitude = min(1.0, hypot(tiltX, tiltY) / 20.0)
        let innerRadius = max(4.0, cornerRadius - 2.4)

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isRimPaused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angleDeg = (t.truncatingRemainder(dividingBy: 8.0) / 8.0) * 360.0
            let rimGradient = AngularGradient(
                gradient: Gradient(stops: stops),
                center: .center,
                startAngle: .degrees(angleDeg),
                endAngle: .degrees(angleDeg + 360.0)
            )

            ZStack {
                // Продлённый 3D-объём при наклоне гироскопа: каждый слой несёт и пиксели края обложки, И синхронно бегущую световую обводку!
                if tiltMagnitude > 0.012 {
                    ForEach((1...5).reversed(), id: \.self) { sliceIdx in
                        let frac = Double(sliceIdx) / 5.0
                        ZStack {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(rimGradient)
                                .overlay(
                                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                        .fill(Color.black.opacity(0.10 + 0.34 * frac))
                                )

                            coverFaceLayer(innerRadius: innerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                                        .fill(Color.black.opacity(0.14 + 0.32 * frac))
                                )
                                .padding(2.4)
                        }
                        .offset(
                            x: CGFloat(-tiltY * 0.46 * frac),
                            y: CGFloat(tiltX * 0.46 * frac)
                        )
                        .allowsHitTesting(false)
                    }
                }

                // Лицевая грань с живой обводкой и мягким зеркальным бликом гироскопа
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(rimGradient)

                    coverFaceLayer(innerRadius: innerRadius)
                        .padding(2.4)
                }
                .overlay {
                    if tiltMagnitude > 0.012 {
                        let lightCenter = UnitPoint(
                            x: max(0.05, min(0.95, 0.5 - specularOffset.width * 0.42)),
                            y: max(0.05, min(0.95, 0.38 - specularOffset.height * 0.42))
                        )
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.15 * tiltMagnitude),
                                        Color.white.opacity(0.025 * tiltMagnitude),
                                        Color.clear
                                    ],
                                    center: lightCenter,
                                    startRadius: 8,
                                    endRadius: coverSide * 0.78
                                )
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .shadow(color: pureAccent.opacity(isMonochrome ? 0.20 : 0.34), radius: 13, x: 0, y: 0)
        .shadow(color: pureAccent.opacity(isMonochrome ? 0.24 : 0.38), radius: 3.5, x: 0, y: 0)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.55), value: accentRGB)
    }

    @ViewBuilder
    private func coverFaceLayer(innerRadius: CGFloat) -> some View {
        ZStack {
            if let out = outgoingImage {
                Image(decorative: out, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: coverSide - 4.8, height: coverSide - 4.8)
            }

            if let cur = primaryImage {
                Image(decorative: cur, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: coverSide - 4.8, height: coverSide - 4.8)
                    .opacity(outgoingImage != nil ? incomingAlpha : 1.0)
            } else {
                uniformBlackPlaceholder
                    .frame(width: coverSide - 4.8, height: coverSide - 4.8)
                    .opacity(outgoingImage != nil ? incomingAlpha : 1.0)
            }
        }
        .frame(width: coverSide - 4.8, height: coverSide - 4.8)
        .background(Color(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 5.0 / 255.0))
        .clipShape(RoundedRectangle(cornerRadius: innerRadius, style: .continuous))
    }

    private var uniformBlackPlaceholder: some View {
        ZStack {
            Color(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 5.0 / 255.0)
            Image(systemName: "music.note")
                .font(.system(size: max(28, coverSide * 0.22), weight: .regular))
                .foregroundStyle(Color(red: 218.0 / 255.0, green: 218.0 / 255.0, blue: 228.0 / 255.0).opacity(0.60))
        }
    }
}

private enum CoverLivingRimGradientBuilder {
    static func mixColor(accentRGB: MeshRGB, accentWeight: Double, baseR: Double, baseG: Double, baseB: Double) -> Color {
        let norm = accentRGB.normalizedDouble
        let w = min(1.0, max(0.0, accentWeight))
        let r = norm.r * w + baseR * (1.0 - w)
        let g = norm.g * w + baseG * (1.0 - w)
        let b = norm.b * w + baseB * (1.0 - w)
        return Color(red: r, green: g, blue: b)
    }

    static func buildStops(accentRGB: MeshRGB, isMonochrome: Bool) -> [Gradient.Stop] {
        if isMonochrome {
            let graphite = Color(red: 0.14, green: 0.15, blue: 0.17)
            let silver = Color(red: 0.72, green: 0.74, blue: 0.78)
            let platinum = Color(red: 0.96, green: 0.97, blue: 0.99)
            return [
                .init(color: graphite, location: 0.0 / 360.0),
                .init(color: silver, location: 55.0 / 360.0),
                .init(color: platinum, location: 100.0 / 360.0),
                .init(color: silver, location: 160.0 / 360.0),
                .init(color: graphite, location: 220.0 / 360.0),
                .init(color: platinum, location: 280.0 / 360.0),
                .init(color: graphite, location: 1.0)
            ]
        } else {
            let norm = accentRGB.normalizedDouble
            let pureAccent = Color(red: norm.r, green: norm.g, blue: norm.b)
            let dark50 = mixColor(accentRGB: accentRGB, accentWeight: 0.50, baseR: 0.067, baseG: 0.067, baseB: 0.067)
            let dark48 = mixColor(accentRGB: accentRGB, accentWeight: 0.48, baseR: 0.067, baseG: 0.067, baseB: 0.067)
            let bright82 = mixColor(accentRGB: accentRGB, accentWeight: 0.82, baseR: 1.0, baseG: 1.0, baseB: 1.0)
            let bright78 = mixColor(accentRGB: accentRGB, accentWeight: 0.78, baseR: 1.0, baseG: 1.0, baseB: 1.0)
            return [
                .init(color: dark50, location: 0.0 / 360.0),
                .init(color: pureAccent, location: 55.0 / 360.0),
                .init(color: bright82, location: 100.0 / 360.0),
                .init(color: pureAccent, location: 160.0 / 360.0),
                .init(color: dark48, location: 220.0 / 360.0),
                .init(color: bright78, location: 280.0 / 360.0),
                .init(color: dark50, location: 1.0)
            ]
        }
    }
}

/// Живой бегущий световой ободок вокруг обложки (используется в 3D Touch увеличении)
private struct CoverLivingRimShellView<FaceContent: View>: View {
    let accentRGB: MeshRGB
    let cornerRadius: CGFloat
    let isPaused: Bool
    @ViewBuilder let faceContent: () -> FaceContent

    var body: some View {
        let isMonochrome = HarmonoidMeshEngine.chroma(accentRGB.r, accentRGB.g, accentRGB.b) < 0.09
        let norm = accentRGB.normalizedDouble
        let pureAccent = isMonochrome
            ? Color(red: 0.90, green: 0.91, blue: 0.94)
            : Color(red: norm.r, green: norm.g, blue: norm.b)
        let stops = CoverLivingRimGradientBuilder.buildStops(accentRGB: accentRGB, isMonochrome: isMonochrome)

        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let angleDeg = (t.truncatingRemainder(dividingBy: 8.0) / 8.0) * 360.0

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: stops),
                            center: .center,
                            startAngle: .degrees(angleDeg),
                            endAngle: .degrees(angleDeg + 360.0)
                        )
                    )
            }

            faceContent()
                .background(Color(red: 5.0 / 255.0, green: 5.0 / 255.0, blue: 5.0 / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: max(4, cornerRadius - 2.4), style: .continuous))
                .padding(2.4)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: pureAccent.opacity(isMonochrome ? 0.22 : 0.36), radius: 14, x: 0, y: 0)
        .shadow(color: pureAccent.opacity(isMonochrome ? 0.28 : 0.42), radius: 4, x: 0, y: 0)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.65), value: accentRGB)
    }
}
