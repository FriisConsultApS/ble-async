//
//  BatteryMonitor.swift
//  BLEConcurrency
//
//  Created by Per Friis on 31/03/2022.
//

import Foundation
import CoreBluetooth
import os.log

class BatteryMonitor: NSObject, AsyncCBPeripheral {
    typealias InitContinuation = CheckedContinuation<Void, Error>
    static let batteryService = CBUUID(string: "180F")
    static let batteryChar = CBUUID(string: "2A19")

    static var services: [CBUUID] = [batteryService]
    static var nameFilter: String?

    private(set) var peripheral: CBPeripheral
    private var initContinuation: InitContinuation?
    private var initHandler: (BatteryMonitor) -> Void = { _ in }

    private let debugLog: Logger = .init(subsystem: Bundle.main.bundleIdentifier!, category: "BatteryMonitor")

    private var batteryChar: CBCharacteristic?

    private var batteryValueHandler: (Double) -> Void = { _ in }
    private var batteryValueCancelHandler: () -> Void = { }

    var batteryValue: AsyncStream<Double> {
        AsyncStream(Double.self) { continuation in
            guard let batteryChar = batteryChar else {
                continuation.finish()
                return
            }

            batteryValueHandler = { value in
                continuation.yield(value)
            }

            batteryValueCancelHandler = {
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                if let batteryChar = self.batteryChar {
                    self.peripheral.setNotifyValue(false, for: batteryChar)
                }
            }

            peripheral.setNotifyValue(true, for: batteryChar)
        }
    }

    required init(peripheral: CBPeripheral) async throws {
        debugLog.info("ℹ:\(#function) - start")
        self.peripheral = peripheral
        super.init()
        self.peripheral.delegate = self

        peripheral.discoverServices(Self.services)
        try await completeInit()
        debugLog.info("ℹ:\(#function) - end")
    }

    private func completeInit() async throws {
        return try await withCheckedThrowingContinuation({ (continuation: InitContinuation) in
            self.initContinuation = continuation
        })
    }
}

extension BatteryMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        debugLog.info("ℹ:\(#function) - start")
        guard error == nil else {
            initContinuation?.resume(throwing: error!)
            return
        }

        guard let services = peripheral.services else {
            initContinuation?.resume(throwing: AsyncPeripheralError.noServicesFound)
            return
        }

        services.forEach { service in
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        debugLog.info("ℹ:\(#function) - start")
        guard error == nil else {
            initContinuation?.resume(throwing: error!)
            return
        }

        // This is only handling one service and one characteristic on that service.
        // A real life implementation, the numbers of expected characteristics must be handled prior to complete the  ``InitContinuation``
        // There is a potential failure here, if for some reason non of the ``InitContinuation`` is called the await init will wait for ever....
        switch service.uuid {

        case Self.batteryService: // the battery service and characteristic was found and are saved
            if let char = service.characteristics?.first(where: {$0.uuid == Self.batteryChar}) {
                self.batteryChar = char
            } else {
                initContinuation?.resume(throwing: AsyncPeripheralError.noServicesFound)
            }

        default: // we got a services that we didn'r request
            initContinuation?.resume(throwing: AsyncPeripheralError.noServicesFound)
        }

        // when all the requested characteristics is found, we can complete the init
        if self.batteryChar != nil {
            initContinuation?.resume()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else {
            batteryValueCancelHandler()
            return
        }
        debugLog.info("ℹ:\(#function) - info")

        switch characteristic.uuid {
        case Self.batteryChar:
            if let value = data.first {
                batteryValueHandler(Double(value))
            }

        default:
            break
        }
    }
}
