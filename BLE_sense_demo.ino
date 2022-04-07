/************************************************************/
/*                                                          */
/* Created by Per Friis, Friis Consult ApS    April 6. 2022 */
/* This is only for demo purpose, not valid for production  */
/* in any was, the code is as is, and you can use it as you */
/* please.                                                  */
/* if you at some point publish or refer to this code,      */
/* please give me the credit you find that i deserve        */
/*                                                          */
/* Current version, don't have all the features/services    */
/* Implemented yet.                                         */
/************************************************************/



#include <Arduino_HTS221.h>
#include <Arduino_APDS9960.h>
#include <Arduino_LSM9DS1.h>
#include <Arduino_LPS22HB.h>
#include <ArduinoBLE.h>

const int MAX_BUFFER_SIZE = 255;

const char* DEVICE_NAME = "BLE Sense Demo";
const char* SERIAL_NUMBER = "00001";

const char* devideInfoServiceUUID   = "180A";
const char* serialNumberCharUUID    = "2A25";

const char* motionServiceUUID       = "4000";
const char* accelerationCharUUID    = "4001";
const char* gyroscopeCharUUID       = "4002";
const char* magneticCharUUID        = "4003";

const char* opticalServiceUUID      = "4A00";
const char* gestureCharUUID         = "4A01";
const char* proximityCharUUID       = "4A02";
const char* colorCharUUID           = "4A03";


const char* environmentServiceUUID  = "4C00";
const char* temperatureCharUUID     = "4C01";
const char* humidityCharUUID        = "4C02";

const char* pressureServiceUUID     = "4D00";
const char* pressureCharUUID        = "4D01";


BLEService deviceInfoService(devideInfoServiceUUID);
BLECharacteristic serialNumberChar(serialNumberCharUUID, BLERead, MAX_BUFFER_SIZE, true);

BLEService motionService(motionServiceUUID);
BLEFloatCharacteristic accelarationChar(accelerationCharUUID, BLERead | BLENotify);
BLEFloatCharacteristic gyroscopeChar(gyroscopeCharUUID, BLERead | BLENotify);
BLEFloatCharacteristic magneticChar(magneticCharUUID, BLERead | BLENotify);


BLEService opticalService(opticalServiceUUID);
BLEIntCharacteristic gestureChar(gestureCharUUID,BLERead | BLENotify);
BLECharacteristic colorChar(colorCharUUID, BLERead | BLENotify,3,true);
BLEIntCharacteristic proximityChar(proximityCharUUID, BLERead | BLENotify);


BLEService environmentService(environmentServiceUUID);
BLEFloatCharacteristic temperatureChar(temperatureCharUUID,BLERead | BLENotify);
BLEFloatCharacteristic humidityChar(humidityCharUUID,BLERead | BLENotify);

BLEService pressureService(pressureServiceUUID);
BLEFloatCharacteristic pressureChar(pressureCharUUID, BLERead | BLENotify);

BLEDevice central;

// timers
unsigned long motionCheck;
unsigned long opticalCheck;
unsigned long environmentCheck;
unsigned long pressureCheck;

bool motionSubscription = false;
bool opticalSubscription = false;
bool environmentSubscription = false;
bool pressureSubscription = false;

void setup() {
  // put your setup code here, to run once:
  Serial.begin(9600);
  delay(500);

  unsigned long start = millis();
  //while( start - millis() < 500 && !Serial);
  Serial.println("We are getting ready to start the device");

   setupBLE();
}

void loop() {

  central = BLE.central();
  while ( central.connected()) {
    if (opticalSubscription) {
      opticalSendorHandler();
    }

    if (environmentSubscription) {
      environmentSensorHandler();
    }

    if (motionSubscription) {
      motionSensorHandler();
    }

    if (pressureSubscription) {
      pressureSensorHandler();
    }

     delay(50);
  }
}


void pressureSensorHandler(){
  if (millis() - pressureCheck < 500) {
    return;
  }

  pressureCheck = millis();
  float pressure = BARO.readPressure();
  pressureChar.writeValue(pressure);
}

