import Foundation

enum AMapResponseMapper {
    private static let decoder = JSONDecoder()

    // MARK: - Driving routes

    static func drivingRoutes(
        from data: Data,
        request: RouteRequest,
        fetchedAt: Date = Date()
    ) throws -> ProviderRouteResult {
        let envelope: AMapDrivingEnvelope
        do {
            envelope = try decoder.decode(AMapDrivingEnvelope.self, from: data)
        } catch {
            AppLog.routing.error("AMap envelope decode failed: \(String(describing: error), privacy: .public)")
            throw RouteProviderError.decodingFailed
        }

        try validateStatus(envelope.status, info: envelope.info, infocode: envelope.infocode)
        guard let paths = envelope.route?.paths, !paths.isEmpty else {
            throw RouteProviderError.noRoute
        }

        let alternatives = try paths.enumerated().map { index, path in
            try mapPath(path, index: index, fetchedAt: fetchedAt)
        }
        guard !alternatives.isEmpty else { throw RouteProviderError.noRoute }

        return ProviderRouteResult(
            provider: .amap,
            alternatives: alternatives,
            fetchedAt: fetchedAt,
            // AMap's v5 driving request has no departure-time/prediction
            // parameter. The result is therefore current traffic only.
            forecastAvailability: .currentConditions
        )
    }

    private static func mapPath(
        _ path: AMapDrivingPath,
        index: Int,
        fetchedAt: Date
    ) throws -> RouteAlternative {
        let steps = path.steps ?? []

        let stepDistanceTotal = steps.reduce(0.0) {
            $0 + ($1.stepDistance?.number ?? 0)
        }
        let distance = path.distance?.number
            ?? (stepDistanceTotal > 0 ? stepDistanceTotal : nil)
        guard let distance, distance.isFinite, distance >= 0 else {
            throw RouteProviderError.missingRouteData("AMap 路线距离缺失或无效")
        }

        let stepDurationTotal = steps.reduce(0.0) {
            $0 + ($1.cost?.duration?.number ?? $1.duration?.number ?? 0)
        }
        let duration = path.cost?.duration?.number
            ?? path.duration?.number
            ?? (stepDurationTotal > 0 ? stepDurationTotal : nil)
        guard let duration, duration.isFinite, duration > 0 else {
            throw RouteProviderError.missingRouteData("AMap 路线耗时缺失或无效")
        }

        let castSteps = steps.enumerated().map { stepIndex, step in
            RouteStep(
                id: stepIndex,
                instruction: step.instruction?.trimmed
                    ?? step.roadName?.trimmed
                    ?? "继续行驶",
                roadName: step.roadName?.trimmed,
                distanceMeters: step.stepDistance?.number ?? 0,
                expectedTravelTime: step.cost?.duration?.number ?? step.duration?.number,
                maneuver: step.navi?.action?.trimmed
            )
        }

        var notes: [String] = []
        let geometry = routeGeometry(path: path, steps: steps)
        if geometry.isEmpty {
            notes.append("高德未返回完整路线轨迹，地图上仅显示起点和终点。")
        }

        let traffic = trafficInformation(steps: steps, fetchedAt: fetchedAt)
        if let traffic, !traffic.hasGeometry, traffic.hasUsableData {
            notes.append("已获取高德路况，但缺少分段轨迹，无法在地图上着色。")
        }

        let cost = path.cost
        let tollsRaw = cost?.tolls?.number ?? path.tolls?.number
        let tollDistance = cost?.tollDistance?.number ?? path.tollDistance?.number
        let tollRoadText = cost?.tollRoad?.trimmed ?? path.tollRoad?.trimmed
        let tollRoads = parseRoadList(tollRoadText)
        let hasTolls: Bool? = {
            if let tollsRaw, tollsRaw > 0 { return true }
            if let tollDistance, tollDistance > 0 { return true }
            if tollsRaw != nil || tollDistance != nil { return false }
            return nil
        }()
        if let tollRoads = tollRoadText, !tollRoads.isEmpty {
            notes.append("收费道路：\(tollRoads)")
        }
        if path.restriction?.trimmed == "1" {
            notes.append("该路线含有限行路段，请以当地交通规定为准。")
        }
        if let lights = cost?.trafficLights?.integer ?? path.trafficLights?.integer, lights > 0 {
            notes.append("沿途约 \(lights) 个红绿灯")
        }
        if let tollsRaw, tollsRaw > 0 {
            notes.append("高德预估过路费 \(CurrencyFormatter.yuan(tollsRaw))")
        }

        let providerID = path.pathID?.trimmed

        return RouteAlternative(
            title: index == 0 ? "推荐路线" : "备选路线 \(index + 1)",
            providerRouteIdentifier: providerID,
            distanceMeters: distance,
            expectedTravelTime: duration,
            polyline: geometry,
            steps: castSteps,
            traffic: traffic,
            tollAmountYuan: tollsRaw,
            tollDistanceMeters: tollDistance,
            tollRoads: tollRoads,
            hasTolls: hasTolls,
            isRecommended: index == 0,
            notes: notes
        )
    }

    private static func routeGeometry(path: AMapDrivingPath, steps: [AMapDrivingStep]) -> [GeoCoordinate] {
        let pathGeometry = parsePolyline(path.polyline?.trimmed)
        if pathGeometry.count >= 2 {
            return pathGeometry
        }

        guard !steps.isEmpty else { return [] }
        var combined: [GeoCoordinate] = []
        var missing = false
        for step in steps {
            let stepDistance = step.stepDistance?.number ?? 0
            let geometry = parsePolyline(step.polyline?.trimmed)
            if stepDistance > 0 && geometry.count < 2 {
                missing = true
                break
            }
            appendDeduplicated(geometry, to: &combined)
        }
        if missing {
            return []
        }
        return combined.count >= 2 ? combined : []
    }

