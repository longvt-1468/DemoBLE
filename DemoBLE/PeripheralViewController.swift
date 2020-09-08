//
//  PeripheralViewController.swift
//  DemoBLE
//
//  Created by vu.thanh.long on 9/8/20.
//  Copyright © 2020 vu.thanh.long. All rights reserved.
//

import UIKit
import CoreBluetooth

class PeripheralViewController: UIViewController {
    
    @IBOutlet var textView: UITextView!
    @IBOutlet weak var advertisingSwitch: UISwitch!
    
    var peripheralManager: CBPeripheralManager!
    var connectedCentral: CBCentral?
    var transferCharacteristic: CBMutableCharacteristic?
    
    var dataToSend = Data()
    var sendDataIndex = 0
    
    static var sendingEOM = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        peripheralManager = CBPeripheralManager(delegate: self,
                                                queue: nil,
                                                options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        peripheralManager.stopAdvertising()
    }
    
    @IBAction func advertisingAction(_ sender: Any) {
        if advertisingSwitch.isOn {
            peripheralManager
                .startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID]])
        } else {
            peripheralManager.stopAdvertising()
        }
    }
    
    private func setupPeripheral() {
        let transferCharacteristic = CBMutableCharacteristic(type: TransferService.characteristicUUID,
                                                             properties: [.notify, .writeWithoutResponse],
                                                             value: nil,
                                                             permissions: [.readable, .writeable])
        
        let transferService = CBMutableService(type: TransferService.serviceUUID,
                                               primary: true)
        
        transferService.characteristics = [transferCharacteristic]
        peripheralManager.add(transferService)
        self.transferCharacteristic = transferCharacteristic
    }
    
    private func sendData() {
        guard let transferCharacteristic = transferCharacteristic else { return }
        if PeripheralViewController.sendingEOM {
            let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                        for: transferCharacteristic,
                                                        onSubscribedCentrals: nil)
            
            if didSend {
                PeripheralViewController.sendingEOM = false
            }
            return
        }
        
        if sendDataIndex >= dataToSend.count { return }
        
        var didSend = true
        while didSend {
            var amountToSend = dataToSend.count - sendDataIndex
            if let mtu = connectedCentral?.maximumUpdateValueLength {
                amountToSend = min(amountToSend, mtu)
            }
            let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))
            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)
            if !didSend {
                return
            }
            
            sendDataIndex += amountToSend
            if sendDataIndex >= dataToSend.count {
                PeripheralViewController.sendingEOM = true
                let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                            for: transferCharacteristic, onSubscribedCentrals: nil)
                if eomSent {
                    PeripheralViewController.sendingEOM = false
                }
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension PeripheralViewController: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        advertisingSwitch.isEnabled = peripheral.state == .poweredOn
        switch peripheral.state {
        case .poweredOn:
            print("CBManager is powered on")
            setupPeripheral()
        case .poweredOff:
            print("CBManager is not powered on")
        case .resetting:
            print("CBManager is resetting")
        case .unauthorized:
            if #available(iOS 13.0, *) {
                switch peripheral.authorization {
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
        case .unknown:
            print("CBManager state is unknown")
        case .unsupported:
            print("Bluetooth is not supported on this device")
        @unknown default:
            print("A previously unknown peripheral manager state occurred")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        dataToSend = textView.text.data(using: .utf8) ?? Data()
        sendDataIndex = 0
        connectedCentral = central
        sendData()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedCentral = nil
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        sendData()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        requests.forEach { request in
            guard let requestValue = request.value,
                let stringFromData = String(data: requestValue, encoding: .utf8) else { return }
            textView.text = stringFromData
        }
    }
}

// MARK: UITextViewDelegate
extension PeripheralViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        if advertisingSwitch.isOn {
            advertisingSwitch.isOn = false
            peripheralManager.stopAdvertising()
        }
    }
    func textViewDidBeginEditing(_ textView: UITextView) {
        let rightButton = UIBarButtonItem(title: "Done",
                                          style: .done,
                                          target: self,
                                          action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
    }
    
    @objc
    func dismissKeyboard() {
        textView.resignFirstResponder()
        navigationItem.rightBarButtonItem = nil
    }
}
