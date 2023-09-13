/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 A view controller for testing SimplePing on iOS.
 */

import UIKit

class MainViewController: UITableViewController {
    let hostName = "www.apple.com"
    
    let pingManager = SimplePingManager()
    
    @IBOutlet var forceIPv4Cell: UITableViewCell!
    @IBOutlet var forceIPv6Cell: UITableViewCell!
    @IBOutlet var startStopCell: UITableViewCell!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = hostName
    }
}

// MARK: UITableViewDelegate

extension MainViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)!
        
        switch cell {
        case forceIPv4Cell, forceIPv6Cell:
            cell.accessoryType = cell.accessoryType == .none ? .checkmark : .none
            
        case startStopCell:
            if pingManager.isStarted {
                stop()
            } else {
                let forceIPv4: Bool = forceIPv4Cell.accessoryType != .none
                let forceIPv6: Bool = forceIPv6Cell.accessoryType != .none
                
                let address: SimplePing.AddressStyle = {
                    
                    let address: SimplePing.AddressStyle
                    
                    switch (forceIPv4, forceIPv6)
                    {
                        case (true, false):
                            address = .icmpV4
                        
                        case (false, true):
                            address = .icmpV6
                        
                        default:
                        address = .any
                    }
                    
                    return address
                }()
                
                self.start(addressStyle: address)
            }
            
        default:
            fatalError()
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Private utility methods

private extension MainViewController {
    /// Called by the table view selection delegate callback to start the ping.
    
    func start(addressStyle: SimplePing.AddressStyle) {
        pingerWillStart()
        
        pingManager.start(hostName: self.hostName, addressStyle: addressStyle) {
            
            result in
            
            print(result)
        }
    }
    
    /// Called by the table view selection delegate callback to stop the ping.
    
    func stop() {
        pingManager.stop()
        pingerDidStop()
    }
    
    func pingerWillStart() {
        startStopCell.textLabel!.text = "Stop…"
    }
    
    func pingerDidStop() {
        startStopCell.textLabel!.text = "Start…"
    }
}
