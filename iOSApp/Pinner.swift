//
//  Pinner.swift
//  iOSApp
//
//  Created by Eden on 2023/9/18.
//

import Foundation
import Network

class Pinner
{
    let host: NWEndpoint.Host
    private let pathMonitor = NWPathMonitor()
    
    init(host: String) {
        self.host = NWEndpoint.Host(host)
    }
}
import Network

final class HostPinger {
    let host: NWEndpoint.Host
    private let pathMonitor = NWPathMonitor()
    
    init(host: String) {
        self.host = NWEndpoint.Host(host)
    }
    
    //...
}
