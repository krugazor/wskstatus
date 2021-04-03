import Foundation

// I have NO idea whether the times and dates are stored in UTC or with the server's timezone, or what
extension Date {
    var timeIntervalSince1970TZ : Double {
        let timezoneOffset =  TimeZone.current.secondsFromGMT()
        return self.timeIntervalSince1970 + Double(timezoneOffset)
    }

    init(owtz: Int64) {
        let seconds = Double(owtz/1000)
        let timezoneOffset =  Double(TimeZone.current.secondsFromGMT())
        self.init(timeIntervalSince1970: seconds+timezoneOffset)
    }

    init(ow: Int64) {
        let seconds = Double(ow/1000)
         self.init(timeIntervalSince1970: seconds)
    }
}

struct ActivationLimits : Codable, Hashable {
    var concurrency: Int
    var logs: Int64
    var memory: Int64
    var timeout: Int64

    enum CodingKeys: String, CodingKey {
        case concurrency
        case logs
        case memory
        case timeout
    }
}

enum ValueType : Codable, Hashable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([ValueType])
    case limits(ActivationLimits)

    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            if let val = try? container.decode(String.self) { self = .string(val) ; return }
            if let val = try? container.decode(Int64.self) { self = .int(val) ; return }
            if let val = try? container.decode(Double.self) { self = .double(val) ; return }
            if let val = try? container.decode(Bool.self) { self = .bool(val) ; return }
        } catch { }
        do {
            var container = try decoder.unkeyedContainer()
            if let values = try? container.decode([ValueType].self) { self = .array(values) ; return }
        } catch { }
        do {
            let container = try decoder.container(keyedBy: ActivationLimits.CodingKeys.self)
            if let c = try? container.decode(Int.self, forKey: .concurrency),
               let l = try? container.decode(Int64.self, forKey: .logs),
               let m = try? container.decode(Int64.self, forKey: .memory),
               let t = try? container.decode(Int64.self, forKey: .timeout) {
                self = .limits(ActivationLimits(concurrency: c, logs: l, memory: m, timeout: t))
                return
            }
        }
        throw DecodingError.typeMismatch(ValueType.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for ValueType"))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let v):
            var container = encoder.singleValueContainer()
            try container.encode(v)
        case .int(let v):
            var container = encoder.singleValueContainer()
            try container.encode(v)
        case .double(let v):
            var container = encoder.singleValueContainer()
            try container.encode(v)
        case .bool(let v):
            var container = encoder.singleValueContainer()
            try container.encode(v)
        case .array(let v):
            var container = encoder.unkeyedContainer()
            try container.encode(v)
        case .limits(let v):
            var container = encoder.container(keyedBy: ActivationLimits.CodingKeys.self)
            try container.encode(v.concurrency, forKey: .concurrency)
            try container.encode(v.logs, forKey: .logs)
            try container.encode(v.memory, forKey: .memory)
            try container.encode(v.timeout, forKey: .timeout)
        }
    }
}

struct BasicInfo : Codable, Hashable {
    static func == (lhs: BasicInfo, rhs: BasicInfo) -> Bool {
        return lhs.key == rhs.key
    }

    var key: String
    var value: ValueType
}

struct ActivationInfo : Codable, Equatable, Hashable {
    static func == (lhs: ActivationInfo, rhs: ActivationInfo) -> Bool {
        return lhs.activationId == rhs.activationId
    }

    var activationId: String
    var annotations: [BasicInfo]?
    var duration: Int64
    var end: Int64
    var name: String
    var namespace: String
    var publish: Bool
    var start: Int64
    var statusCode: Int? // either status or logs
    var version: String
    var logs: [String]? // either status or logs

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activationId = try container.decode(String.self, forKey: .activationId)
        annotations = try? container.decode([BasicInfo].self, forKey: .annotations)
        start = try container.decode(Int64.self, forKey: .start)
        duration = try container.decode(Int64.self, forKey: .duration)
        end = try container.decode(Int64.self, forKey: .end)
        name = try container.decode(String.self, forKey: .name)
        namespace = try container.decode(String.self, forKey: .namespace)
        publish = try container.decode(Bool.self, forKey: .publish)
        statusCode = try? container.decode(Int.self, forKey: .statusCode)
        version = try container.decode(String.self, forKey: .version)
        logs = try? container.decode([String].self, forKey: .logs)
    }
}