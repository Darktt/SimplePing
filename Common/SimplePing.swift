/*
 * SimplePing.swift
 * SimpleSwiftPing
 *
 * Created by François Lamboley on 12/06/2018.
 * Copyright © 2018 Frizlab. All rights reserved.
 */

import CFNetwork
import Foundation

public
class SimplePing
{
    // MARK: - Properties -
    
    public
    let hostName: String
    
    /** The IP address version to use. Should be set before starting the ping. */
    public
    var addressStyle: AddressStyle
    
    public
    weak var delegate: SimplePingDelegate?
    
    /** The identifier used by pings by this object.
     
     When you create an instance of this object it generates a random identifier
     that it uses to identify its own pings. */
    public
    let identifier: UInt16
    
    /** The address being pinged.
     
     The contents of the Data is a (struct sockaddr) of some form. The value is
     nil while the object is stopped and remains nil on start until
     `-simplePing:didStartWithAddress:` is called. */
    public private(set)
    var hostAddress: Data?
    
    /** The address family for `hostAddress`, or `AF_UNSPEC` if that’s nil. */
    public
    var hostAddressFamily: sa_family_t {
        
        guard let hostAddress: Data = self.hostAddress,
              hostAddress.count >= MemoryLayout<sockaddr>.size else {
            
            return sa_family_t(AF_UNSPEC)
        }
        
        let addressFamily: sa_family_t = hostAddress.withUnsafeBytes {
            
            buffterPointer in
            
            buffterPointer.load(as: sockaddr.self).sa_family
        }
        
        return addressFamily
    }
    
    /** The next sequence number to be used by this object.
     
     
     This value starts at zero and increments each time you send a ping (safely
     wrapping back to zero if necessary). The sequence number is included in the
     ping, allowing you to match up requests and responses, and thus calculate
     ping times and so on. */
    public private(set)
    var nextSequenceNumber: UInt16 = 0
    
    fileprivate
    var host: CFHost?
    
    fileprivate
    var sock: CFSocket?
    
    /** True if nextSequenceNumber has wrapped from 65535 to 0. */
    private
    var nextSequenceNumberHasWrapped = false
    
    // MARK: - Methods -
    // MARK: Initial Method
    
    /** Initialise the object to ping the specified host.
     
     - parameter hostName: The DNS name of the host to ping; an IPv4 or IPv6
     address in string form will work here.
     - returns: The initialised object. */
    public
    init(hostName: String, addressStyle: AddressStyle = .any)
    {
        self.hostName = hostName
        self.addressStyle = addressStyle
        self.identifier = UInt16.random(in: .min ... .max)
    }
    
    deinit
    {
        self.stop()
    }
    
    /** Starts the object.
     
     You should set up the delegate and any ping parameters before calling this.
     
     If things go well you'll soon get the `-simplePing:didStartWithAddress:`
     delegate callback, at which point you can start sending pings (via
     `-sendPingWithData:`) and will start receiving ICMP packets (either ping
     responses, via the `-simplePing:didReceivePingResponsePacket:sequenceNumber:`
     delegate callback, or unsolicited ICMP packets, via the
     `-simplePing:didReceiveUnexpectedPacket:` delegate callback).
     
     If the object fails to start, typically because `hostName` doesn't resolve,
     you'll get the `-simplePing:didFailWithError:` delegate callback.
     
     It is not correct to start an already started object. */
    public
    func start()
    {
        assert(self.host == nil)
        assert(self.hostAddress == nil)
        
        var context = CFHostClientContext(version: 0, info: unsafeBitCast(self, to: UnsafeMutableRawPointer.self), retain: nil, release: nil, copyDescription: nil)
        let host = CFHostCreateWithName(nil, self.hostName as CFString).autorelease().takeUnretainedValue()
        self.host = host
        
        CFHostSetClient(host, kHostResolveCallback, &context)
        
        CFHostScheduleWithRunLoop(host, CFRunLoopGetCurrent(), RunLoop.Mode.default.rawValue as CFString)
        
        var error = CFStreamError()
        if !CFHostStartInfoResolution(host, CFHostInfoType.addresses, &error) {
            
            self.didFail(hostStreamError: error)
        }
    }
    
