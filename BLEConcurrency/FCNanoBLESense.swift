//
//  FCNanoBLESense.swift
//  BLEConcurrency
//
//  Created by Per Friis on 06/04/2022.
//

import Foundation
import os.log
import CoreBluetooth

/// This is use to connect with a Arduino Nano 33 BLE SENSE with the firmware created specific for this.
/// The firmware is included in this project "BLE_sense_demo.ino" and can be flashed to Arduino nano BLE sense
/// Using the Arduino IDE (version 2) check out the arduino.cc website
class FCNanoBLESense: NSObject, AsyncCBPeripheral {
    /// This is the Continuation "call back" that are used for the initializations of an object
    typealias InitContinuation = CheckedContinuation<Void, Error>
    typealias RGBvalues = (red: Double, green: Double, blue: Double)

    /// Handle to the peripheral
    var peripheral: CBPeripheral

    /// An non-optional name
    var name: String { peripheral.name ?? "unknown" }

    /// the continuation, that is to be called when a temperature is send from the BLE device
    private var temperatureContinuation: AsyncStream<Measurement<UnitTemperature>>.Continuation?

    /// streams the current measured temperature, using Measurement struct
    var temperature: AsyncStream<Measurement<UnitTemperature>> {
        AsyncStream(Measurement<UnitTemperature>.self) { continuation in

            temperatureContinuation = continuation

            /// Let's do some cleaning when we  stop the stream
            continuation.onTermination = { @Sendable _ in
                self.peripheral.setNotifyValue(false, for: self.temperatureChar)
            }

            /// here we start the stream, by subscribing to the temperature characteristic
            peripheral.setNotifyValue(true, for: temperatureChar)
        }
    }

    private var humidityContinuation: AsyncStream<Float>.Continuation?

    /// streams the current humidity in % eg 50.99 = 50.99% if used with .formatter(.percent) remember to dived by 100
    var humidity: AsyncStream<Float> {
        AsyncStream(Float.self) { continuation in
            humidityContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                self.peripheral.setNotifyValue(false, for: self.humidityChar)
            }

            self.peripheral.setNotifyValue(true, for: humidityChar)
        }
    }

    private var colorContinuation: AsyncStream<RGBvalues>.Continuation?
    /// stream the read color, using double RGB, Please note that the optical color reader on the
    var colorHex: AsyncStream<RGBvalues> {
        AsyncStream(RGBvalues.self) { continuation in
           colorContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                self.peripheral.setNotifyValue(false, for: self.colorChar)
            }

            self.peripheral.setNotifyValue(true, for: colorChar)
        }
    }

    /// return the current pressure
    var pressure: AsyncStream<Measurement<UnitPressure>> {
        AsyncStream(Measurement<UnitPressure>.self) { continuation in
            guard let pressureChar = self.pressureChar else {
                continuation.finish()
                return
            }

            pressureHandler = { value in
                continuation.yield(Measurement<UnitPressure>(value: value, unit: .kilopascals))
            }

            pressureCancelHandler = {
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                self.peripheral.setNotifyValue(false, for: pressureChar)
            }

            self.peripheral.setNotifyValue(true, for: pressureChar)
        }
    }

    private let debugLog: Logger = .init(subsystem: Bundle.main.bundleIdentifier!, category: "BLESense")

    private var initContinuation: InitContinuation?
    private var serialChar: CBCharacteristic!

    private var gestureChar: CBCharacteristic!
    private var proximityChar: CBCharacteristic!
    private var colorChar: CBCharacteristic!

    private var temperatureChar: CBCharacteristic!
    private var humidityChar: CBCharacteristic!

    private var magneticChar: CBCharacteristic!
    private var accelerationChar: CBCharacteristic!
    private var gyroscopeChar: CBCharacteristic!

    private var pressureChar: CBCharacteristic!

    private var pressureHandler: (Double) -> Void = { _ in }
    private var pressureCancelHandler: () -> Void = { }

    required init(peripheral: CBPeripheral) async throws {
        debugLog.info("ℹ:\(#function) - Start")

        self.peripheral = peripheral

        super.init()

        self.peripheral.delegate = self

        try await withCheckedThrowingContinuation { (continuation: InitContinuation) in
            self.initContinuation = continuation

            peripheral.discoverServices([Self.deviceInfoService, Self.opticalService, Self.environmentService, Self.motionService])
        }
        debugLog.info("ℹ:\(#function) - done")
    }
}

