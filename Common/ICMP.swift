/*
 * ICMP.swift
 * SimpleSwiftPing
 *
 * Created by François Lamboley on 13/06/2018.
 * Copyright © 2018 Frizlab. All rights reserved.
 */

import Foundation

public
enum ICMPv4TypeEcho : UInt8
{
    /** The ICMP `type` for a ping request; in this case `code` is always 0. */
    case request = 8
    /** The ICMP `type` for a ping response; in this case `code` is always 0. */
    case reply   = 0
    
}

public
enum ICMPv6TypeEcho : UInt8
{
    /** The ICMP `type` for a ping request; in this case `code` is always 0. */
    case request = 128
    /** The ICMP `type` for a ping response; in this case `code` is always 0. */
    case reply   = 129
    
}

/* If we could force C-based struct layout, this would be the struct definition
 * we would have for an ICMP header. With the current state of Swift, this is
 * **not** possible. Do **NOT** dump the ICMPHeader struct on the wire expecting
 * things to go great! They might, but we have no guarantee they will…
 *
 * Because we won't/can't dump the struct on the wire, all of the values have
 * the endianness of the host. The conversion is done directly when initing the
 * struct from the data or retrieving the header data. */
public struct ICMPHeader
{
    // MARK: - Properties -
    
    public static
    let size = 8
    
    public static
    let checksumDelta = 2
    
    public
    var type: UInt8 {
        
        didSet {
            
            self.headerBytes[0] = type
        }
    }
    
    public
    var code: UInt8 {
        
        didSet {
            
            self.headerBytes[1] = type
        }
    }
    
    public
    var checksum: UInt16 {
        
        didSet {
            
            self.headerBytes[2...].withUnsafeMutableBytes {
                
                bufferPointer in
                
                bufferPointer.storeBytes(of: self.checksum.bigEndian, as: UInt16.self)
            }
        }
    }
    
    public
    var identifier: UInt16 {
        
        didSet {
            
            self.headerBytes[4...].withUnsafeMutableBytes {
                
                bufferPointer in
                
                bufferPointer.storeBytes(of: self.identifier.bigEndian, as: UInt16.self)
            }
        }
    }
    
    public
    var sequenceNumber: UInt16 {
        
        didSet {
            
            self.headerBytes[6...].withUnsafeMutableBytes {
                
                bufferPointer in
                
                bufferPointer.storeBytes(of: self.sequenceNumber.bigEndian, as: UInt16.self)
            }
        }
    }
    /* data... */
    
    public private(set)
    var headerBytes: Data
    
    // MARK: - Methods -
    // MARK: Initial Method
    
    public init(type t: UInt8, code c: UInt8, checksum chk: UInt16, identifier i: UInt16, sequenceNumber n: UInt16)
    {
        self.type = t
        self.code = c
        self.checksum = chk
        self.identifier = i
        self.sequenceNumber = n
        
        self.headerBytes = Data(count: ICMPHeader.size)
        self.headerBytes.withUnsafeMutableBytes {
            
            bufferPointer in
            
            guard var currentPositionUInt8 = bufferPointer.assumingMemoryBound(to: UInt8.self).baseAddress else {
                
                return
            }
            
            currentPositionUInt8.pointee = type
            currentPositionUInt8 = currentPositionUInt8.advanced(by: 1)
            currentPositionUInt8.pointee = code
            currentPositionUInt8 = currentPositionUInt8.advanced(by: 1)
            
            var currentPositionUInt16 = UnsafeMutablePointer<UInt16>(OpaquePointer(currentPositionUInt8))
            currentPositionUInt16.pointee = checksum.bigEndian; currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
            currentPositionUInt16.pointee = identifier.bigEndian; currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
            currentPositionUInt16.pointee = sequenceNumber.bigEndian; currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
        }
    }
    
    public init(data: Data)
    {
        assert(data.count >= ICMPHeader.size)
        
        var typeI: UInt8 = 0
        var codeI: UInt8 = 0
        var checksumI: UInt16 = 0
        var identifierI: UInt16 = 0
        var sequenceNumberI: UInt16 = 0
        
        data.withUnsafeBytes {
            
            bufferPointer in
            
            guard var currentPositionUInt8 = bufferPointer.assumingMemoryBound(to: UInt8.self).baseAddress else {
                
                return
            }
            
            typeI = currentPositionUInt8.pointee
            currentPositionUInt8 = currentPositionUInt8.advanced(by: 1)
           
            codeI = currentPositionUInt8.pointee
            currentPositionUInt8 = currentPositionUInt8.advanced(by: 1)
            
            /* Note: UInt16(bigEndian:) <=> CFSwapInt16BigToHost() */
            var currentPositionUInt16 = UnsafePointer<UInt16>(OpaquePointer(currentPositionUInt8))
            
            checksumI = UInt16(bigEndian: currentPositionUInt16.pointee)
            currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
            
            identifierI = UInt16(bigEndian: currentPositionUInt16.pointee)
            currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
            
            sequenceNumberI = UInt16(bigEndian: currentPositionUInt16.pointee)
            currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
        }
        self.type = typeI
        self.code = codeI
        self.checksum = checksumI
        self.identifier = identifierI
        self.sequenceNumber = sequenceNumberI
        self.headerBytes = Data(data[..<ICMPHeader.size])
    }
    
}
