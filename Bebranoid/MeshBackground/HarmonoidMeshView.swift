import SwiftUI

/// Общие часы движения Mesh-фона (`meshMotionMs` в `HarmonoidMeshBackground.jsx`),
/// чтобы открытие/закрытие полноэкранного плеера и экрана текстов никогда не сбрасывало фазу волн.
public final class SharedMeshMotionClock: @unchecked Sendable {
    public static let shared = SharedMeshMotionClock()
    private let lock = NSLock()
    private var accumulatedMs: Double = 0.0
    private var lastSampleDate: Date?

    private init() {}

    public func sampleSeconds(at date: Date, paused: Bool, fixedOverrideSeconds: Double? = nil) -> Double {
        if let fixed = fixedOverrideSeconds {
            return fixed
        }
        lock.lock()
        defer { lock.unlock() }
        if paused {
            return accumulatedMs / 1000.0
        }
        if let last = lastSampleDate {
            let deltaMs = date.timeIntervalSince(last) * 1000.0
            if deltaMs >= 0.0 && deltaMs < 80.0 {
                accumulatedMs += deltaMs
            }
        }
        lastSampleDate = date
        return accumulatedMs / 1000.0
    }
}

/// SwiftUI-представление фирменного фона `HarmonoidMeshBackground` (`src/components/HarmonoidMeshBackground.jsx` 1:1).
/// Реализует:
/// - Базовую подложку `fillBase` (`r = max(4, floor(c0.r * 0.35))`, `g = max(4, floor(c0.g * 0.35))`, `b = max(6, floor(c0.b * 0.40))`)
/// - 4 контрольные точки с синусоидальным движением (`speed = 0.45`) и дышащим радиусом `max(w, h) * (0.55 + 0.08 * sin(t * 0.35 + i))`
/// - Пятно `0` в режиме `.normal` (`source-over`), пятна `1..3` в режиме `.plusLighter` (`lighter`)
/// - Радиальные стопы `0.0 -> 0.95`, `0.45 -> 0.45`, `1.0 -> 0.0`
/// - Внутреннее затемнение `12%`, вертикальную виньетку (`0.22` сверху до `20%`, прозрачный центр `20%..55%`, `0.28` снизу к `100%`) и верхний слой `18%`
/// - Плавный `smoothstep` морфинг палитры длительностью `max(1400ms, transitionMs)` (по умолчанию `1650ms`) или синхронно с `crossfadeProgress`
public struct HarmonoidMeshView: View {
    public var currentPalette: [MeshRGB]
    public var nextPalette: [MeshRGB]?
    public var crossfadeProgress: Double
    public var transitionMs: Double
    public var isReducedMotion: Bool
    public var fixedAnimationTime: Double?

    @State private var transitionFromPalette: [MeshRGB] = HarmonoidMeshEngine.defaultPalette
    @State private var transitionTargetPalette: [MeshRGB] = HarmonoidMeshEngine.defaultPalette
    @State private var transitionStartTime: Date = .distantPast
    @State private var hasInitialized: Bool = false