extension FCNanoBLESense: CBPeripheralDelegate {
    /// When services are discovered, we ask each service to discover all the required characteristics that we want to register
    /// - Parameters:
    ///   - peripheral: device
    ///   - error: if an error is raised
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
            switch service.uuid {
            case Self.deviceInfoService:
                peripheral.discoverCharacteristics([Self.serialNumberChar], for: service)

            case Self.opticalService:
                peripheral.discoverCharacteristics([Self.proximityChar, Self.gestureChar, Self.colorChar], for: service)

            case Self.environmentService:
                peripheral.discoverCharacteristics([Self.temperatureChar, Self.humidityChar], for: service)

            case Self.motionService:
                peripheral.discoverCharacteristics([Self.accelerationChar, Self.gyroscopeChar, Self.magneticChar], for: service)

            default:
                initContinuation?.resume(throwing: AsyncPeripheralError.unknownServiceFound)
            }
        }

        debugLog.info("ℹ:\(#function) - done")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        debugLog.info("ℹ:\(#function) - start")
        guard error == nil else {
            initContinuation?.resume(throwing: error!)
            return
        }

        switch service.uuid {
        case Self.deviceInfoService:
            if let char = service.characteristics?.first(where: {$0.uuid == Self.serialNumberChar}) {
                self.serialChar = char
            } else {
                initContinuation?.resume(throwing: AsyncPeripheralError.characteristicsMissing)
            }

        case Self.opticalService:
            if let gestureChar = service.characteristics?.first(where: {$0.uuid == Self.gestureChar}),
               let proximityChar = service.characteristics?.first(where: {$0.uuid == Self.proximityChar}),
               let colorChar = service.characteristics?.first(where: {$0.uuid == Self.colorChar}) {
                self.gestureChar = gestureChar
                self.proximityChar = proximityChar
                self.colorChar = colorChar
            } else {
                initContinuation?.resume(throwing: AsyncPeripheralError.characteristicsMissing)
            }

        case Self.environmentService:
            if let temperatureChar = service.characteristics?.first(where: {$0.uuid == Self.temperatureChar}),
               let humidityChar = service.characteristics?.first(where: {$0.uuid == Self.humidityChar}) {
                self.temperatureChar = temperatureChar
                self.humidityChar = humidityChar
            } else {
                initContinuation?.resume(throwing: AsyncPeripheralError.characteristicsMissing)
            }

        case Self.motionService:
            if let magneticChar = service.characteristics?.first(where: {$0.uuid == Self.magneticChar}),
               let accelerationChar = service.characteristics?.first(where: {$0.uuid == Self.magneticChar}),
               let gyroscopeChar = service.characteristics?.first(where: {$0.uuid == Self.gyroscopeChar}) {
                self.magneticChar = magneticChar
                self.accelerationChar = accelerationChar
                self.gyroscopeChar = gyroscopeChar
            } else {
                initContinuation?.resume(throwing: AsyncPeripheralError.characteristicsMissing)
            }

        default:
            initContinuation?.resume(throwing: AsyncPeripheralError.unknownServiceFound)
        }

        if self.serialChar != nil,
           self.gestureChar != nil,
           self.proximityChar != nil,
           self.colorChar != nil,
           self.temperatureChar != nil,
           self.humidityChar != nil,
           self.accelerationChar != nil,
           self.magneticChar != nil,
           self.gyroscopeChar != nil {
            initContinuation?.resume()
        }
    }

    /// Read the data when it comes in to the characteristic, and try to return it to the correct stream
    /// - Parameters:
    ///   - peripheral: -
    ///   - characteristic: -
    ///   - error: -
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case Self.temperatureChar:
            let value = Data(data.reversed())
            temperatureContinuation?.yield(.init(value: Double(value.float), unit: .celsius))

        case Self.humidityChar:
            let value = Data(data.reversed())
            humidityContinuation?.yield(value.float)

        case Self.colorChar:
            guard data.count == 3 else { return }
            let red = Double(data[0]) / 255.0
            let green = Double(data[1]) / 255
            let blue = Double(data[2]) / 255

            debugLog.info("ℹ:\(#function) - \(data.hex) \(red),\(green), \(blue)")
            colorContinuation?.yield((red, green, blue))

        case Self.pressureChar:
            let value = Data(data.reversed())
            let pressure = Double(value.float)
            pressureHandler(pressure)

        default:
            break
        }
    }
}

extension FCNanoBLESense {
    static var services: [CBUUID] { [deviceInfoService]}

    static var nameFilter: String?

    static let deviceInfoService = CBUUID(string: "180A")
    static let serialNumberChar = CBUUID(string: "2A25")

    /// motion service is not fully implemented in the Arduino firmware
    static let motionService    = CBUUID(string: "4000")
    static let accelerationChar = CBUUID(string: "4001")
    static let gyroscopeChar    = CBUUID(string: "4002")
    static let magneticChar     = CBUUID(string: "4003")

    static let opticalService   = CBUUID(string: "4A00")
    static let gestureChar      = CBUUID(string: "4A01")
    static let proximityChar    = CBUUID(string: "4A02")
    static let colorChar        = CBUUID(string: "4A03")

    static let environmentService = CBUUID(string: "4C00")
    static let temperatureChar  = CBUUID(string: "4C01")
    static let humidityChar     = CBUUID(string: "4C02")

    /// Barometric is not implemented in the Arduino firmware
    static let pressureService = CBUUID(string: "4D00")
    static let pressureChar   = CBUUID(string: "4D01")
}
