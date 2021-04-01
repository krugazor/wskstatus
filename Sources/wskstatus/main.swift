import Foundation
import ArgumentParser
import Dispatch

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
    var statusCode: Int
    var version: String
}

enum TimeFrame : String, ExpressibleByArgument {
    case minutely
    case hourly
    case daily
    case weekly
    case monthly
    case yearly
}

struct ConfigurationError : Error {
    var msg: String
}
struct CommunicationError : Error {
    var msg: String
}

var networkSession = URLSession(configuration: URLSessionConfiguration.default)

// https://github.com/apache/openwhisk-client-js/blob/master/README.md#openwhisk-client-for-javascript
func pollActivations(base: String, auth: String, since: Int64? = nil, upto: Int64? = nil, namespace: String, handler: @escaping ((Result<[ActivationInfo], CommunicationError>)->Void)) {
    guard var apiurl = URL(string: "https://\(base)/api/v1/namespaces/\(namespace)/activations") else {
        handler(.failure(CommunicationError(msg: "base url not correct")))
        return
    }
    guard let auth64 = auth.data(using: .utf8)?.base64EncodedString() else {
        handler(.failure(CommunicationError(msg: "auth not correct")))
        return
    }
    
    var queryString: String = ""
    if let since = since {
        queryString = "since=\(since)"
    }
    if let upto = upto {
        if queryString.isEmpty {
            queryString = "upto=\(upto)"
        }
    }
    if !queryString.isEmpty {
        apiurl = URL(string: apiurl.absoluteString+"?\(queryString)")!
    }
    var request = URLRequest(url: apiurl)
    request.addValue("Basic " + auth64, forHTTPHeaderField: "Authorization")
    let task = networkSession.dataTask(with: request) { data, res, err in
        if let err = err {
            handler(.failure(CommunicationError(msg: err.localizedDescription)))
            return
        }
        
        guard let json = data, let activations = try? JSONDecoder().decode([ActivationInfo].self, from: json) else {
            handler(.failure(CommunicationError(msg: "server responded with malformed data")))
            return
        }
        
        handler(.success(activations))
    }
    task.resume()
}

func pollActivationsSync(base: String, auth: String, since: Int64? = nil, upto: Int64? = nil, namespace: String, handler: @escaping ((Result<[ActivationInfo], CommunicationError>)->Void)) {
    let sem = DispatchSemaphore(value: 0)
    var result : Result<[ActivationInfo], CommunicationError>?
    
    pollActivations(base: base, auth: auth, since: since, upto: upto, namespace: namespace) { resultasync in
        result = resultasync
        sem.signal()
    }
    
    sem.wait()
    if let result = result {
        handler(result)
    } else {
        handler(.failure(CommunicationError(msg: "unknown error")))
    }
}

struct ActivationStore {
    var base: String
    var auth: String
    var namespace: String
    var minDate : Date = Date(timeIntervalSinceNow: -24*3600)
    var timeframe: TimeFrame = .hourly
    var items: [ActivationInfo] = []
    
    // make sure it's always sorted by date
    mutating func refresh(_ done: ()->Void) {
        // check forward
        if let firstDate = items.first?.end {
            var list : [ActivationInfo] = []
            pollActivationsSync(base: base, auth: auth, since: Int64(firstDate) + 1, namespace: namespace) { result in
                switch result {
                case .success(let activations):
                    list=activations.sorted(by: { $0.start > $1.start })
                case.failure( _):
                    break
                }
            }
            items.insert(contentsOf: list, at: 0)
        } else {
            var list : [ActivationInfo] = []
            pollActivationsSync(base: base, auth: auth, namespace: namespace) { result in
                switch result {
                case .success(let activations):
                    list=activations.sorted(by: { $0.start > $1.start })
                case.failure( _):
                    break
                }
            }
            items = list
        }
        
        // check backward
        let minEpoch = Int64(minDate.timeIntervalSince1970 * 1000)
        while (items.last?.start ?? Int64.min) >= minEpoch {
            var list : [ActivationInfo] = []
            if let upto = items.last?.start {
                pollActivationsSync(base: base, auth: auth, upto: upto - 1, namespace: namespace) { result in
                    switch result {
                    case .success(let activations):
                        list = activations.sorted(by: { $0.start > $1.start }).filter({ $0.start >= minEpoch })
                    case.failure( _):
                        break
                    }
                }
            }
            if list.isEmpty { break }
            items.append(contentsOf: list)
        }
        
        done()
    }
    
    mutating func truncate() {
        let minEpoch = Int64(minDate.timeIntervalSince1970 * 1000)
        items = items.filter({ aif in
            aif.start >= minEpoch
        })
    }
    
