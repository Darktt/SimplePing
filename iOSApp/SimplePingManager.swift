//
//  SimplePingManager.swift
//  iOSApp
//
//  Created by Robert Ryan on 4/4/20.
//

import Foundation
import Combine

public
enum SimplePingResponse
{
    case start(String)
    
    case sendFailed(Data, UInt16, Error)
    
    case sent(Data, UInt16)
    
    case received(Data, UInt16, TimeInterval)
    
    case unexpectedPacket(Data)
    
    case failed(Error)
}

public
class SimplePingManager: NSObject
{
    // MARK: - Properties -
    
    public
    typealias SimplePingHandler = (SimplePingResponse) -> Void
    
    private
    var pinger: SimplePing?
    
    private
    var handler: SimplePingHandler?
    
    private
    weak var sendTimer: Timer?
    
    public
    var isStarted: Bool {
        
        self.pinger != nil
    }
    
    private
    var nextSequenceNumber: Int? {
        
        (self.pinger?.nextSequenceNumber).flatMap(Int.init)
    }
    
    private
    var waitingResponseMap: Dictionary<UInt16, Date> = [:]
    
    // MARK: - Methods -
    // MARK: Initial Method
    
    deinit
    {
        self.stop()
    }
}

// MARK: Public interface

extension SimplePingManager
{
    /// Called by the table view selection delegate callback to start the ping.
    func start(hostName: String, addressStyle: SimplePingAddressStyle = .any, handler: @escaping SimplePingHandler)
    {
        guard !self.isStarted else {
            
            return
        }
        
        self.handler = handler
        self.pinger = SimplePing(hostName: hostName)
        self.pinger?.addressStyle = addressStyle
        self.pinger?.delegate = self
        self.pinger?.start()
    }
    
    /// Called by the table view selection delegate callback to stop the ping.
    func stop()
    {
        self.pinger?.stop()
        self.pinger = nil
        self.sendTimer?.invalidate()
        self.sendTimer = nil
        self.handler = nil
    }
}

// MARK: - private utility methods

private
extension SimplePingManager
{
    /// Sends a ping.
    ///
    /// Called to send a ping, both directly (as soon as the SGSimplePing object starts up).
    func sendPing()
    {
        guard self.pinger?.hostAddress != nil else {
            
            return
        }
        
        self.pinger?.sendPing(data: nil)
    }
    
    func sendNextPing()
    {
        self.sendTimer?.invalidate()
        self.sendTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {
            
            [weak self] timer in
            
            guard timer.isValid, let self = self else {
                
                timer.invalidate()
                return
            }
            
            self.sendPing()
        }
    }
    
    /// Returns the string representation of the supplied address.
    ///
    /// - parameter address: Contains a `(struct sockaddr)` with the address to render.
    ///
    /// - returns: A string representation of that address.
    
    func stringRepresentation(forAddress address: Data) -> String
    {
        var hostStr = [Int8](repeating: 0, count: Int(NI_MAXHOST))
        
        let result = address.withUnsafeBytes {
            
            pointer in
            
            getnameinfo(
                
                pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                socklen_t(address.count),
                &hostStr,
                socklen_t(hostStr.count),
                nil,
                0,
                NI_NUMERICHOST
            )
        }
        return result == 0 ? String(cString: hostStr) : "?"
    }
    
    /// Returns a short error string for the supplied error.
    ///
    /// - parameter error: The error to render.
    ///
    /// - returns: A short string representing that error.
    
    func shortErrorFromError(error: Error) -> String
    {
        let error = error as NSError
        var checkErrorType: Bool = (error.domain == kCFErrorDomainCFNetwork as String)
        checkErrorType = checkErrorType && (error.code == Int(CFNetworkErrors.cfHostErrorUnknown.rawValue))
        
        guard checkErrorType else {
            
            return error.localizedDescription
        }
        
        if let failureValue = error.userInfo[kCFGetAddrInfoFailureKey as String] as? Int,
           failureValue != 0,
           let f = gai_strerror(Int32(failureValue)) {
            
            return String(cString: f)
        }
        
        if let result = error.localizedFailureReason {
            
            return result
        }
        
        return error.localizedDescription
    }
}

// MARK: pinger delegate callback

extension SimplePingManager: SimplePingDelegate
{
    public
    func simplePing(_ pinger: SimplePing, didStart address: Data)
    {
        self.waitingResponseMap.removeAll()
        self.handler?(.start(stringRepresentation(forAddress: address)))
        self.sendPing()
    }
    
    public
    func simplePing(_ pinger: SimplePing, didFail error: Error)
    {
        self.waitingResponseMap.removeAll()
        self.handler?(.failed(error))
        self.stop()
    }
    
    public
    func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16)
    {
        self.waitingResponseMap[sequenceNumber] = Date()
        self.handler?(.sent(packet, sequenceNumber))
    }
    
    public
    func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error)
    {
        self.waitingResponseMap[sequenceNumber] = nil
        self.handler?(.sendFailed(packet, sequenceNumber, error))
        self.sendNextPing()
    }
    
    public
    func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16)
    {
        guard let date = self.waitingResponseMap[sequenceNumber] else {
            
            return
        }
        
        let interval: TimeInterval = Date().timeIntervalSince(date)
        self.waitingResponseMap[sequenceNumber] = nil
        self.handler?(.received(packet, sequenceNumber, interval))
        self.sendNextPing()
    }
    
    public
    func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data)
    {
        self.handler?(.unexpectedPacket(packet))
    }
}

// MARK: - SimplePingSubscription -

@available(iOS 13.0, *)
public
class SimplePingSubscription<SubscriberType: Subscriber>: Subscription where SubscriberType.Input == SimplePingResponse, SubscriberType.Failure == Error
{
    // MARK: - Properties -
    
    private
    var subscriber: SubscriberType?
    
    private
    var manager = SimplePingManager()
    
    // MARK: - Methods -
    // MARK: Initial Method
    
    public
    init(subscriber: SubscriberType, hostName: String, addressStyle: SimplePingAddressStyle = .any)
    {
        self.subscriber = subscriber
        self.manager.start(hostName: hostName, addressStyle: addressStyle) {
            
            response in
            
            if case let .failed(error) = response {
                
                subscriber.receive(completion: .failure(error))
                return
            }
            
            _ = subscriber.receive(response)
        }
    }
    
    public
    func request(_ demand: Subscribers.Demand)
    {
        // We do nothing here as we only want to send events when they occur.
        // See, for more info: https://developer.apple.com/documentation/combine/subscribers/demand
    }
    
    public
    func cancel()
    {
        self.subscriber = nil
        self.manager.stop()
    }
}

// MARK: - SimplePingPublisher -

@available(iOS 13.0, *)
public
struct SimplePingPublisher: Publisher
{
    // MARK: - Properties -
    
    public
    typealias Output = SimplePingResponse
    
    public
    typealias Failure = Error
    
    public
    let hostName: String
    
    public
    let addressStyle: SimplePingAddressStyle
    
    // MARK: - Methods -
    // MARK: Initial Method
    
    public
    init(hostName: String, addressStyle: SimplePingAddressStyle = .any)
    {
        self.hostName = hostName
        self.addressStyle = .any
    }
    
    public
    func receive<S>(subscriber: S) where S : Subscriber, S.Failure == Failure, S.Input == Output
    {
        let subscription = SimplePingSubscription(subscriber: subscriber, hostName: self.hostName, addressStyle: self.addressStyle)
        subscriber.receive(subscription: subscription)
    }
}
