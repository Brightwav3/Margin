/// Barnes–Hut quadtree over unit-mass bodies, stored in flat arrays (an arena) so it can be
/// rebuilt every layout step without reallocating. Cells are allocated in groups of four.
struct QuadTree: Sendable {
    /// Cell geometry: centre and half-width (cells are square).
    private(set) var cellX: [Double] = []
    private(set) var cellY: [Double] = []
    private(set) var cellHalf: [Double] = []
    /// Body count and centre of mass (sums until `finalize`, then means).
    private(set) var mass: [Double] = []
    private(set) var comX: [Double] = []
    private(set) var comY: [Double] = []
    /// Index of the first of four children, or -1 for a leaf.
    private(set) var firstChild: [Int32] = []
    /// Body index stored in a leaf, or -1.
    private(set) var body: [Int32] = []
    private(set) var cellCount = 0

    static let maxDepth = 40

    /// Read-only unsafe views of the cell arrays, valid only inside `withBuffers`.
    struct Buffers {
        let mass: UnsafeBufferPointer<Double>
        let comX: UnsafeBufferPointer<Double>
        let comY: UnsafeBufferPointer<Double>
        let cellHalf: UnsafeBufferPointer<Double>
        let firstChild: UnsafeBufferPointer<Int32>
        let body: UnsafeBufferPointer<Int32>
    }

    func withBuffers<R>(_ work: (Buffers) -> R) -> R {
        mass.withUnsafeBufferPointer { m in
        comX.withUnsafeBufferPointer { cx in
        comY.withUnsafeBufferPointer { cy in
        cellHalf.withUnsafeBufferPointer { h in
        firstChild.withUnsafeBufferPointer { f in
        body.withUnsafeBufferPointer { bd in
            work(Buffers(mass: m, comX: cx, comY: cy, cellHalf: h, firstChild: f, body: bd))
        }}}}}}
    }

    private mutating func resetArena(capacity: Int) {
        cellCount = 0
        if cellX.count < capacity {
            cellX = [Double](repeating: 0, count: capacity)
            cellY = cellX; cellHalf = cellX; mass = cellX; comX = cellX; comY = cellX
            firstChild = [Int32](repeating: -1, count: capacity)
            body = firstChild
        }
    }

    private mutating func allocate(_ n: Int, x: Double, y: Double, half: Double) -> Int {
        let c = cellCount
        cellCount += n
        if cellCount > cellX.count { grow(to: max(cellCount, cellX.count * 2)) }
        for i in c..<cellCount { clear(i, x: x, y: y, half: half) }
        return c
    }

    private mutating func clear(_ i: Int, x: Double, y: Double, half: Double) {
        cellX[i] = x; cellY[i] = y; cellHalf[i] = half
        mass[i] = 0; comX[i] = 0; comY[i] = 0
        firstChild[i] = -1; body[i] = -1
    }

    private mutating func grow(to capacity: Int) {
        let extra = capacity - cellX.count
        let zeros = [Double](repeating: 0, count: extra)
        let minus = [Int32](repeating: -1, count: extra)
        cellX += zeros; cellY += zeros; cellHalf += zeros
        mass += zeros; comX += zeros; comY += zeros
        firstChild += minus; body += minus
    }

    /// Rebuilds the tree for the given positions. Reuses the arena from the previous build.
    mutating func build(xs: [Double], ys: [Double]) {
        let n = xs.count
        resetArena(capacity: max(8 * n + 8, cellX.count))
        guard n > 0 else { return }
        var minX = xs[0], maxX = xs[0], minY = ys[0], maxY = ys[0]
        for i in 1..<n {
            minX = Swift.min(minX, xs[i]); maxX = Swift.max(maxX, xs[i])
            minY = Swift.min(minY, ys[i]); maxY = Swift.max(maxY, ys[i])
        }
        let half = Swift.max(maxX - minX, maxY - minY) / 2 + 1e-6
        _ = allocate(1, x: (minX + maxX) / 2, y: (minY + maxY) / 2, half: half)
        for i in 0..<n { insert(i, xs[i], ys[i]) }
        for c in 0..<cellCount where mass[c] > 0 {
            comX[c] /= mass[c]; comY[c] /= mass[c]
        }
    }

    @inline(__always)
    private func quadrant(_ c: Int, _ x: Double, _ y: Double) -> Int {
        (x >= cellX[c] ? 1 : 0) | (y >= cellY[c] ? 2 : 0)
    }

    private mutating func subdivide(_ c: Int) {
        let h = cellHalf[c] / 2
        let first = allocate(4, x: 0, y: 0, half: h)
        for q in 0..<4 {
            cellX[first + q] = cellX[c] + ((q & 1) == 1 ? h : -h)
            cellY[first + q] = cellY[c] + ((q & 2) == 2 ? h : -h)
        }
        firstChild[c] = Int32(first)
    }

    private mutating func insert(_ b: Int, _ x: Double, _ y: Double) {
        var c = 0
        var depth = 0
        while true {
            if firstChild[c] >= 0 {
                mass[c] += 1; comX[c] += x; comY[c] += y
                c = Int(firstChild[c]) + quadrant(c, x, y)
                depth += 1
                continue
            }
            if mass[c] == 0 {
                body[c] = Int32(b); mass[c] = 1; comX[c] = x; comY[c] = y
                return
            }
            if depth >= Self.maxDepth {
                // Practically coincident bodies share a leaf.
                mass[c] += 1; comX[c] += x; comY[c] += y
                return
            }
            // Occupied leaf: split it and push the resident body one level down.
            let resident = Int(body[c])
            let rx = comX[c] / mass[c], ry = comY[c] / mass[c]
            subdivide(c)
            let child = Int(firstChild[c]) + quadrant(c, rx, ry)
            body[child] = Int32(resident); mass[child] = mass[c]
            comX[child] = comX[c]; comY[child] = comY[c]
            body[c] = -1
        }
    }
}
