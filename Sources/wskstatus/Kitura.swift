import Foundation
import Kitura
import KituraStencil

extension Router {
    func webStart(_ port: Int = 8085) {
        print("Starting server on port \(port)")
        print("Will be available on URL: http://localhost:\(port)/")

        Kitura.addHTTPServer(onPort: port, with: self)
        Kitura.run()
    }
}

var data = ActivationStore(base: "", auth: "", namespace: "")

func setupWebServices(apibase: String, apiauth: String, apins: String, frame: TimeFrame) -> Router {
    data = ActivationStore(base: apibase, auth: apiauth, namespace: apins)
    let tick: TimeInterval = 1
    let total: TimeInterval = 80
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
    let _ = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { timer in
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
    }
    let router = Router()
    
    router.all(middleware: BodyParser(), StaticFileServer(path: "./Public"))
    router.add(templateEngine: StencilTemplateEngine())
    
    router.get("/") { req, res, next in
        try res.redirect("index.html")
        next()
    }
    
    router.get("/data/") { req, res, next in
        let activations = data.binned.map( { $0.count } )
        let durations = data.averageDurations
        var deltas = [Int]()
        for i in 1...activations.count {
            deltas.append(i-activations.count)
        }
        
        let computed : [[String:Codable]] = [
            ["x": deltas,
            "y": activations,
            "type": "line",
            "name": "Activations",
            "xaxis": "x1",
            "yaxis": "y1"
            ],
            ["x": deltas,
            "y": durations,
            "type": "bar",
            "name": "Average Duration",
            "xaxis": "x2",
            "yaxis": "y2"]
        ]
        res.send(json: computed)
        next()
    }
    
    return router
}

