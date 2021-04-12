import Foundation
import ArgumentParser
import TermPlot

#if os(macOS)
import AppKit
#endif

#if os(Linux)
extension NSMutableAttributedString {
    convenience init() {
        self.init(string: "")
    }
}
#endif

// from https://stackoverflow.com/questions/32830519/is-there-joinwithseparator-for-attributed-strings
extension Sequence where Iterator.Element == NSAttributedString {
    func joined(with separator: NSAttributedString) -> NSAttributedString {
        return self.reduce(NSMutableAttributedString()) {
            (r, e) in
            if r.length > 0 {
                r.append(separator)
            }
            r.append(e)
            return r
        }
    }

    func joined(with separator: String = "") -> NSAttributedString {
        return self.joined(with: NSAttributedString(string: separator))
    }
}
extension ActivationStore {
    func topAttributedString(_ count: Int) -> NSAttributedString {
        var elements = [NSAttributedString]()
        for item in self.top(count) {
            #if os(macOS)
            elements.append( NSAttributedString(string: item.name, attributes: [ NSAttributedString.Key("NSFont"): NSFont.boldSystemFont(ofSize: 9) ]) )
            elements.append( NSAttributedString(string: ": \(item.occurences) activations, \(item.average)ms average duration\n") )
            #elseif os(Linux)
            elements.append( NSAttributedString(item.name, color: .default, style: .bold) )
            elements.append( NSAttributedString(": \(item.occurences) activations, \(item.average)ms average duration\n", color: .default, style: .default) )
            #else
            elements.append( NSAttributedString(string: item.name) )
            elements.append( NSAttributedString(string: ": \(item.occurences) activations, \(item.average)ms average duration\n") )
           #endif
        }
        return elements.joined()
    }
    
    var top5AttributedString : NSAttributedString {
        self.topAttributedString(5)
    }

    func lastLogs(_ count: Int) -> [String] {
        let logs = self.last(count).reversed().compactMap( { activation in
            activation.logs?.map( { activation.activationId+" \(activation.name): "+$0 } )
        } )
        return logs.map( { $0.joined(separator: "\n") } )
    }

    var last5Logs : [String] {
        return lastLogs(5)
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
            let tick: TimeInterval = 1
            var total: TimeInterval = 80
            switch frame {
            case .minutely:
                data.minDate = Date(timeIntervalSinceNow: -total*60)
            case .hourly:
                data.minDate = Date(timeIntervalSinceNow: -total*3600)
            case .daily:
                data.minDate = Date(timeIntervalSinceNow: -total*24*3600)
            case .weekly:
                data.minDate = Date(timeIntervalSinceNow: -total*7*24*3600)
            case .monthly:
                data.minDate = Date(timeIntervalSinceNow: -total*30*24*3600) // yea yea, I know
            case .yearly:
                data.minDate = Date(timeIntervalSinceNow: -total*365*24*3600) // yea yea, I know
            }
            data.timeframe = frame
            data.refresh {
            }

            // Screen setup
            let activations = StandardSeriesWindow(tick: tick, total: total)
            activations.seriesColor = .monochrome(.light_yellow)
            activations.seriesStyle = .line
            activations.boxStyle = .ticked
            activations.addValues(data.binned.map( { Double($0.count) }))
            let averages = StandardSeriesWindow(tick: tick, total: total)
            averages.addValues(data.averageDurations.map( { Double($0) } ))
            averages.seriesColor = .monochrome(.light_cyan)
            averages.seriesStyle = .line
            averages.boxStyle = .ticked
            let top = TextWindow()
            top.replace(with: "Top activations\n")
            top.add(data.top5AttributedString)
            let last = TextWindow()
            last.add(data.last5Logs.joined(separator: "\n"))
            let screenLeft = try TermMultiWindow.setup(stack: .vertical, ratios:[0.5,0.5], activations, averages)
            let screenRight = try TermMultiWindow.setup(stack: .vertical, ratios:[0.5,0.5], top, last)
            let screen = try TermMultiWindow.setup(stack: .horizontal, ratios: [0.5, 0.5], screenLeft, screenRight)
            screen.start()

            let _ = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [self] timer in
                total = Double(activations.cols*3/4)
                // update the data
                switch frame {
                case .minutely:
                    data.minDate = Date(timeIntervalSinceNow: -total*60)
                case .hourly:
                    data.minDate = Date(timeIntervalSinceNow: -total*3600)
                case .daily:
                    data.minDate = Date(timeIntervalSinceNow: -total*24*3600)
                case .weekly:
                    data.minDate = Date(timeIntervalSinceNow: -total*7*24*3600)
                case .monthly:
                    data.minDate = Date(timeIntervalSinceNow: -total*30*24*3600) // yea yea, I know
                case .yearly:
                    data.minDate = Date(timeIntervalSinceNow: -total*365*24*3600) // yea yea, I know
                }
                data.refresh {
                }
                activations.replaceValues(with: data.binned(activations.cols*3/4).map({ Double($0.count) }) + [0.0])
                averages.replaceValues(with: data.averaged(averages.cols*3/4).map( { Double($0) } ) + [0.0] )
                top.replace(with: "Top activations\n")
                top.add( data.topAttributedString(top.rows-4))
                last.replace(with:data.lastLogs(20).joined(separator: "\n"))
            }

            RunLoop.current.run(until: Date.distantFuture)
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
