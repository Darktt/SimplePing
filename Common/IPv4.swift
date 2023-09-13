/*
 * IPv4.swift
 * SimpleSwiftPing
 *
 * Created by François Lamboley on 13/06/2018.
 * Copyright © 2018 Frizlab. All rights reserved.
 */

import Foundation



/** Describes the on-the-wire header format for an IPv4 packet.

This defines the header structure of IPv4 packets on the wire. We need this in
order to skip this header in the IPv4 case, where the kernel passes it to us for
no obvious reason. */
public
struct IPv4Header
{
    // MARK: - Properties -
    
    public static
    let size = 20
    
    public let versionAndHeaderLength: UInt8
    
    public let differentiatedServices: UInt8
    
    public let totalLength: UInt16
    
    public let identification: UInt16
    
    public let flagsAndFragmentOffset: UInt16
    
    public let timeToLive: UInt8
    
    public let `protocol`: UInt8
    
    public let headerChecksum: UInt16
    
    public let sourceAddress: Address
    
    public let destinationAddress: Address
    
    // MARK: - Methods -
    // MARK: Initial Method
    
    /* data... */
    init(data: Data)
    {
        assert(data.count >= IPv4Header.size)
        
        var versionAndHeaderLengthI: UInt8 = 0
        var differentiatedServicesI: UInt8 = 0
        var totalLengthI: UInt16 = 0
        var identificationI: UInt16 = 0
        var flagsAndFragmentOffsetI: UInt16 = 0
        var timeToLiveI: UInt8 = 0
        var protocolI: UInt8 = 0
        var headerChecksumI: UInt16 = 0
        var sourceAddressI = Address()
        var destinationAddressI = Address()
        
        data.withUnsafeBytes {
            
            bufferPointer -> Void in
            
            guard var currentPositionUInt8 = bufferPointer.assumingMemoryBound(to: UInt8.self).baseAddress else {
                
                return
            }
            
            versionAndHeaderLengthI = currentPositionUInt8.pointee
            currentPositionUInt8 = currentPositionUInt8.advanced(by: 1)
            
            differentiatedServicesI = currentPositionUInt8.pointee
            currentPositionUInt8 = currentPositionUInt8.advanced(by: 1)
            
            var currentPositionUInt16 = UnsafePointer<UInt16>(OpaquePointer(currentPositionUInt8))
            totalLengthI = currentPositionUInt16.pointee
            currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
            
            identificationI = currentPositionUInt16.pointee
            currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
            
            flagsAndFragmentOffsetI = currentPositionUInt16.pointee
            currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
            
            currentPositionUInt8 = UnsafePointer<UInt8>(OpaquePointer(currentPositionUInt16))
            timeToLiveI = currentPositionUInt8.pointee
            currentPositionUInt8 = currentPositionUInt8.advanced(by: 1)
            
            protocolI = currentPositionUInt8.pointee
            currentPositionUInt8 = currentPositionUInt8.advanced(by: 1)
            
            currentPositionUInt16 = UnsafePointer<UInt16>(OpaquePointer(currentPositionUInt8))
            headerChecksumI = currentPositionUInt16.pointee; currentPositionUInt16 = currentPositionUInt16.advanced(by: 1)
            
            currentPositionUInt8 = UnsafePointer<UInt8>(OpaquePointer(currentPositionUInt16))
            sourceAddressI = Address(dataPointer: &currentPositionUInt8)
            destinationAddressI = Address(dataPointer: &currentPositionUInt8)
        }
        
        self.versionAndHeaderLength = versionAndHeaderLengthI
        self.differentiatedServices = differentiatedServicesI
        self.totalLength = totalLengthI
        self.identification = identificationI
        self.flagsAndFragmentOffset = flagsAndFragmentOffsetI
        self.timeToLive = timeToLiveI
        self.protocol = protocolI
        self.headerChecksum = headerChecksumI
        self.sourceAddress = sourceAddressI
        self.destinationAddress = destinationAddressI
    }
    
}

public extension IPv4Header
{
    struct Address
    {
        let byte1: UInt8
        let byte2: UInt8
        let byte3: UInt8
        let byte4: UInt8
        
        public
        init()
        {
            self.byte1 = 0
            self.byte2 = 0
            self.byte3 = 0
            self.byte4 = 0
        }
        
        public
        init(dataPointer: inout UnsafePointer<UInt8>)
        {
            self.byte1 = dataPointer.pointee
            dataPointer = dataPointer.advanced(by: 1)
            
            self.byte2 = dataPointer.pointee
            dataPointer = dataPointer.advanced(by: 1)
            
            self.byte3 = dataPointer.pointee
            dataPointer = dataPointer.advanced(by: 1)
            
            self.byte4 = dataPointer.pointee
            dataPointer = dataPointer.advanced(by: 1)
        }
    }
}
