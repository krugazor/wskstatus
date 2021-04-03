import Foundation
import ArgumentParser

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
    var frame: TimeFrame = .hourly
    
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
            print(data.last5)
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
