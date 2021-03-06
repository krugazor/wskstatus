import Foundation
import ArgumentParser
import AnyCodable
import Dispatch
#if os(Linux)
import TermPlot
import FoundationNetworking
#endif

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
func pollActivations(base: String, auth: String, since: Int64? = nil, upto: Int64? = nil, namespace: String, moreInfo: Bool = false, handler: @escaping ((Result<[ActivationInfo], CommunicationError>)->Void)) {
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
        } else {
            queryString = queryString + "&upto=\(upto)"
        }
    }
    if moreInfo {
        if queryString.isEmpty {
            queryString = "docs=true"
        } else {
            queryString = queryString + "&docs=true"
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

func pollActivationsSync(base: String, auth: String, since: Int64? = nil, upto: Int64? = nil, namespace: String, moreInfo: Bool = false, handler: @escaping ((Result<[ActivationInfo], CommunicationError>)->Void)) {
    let sem = DispatchSemaphore(value: 0)
    var result : Result<[ActivationInfo], CommunicationError>?

    pollActivations(base: base, auth: auth, since: since, upto: upto, namespace: namespace, moreInfo: moreInfo) { resultasync in
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
            pollActivationsSync(base: base, auth: auth, since: Int64(firstDate) + 1, namespace: namespace, moreInfo: true) { result in
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
            pollActivationsSync(base: base, auth: auth, namespace: namespace, moreInfo: true) { result in
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
                pollActivationsSync(base: base, auth: auth, upto: upto - 1, namespace: namespace, moreInfo: true) { result in
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
        let compSet = Set<Calendar.Component>(arrayLiteral: .year, .yearForWeekOfYear, .month, .weekOfYear, .day, .hour, .minute, .timeZone)

        var upto : DateComponents
        let interval : DateComponents
        switch timeframe {
        case .minutely:
            upto = Calendar.current.dateComponents(compSet,
                    from: Calendar.current.date(byAdding: .minute, value: 1, to: Date(), wrappingComponents: false) ?? Date.distantPast)
            interval = DateComponents(minute: -1) ; upto.minute = upto.minute! + 1
        case .hourly:
            interval = DateComponents(hour: -1)
            upto = Calendar.current.dateComponents(compSet,
                    from: Calendar.current.date(byAdding: .hour, value: 1, to: Date(), wrappingComponents: false) ?? Date.distantPast)
            upto.minute = 0
            upto.second = 0
        case .daily:
            interval = DateComponents(day: -1)
            upto = Calendar.current.dateComponents(compSet,
                    from: Calendar.current.date(byAdding: .day, value: 1, to: Date(), wrappingComponents: false) ?? Date.distantPast)
            upto.hour = 0
            upto.minute = 0
            upto.second = 0
        case .weekly:
            interval = DateComponents(weekOfYear: -1)
            upto = Calendar.current.dateComponents(compSet,
                    from: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date(), wrappingComponents: false) ?? Date.distantPast)
            upto.hour = 0
            upto.minute = 0
            upto.second = 0
       case .monthly:
            interval = DateComponents(month: -1)
            upto = Calendar.current.dateComponents(compSet,
                    from: Calendar.current.date(byAdding: .month, value: 1, to: Date(), wrappingComponents: false) ?? Date.distantPast)
            upto.day = 1
            upto.hour = 0
            upto.minute = 0
            upto.second = 0
        case .yearly:
            interval = DateComponents(year: -1)
            upto = Calendar.current.dateComponents(compSet,
                    from: Calendar.current.date(byAdding: .year, value: 1, to: Date(), wrappingComponents: false) ?? Date.distantPast)
            upto.month = 1
            upto.weekOfYear = nil
            upto.day = 1
            upto.hour = 0
            upto.minute = 0
            upto.second = 0
        }

        var uptodate = (Calendar.current.date(from: upto) ?? Date.distantPast)
        var downtodate = Calendar.current.date(byAdding: interval, to: uptodate) ?? Date.distantPast
        while uptodate > minDate {
            result.insert(items.filter({
                $0.start > Int64(downtodate.timeIntervalSince1970*1000)
                        && $0.start <= Int64(uptodate.timeIntervalSince1970*1000)
            }), at: 0)
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

    func binned(_ count: Int) -> [[ActivationInfo]]{
        var bins = self.binned
        while bins.count > count {
            bins.remove(at: 0)
        }
        return bins
    }

    func averaged(_ count: Int) -> [Int64] {
        var bins = self.binned
        while bins.count > count {
            bins.remove(at: 0)
        }
        
        return bins.map { list in
            if list.isEmpty { return 0 }
            let sum = list.reduce(0) { (prev, cur) in
                return prev + (cur.end - cur.start)
            }
            return sum / Int64(list.count)
        }
    }

    func top(_ count: Int) -> [(name: String, occurences: Int, average: Int64)] {
        let names = items.compactMap({ (name:$0.name, duration: $0.duration) })
        let occurences = names.reduce([:]) { prev, item -> [String:(Int, Int64)] in // cumulative time
            var next = prev
            next[item.name] = ((next[item.name]?.0 ?? 0) + 1, (next[item.name]?.1 ?? 0) + item.duration)
            return next
        }
        let sorted = occurences.sorted { (arg0, arg1) -> Bool in
            arg0.value > arg1.value
        }
        var result : [(name: String, occurences: Int, average: Int64)] = []
        for i in 0..<min(count,sorted.count) {
            let avg : Int64 = sorted[i].value.0 == 0 ? 0 : sorted[i].value.1 / Int64(sorted[i].value.0)
            result.append((sorted[i].key, sorted[i].value.0, avg))
        }
        return result
    }

    var top5 : [(name: String, occurences: Int, average: Int64)] {
        return top(5)
    }

    func last(_ count: Int = 5) -> [ActivationInfo] {
        return Array(items[ 0..<min(count,items.count) ])
    }

    var last5 : [ActivationInfo] {
        return last(5)
    }

    var duplicates : Int {
        let set = Set(items)
        return items.count - set.count
    }
}