    public init(
        currentPalette: [MeshRGB] = HarmonoidMeshEngine.defaultPalette,
        nextPalette: [MeshRGB]? = nil,
        crossfadeProgress: Double = 0.0,
        transitionMs: Double = HarmonoidMeshEngine.defaultTransitionMs,
        isReducedMotion: Bool = false,
        fixedAnimationTime: Double? = nil
    ) {
        self.currentPalette = currentPalette.count >= 4 ? currentPalette : HarmonoidMeshEngine.defaultPalette
        self.nextPalette = nextPalette
        self.crossfadeProgress = crossfadeProgress
        self.transitionMs = max(HarmonoidMeshEngine.minTransitionMs, transitionMs)
        self.isReducedMotion = isReducedMotion
        self.fixedAnimationTime = fixedAnimationTime
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: isReducedMotion ? (1.0 / 15.0) : (1.0 / 30.0), paused: fixedAnimationTime != nil)) { timeline in
            Canvas { context, size in
                let elapsedSec = SharedMeshMotionClock.shared.sampleSeconds(
                    at: timeline.date,
                    paused: false,
                    fixedOverrideSeconds: fixedAnimationTime
                )
                let activeColors = resolveActivePalettePure(at: timeline.date)

                drawMesh(
                    in: &context,
                    size: size,
                    palette: activeColors,
                    timeSec: elapsedSec
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if !hasInitialized {
                transitionFromPalette = currentPalette
                transitionTargetPalette = currentPalette
                hasInitialized = true
            }
        }
        .onChange(of: currentPalette) { _, newVal in
            let now = Date()
            let currentDisplayed = resolveActivePalettePure(at: now)
            if HarmonoidMeshEngine.colorsNearlyEqual(currentDisplayed, newVal) {
                transitionFromPalette = newVal
                transitionTargetPalette = newVal
                transitionStartTime = .distantPast
                return
            }
            transitionFromPalette = currentDisplayed
            transitionTargetPalette = newVal
            transitionStartTime = now
        }
    }

    private func resolveActivePalettePure(at now: Date) -> [MeshRGB] {
        if crossfadeProgress > 0.001, let next = nextPalette, next.count >= 4 {
            return HarmonoidMeshEngine.lerpPalette(currentPalette, next, progress: crossfadeProgress)
        }

        guard transitionStartTime != .distantPast else {
            return currentPalette
        }

        let blendMs = max(HarmonoidMeshEngine.minTransitionMs, transitionMs)
        let elapsedMs = now.timeIntervalSince(transitionStartTime) * 1000.0
        if elapsedMs >= blendMs {
            return transitionTargetPalette
        }
        let progress = HarmonoidMeshEngine.clamp(elapsedMs / blendMs, 0.0, 1.0)
        return HarmonoidMeshEngine.lerpPalette(
            transitionFromPalette,
            transitionTargetPalette,
            progress: progress
        )
    }

    private func drawMesh(
        in context: inout GraphicsContext,
        size: CGSize,
        palette: [MeshRGB],
        timeSec: Double
    ) {
        let w = Double(size.width)
        let h = Double(size.height)
        guard w > 1, h > 1 else { return }

        let colors = palette.count >= 4 ? palette : HarmonoidMeshEngine.defaultPalette
        let fullRect = CGRect(origin: .zero, size: size)

        // 1. fillBase: r = max(4, floor(c0.r * 0.35)), g = max(4, floor(c0.g * 0.35)), b = max(6, floor(c0.b * 0.40))
        let baseRGB = HarmonoidMeshEngine.computeBaseFillColor(from: colors).normalizedDouble
        context.fill(
            Path(fullRect),
            with: .color(Color(red: baseRGB.r, green: baseRGB.g, blue: baseRGB.b))
        )

        // 2. 4 blobs: blob 0 is source-over (.normal), blobs 1..3 are lighter (.plusLighter)
        let blobs = HarmonoidMeshEngine.blobCenters(
            at: timeSec,
            width: w,
            height: h,
            meshColors: colors
        )

        for blob in blobs {
            var layerContext = context
            layerContext.blendMode = blob.isSourceOver ? .normal : .plusLighter

            let norm = blob.color.normalizedDouble
            let center = CGPoint(x: blob.x, y: blob.y)
            let gradient = Gradient(stops: [
                .init(color: Color(red: norm.r, green: norm.g, blue: norm.b).opacity(0.95), location: 0.0),
                .init(color: Color(red: norm.r, green: norm.g, blue: norm.b).opacity(0.45), location: 0.45),
                .init(color: Color(red: norm.r, green: norm.g, blue: norm.b).opacity(0.0), location: 1.0)
            ])

            let circleRect = CGRect(
                x: center.x - blob.radius,
                y: center.y - blob.radius,
                width: blob.radius * 2.0,
                height: blob.radius * 2.0
            )
            layerContext.fill(
                Path(ellipseIn: circleRect),
                with: .radialGradient(
                    gradient,
                    center: center,
                    startRadius: 0,
                    endRadius: CGFloat(blob.radius)
                )
            )
        }

        // 3. Canvas 12% darkening: rgba(0, 0, 0, 0.12)
        context.fill(
            Path(fullRect),
            with: .color(Color.black.opacity(HarmonoidMeshEngine.canvasDarkeningAlpha))
        )

        // 4. Desktop Now Playing vignette:
        // linear-gradient(180deg, rgba(0,0,0,0.22) 0%, transparent 20%, transparent 55%, rgba(0,0,0,0.28) 100%)
        let vignetteGradient = Gradient(stops: [
            .init(color: Color.black.opacity(HarmonoidMeshEngine.topVignetteAlpha), location: 0.0),
            .init(color: Color.black.opacity(0.0), location: 0.20),
            .init(color: Color.black.opacity(0.0), location: 0.55),
            .init(color: Color.black.opacity(HarmonoidMeshEngine.bottomVignetteAlpha), location: 1.0)
        ])
        context.fill(
            Path(fullRect),
            with: .linearGradient(
                vignetteGradient,
                startPoint: CGPoint(x: w * 0.5, y: 0),
                endPoint: CGPoint(x: w * 0.5, y: h)
            )
        )

        // 5. Top ambient overlay: rgba(0, 0, 0, 0.18)
        context.fill(
            Path(fullRect),
            with: .color(Color.black.opacity(HarmonoidMeshEngine.ambientOverlayAlpha))
        )
    }
}
