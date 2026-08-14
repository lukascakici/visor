import Foundation
import Guidance

/// The road as the HUD would draw it, in characters.
///
/// The same frame the display uses: a fixed window, the rider always in the
/// same place, up the screen being the way they are heading. Which makes this
/// the only way to see what the path channel is actually sending without a Mac,
/// a phone and a Bluetooth link all working at once.
enum PathMap {
    /// Matches the display's own window, so what shows here is what would show
    /// there rather than a differently framed picture of the same numbers.
    static let ahead = 450.0
    static let behind = 60.0

    static func render(_ path: RoutePath, width: Int = 52, height: Int = 13) -> [String] {
        var grid = [[Character]](repeating: [Character](repeating: " ", count: width), count: height)

        let depth = ahead + behind
        let metersPerRow = depth / Double(height)
        // A character cell is about twice as tall as it is wide, so a meter
        // across costs half of what a meter along does. Without this the road
        // appears to turn twice as sharply as it does.
        let metersPerColumn = metersPerRow / 2

        let riderRow = Int((ahead / depth) * Double(height - 1))
        let centre = width / 2

        func plot(_ right: Double, _ ahead: Double, _ mark: Character) {
            let column = centre + Int((right / metersPerColumn).rounded())
            let row = riderRow - Int((ahead / metersPerRow).rounded())
            guard row >= 0, row < height, column >= 0, column < width else { return }
            grid[row][column] = mark
        }

        // Walked in short steps rather than plotted point by point: the packet's
        // points can be hundreds of meters apart on a straight road, and a road
        // drawn as two dots is not a road.
        for index in 1..<max(1, path.points.count) {
            let from = path.points[index - 1]
            let to = path.points[index]
            let span = ((to.right - from.right) * (to.right - from.right)
                + (to.ahead - from.ahead) * (to.ahead - from.ahead)).squareRoot()
            let steps = max(1, Int(span / 4))

            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                plot(
                    from.right + (to.right - from.right) * fraction,
                    from.ahead + (to.ahead - from.ahead) * fraction,
                    "•"
                )
            }
        }

        if let index = path.maneuverIndex, path.points.indices.contains(index) {
            plot(path.points[index].right, path.points[index].ahead, "◉")
        }

        grid[riderRow][centre] = "▲"

        return grid.map { "        │" + String($0) + "│" }
    }
}