    /** Sends a ping packet containing the specified data.
     
     The object must be started when you call this method and, on starting the
     object, you must wait for the `-simplePing:didStartWithAddress:` delegate
     callback before calling it.
     
     - parameter data: Some data to include in the ping packet, after the ICMP
     header, or nil if you want the packet to include a standard 56 byte payload
     (resulting in a standard 64 byte ping). */
    public
    func sendPing(data: Data?)
    {
        guard self.hostAddress != nil else {
            
            fatalError("Gotta wait for -simplePing:didStartWithAddress: before sending a ping")
        }
        
        /* *** Construct the ping packet. *** */
        
        /* Our dummy payload is sized so that the resulting ICMP packet, including
          * the ICMPHeader, is 64-bytes, which makes it easier to recognise our
          * packets on the wire. */
        let payload = data ?? String(format: "%28zd bottles of beer on the wall", 99 - (self.nextSequenceNumber % 100)).data(using: .ascii)!
        assert(data != nil || payload.count == 56)
        
        let packet: Data
        switch self.hostAddressFamily
        {
        case sa_family_t(AF_INET):
            packet = self.pingPacket(type: ICMPv4TypeEcho.request.rawValue, payload: payload, requiresChecksum: true)
            
        case sa_family_t(AF_INET6):
            packet = self.pingPacket(type: ICMPv6TypeEcho.request.rawValue, payload: payload, requiresChecksum: true)
            
        default:
            fatalError()
        }
        
        /* *** Send the packet. *** */
        
        var err: Int32 = EBADF
        var bytesSent: Int = -1
        if let socket = self.sock {
            
            bytesSent = packet.withUnsafeBytes {
                
                bufferPointer in
                
                let sockaddr: UnsafePointer<sockaddr>? = bufferPointer.assumingMemoryBound(to: sockaddr.self).baseAddress
                let result: Int = sendto(CFSocketGetNative(socket), bufferPointer.baseAddress, packet.count, 0, sockaddr, socklen_t(bufferPointer.count))
                
                return result
            }
            
            err = (bytesSent >= 0) ? 0 : errno
        }
        
        /* *** Handle the results of the send. *** */
        
        if bytesSent > 0 && bytesSent == packet.count {
            
            /* Complete success. Tell the client. */
            self.delegate?.simplePing(self, didSendPacket: packet, sequenceNumber: self.nextSequenceNumber)
        } else {
            
            /* Some sort of failure. Tell the client. */
            let error = NSError(domain: NSPOSIXErrorDomain, code: Int(err != 0 ? err : ENOBUFS), userInfo: nil)
            self.delegate?.simplePing(self, didFailToSendPacket: packet, sequenceNumber: self.nextSequenceNumber, error: error)
        }
        
        // add value and avoid overflow.
        self.nextSequenceNumber &+= 1
        if self.nextSequenceNumber == 0 {
            self.nextSequenceNumberHasWrapped = true
        }
    }
    
    /** Stops the object.
     
     You should call this when you're done pinging.
     It is safe to call this on an object that's stopped. */
    public
    func stop()
    {
        self.stopHostResolution()
        self.stopSocket()
        
        /* Junk the host address on stop. If the client calls -start again, we’ll
          * re-resolve the host name. */
        self.hostAddress = nil
    }
}

// MARK: - Private Methods -
private
extension SimplePing
{
    /** Returns the **big-endian representation** of the checksum of the packet. */
    static
    func packetChecksum(packetData: Data) -> UInt16
    {
        var sum: Int32 = 0
        var packetData: Data = packetData
        
        /* Mop up an odd byte, if necessary */
        if packetData.count % 2 == 1 {
            packetData += Data(count: 1)
        }
        
        /* Our algorithm is simple, using a 32 bit accumulator (sum), we
         * add sequential 16 bit words to it, and at the end, fold back all the
         * carry bits from the top 16 bits into the lower 16 bits. */
        packetData.withUnsafeBytes {
            
            bufferPointer in
            
            assert(packetData.count % 2 == 0)
            var position: UInt16 = bufferPointer.load(as: UInt16.self)
            (0 ..< packetData.count / 2).forEach {
                
                if $0 != ICMPHeader.checksumDelta / 2 {
                    
                    sum &+= Int32(position)
                }
                position += 1
            }
        }
        
        /* Add back carry outs from top 16 bits to low 16 bits */
        sum = (sum >> 16) &+ (sum & 0xffff)              /* add hi 16 to low 16 */
        sum &+= (sum >> 16)                              /* add carry */
        let answer = UInt16(truncating: NSNumber(value: ~sum)) /* truncate to 16 bits */
        
        return answer
    }
    
