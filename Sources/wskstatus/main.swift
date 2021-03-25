import Foundation
import ArgumentParser
import Dispatch

struct ActivationLimits : Codable {
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


enum ValueType : Codable {
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

struct BasicInfo : Codable {
    var key: String
    var value: ValueType
}

struct ActivationInfo : Codable {
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

var networkSession = URLSession(configuration: URLSessionConfiguration.default)
struct WskStatus : ParsableCommand {
    struct ConfigurationError : Error {
        var msg: String
    }
    struct CommunicationError : Error {
        var msg: String
    }
    
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
    
    
    func pollActivations(base: String, auth: String, namespace: String, handler: @escaping ((Result<[ActivationInfo], CommunicationError>)->Void)) {
        guard let apiurl = URL(string: "https://\(base)/api/v1/namespaces/\(namespace)/activations") else {
            handler(.failure(CommunicationError(msg: "base url not correct")))
            return
        }
        guard let auth64 = auth.data(using: .utf8)?.base64EncodedString() else {
            handler(.failure(CommunicationError(msg: "auth not correct")))
            return
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
    
    func pollActivationsSync(base: String, auth: String, namespace: String, handler: @escaping ((Result<[ActivationInfo], CommunicationError>)->Void)) {
        let sem = DispatchSemaphore(value: 0)
        var result : Result<[ActivationInfo], CommunicationError>?
        
        pollActivations(base: base, auth: auth, namespace: namespace) { resultasync in
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

    mutating func run() throws {
        do {
            let props = try readWskProps()
            let tapibase = baseurl ?? props["APIHOST"]
            let tapins = namespace ?? props["NAMESPACE"]
            let tapiauth = token ?? props["AUTH"]
            
            guard let apibase = tapibase, let apins = tapins, let apiauth = tapiauth else { throw ConfigurationError(msg: "Missing configuration fields. Please check your options and your .wskprops") }
            
            pollActivationsSync(base: apibase, auth: apiauth, namespace: apins) { result in
                switch result {
                case .failure(let err):
                    print(err.msg)
                case .success(let activations):
                    print("\(activations.count) activations")
                }
            }
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