void motionSensorHandler(){
  if (millis() - motionCheck < 250) {
    return;
  }

  if (IMU.accelerationAvailable()) {
    float x,y,z;
    IMU.readAcceleration(x,y,z);
    accelarationChar.writeValue(0);
    accelarationChar.writeValue(x);
    accelarationChar.writeValue(y);
    accelarationChar.writeValue(z);
    accelarationChar.writeValue(-1);
        
    // TODO: send to ble char, format not found yet
    Serial.print(x);
    Serial.print('\t');
    Serial.print(y);
    Serial.print('\t');
    Serial.println(z);
  }

  if (IMU.gyroscopeAvailable()) {
    float x,y,z;
    IMU.readGyroscope(x, y, z);
    gyroscopeChar.writeValue(0);
    gyroscopeChar.writeValue(x);
    gyroscopeChar.writeValue(y);
    gyroscopeChar.writeValue(z);
    gyroscopeChar.writeValue(-1);
  // TODO: send to ble char, format not found yet
    Serial.print(x);
    Serial.print('\t');
    Serial.print(y);
    Serial.print('\t');
    Serial.println(z);
  }

  if (IMU.magneticFieldAvailable()) {
    float x,y,z;
    IMU.readMagneticField(x, y, z);
    magneticChar.writeValue(0);
    magneticChar.writeValue(x);
    magneticChar.writeValue(y);
    magneticChar.writeValue(z);
    magneticChar.writeValue(-1);
  // TODO: send to ble char, format not found yet

    Serial.print(x);
    Serial.print('\t');
    Serial.print(y);
    Serial.print('\t');
    Serial.println(z);
  }
}

void opticalSendorHandler(){
  // only one check every 1 second
  if (millis() - opticalCheck < 1000) {
    return;
  }

  opticalCheck = millis();
  Serial.println("Check for optical sensor info");
  if (APDS.gestureAvailable()) {
    int gesture = APDS.readGesture();
    Serial.println(gesture);
    gestureChar.writeValue(gesture);
  }

  if (APDS.proximityAvailable()) {
      int proximity = APDS.readProximity();
      Serial.print("proximity: ");
      Serial.println(proximity);
      proximityChar.writeValue(proximity);
  }

  if (APDS.colorAvailable()) {
    int r,g,b;
    APDS.readColor(r,g,b);
    byte rgb[] = {r,g,b};
    colorChar.writeValue(rgb, 3);
    Serial.print("Color - r:");
    Serial.print(r);
    Serial.print(", g:");
    Serial.print(g);
    Serial.print(", b:");
    Serial.println(b);
  }
}

void environmentSensorHandler(){
  if (millis() - environmentCheck < 1000) {
    return;
  }
  environmentCheck = millis();
  Serial.println("Check environment");

  float temperature = HTS.readTemperature();
  temperatureChar.writeValue(temperature);

  float humidity = HTS.readHumidity();
  humidityChar.writeValue(humidity);

  Serial.print("Temperature: ");
  Serial.print(temperature);
  Serial.println("°C");

  Serial.print("Humidity: ");
  Serial.print(humidity);
  Serial.println("%");

}


/******************
  BLE
  *****************/