    /** Calculates the offset of the ICMP header within an IPv4 packet.
    
    In the IPv4 case the kernel returns us a buffer that includes the IPv4
    header. We're not interested in that, so we have to skip over it. This code
    does a rough check of the IPv4 header and, if it looks OK, returns the offset
    of the ICMP header.
    
    - parameter packet: The IPv4 packet, as returned to us by the kernel.
    - returns: The offset of the ICMP header, or nil. */
    static func icmpHeaderOffset(in ipv4Packet: Data) -> Int?
    {
        guard ipv4Packet.count >= IPv4Header.size + ICMPHeader.size else {
            
            return nil
        }
        
        let ipv4Header = IPv4Header(data: ipv4Packet)
        
        if ipv4Header.versionAndHeaderLength & 0xF0 == 0x40 /* IPv4 */ && Int32(ipv4Header.protocol) == IPPROTO_ICMP {
            
            let ipHeaderLength = Int(ipv4Header.versionAndHeaderLength & 0x0F) * MemoryLayout<UInt32>.size
            
            if ipv4Packet.count >= (ipHeaderLength + ICMPHeader.size) {
                
                return ipHeaderLength
            }
        }
        
        return nil
    }
    
    func didFail(error: Error)
    {
        self.delegate?.simplePing(self, didFail: error)
        
        /* Below is more or less the direct translation from ObjC to Swift of the
         * original project. I simplified a bit as I think most of the protections
         * are not needed anymore.
        
        --------------
        
        /* We retain ourselves temporarily because it's common for the delegate
         * method to release its last reference to us, which causes -dealloc to be
         * called here.
         * If we then reference self on the return path, things go badly. I don't
         * think that happens currently, but I've got into the habit of doing this
         * as a defensive measure. */
        let strongSelf = self
        let strongDelegate = strongSelf.delegate
        
        strongSelf.stop()
        strongDelegate?.simplePing(self, didFail: error) */
    }
    
