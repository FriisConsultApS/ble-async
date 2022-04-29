//
//  AsyncCBPeripheral.swift
//  BLEConcurrency
//
//  Created by Per Friis on 30/03/2022.
//

import Foundation
import CoreBluetooth
import os.log

/// This is a test to create a protocol that need to be used when implementing a AsyncCBPeripheral wrapper
protocol AsyncCBPeripheral {
    /// the peripheral that are connected
    var peripheral: CBPeripheral {get}

    /// List of the services to use / scan for
    static var services: [CBUUID] { get }

    static var nameFilter: String? { get }

    init(peripheral: CBPeripheral) async throws
}

/// A list of error that are use for the Peripheral when throwing
enum AsyncPeripheralError: Error, LocalizedError {
    case noServicesFound
    case unknownServiceFound
    case characteristicsMissing

    var errorDescription: String? {
        switch self {
        case .noServicesFound:
            return NSLocalizedString("No services found", comment: "")
        case .unknownServiceFound:
            return NSLocalizedString("Unexpected service found", comment: "")
        case .characteristicsMissing:
            return NSLocalizedString("Characteristic missing", comment: "")
        }
    }
}

/// This is used in SwiftUI and in the central manager, convent way to enable the usage of ForEach ...
extension CBPeripheral: Identifiable {
    public var id: String { identifier.uuidString }
}
