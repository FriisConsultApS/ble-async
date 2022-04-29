//
//  AsyncCBPeripheral.swift
//  BLEConcurrency
//
//  Created by Per Friis on 30/03/2022.
//

import Foundation
import CoreBluetooth
import os.log

protocol AsyncCBPeripheral {
    /// the peripheral that are connected
    var peripheral: CBPeripheral {get}

    /// List of the services to use / scan for
    static var services: [CBUUID] { get }

    static var nameFilter: String? { get }

    init(peripheral: CBPeripheral) async throws
}

enum AsyncPeripheralError: Error {
    case noServicesFound
    case unknownServiceFound
    case characteristicsMissing
}

extension CBPeripheral: Identifiable {
    public var id: String { identifier.uuidString }
}