    func didFail(hostStreamError streamError: CFStreamError)
    {
        let userInfo: [String: Any]?
        
        switch streamError.domain
        {
            case CFIndex(kCFStreamErrorDomainNetDB):
                userInfo = [kCFGetAddrInfoFailureKey as String: streamError.error]
            
            default:
                userInfo = nil
        }
        
        self.didFail(error: NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorUnknown.rawValue), userInfo: userInfo))
    }
    
    func pingPacket(type: UInt8, payload: Data, requiresChecksum: Bool) -> Data
    {
        let header = ICMPHeader(
            type: type,
            code: 0,
            checksum: 0,
            identifier: self.identifier,
            sequenceNumber: self.nextSequenceNumber
        )
        
        var packet: Data = header.headerBytes + payload
        if requiresChecksum {
            /* The IP checksum routine returns a 16-bit number that's already in
             * correct byte order (due to wacky 1's complement maths), so we just
             * put it into the packet as a 16-bit unit. */
            let checksumBig: UInt16 = SimplePing.packetChecksum(packetData: packet)
            packet.withUnsafeMutableBytes {
                
                bufferPointer in
                
                bufferPointer.storeBytes(of: checksumBig, toByteOffset: ICMPHeader.checksumDelta, as: UInt16.self)
            }
        }
        
        return packet
    }
    
    /** Checks whether the specified sequence number is one we sent.
    
    - parameter sequenceNumber: The incoming sequence number.
    - returns: `true` if the sequence number looks like one we sent. */
    func validateSequenceNumber(_ sequenceNumber: UInt16) -> Bool
    {
        guard self.nextSequenceNumberHasWrapped else {
            
            return sequenceNumber < self.nextSequenceNumber
        }
        
        /* If the sequence numbers have wrapped that we can't reliably check
         * whether this is a sequence number we sent.  Rather, we check to see
         * whether the sequence number is within the last 120 sequence numbers
         * we sent. Note that the UInt16 subtraction here does the right thing
         * regardless of the wrapping.
         *
         * Why 120? Well, if we send one ping per second, 120 is 2 minutes,
         * which is the standard “max time a packet can bounce around the
         * Internet” value. */
        return (self.nextSequenceNumber &- sequenceNumber) < 120
    }
    
    /** Checks whether an incoming IPv4 packet looks like a ping response.
    
    This routine can modify the `packet` data. If the packet is validated, it
    removes the IPv4 header from the front of the packet.
    
    - parameter packet: The IPv4 packet, as returned to us by the kernel.
    - parameter sequenceNumber: A pointer to a place to start the ICMP sequence
    number.
    - returns: true if the packet looks like a reasonable IPv4 ping response. */
    func validatePing4ResponsePacket(_ packet: inout Data, sequenceNumber: inout UInt16) -> Bool
    {
        guard let icmpHeaderOffset = SimplePing.icmpHeaderOffset(in: packet) else {
            
            return false
        }
        
        /* Note: We crash when we don’t copy the slice content; not sure why… (Xcode 10.0 beta (10L176w)) */
        let icmpPacket = Data(packet[icmpHeaderOffset...])
        let icmpHeader = ICMPHeader(data: icmpPacket)
        
        let receivedChecksum = icmpHeader.checksum
        /* The checksum method returns a big-endian UInt16 */
        let calculatedChecksum = UInt16(bigEndian: SimplePing.packetChecksum(packetData: icmpPacket))
        var checkSuccess: Bool = (receivedChecksum == calculatedChecksum)
        checkSuccess = checkSuccess && (icmpHeader.type == ICMPv4TypeEcho.reply.rawValue)
        checkSuccess = checkSuccess && (icmpHeader.code == 0)
        checkSuccess = checkSuccess && (icmpHeader.identifier == self.identifier)
        checkSuccess = checkSuccess && self.validateSequenceNumber(icmpHeader.sequenceNumber)
        
        if !checkSuccess {
            
            return false
        }
        
        /* Remove the IPv4 header off the front of the data we received, leaving
         * us with just the ICMP header and the ping payload. */
        packet = icmpPacket
        sequenceNumber = icmpHeader.sequenceNumber
        
        return true
    }
    
    /** Checks whether an incoming IPv6 packet looks like a ping response.
    
    - parameter packet: The IPv6 packet, as returned to us by the kernel; note
    that this routine could modify this data but does not need to in the IPv6
    case.
    - parameter sequenceNumber: A pointer to a place to start the ICMP sequence
    number.
    - returns: true if the packet looks like a reasonable IPv4 ping response. */
    func validatePing6ResponsePacket(_ packet: inout Data, sequenceNumber: inout UInt16) -> Bool
    {
        guard packet.count >= ICMPHeader.size else {
            
            return false
        }
        
        let icmpHeader = ICMPHeader(data: packet)
        
        /* In the IPv6 case we don't check the checksum because that’s hard (we
         * need to cook up an IPv6 pseudo header and we don’t have the
         * ingredients) and unnecessary (the kernel has already done this check). */
        var checkSuccess: Bool = (icmpHeader.type == ICMPv6TypeEcho.reply.rawValue)
        checkSuccess = checkSuccess && (icmpHeader.code == 0)
        checkSuccess = checkSuccess && (icmpHeader.identifier == identifier)
        checkSuccess = checkSuccess && (self.validateSequenceNumber(icmpHeader.sequenceNumber))
        
        if !checkSuccess {
            
            return false
        }
        
        sequenceNumber = icmpHeader.sequenceNumber
        
        return true
    }
    
    /** Checks whether an incoming packet looks like a ping response.
    
    - parameter packet: The packet, as returned to us by the kernel; note that
    we may end up modifying this data.
    - parameter sequenceNumber: A pointer to a place to start the ICMP sequence
    number.
    - returns: true if the packet looks like a reasonable IPv4 ping response. */
    func validatePingResponsePacket(_ packet: inout Data, sequenceNumber: inout UInt16) -> Bool
    {
        switch self.hostAddressFamily
        {
            case sa_family_t(AF_INET):
                return self.validatePing4ResponsePacket(&packet, sequenceNumber: &sequenceNumber)
            
            case sa_family_t(AF_INET6):
                return self.validatePing6ResponsePacket(&packet, sequenceNumber: &sequenceNumber)
            
            default: fatalError()
        }
    }
    
    /** Reads data from the ICMP socket.
    
    Called by the socket handling code (SocketReadCallback) to process an ICMP
    message waiting on the socket. */
    func readData()
    {
        /* 65535 is the maximum IP packet size, which seems like a reasonable bound
         * here (plus it's what <x-man-page://8/ping> uses). */
        let bufferSize = 65535
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 0 /* We don’t need a specific alignment AFAICT */)
        
        defer {
            
            buffer.deallocate()
        }
        
        /* Actually read the data. We use recvfrom(), and thus get back the source
         * address, but we don’t actually do anything with it. It would be trivial
         * to pass it to the delegate but we don’t need it in this example. */
        let err: Int32
        var addr = sockaddr_storage()
        var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let bytesRead = withUnsafeMutablePointer(to: &addr) {
            
            (addrStoragePtr: UnsafeMutablePointer<sockaddr_storage>) -> Int in
            
            let addrPtr = UnsafeMutablePointer<sockaddr>(OpaquePointer(addrStoragePtr))
            let bytesRead: Int = recvfrom(CFSocketGetNative(sock), buffer, bufferSize, 0 /* flags */, addrPtr, &addrLen)
            
            return bytesRead
        }
        
        err = (bytesRead >= 0) ? 0 : errno
        
        /* *** Process the data we read. *** */
        
        if bytesRead > 0 {
            /* We got some data, pass it up to our client. */
            var sequenceNumber = UInt16(0)
            var packet = Data(bytes: buffer, count: bytesRead)
            
            if self.validatePingResponsePacket(&packet, sequenceNumber: &sequenceNumber) {
                self.delegate?.simplePing(self, didReceivePingResponsePacket: packet, sequenceNumber: sequenceNumber)
            } else {
                self.delegate?.simplePing(self, didReceiveUnexpectedPacket: packet)
            }
        } else {
            /* Error reading from the socket. We shut everything down. */
            self.didFail(error: NSError(domain: NSPOSIXErrorDomain, code: Int(err != 0 ? err : EPIPE), userInfo: nil))
        }
        
        /* Note that we don't loop back trying to read more data. Rather, we just
         * let CFSocket call us again. */
    }
    
    /** Starts the send and receive infrastructure.
    
    This is called once we've successfully resolved `hostName` in to
    `hostAddress`. It is responsible for setting up the socket for sending and
    receiving pings. */
    func startWithHostAddress()
    {
        /* *** Open the socket. *** */
        let socketHandler: CFSocketNativeHandle
        let err: Int32
        
        switch self.hostAddressFamily
        {
            case sa_family_t(AF_INET):
                socketHandler = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
                err = (socketHandler >= 0) ? 0 : errno
            
            case sa_family_t(AF_INET6):
                socketHandler = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)
                err = (socketHandler >= 0) ? 0 : errno
                
            default:
                socketHandler = -1
                err = EPROTONOSUPPORT
        }
        
        guard err == 0 else {
            
            self.didFail(error: NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: nil))
            return
        }
        
        /* *** Wrap it in a CFSocket and schedule it on the runloop. *** */
        var context = CFSocketContext(version: 0, info: unsafeBitCast(self, to: UnsafeMutableRawPointer.self), retain: nil, release: nil, copyDescription: nil)
        let socket: CFSocket = CFSocketCreateWithNative(nil, socketHandler, CFSocketCallBackType.readCallBack.rawValue, kSocketReadCallback, &context)
        self.sock = socket
        assert(self.sock != nil)
        
        /* *** The socket will now take care of cleaning up our file descriptor. *** */
        assert(CFSocketGetSocketFlags(self.sock) & kCFSocketCloseOnInvalidate != 0)
        let rls = CFSocketCreateRunLoopSource(nil, self.sock, 0)
        assert(rls != nil)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, CFRunLoopMode.defaultMode)
        self.delegate?.simplePing(self, didStart: hostAddress!)
    }
    
    /** Processes the results of our name-to-address resolution.
    
    Called by our CFHost resolution callback (HostResolveCallback) when host
    resolution is complete. We just latch the first appropriate address and kick
    off the send and receive infrastructure. */
    func hostResolutionDone()
    {
        /* *** Find the first appropriate address. *** */
        var _resolved: DarwinBoolean = false
        let addresses = CFHostGetAddressing(self.host!, &_resolved)?.retain().autorelease()
        var resolved: Bool = _resolved.boolValue
        
        if resolved, let addresses = addresses?.takeUnretainedValue() as? [Data] {
            
            resolved = false
            
            for address in addresses {
                
                assert(self.hostAddress == nil)
                
                guard address.count >= MemoryLayout<sockaddr>.size else {
                    
                    continue
                }
                
                address.withUnsafeBytes {
                    
                    bufferPointer in
                    
                    let sockaddr = bufferPointer.load(as: sockaddr.self)
                    
                    switch (sockaddr.sa_family, addressStyle)
                    {
                        case (sa_family_t(AF_INET),  .any), (sa_family_t(AF_INET),  .icmpV4):
                            self.hostAddress = address
                            resolved = true
                        
                        case (sa_family_t(AF_INET6), .any), (sa_family_t(AF_INET6), .icmpV6):
                            self.hostAddress = address
                            resolved = true
                        
                        default:
                            ()
                    }
                }
                
                if resolved {
                    
                    break
                }
            }
        }
        
        /* *** We’re done resolving, so shut that down. *** */
        
        self.stopHostResolution()
        
        /* *** If all is OK, start the send and receive infrastructure, otherwise stop. *** */
        
        if resolved {
            
            assert(hostAddress != nil)
            self.startWithHostAddress()
            
        } else {
            
            self.didFail(error: NSError(domain: kCFErrorDomainCFNetwork as String, code: Int(CFNetworkErrors.cfHostErrorHostNotFound.rawValue), userInfo: nil))
        }
    }
    
    /** Stops the name-to-address resolution infrastructure. */
    func stopHostResolution()
    {
        /* Shut down the CFHost. */
        guard let host = self.host else {
            
            return
        }
        
        self.host = nil
        CFHostSetClient(host, nil, nil)
        CFHostUnscheduleFromRunLoop(host, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }
    
    /** Stops the send and receive infrastructure. */
    func stopSocket()
    {
        guard let socket = sock else {
            
            return
        }
        
        self.sock = nil
        CFSocketInvalidate(socket)
    }
}

