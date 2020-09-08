//
//  TranferSercive.swift
//  DemoBLE
//
//  Created by vu.thanh.long on 9/8/20.
//  Copyright © 2020 vu.thanh.long. All rights reserved.
//

import Foundation
import CoreBluetooth

struct TransferService {
    static let serviceUUID = CBUUID(string: "E20A39F4-73F5-4BC4-A12F-17D1AD07A961")
    static let characteristicUUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")
}
