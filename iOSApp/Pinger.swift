//
//  Pinger.swift
//  iOSApp
//
//  Created by Eden on 2023/9/18.
//

import Foundation
import Network

@available(iOS 12.0, *)
public final
class Pinger
{
    public
    typealias ResultHandler = (Result) -> Void
    
    // MARK: - Properties -
    
    public
    var timeoutInterval: TimeInterval = 4.0 // 4 Sec.
    
    public
    let host: NWEndpoint.Host
    
    public
    let port: NWEndpoint.Port
    
    public private(set)
    var isRunning: Bool = false
    
    private
    let hostName: String
    
    private
    var pathMonitor: NWPathMonitor?
    
    private
    var connection: NWConnection?
    
    private
    var resultHandler: ResultHandler?
    
    private
    var timer: Timer?
    
    // MARK: - Methods -
    // MARK: Initial Method
    
    public
    init(hostName: String, port: UInt16 = 80)
    {
        let host = NWEndpoint.Host(hostName)
        let port = NWEndpoint.Port(rawValue: port) ?? .http
        
        self.hostName = hostName
        self.host = host
        self.port = port
    }
    
    public
    convenience
    init?(url: URL)
    {
        guard let hostName = url.hostName else {
            
            return nil
        }
        
        let port = UInt16(url.port ?? 80)
        
        self.init(hostName: hostName, port: port)
    }
    
    func start(result: @escaping ResultHandler)
    {
        let updateHandler: (NWPath) -> Void = {
            
            [weak self] path in
            
            guard let self = self else {
                
                return
            }
            
            guard path.status == .satisfied else {
                
                return
            }
            
            DispatchQueue.main.async {
                
                self.preparePing()
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        
        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = updateHandler
        pathMonitor.start(queue: queue)
        
        self.pathMonitor = pathMonitor
        self.resultHandler = result
        self.isRunning = true
    }
    
    func stop()
    {
        self.resultHandler?(.stop(self.hostName))
        
        self.pathMonitor?.cancel()
        self.pathMonitor = nil
        self.connection?.cancel()
        self.connection = nil
        self.resultHandler = nil
        self.stopTimer()
        self.isRunning = false
    }
    
    deinit
    {
        
    }
}

// MARK: - Private Methods -

@available(iOS 12.0, *)
private
extension Pinger
{
    private
    func preparePing()
    {
        let endpoint = NWEndpoint.hostPort(host: self.host, port: self.port)
        
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.stateUpdateHandler = {
            
            [weak self] state in
            
            guard let self = self else {
                
                return
            }
            
            switch state {
                
                case .ready:
                    self.resultHandler?(.start(self.hostName))
                    self.startPing()
                
                case let .failed(error):
                    self.resultHandler?(.conectFailed(self.hostName, error))
                
                default:
                    break
            }
        }
        
        connection.start(queue: .main)
        self.connection = connection
    }
    
    private
    func startPing(at sequence: Int = 0)
    {
        let content: Data? = "Ping".data(using: .utf8)
        let startTimeInterval: TimeInterval = Date().timeIntervalSince1970
        let completion = NWConnection.SendCompletion.contentProcessed {
            
            [weak self] error in
            
            guard let self = self else {
                
                return
            }
            
            if let error = error, self.timer != nil {
                
                self.resultHandler?(.pingFailed(self.hostName, error))
                return
            }
            
            let endTimeInterval = Date().timeIntervalSince1970
            let interval: TimeInterval = endTimeInterval - startTimeInterval
            
            self.resultHandler?(.ping(self.hostName, sequence, interval))
            self.startNextPing(at: sequence + 1)
        }
        
        self.connection?.send(content: content, completion: completion)
        self.stopTimer()
        self.timeoutTimer(at: sequence)
    }
    
    private
    func startNextPing(at sequence: Int)
    {
        let popTime: DispatchTime = DispatchTime.now() + 1.0
        let queue = DispatchQueue.main
        queue.asyncAfter(deadline: popTime, execute: {
            
            [weak self] in
            
            guard let self = self else {
                
                return
            }
            
            self.startPing(at: sequence)
        })
    }
    
    private
    func timeoutTimer(at sequence: Int)
    {
        let timer = Timer.scheduledTimer(timeInterval: self.timeoutInterval, target: self, selector: #selector(self.handlerTimeoutTimer(_:)), userInfo: sequence, repeats: false)
        
        self.timer = timer
    }
    
    @objc
    private
    func handlerTimeoutTimer(_ timer: Timer)
    {
        guard self.timer != nil,
                let sequence = timer.userInfo as? Int else {
            
            return
        }
        
        self.stop()
        self.resultHandler?(.timeout(self.hostName, sequence))
    }
    
    private
    func stopTimer()
    {
        self.timer?.invalidate()
        self.timer = nil
    }
}

// MARK: - Pinger.Result -

@available(iOS 12.0, *)
public
extension Pinger
{
    enum Result
    {
        case start(String/* hostName */)
        
        case ping(String/* hostName */, Int/* sequence */, TimeInterval/* ping time */)
        
        case timeout(String/* hostName */, Int/* sequence */)
        
        case pingFailed(String/* hostName */, Error)
        
        case conectFailed(String/* hostName */, Error)
        
        case stop(String/* hostName */)
    }
}

// MARK: - Private URL Extension -

private
extension URL
{
    var hostName: String? {
        
        if #available(iOS 16.0, *) {
            
            return self.host()
        }
        
        return self.host
    }
}