    private static func trafficInformation(
        steps: [AMapDrivingStep],
        fetchedAt: Date
    ) -> TrafficInformation? {
        var segments: [TrafficInformation.Segment] = []
        var segmentID = 0
        for step in steps {
            for tmc in step.tmcs ?? [] {
                let level = TrafficInformation.Level.fromAMapStatus(tmc.status?.trimmed ?? "")
                let length = tmc.distance?.number
                let coordinates = parsePolyline(tmc.polyline?.trimmed)
                segments.append(
                    TrafficInformation.Segment(
                        id: segmentID,
                        level: level,
                        coordinates: coordinates,
                        lengthMeters: length
                    )
                )
                segmentID += 1
            }
        }
        guard !segments.isEmpty else { return nil }
        return TrafficInformation(
            segments: segments,
            fetchedAt: fetchedAt,
            isComplete: nil,
            sourceLabel: "高德路况"
        )
    }

    private static func parseRoadList(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: ";,|，；")
        var seen = Set<String>()
        return raw.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Places

    static func places(
        from data: Data,
        fetchedAt: Date = Date()
    ) throws -> [LocationResult] {
        let envelope: AMapPlaceEnvelope
        do {
            envelope = try decoder.decode(AMapPlaceEnvelope.self, from: data)
        } catch {
            AppLog.search.error("AMap place decode failed: \(String(describing: error), privacy: .public)")
            throw RouteProviderError.decodingFailed
        }
        try validateStatus(envelope.status, info: envelope.info, infocode: envelope.infocode)
        guard let pois = envelope.pois, !pois.isEmpty else { return [] }

        var seen = Set<String>()
        var results: [LocationResult] = []
        for poi in pois {
            guard let name = poi.name?.trimmed,
                  let location = poi.location?.trimmed,
                  let coordinate = parseCoordinate(location) else {
                continue
            }
            let id = poi.id?.trimmed
            let uniqueKey = id ?? "\(name)|\(location)"
            guard seen.insert(uniqueKey).inserted else { continue }
            let category = poi.type?.trimmed?.split(separator: ";").first.map(String.init)
            results.append(
                LocationResult(
                    name: name,
                    city: poi.cityName?.trimmed,
                    district: poi.districtName?.trimmed,
                    address: poi.address?.trimmed,
                    category: category,
                    coordinate: coordinate,
                    provider: .amap,
                    providerPlaceID: id,
                    source: .amap,
                    createdAt: fetchedAt
                )
            )
        }
        return results
    }

    // MARK: - Errors / primitives

    static func validateStatus(
        _ status: FlexibleString?,
        info: FlexibleString?,
        infocode: FlexibleString?
    ) throws {
        guard status?.trimmed == "1" else {
            let code = infocode?.trimmed ?? "unknown"
            let debugInfo = info?.trimmed ?? "no info"
            AppLog.routing.error("AMap rejected request: \(code, privacy: .public) \(debugInfo, privacy: .public)")
            throw mapProviderError(infocode: code)
        }
    }

    static func mapProviderError(infocode: String?) -> RouteProviderError {
        guard let infocode, !infocode.isEmpty, infocode != "10000" else {
            return .providerRejected(code: infocode ?? "unknown", message: "地图服务暂时无法完成这次查询，请稍后重试。")
        }
        switch infocode {
        case "10001", "10002", "10005", "10006", "10007", "10008", "10009":
            return .unauthorized
        case "10003", "10004", "10010", "10011", "10012", "10013", "10044":
            return .quotaExceeded
        case "10021", "10022", "10023", "10024", "10025", "10026", "10029", "10041":
            return .rateLimited(retryAfter: nil)
        case let code where code.hasPrefix("208"):
            return .noRoute
        default:
            return .providerRejected(
                code: infocode,
                message: "高德地图暂时无法计算这条路线，请稍后重试。"
            )
        }
    }

    /// Parses an AMap `lng,lat` or `lat,lon`? AMap Web Services are always
    /// longitude first. Never guess or swap silently.
    static func parseCoordinate(_ raw: String) -> GeoCoordinate? {
        let parts = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2,
              let longitude = Double(parts[0]),
              let latitude = Double(parts[1]),
              longitude >= -180, longitude <= 180,
              latitude >= -90, latitude <= 90 else {
            return nil
        }
        return GeoCoordinate(latitude: latitude, longitude: longitude, datum: .gcj02)
    }

    /// AMap polylines are semicolon-separated longitude,latitude pairs. The
    /// parser is all-or-nothing: one malformed point invalidates the geometry
    /// so the UI can never draw a misleading partial/straight-line route.
    static func parsePolyline(_ raw: String?) -> [GeoCoordinate] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let tokens = raw.split(separator: ";", omittingEmptySubsequences: false)
        var points: [GeoCoordinate] = []
        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let coordinate = parseCoordinate(trimmed) else {
                return []
            }
            if let last = points.last, last.latitude == coordinate.latitude,
               last.longitude == coordinate.longitude {
                continue
            }
            points.append(coordinate)
        }
        return points.count >= 2 ? points : []
    }

    private static func appendDeduplicated(_ points: [GeoCoordinate], to target: inout [GeoCoordinate]) {
        for point in points {
            if let last = target.last, last.latitude == point.latitude,
               last.longitude == point.longitude {
                continue
            }
            target.append(point)
        }
    }
}
