//
//  CentralViewController.swift
//  DemoBLE
//
//  Created by vu.thanh.long on 9/8/20.
//  Copyright © 2020 vu.thanh.long. All rights reserved.
//

import UIKit
import CoreBluetooth

class CentralViewController: UIViewController {
    
    @IBOutlet var textView: UITextView!
    
    var centralManager: CBCentralManager!
    var discoveredPeripheral: CBPeripheral?
    var transferCharacteristic: CBCharacteristic?
    
    var data = Data()
    var writeIterationsComplete = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        centralManager = CBCentralManager(delegate: self,
                                          queue: nil,
                                          options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        data.removeAll(keepingCapacity: false)
        centralManager.stopScan()
    }
    
    private func retrievePeripheral() {
        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID])
        if let connectedPeripheral = connectedPeripherals.last {
            discoveredPeripheral = connectedPeripheral
            centralManager.connect(connectedPeripheral,
                                   options: nil)
        } else {
            centralManager.scanForPeripherals(withServices: [TransferService.serviceUUID],
                                              options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
    
    private func cleanUp() {
        guard let discoveredPeripheral = discoveredPeripheral,
            case .connected = discoveredPeripheral.state else { return }
        
        discoveredPeripheral.services?.forEach({ [weak self] service in
            service.characteristics?.forEach({ characteristic in
                if characteristic.uuid == TransferService.characteristicUUID,
                    characteristic.isNotifying {
                    self?.discoveredPeripheral?.setNotifyValue(false, for: characteristic)
                }
            })
        })
        
        centralManager.cancelPeripheralConnection(discoveredPeripheral)
    }
    
    private func writeData() {
        guard let discoveredPeripheral = discoveredPeripheral,
            let transferCharacteristic = transferCharacteristic else {
            return
        }
        
        while discoveredPeripheral.canSendWriteWithoutResponse {
            let mtu = discoveredPeripheral.maximumWriteValueLength (for: .withoutResponse)
            var rawPacket = [UInt8]()
            
            let bytesToCopy: size_t = min(mtu, data.count)
            data.copyBytes(to: &rawPacket, count: bytesToCopy)
            let packetData = Data(bytes: &rawPacket, count: bytesToCopy)
            discoveredPeripheral.writeValue(packetData, for: transferCharacteristic, type: .withoutResponse)
            writeIterationsComplete += 1
        }
        discoveredPeripheral.setNotifyValue(false, for: transferCharacteristic)
    }
}

// MARK: - CBCentralManagerDelegate
extension CentralViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("CBManager is powered on")
            retrievePeripheral()
        case .poweredOff:
            print("CBManager is not powered on")
        case .resetting:
            print("CBManager is resetting")
        case .unauthorized:
            if #available(iOS 13.0, *) {
                switch central.authorization {
                case .denied:
                    print("You are not authorized to use Bluetooth")
                case .restricted:
                    print("Bluetooth is restricted")
                default:
                    print("Unexpected authorization")
                }
            } else {
                // Fallback on earlier versions
            }
            return
        case .unknown:
            print("CBManager state is unknown")
            return
        case .unsupported:
            print("Bluetooth is not supported on this device")
            return
        @unknown default:
            print("A previously unknown central manager state occurred")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        guard RSSI.intValue >= -50 else { return }
        if discoveredPeripheral != peripheral {
            discoveredPeripheral = peripheral
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        cleanUp()
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        centralManager.stopScan()
        writeIterationsComplete = 0
        data.removeAll(keepingCapacity: false)
        peripheral.delegate = self
        peripheral.discoverServices([TransferService.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        discoveredPeripheral = nil
        retrievePeripheral()
    }
}

// MARK: - CBPeripheralDelegate
extension CentralViewController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            cleanUp()
            return
        }
        
        guard let peripheralServices = peripheral.services else { return }
        peripheralServices.forEach { service in
            peripheral.discoverCharacteristics([TransferService.characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        invalidatedServices.filter { $0.uuid == TransferService.serviceUUID }.forEach { service in
            peripheral.discoverServices([TransferService.serviceUUID])
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            cleanUp()
            return
        }
        
        guard let serviceCharacteristic = service.characteristics else { return }
        serviceCharacteristic.filter { $0.uuid == TransferService.characteristicUUID }.forEach { characteristic in
            transferCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            cleanUp()
            return
        }
        
        guard let characteristicData = characteristic.value,
            let stringFromData = String(data: characteristicData, encoding: .utf8) else { return }
        
        if stringFromData == "EOM" {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.textView.text = String(data: self.data, encoding: .utf8)
            }
            writeData()
        } else {
            data.append(characteristicData)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if error != nil {
            return
        }
        
        guard characteristic.uuid == TransferService.characteristicUUID else { return }
        
        if !characteristic.isNotifying {
            cleanUp()
        }
    }
    
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        writeData()
    }
}