// MARK: -

public
extension SimplePing
{
    enum AddressStyle {
        
        /* Use the first IPv4 or IPv6 address found (default). */
        case any
        
        /* Use the first IPv4 address found. */
        case icmpV4
        
        /* Use the first IPv6 address found. */
        case icmpV6
    }
}

/** The callback for our CFSocket object.

This simply routes the call to our `-readData` method.

- parameter s: See the documentation for CFSocketCallBack.
- parameter type: See the documentation for CFSocketCallBack.
- parameter address: See the documentation for CFSocketCallBack.
- parameter data: See the documentation for CFSocketCallBack.
- parameter info: See the documentation for CFSocketCallBack; this is actually a
pointer to the 'owning' object. */
private
func kSocketReadCallback(s: CFSocket?, type: CFSocketCallBackType, address: CFData?, data: UnsafeRawPointer?, info: UnsafeMutableRawPointer?) -> Void
{
    /* This C routine is called by CFSocket when there's data waiting on our ICMP
     * socket. It just redirects the call to Swift code. */
    let obj = unsafeBitCast(info, to: SimplePing.self)
    
    assert(obj.sock === s)
    assert(type == CFSocketCallBackType.readCallBack)
    assert(address == nil)
    assert(data == nil)
    
    obj.readData()
}

/** The callback for our CFHost object.

This simply routes the call to our `-hostResolutionDone` or
`-didFailWithHostStreamError:` methods.

- parameter theHost: See the documentation for CFHostClientCallBack.
- parameter typeInfo: See the documentation for CFHostClientCallBack.
- parameter error: See the documentation for CFHostClientCallBack.
- parameter info: See the documentation for CFHostClientCallBack; this is
actually a pointer to the 'owning' object. */
private
func kHostResolveCallback(theHost: CFHost, typeInfo: CFHostInfoType, error: UnsafePointer<CFStreamError>?, info: UnsafeMutableRawPointer?) -> Void
{
    /* This C routine is called by CFHost when the host resolution is complete.
     * It just redirects the call to the appropriate Swift method. */
    let obj = unsafeBitCast(info, to: SimplePing.self)
    
    assert(obj.host === theHost)
    assert(typeInfo == CFHostInfoType.addresses)
    
    if let error = error, error.pointee.domain != 0 {
        
        obj.didFail(hostStreamError: error.pointee)
    } else {
        
        obj.hostResolutionDone()
    }
}
