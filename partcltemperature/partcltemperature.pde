#include <SPI.h>
#include <Ethernet.h>
#include <Wire.h>


#define DHCP //use DHCP for network configuring
#define DNS  //use DNS for hostname resolving

byte mac[] = {  
  0x90, 0xA2, 0xDA, 0x00, 0x61, 0x56 }; //your MAC address
#ifdef DHCP
//Note! In some arduino sdk versions #include directive works even if it's placed
//in disabled by ifdef area, so you should comment corresponding line manually
#include <EthernetDHCP.h>
#endif
byte ipAddr[] = { 
  192,168,0,2 };
byte gatewayAddr[] = { 
  192,168,0,1 };
byte dnsAddr[] = { 
  192,168,0,1 };


#ifdef DNS
//See comment above!
#include <EthernetDNS.h>
char hostname[] = "partcl.com";
bool dnsRenew = true;
#endif
byte serverIP[] = { 
  67, 202, 35, 165 }; // partcl.com, can be set later via DNS resolve if enabled

const char pubKey[] = "YOUR_PUB_KEY_HERE";
const char keyId[] = "sensor_id";
const int postingInterval = 500;
const int timeoutInterval = 1000;

int tmp102Address = 0x48; //temperature sensor address
int ledPin = 13; // select the pin for the LED
int delaYms=200;
byte res;
int val;
const char* ip_to_str(const uint8_t*);

void setup()
{
  SPI.begin();
  pinMode(ledPin, OUTPUT);
  Serial.begin(9600);
  Wire.begin();
#ifdef DHCP
  EthernetDHCP.begin(mac, 1);
#else
  Ethernet.begin(mac,ipAddr,gatewayAddr);
#ifdef DNS
  EthernetDNS.setDNSServer(dnsAddr);
#endif
#endif

}

#ifdef DHCP
bool SetupDHCP() { //returns true if everythin's ok, otherwise returns false
  static DhcpState prevState = DhcpStateNone;
  static unsigned long prevTime = 0;

  DhcpState state = EthernetDHCP.poll();
  bool good = false;

  if (prevState != state) {
    Serial.println();
    switch (state) {
    case DhcpStateDiscovering:
      Serial.print("Discovering servers.");
      break;
    case DhcpStateRequesting:
      Serial.print("Requesting lease.");
      break;
    case DhcpStateRenewing:
      Serial.print("Renewing lease.");
      break;
    case DhcpStateLeased: 
      {
        Serial.print("Obtained lease!");
        memcpy(ipAddr,EthernetDHCP.ipAddress(),sizeof(ipAddr));
        memcpy(gatewayAddr,EthernetDHCP.gatewayIpAddress(),sizeof(gatewayAddr));
        memcpy(dnsAddr,EthernetDHCP.dnsIpAddress(),sizeof(dnsAddr));
        Serial.print(" IP:");
        Serial.print(ip_to_str(ipAddr));
        Serial.print(" Gateway:");
        Serial.print(ip_to_str(gatewayAddr));
        Serial.print(" DNS:");
        Serial.println(ip_to_str(dnsAddr));
#ifdef DNS
        EthernetDNS.setDNSServer(dnsAddr);
        dnsRenew = true;
#endif
        good = true;
        break;
      }
    }
  } 
  else if (state != DhcpStateLeased && millis() - prevTime > 300) {
    prevTime = millis();
    Serial.print('.');
  }
  prevState = state;
  return good;
}
#endif


#ifdef DNS
bool ResolveHostname(const char* hostName, byte result[4]) { //returns true if resolved, otherwise returns false.
  if (!dnsRenew)
    return true;

  Serial.print("Resolving ");
  Serial.print(hostName);
  Serial.print("...");

  DNSError err = EthernetDNS.sendDNSQuery(hostName);

  if (err == DNSSuccess ) {
    do {
      err = EthernetDNS.pollDNSReply(ipAddr);
      if (err == DNSTryLater) {
        delay(20);
        Serial.print(".");
      }
    } while (err == DNSTryLater);
  }

  switch (err) {
  case DNSSuccess:
    Serial.print("The IP address is ");
    Serial.println(ip_to_str(result));
    dnsRenew = false;
    return true;
  case DNSTimedOut:
    Serial.println("Timed out.");
    return false;
  case DNSNotFound:
    Serial.println("Does not exist.");
    return false;
  default:
    Serial.print("Failed with error code ");
    Serial.print((int)err, DEC);
    Serial.println(".");
    return false;
  }
}
#endif

void loop()
{
#ifdef DHCP
  if (!SetupDHCP())
    return;
#endif
#ifdef DNS
  if (!ResolveHostname(hostname,serverIP))
    return;
#endif

  Client client(serverIP,80); //connect to HTTP port
  client.connect();

  unsigned long lastSent = 0;
  while(true) {
    if (millis()-lastSent>postingInterval) {
      Wire.requestFrom(tmp102Address,2);
      byte MSB = Wire.receive();
      byte LSB = Wire.receive();
      int TemperatureSum = ((MSB << 8) | LSB) >> 4; //it's a 12bit int, using two's compliment for negative
      float result = TemperatureSum*0.0625; //uncomment line below to use fahrenheit
      //float result = (TemperatureSum*0.1125) + 32;

      Serial.print("Connecting.");
      unsigned long firstConnTry = millis();
      while (!client.connected() && millis()-firstConnTry < timeoutInterval) {
        client.connect();
        if (client.connected()) {
          Serial.print("done! Sending ");
          Serial.println(result,2);
          sendData(client,result);
        }
        else 
          Serial.print(".");        
      }
      if (!client.connected()) {
        Serial.println("Timeout reached!");
        break;
      }
      else
        lastSent = millis();
      
      client.stop();
    }
    client.flush();
  }
  client.stop();
}


void sendData(Client& client,float thisData){
  client.print("GET /publish?publish_key=");
  client.print(pubKey);
  client.print("&id=");
  client.print(keyId);
  client.print("&value=");
  client.print(thisData, 2);
  client.print(" HTTP/1.1\n");
  client.print("Host: partcl.com\n");
  client.print("User-Agent: Arduino For Teh Win!\n");
  client.print("Accept: text/html\n");
  client.println("Connection: close\n");
  client.println();
}

const char* ip_to_str(const uint8_t* ipAddr)
{
  static char buf[16];
  sprintf(buf, "%d.%d.%d.%d\0", ipAddr[0], ipAddr[1], ipAddr[2], ipAddr[3]);
  return buf;
}

