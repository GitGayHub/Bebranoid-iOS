import Foundation

/// Точный 1:1 математический порт `src/beautiful-lyrics/spline.js` (`GetSpline`).
/// Строит натуральный кубический сплайн по набору контрольных точек `(t, value)`.
public struct CubicSpline: Sendable {
    public struct Point: Sendable, Equatable {
        public var time: Double
        public var value: Double

        public init(time: Double, value: Double) {
            self.time = time
            self.value = value
        }
    }

    private let xs: [Double]
    private let ys: [Double]
    private let ks: [Double]

    public init(points: [Point]) {
        let sorted = points.sorted { $0.time < $1.time }
        let n = sorted.count
        self.xs = sorted.map { $0.time }
        self.ys = sorted.map { $0.value }

        if n < 2 {
            self.ks = Array(repeating: 0.0, count: max(1, n))
            return
        }

        // Решаем трёхдиагональную систему натурального кубического сплайна (метод прогонки Томаса)
        var a = Array(repeating: 0.0, count: n)
        var b = Array(repeating: 0.0, count: n)
        var c = Array(repeating: 0.0, count: n)
        var r = Array(repeating: 0.0, count: n)

        let dx0 = max(1e-9, xs[1] - xs[0])
        b[0] = 2.0 / dx0
        c[0] = 1.0 / dx0
        r[0] = 3.0 * (ys[1] - ys[0]) / (dx0 * dx0)

        for i in 1..<(n - 1) {
            let dxPrev = max(1e-9, xs[i] - xs[i - 1])
            let dxNext = max(1e-9, xs[i + 1] - xs[i])
            a[i] = 1.0 / dxPrev
            b[i] = 2.0 * (1.0 / dxPrev + 1.0 / dxNext)
            c[i] = 1.0 / dxNext
            r[i] = 3.0 * (
                (ys[i] - ys[i - 1]) / (dxPrev * dxPrev) +
                (ys[i + 1] - ys[i]) / (dxNext * dxNext)
            )
        }

        let dxLast = max(1e-9, xs[n - 1] - xs[n - 2])
        a[n - 1] = 1.0 / dxLast
        b[n - 1] = 2.0 / dxLast
        c[n - 1] = 0.0
        r[n - 1] = 3.0 * (ys[n - 1] - ys[n - 2]) / (dxLast * dxLast)

        // Forward sweep
        for i in 1..<n {
            let w = a[i] / b[i - 1]
            b[i] -= w * c[i - 1]
            r[i] -= w * r[i - 1]
        }

        // Back substitution
        var k = Array(repeating: 0.0, count: n)
        k[n - 1] = r[n - 1] / b[n - 1]
        for i in stride(from: n - 2, through: 0, by: -1) {
            k[i] = (r[i] - c[i] * k[i + 1]) / b[i]
        }
        self.ks = k
    }

    public func evaluate(at x: Double) -> Double {
        guard !xs.isEmpty else { return 0.0 }
        if xs.count == 1 || x <= xs[0] {
            return ys[0]
        }
        if x >= xs[xs.count - 1] {
            return ys[ys.count - 1]
        }

        var i = 1
        while i < xs.count - 1 && xs[i] < x {
            i += 1
        }
        let idx = i - 1
        let dx = xs[i] - xs[idx]
        guard dx > 1e-9 else { return ys[idx] }

        let t = (x - xs[idx]) / dx
        let a = ks[idx] * dx - (ys[i] - ys[idx])
        let b = -ks[i] * dx + (ys[i] - ys[idx])

        return (1.0 - t) * ys[idx] + t * ys[i] + t * (1.0 - t) * (a * (1.0 - t) + b * t)
    }
}