void setupBLE() {

  Serial.println("Setup BLE");
  BLE.begin();

  BLE.setDeviceName(DEVICE_NAME);
  BLE.setLocalName(DEVICE_NAME);

  BLE.setConnectionInterval(0x014, 0x0C80);

  // Device info service
  deviceInfoService.addCharacteristic(serialNumberChar);
  serialNumberChar.writeValue(SERIAL_NUMBER);
  BLE.addService(deviceInfoService);

  // Motion service
  motionService.addCharacteristic(accelarationChar);
  accelarationChar.setEventHandler(BLESubscribed, subscribeToChar);
  accelarationChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  motionService.addCharacteristic(gyroscopeChar);
  gyroscopeChar.setEventHandler(BLESubscribed, subscribeToChar);
  gyroscopeChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  motionService.addCharacteristic(magneticChar);
  magneticChar.setEventHandler(BLESubscribed, subscribeToChar);
  magneticChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  BLE.addService(motionService);

  // Optical sensor, returning color, gesture and proximity
  opticalService.addCharacteristic(gestureChar);
  gestureChar.setEventHandler(BLESubscribed, subscribeToChar);
  gestureChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  opticalService.addCharacteristic(proximityChar);
  proximityChar.setEventHandler(BLESubscribed, subscribeToChar);
  proximityChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  opticalService.addCharacteristic(colorChar);
  colorChar.setEventHandler(BLESubscribed, subscribeToChar);
  colorChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  BLE.addService(opticalService);

  // environment, returning temperature and humidity
  environmentService.addCharacteristic(temperatureChar);
  temperatureChar.setEventHandler(BLESubscribed, subscribeToChar);
  temperatureChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  environmentService.addCharacteristic(humidityChar);
  humidityChar.setEventHandler(BLESubscribed, subscribeToChar);
  humidityChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  BLE.addService(environmentService);

  pressureService.addCharacteristic(pressureChar);
  pressureChar.setEventHandler(BLESubscribed, subscribeToChar);
  pressureChar.setEventHandler(BLEUnsubscribed, unsubscribeToChar);

  BLE.setAdvertisedService(deviceInfoService);
  
  BLE.setEventHandler(BLEConnected, didConnectBLE);
  BLE.setEventHandler(BLEDisconnected, didDisconnectBLE);

  BLE.advertise();

  Serial.println("BLE communication is up and running, advertising now....");
  
}

void didConnectBLE(BLEDevice ConnectedCentral) {
  Serial.println("will connect");
  digitalWrite(LED_BUILTIN, HIGH);
  central = ConnectedCentral;
  Serial.print("did connect to ");
  Serial.println(central.address());
}

void didDisconnectBLE(BLEDevice central) {
  digitalWrite(LED_BUILTIN, LOW);
  Serial.print("did disconnect from ");
  Serial.println(central.address());
}



void subscribeToChar(BLEDevice central, BLECharacteristic characteristic){
  Serial.print("new subscription to:");
  Serial.println(characteristic.uuid());
  
  if (characteristic.uuid() == gestureChar.uuid() ||
     characteristic.uuid() == proximityChar.uuid() ||
     characteristic.uuid() == colorChar.uuid() ) {
       Serial.println("Optical subscription");
      opticalSubscription = true;
      APDS.begin();
  }

  if (characteristic.uuid() == accelarationChar.uuid() ||
      characteristic.uuid() == gyroscopeChar.uuid()    ||
      characteristic.uuid() == magneticChar.uuid() ) {
        Serial.println("Motion subscription");
    motionSubscription = true;
    IMU.begin();
  }
  

  if (characteristic.uuid() == temperatureChar.uuid() ||
      characteristic.uuid() == humidityChar.uuid()) {
    Serial.println("environment subscription");

    environmentSubscription = true;
    HTS.begin();
  }

  if (characteristic.uuid() == pressureChar.uuid()) {
    pressureSubscription = true;
    BARO.begin();
  }

}

void unsubscribeToChar(BLEDevice central, BLECharacteristic characteristic) {
  Serial.print("Unsubscribe for ");
  Serial.println(characteristic.uuid());

  if (characteristic.uuid() == gestureChar.uuid() ||
     characteristic.uuid() == proximityChar.uuid() ||
     characteristic.uuid() == colorChar.uuid() ) {
    opticalSubscription = false;
    APDS.end();
  }

   if (characteristic.uuid() == accelarationChar .uuid()||
      characteristic.uuid() == gyroscopeChar.uuid()    ||
      characteristic.uuid() == magneticChar.uuid() ) {
    motionSubscription = false;
    IMU.end();
  }


  if (characteristic.uuid() == temperatureChar.uuid() ||
      characteristic.uuid() == humidityChar.uuid()) {
    environmentSubscription = false;
    HTS.end();
  }

  if (characteristic.uuid() == pressureChar.uuid()) {
    pressureSubscription = false;
    BARO.end();
  }
}


void showAlert() {
  while(true) {
    digitalWrite(LED_BUILTIN, HIGH);
    delay(500);
    digitalWrite(LED_BUILTIN, LOW);
    delay(1000);
  }
}
