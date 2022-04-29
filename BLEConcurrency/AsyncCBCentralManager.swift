//
//  AsyncCBCentralManager.swift
//  BLEConcurrency
//
//  Created by Per Friis on 30/03/2022.
//

import Foundation
import CoreBluetooth
import os.log
import Combine

class AsyncCBCentralManager<T: AsyncCBPeripheral>: NSObject, ObservableObject, CBCentralManagerDelegate {
    typealias CentralManagerStateContinuation = CheckedContinuation<Bool, Never>
    typealias ConnectPeripheralContinuation = CheckedContinuation<T, Error>

    private let debugLog: Logger = .init(subsystem: Bundle.main.bundleIdentifier!, category: "AsyncCBCentralManager")

    private let centralManger: CBCentralManager
    private let services: [CBUUID]?

    private var stateContinuation: CentralManagerStateContinuation?
    private var stateHandler: (CBManagerState) -> Void = { _ in }

    private var devicesContinuation: AsyncStream<CBPeripheral>.Continuation?

    private(set) var peripherals: [CBPeripheral] = []

    private var countDownSubscriber: AnyCancellable?
    private var countDownFrom: Date = .now

    private var connectContinuation: ConnectPeripheralContinuation?
    private var connectHandler: (T) -> Void = { _ in }

    @Published private(set) var connectionError = false

    /// a async list of the devices that are visible for the phone, using the initialised services
    /// The list will end is reached when no new devices have been discovered within the last "timeOut" seconds or
    /// if the stopScan is called
    var devices: AsyncStream<CBPeripheral> {
        AsyncStream(CBPeripheral.self) { continuation in
            devicesContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                self.centralManger.stopScan()
            }

            peripherals.removeAll()
            centralManger.scanForPeripherals(withServices: services)
        }
    }

    /// return the peripheral if available
    subscript (id: CBPeripheral.ID) -> CBPeripheral? {
        peripherals.first(where: {$0.id == id})
    }

    /// Initialize the acync manager
    /// - Parameters:
    ///   - services: The services to look for, default is nil, that lists all BLE devices in the area
    ///   - timeOut: The longest the scan should continue without finding new devices
    init(services: [CBUUID]? = T.services) {
        self.services = services
        centralManger = .init(delegate: nil, queue: .init(label: "BLE"))

        super.init()
        centralManger.delegate = self
    }

    /// Check if the central manager is ready to scan for devices
    ///
    /// Current implementation, don't handle specific cased where the state is something else than "powered on"
    /// - Returns: if the central manager state is poweredOn
    func isReady() async -> Bool {
        if centralManger.state == .poweredOn {
            return true
        }

        return await withCheckedContinuation({ (continuation: CentralManagerStateContinuation) in
            self.stateContinuation = continuation
        })
    }

    /// stop scanning and "terminate" the devices async stream
    func stopScan() {
        devicesContinuation?.finish()
        self.countDownSubscriber?.cancel()
    }

    /// Connect and return a connected device encapsulated in a async handler
    ///
    /// In case of an error this throws a AsyncCentalManagerError
    /// - Parameter peripheral: the peripheral to connect
    /// - Returns: the customised device
    func connect(_ peripheral: CBPeripheral) async throws -> T {
        centralManger.connect(peripheral)

        return try await withCheckedThrowingContinuation { (continuation: ConnectPeripheralContinuation) in
            self.connectContinuation = continuation
        }
    }

    /// A convince  access to connect using the id
    /// - Parameter id: id (string version of the identifier)
    /// - Returns: a Async encapsulated version of the peripheral
    func connect(_ id: CBPeripheral.ID) async throws -> T {
        guard let peripheral = self[id] else { throw AsyncCentralManagerError.peripheralNotFound }
        return try await connect(peripheral)
    }

    /// Cancel connection to the peripheral within the encapsulation
    ///
    /// This is a shoot and _forget_ as in __I believe it to success, if not I really don't care__
    ///
    /// - Note: This might also be implemented as async as the cancel connection must result in a
    ///     did disconnect with error, and that error could be promoted to this... but for this, I have chosen not do this...
    ///
    /// - Parameter device: The encapsulated device....
    func cancelConnection(_ device: T?) {
        guard let peripheral = device?.peripheral else {
            return
        }
        centralManger.cancelPeripheralConnection(peripheral)
    }

    enum AsyncCentralManagerError: Error {
        case peripheralNotFound
        case unknownError
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        debugLog.info("ℹ:\(#function) - \(central.state)")
        switch central.state {
        case .poweredOn:
            stateContinuation?.resume(returning: true)
        default:
            stateContinuation?.resume(returning: false)
        }
    }

    /// When ever the central manager finds a peripheral that matches the requirements, as in, has published the services that we are looking for. This is called
    ///
    /// Firstly we __check if we already have registered this peripheral__, if not, we check if there is a __name restriction__ on, and if this is parsed,
    /// we "collect" the peripheral and parse it to the stream
    /// - Parameters:
    ///   - central: The central that calls us
    ///   - peripheral: The discovered peripheral
    ///   - advertisementData: The advertised data
    ///   - RSSI: the signal strength
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard !peripherals.contains(peripheral) else { return }
        if let nameFilter = T.nameFilter , let name = peripheral.name, !name.localizedStandardContains(nameFilter) {
            return
        }

        peripherals.append(peripheral)
        devicesContinuation?.yield(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task {
            do {
                let asyncPeripheral = try await T(peripheral: peripheral)
                self.connectContinuation?.resume(returning: asyncPeripheral)
            } catch {
                self.connectContinuation?.resume(throwing: error)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.connectContinuation?.resume(throwing: error ?? AsyncCentralManagerError.unknownError)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard error == nil else {
            DispatchQueue.main.async {
                self.connectionError = true
            }
            return
        }
    }
}

extension CBManagerState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return  "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            fatalError()
        }
    }
}
