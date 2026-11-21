import Foundation

/// A tolerant scalar decoder for AMap Web Service values. AMap documents many
/// numeric fields as strings and can return an empty array for absent optional
/// values. Missing values remain nil instead of turning into fabricated zeroes.
struct FlexibleString: Decodable, Sendable {
    let stringValue: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            stringValue = nil
            return
        }
        if let value = try? container.decode(String.self) {
            stringValue = value
            return
        }
        if let value = try? container.decode(Int.self) {
            stringValue = String(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            stringValue = String(value)
            return
        }
        if let value = try? container.decode(Bool.self) {
            stringValue = value ? "1" : "0"
            return
        }
        // AMap returns [] for some absent optional objects/arrays.
        stringValue = nil
    }

    var trimmed: String? {
        guard let stringValue else { return nil }
        let value = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var number: Double? {
        guard let trimmed else { return nil }
        return Double(trimmed)
    }

    var integer: Int? {
        guard let number else { return nil }
        return Int(number.rounded())
    }
}

struct AMapDrivingEnvelope: Decodable {
    var status: FlexibleString?
    var info: FlexibleString?
    var infocode: FlexibleString?
    var count: FlexibleString?
    var route: AMapDrivingRoutePayload?
}

struct AMapDrivingRoutePayload: Decodable {
    var origin: FlexibleString?
    var destination: FlexibleString?
    var taxiCost: FlexibleString?
    var paths: [AMapDrivingPath]?

    enum CodingKeys: String, CodingKey {
        case origin
        case destination
        case taxiCost = "taxi_cost"
        case paths
    }
}

struct AMapDrivingPath: Decodable {
    var pathID: FlexibleString?
    var distance: FlexibleString?
    var duration: FlexibleString?
    var restriction: FlexibleString?
    var cost: AMapDrivingCost?
    var tolls: FlexibleString?
    var tollDistance: FlexibleString?
    var tollRoad: FlexibleString?
    var trafficLights: FlexibleString?
    var polyline: FlexibleString?
    var steps: [AMapDrivingStep]?

    enum CodingKeys: String, CodingKey {
        case pathID = "path_id"
        case distance
        case duration
        case restriction
        case cost
        case tolls
        case tollDistance = "toll_distance"
        case tollRoad = "toll_road"
        case trafficLights = "traffic_lights"
        case polyline
        case steps
    }
}

struct AMapDrivingCost: Decodable {
    var duration: FlexibleString?
    var tolls: FlexibleString?
    var tollDistance: FlexibleString?
    var tollRoad: FlexibleString?
    var trafficLights: FlexibleString?
    var cost: FlexibleString?

    enum CodingKeys: String, CodingKey {
        case duration
        case tolls
        case tollDistance = "toll_distance"
        case tollRoad = "toll_road"
        case trafficLights = "traffic_lights"
        case cost
    }
}

struct AMapDrivingStep: Decodable {
    var instruction: FlexibleString?
    var roadName: FlexibleString?
    var stepDistance: FlexibleString?
    var duration: FlexibleString?
    var cost: AMapDrivingStepCost?
    var polyline: FlexibleString?
    var navi: AMapNavi?
    var tmcs: [AMapTMC]?

    enum CodingKeys: String, CodingKey {
        case instruction
        case roadName = "road_name"
        case road
        case stepDistance = "step_distance"
        case distance
        case duration
        case cost
        case polyline
        case navi
        case tmcs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instruction = try container.decodeIfPresent(FlexibleString.self, forKey: .instruction)
        let primaryRoadName = try container.decodeIfPresent(FlexibleString.self, forKey: .roadName)
        let fallbackRoadName = try container.decodeIfPresent(FlexibleString.self, forKey: .road)
        roadName = primaryRoadName ?? fallbackRoadName
        let primaryStepDistance = try container.decodeIfPresent(FlexibleString.self, forKey: .stepDistance)
        let fallbackStepDistance = try container.decodeIfPresent(FlexibleString.self, forKey: .distance)
        stepDistance = primaryStepDistance ?? fallbackStepDistance
        duration = try container.decodeIfPresent(FlexibleString.self, forKey: .duration)
        cost = try container.decodeIfPresent(AMapDrivingStepCost.self, forKey: .cost)
        polyline = try container.decodeIfPresent(FlexibleString.self, forKey: .polyline)
        navi = try container.decodeIfPresent(AMapNavi.self, forKey: .navi)
        tmcs = try container.decodeIfPresent([AMapTMC].self, forKey: .tmcs)
    }
}

struct AMapDrivingStepCost: Decodable {
    var duration: FlexibleString?

    enum CodingKeys: String, CodingKey {
        case duration
    }
}

struct AMapNavi: Decodable {
    var action: FlexibleString?
    var assistantAction: FlexibleString?

    enum CodingKeys: String, CodingKey {
        case action
        case assistantAction = "assistant_action"
    }
}

struct AMapTMC: Decodable {
    var status: FlexibleString?
    var distance: FlexibleString?
    var polyline: FlexibleString?

    enum CodingKeys: String, CodingKey {
        case tmcStatus = "tmc_status"
        case tmcDistance = "tmc_distance"
        case tmcPolyline = "tmc_polyline"
        case status
        case distance
        case polyline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let primaryStatus = try container.decodeIfPresent(FlexibleString.self, forKey: .tmcStatus)
        let fallbackStatus = try container.decodeIfPresent(FlexibleString.self, forKey: .status)
        status = primaryStatus ?? fallbackStatus
        let primaryDistance = try container.decodeIfPresent(FlexibleString.self, forKey: .tmcDistance)
        let fallbackDistance = try container.decodeIfPresent(FlexibleString.self, forKey: .distance)
        distance = primaryDistance ?? fallbackDistance
        let primaryPolyline = try container.decodeIfPresent(FlexibleString.self, forKey: .tmcPolyline)
        let fallbackPolyline = try container.decodeIfPresent(FlexibleString.self, forKey: .polyline)
        polyline = primaryPolyline ?? fallbackPolyline
    }
}

struct AMapPlaceEnvelope: Decodable {
    var status: FlexibleString?
    var info: FlexibleString?
    var infocode: FlexibleString?
    var count: FlexibleString?
    var pois: [AMapPOI]?
}

struct AMapPOI: Decodable {
    var name: FlexibleString?
    var id: FlexibleString?
    var location: FlexibleString?
    var type: FlexibleString?
    var typecode: FlexibleString?
    var provinceName: FlexibleString?
    var cityName: FlexibleString?
    var districtName: FlexibleString?
    var address: FlexibleString?
    var adcode: FlexibleString?
    var citycode: FlexibleString?

    enum CodingKeys: String, CodingKey {
        case name
        case id
        case location
        case type
        case typecode
        case provinceName = "pname"
        case cityName = "cityname"
        case districtName = "adname"
        case address
        case adcode
        case citycode
    }
}

struct ProxyErrorEnvelope: Decodable {
    struct ProxyError: Decodable {
        var code: String?
        var message: String?
        var providerInfoCode: String?
        var providerMessage: String?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case providerInfoCode = "provider_infocode"
            case providerMessage = "provider_message"
        }
    }

    var error: ProxyError?
}
