import Foundation

/// Точный 1:1 порт `src/lib/queueOrder.js`
public enum QueueOrder {
    /// Уникальный ключ трека в очереди: `${id}|${filename ?? localPath}`
    public static func trackKey(_ track: Track) -> String {
        let secondary = !track.filename.isEmpty ? track.filename : (track.localPath ?? "")
        return "\(track.id)|\(secondary)"
    }

    /// Перемешивает предстоящую часть очереди (`index + 1 ... end`), сохраняя уже проигранную историю (`0 ... index`),
    /// дедуплицируя треки и гарантируя сдвиг на 1 позицию, если случайная перестановка совпала с предыдущим порядком.
    ///
    /// - Parameters:
    ///   - queue: Текущая очередь треков
    ///   - currentIndex: Индекс текущего воспроизводимого трека
    ///   - sourceTracks: Опциональный исходный список треков контекста
    ///   - randomGenerator: Функция, возвращающая число в `[0, 1)` (по умолчанию `Double.random(in: 0..<1)`)
    public static func reshuffleUpcoming(
        queue: [Track],
        currentIndex: Int,
        sourceTracks: [Track]? = nil,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> [Track] {
        guard !queue.isEmpty else { return [] }
        let safeIndex = max(0, min(currentIndex, queue.count - 1))
        let past = Array(queue[0...safeIndex])
        let previousFuture = safeIndex + 1 < queue.count ? Array(queue[(safeIndex + 1)...]) : []

        var seenKeys = Set<String>()
        for t in past {
            seenKeys.insert(trackKey(t))
        }

        let candidatePool = sourceTracks ?? queue
        var future: [Track] = []
        for candidate in candidatePool {
            let key = trackKey(candidate)
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                future.append(candidate)
            }
        }

        if future.count <= 1 {
            return past + future
        }

        // Fisher-Yates shuffle (1:1 с JS `for (let i = future.length - 1; i > 0; i -= 1)`)
        for i in stride(from: future.count - 1, through: 1, by: -1) {
            let r = min(0.999999999999, max(0.0, random()))
            let j = Int(floor(r * Double(i + 1)))
            if i != j {
                future.swapAt(i, j)
            }
        }

        // Если новый порядок в точности совпал с предыдущим предстоящим порядком, циклически сдвигаем на 1
        if future.count == previousFuture.count {
            let isSameOrder = zip(future, previousFuture).allSatisfy { trackKey($0) == trackKey($1) }
            if isSameOrder {
                let first = future.removeFirst()
                future.append(first)
            }
        }

        return past + future
    }
}