    var binned : [[ActivationInfo]] {
        var result = [[ActivationInfo]]()
        
        var upto = Calendar.current.dateComponents(Set(arrayLiteral: .year, .month, .weekOfYear, .day, .hour, .minute, .timeZone), from: Date())
        let interval : DateComponents
        switch timeframe {
        case .minutely: interval = DateComponents(minute: -1) ; upto.minute = upto.minute! + 1
        case .hourly: interval = DateComponents(hour: -1) ; upto.hour = upto.hour! + 1
        case .daily: interval = DateComponents(day: -1) ; upto.day = upto.day! + 1
        case .weekly: interval = DateComponents(weekOfYear: -1) ; upto.weekOfYear = upto.weekOfYear! + 1
        case .monthly: interval = DateComponents(month: -1) ; upto.month = upto.month! + 1
        case .yearly: interval = DateComponents(year: -1) ; upto.year = upto.year! + 1
        }
        
        var uptodate = (Calendar.current.date(from: upto) ?? Date.distantPast)
        var downtodate = Calendar.current.date(byAdding: interval, to: uptodate) ?? Date.distantPast
        while uptodate > minDate {
            result.insert(items.filter({ $0.start > Int64(downtodate.timeIntervalSince1970*1000) && $0.start <= Int64(uptodate.timeIntervalSince1970*1000) }), at: 0)
            uptodate = downtodate
            downtodate = Calendar.current.date(byAdding: interval, to: uptodate) ?? Date.distantPast
        }
        
        return result
    }
    
    var averageDurations : [Int64] {
        return binned.map { list in
            if list.isEmpty { return 0 }
            let sum = list.reduce(0) { (prev, cur) in
                return prev + (cur.end - cur.start)
            }
            return sum / Int64(list.count)
        }
    }
    
    var top5 : [String] {
        let names = items.compactMap({ $0.name })
        let occurences = names.reduce([:]) { prev, name -> [String:Int] in
            var next = prev
            next[name] = (next[name] ?? 0) + 1
            return next
        }
        let sorted = occurences.sorted { (arg0, arg1) -> Bool in
            arg0.value > arg1.value
        }
        var result : [String] = []
        for i in 0..<min(5,sorted.count) {
            result.append(sorted[i].key)
        }
        return result
    }
    
    var duplicates : Int {
        let set = Set(items)
        return items.count - set.count
    }
}

struct WskStatus : ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: """
            wskstatus lists activations from your wsk instance and displays a bunch of statistics
            """
    )
    @Option(name: .shortAndLong, help: "The base URL for your wsk instance. If omitted, will be read from your .wskprops")
    var baseurl: String?
    
    @Option(name: .shortAndLong, help: "The namespace on your wsk instance. If omitted, will be read from your .wskprops")
    var namespace: String?
    
    @Option(name: .shortAndLong, help: "The authentification token for your wsk instance. If omitted, will be read from your .wskprops")
    var token: String?
    
    @Option(name: .shortAndLong, help: "The tick at which data should be aggregated: minutely, hourly, daly, weekly, monthly, yearly")
    var frame: TimeFrame = .minutely
    
    func readWskProps() throws -> [String:String] {
        var result = [String:String]()
        do {
            let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".wskprops")
            let contents = try String(contentsOf: file)
            let lines = contents.components(separatedBy: CharacterSet.newlines)
            for line in lines {
                if line.isEmpty { continue }
                let comps = line.components(separatedBy: "=")
                if comps.count != 2 { throw ConfigurationError(msg: "Malformed ~/.wskprops")}
                result[comps[0]] = comps[1]
            }
        } catch {
            throw ConfigurationError(msg: error.localizedDescription)
        }
        return result
    }
    
    mutating func run() throws {
        do {
            let props = try readWskProps()
            let tapibase = baseurl ?? props["APIHOST"]
            let tapins = namespace ?? props["NAMESPACE"]
            let tapiauth = token ?? props["AUTH"]
            
            guard let apibase = tapibase, let apins = tapins, let apiauth = tapiauth else { throw ConfigurationError(msg: "Missing configuration fields. Please check your options and your .wskprops") }
            
            var data = ActivationStore(base: apibase, auth: apiauth, namespace: apins)
            switch frame {
            case .minutely:
                data.minDate = Date(timeIntervalSinceNow: -160*60)
            case .hourly:
                data.minDate = Date(timeIntervalSinceNow: -7*24*3600)
            case .daily:
                data.minDate = Date(timeIntervalSinceNow: -2*31*24*3600)
            case .weekly:
                data.minDate = Date(timeIntervalSinceNow: -180*24*3600)
            case .monthly:
                data.minDate = Date(timeIntervalSinceNow: -2*365*24*3600)
            case .yearly:
                data.minDate = Date(timeIntervalSinceNow: -120*365*24*3600)
            }
            data.timeframe = frame
            data.refresh {
            }
            print(data.top5)
            print("\(data.binned.map({ $0.count })) activations")
            print(data.averageDurations)
            print("\(data.duplicates) duplicates")
        } catch {
            if let error = error as? ConfigurationError {
                print(error.msg)
            } else if let error = error as? CommunicationError {
                print(error.msg)
            } else {
                print(error.localizedDescription)
            }
        }
    }
}

WskStatus.main()
