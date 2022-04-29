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
    /// This is the Continuation "call back" that are used for the initialisation of an object
    typealias InitContinuation = CheckedContinuation<Void, Error>
    typealias RGB = (red:Double, green: Double, blue: Double)
    var peripheral: CBPeripheral
    
    var name: String { peripheral.name ?? "unknown" }
    
    /// streams the current measured temperature, using Measurement struct
    var temperature: AsyncStream<Measurement<UnitTemperature>> {
        AsyncStream(Measurement<UnitTemperature>.self) { continuation in
            /// make sure that we have an characteristics that we can read from
            guard let temperatureChar = temperatureChar else {
                continuation.finish()
                return
            }
            
            /// parse the value from the caller to the stream
            temperatureHandler = { value in
                continuation.yield(value)
            }
            
            /// close the stream
            temperatureCancelHandler =  {
                continuation.finish()
            }
            
            /// Let's do some cleaning when we  stop the stream
            continuation.onTermination = { @Sendable _ in
                self.peripheral.setNotifyValue(false, for: temperatureChar)
            }
            
            /// here we start the stream, by subscribing to the temperature characteristic
            peripheral.setNotifyValue(true, for: temperatureChar)
        }
    }
    
    /// streams the current humidity in % eg 50.99 = 50.99% if used with .formatter(.percent) remember to dived by 100
    var humidity: AsyncStream<Float> {
        AsyncStream(Float.self) { continuation in
            guard let humidityChar = humidityChar else {
                continuation.finish()
                return
            }
            
            humidityHandler = { value in
                continuation.yield(value)
            }
            
            humidityCancelHandler = {
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                self.peripheral.setNotifyValue(false, for: humidityChar)
            }
            
            self.peripheral.setNotifyValue(true, for: humidityChar)
        }
    }
    
    /// stream the read color, using double RGB, Please note that the optical color reader on the 
    var colorHex: AsyncStream<RGB> {
        AsyncStream(RGB.self) { continuation in
            guard let colorChar = self.colorChar else {
                continuation.finish()
                return
            }
            
            colorHandler =  { value in
                continuation.yield(value)
            }
            
            colorCancelHandler = {
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                self.peripheral.setNotifyValue(false, for: colorChar)
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
    private var serialChar: CBCharacteristic?
    
    private var gestureChar: CBCharacteristic?
    private var proximityChar: CBCharacteristic?
    private var colorChar: CBCharacteristic?
    
    private var temperatureChar: CBCharacteristic?
    private var humidityChar: CBCharacteristic?
    
    private var magneticChar: CBCharacteristic?
    private var accelerationChar: CBCharacteristic?
    private var gyroscopeChar: CBCharacteristic?
    
    private var pressureChar: CBCharacteristic?
    
    
    /// this is the closure used to parse a new value to the async stream
    private var temperatureHandler: (Measurement<UnitTemperature>) -> Void =  { _ in }
    /// in case we want to shut the stream down, this is the call...
    private var temperatureCancelHandler: () -> Void = { }
    
    private var humidityHandler: (Float) -> Void = { _ in }
    private var humidityCancelHandler: () -> Void = { }
    
    private var colorHandler: (RGB) -> Void = { _ in }
    private var colorCancelHandler: () -> Void = { }
    
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
        guard let data = characteristic.value else {
            switch characteristic.uuid {
            case Self.temperatureChar:
                temperatureCancelHandler()
                
            case Self.humidityChar:
                humidityCancelHandler()
                
            case Self.colorChar:
                colorCancelHandler()
                
            case Self.pressureChar:
                pressureCancelHandler()
                
            default:
                break
            }
            return
        }
        
        switch characteristic.uuid {
        case Self.temperatureChar:
            let value = Data(data.reversed())
            let temperature = Double(value.float)
            temperatureHandler(Measurement<UnitTemperature>(value: temperature, unit: .celsius))
            
        case Self.humidityChar:
            let value = Data(data.reversed())
            let humidity = value.float
            humidityHandler(humidity)
                        
        case Self.colorChar:
            guard data.count == 3 else { return }
            let red = Double(data[0]) / 255.0
            let green = Double(data[1]) / 255
            let blue = Double(data[2]) / 255
             
            //let value = data.uint32
            debugLog.info("ℹ:\(#function) - \(data.hex) \(red),\(green), \(blue)")
            colorHandler((red, green, blue))
            
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
