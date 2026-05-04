import Foundation

enum PolylineDecoder {
    static func decode(_ polyline: String) -> [Coordinate2D] {
        var coordinates: [Coordinate2D] = []
        var index = polyline.startIndex
        var lat = 0
        var lng = 0

        while index < polyline.endIndex {
            var b = 0
            var shift = 0
            var result = 0

            repeat {
                guard index < polyline.endIndex else { break }
                b = Int(polyline[index].unicodeScalars.first!.value) - 63
                result |= (b & 0x1F) << shift
                shift += 5
                index = polyline.index(after: index)
            } while b >= 0x20

            let dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += dlat

            shift = 0
            result = 0

            repeat {
                guard index < polyline.endIndex else { break }
                b = Int(polyline[index].unicodeScalars.first!.value) - 63
                result |= (b & 0x1F) << shift
                shift += 5
                index = polyline.index(after: index)
            } while b >= 0x20

            let dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += dlng

            let coordinate = Coordinate2D(
                latitude: Double(lat) / 1E5,
                longitude: Double(lng) / 1E5
            )
            coordinates.append(coordinate)
        }

        return coordinates
    }
}
