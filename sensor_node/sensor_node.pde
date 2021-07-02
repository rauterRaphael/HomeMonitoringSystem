#include <WaspXBeeDM.h>
#include <WaspFrame.h>
#include <WaspXBee802.h>

// ##################################
// ##### HOME MONITORING SYSTEM #####
// ##################################
// ########## SENSOR NODE ###########
// ##################################

#define SAMPLE_SIZE 5

#define NUM_SEND_RETRIES 5
#define REC_PACKET_TIMEOUT 5000

#define EEPROM_START_IDX 1024

#define CLEAR_EEPROM true

enum MSG_TYPES 
{
  ACKN,
  SYNC,
  UPDA,
  SYNACK
};

enum UPDATE_PAYLOAD_INDICES 
{
  LIGHT_IDX,
  TEMP_IDX,
  BATT_IDX,
  RSSI_IDX,
  MTN_IDX
};

enum ACKN_PAYLOAD_INDICES 
{
  SEQ_NUM_TO_ACK_IDX
};

enum SYNACK_PAYLOAD_INDICES 
{
  SYN_NODE_ID_IDX,
  UTC_SEC_IDX,
  DEFAULT_SLEEP_IDX
};

enum MSG_INDICES
{
  SEQ_NUM_IDX,
  NODE_ID_IDX,
  SOURCE_ADDR_IDX,
  DEST_ADDR_IDX,
  MSG_TYPE_IDX,
  PAYLOAD_LEN_IDX,
  PAYLOAD_IDX,
  CKSUM_IDX
};

enum TX_MODE
{
  TX_BROADCAST,
  TX_DIRECT
};

typedef struct GeneralHMSFrame{
  uint16_t seqNum;
  uint8_t  nodeId;
  uint8_t  srcAddr;
  uint8_t  dstAddr;
  uint8_t  msgType;
  uint8_t  payloadLen;
  char     payload[200];
  uint16_t cksum;
}GeneralHMSFrame;

typedef struct UpdatePayload{
  uint8_t lightIntensity;
  uint8_t temperature;
  uint8_t batteryLevel;
  int     rssiToGateway;
  uint8_t motionDetected;
}UpdatePayload;

typedef struct AcknPayload{
  uint8_t seqNumToAck;
}AcknPayload;

typedef struct SynAckPayload{
  uint8_t  nodeId;
  char     utcSec[40];
  uint32_t defaultSleep;
}SynAckPayload;

uint8_t XBEE_CHANNEL   = 0x12;
uint8_t XBEE_PANID[2]  = {0x17, 0x03};

char XBEE_NODE_ID[]           = "SENSOR_NODE";
char XBEE_NODE_ADDR[]         = "0000000000000001";
char XBEE_BROADCAST_ADDRESS[] = "000000000000FFFF";

char NODE_ID[]   = "SENSOR_NODE";

int storedNodeIsSynced = 0;
int storedNodeID = 0;
int storedDefaultSleep = 0;

int sequenceNum = 0;

/****************************** NODE HIBERNATE FUNCTIONS ******************************/

void hibInterrupt()
{
  intFlag &= ~(HIB_INT);
}

/****************************** EEPROM FUNCTIONS ******************************/

void storeIntInEEPROM(int startAddr, int value)
{
  // Big Endian
  Utils.writeEEPROM(startAddr,   value>>8);     // MSB
  Utils.writeEEPROM(startAddr+1, value);       // LSB
}

void storeFloatInEEPROM(int startAddr, float value)
{
  uint8_t data[4];
  memcpy(data, &value, 4);
  Utils.writeEEPROM(startAddr,   data[0]);
  Utils.writeEEPROM(startAddr+1, data[1]);
  Utils.writeEEPROM(startAddr+2, data[2]);
  Utils.writeEEPROM(startAddr+3, data[3]);
}

int loadIntFromEEPROM(int startAddr)
{
  return (Utils.readEEPROM(startAddr)<<8) + (Utils.readEEPROM(startAddr+1));
}

float loadFloatFromEEPROM(int startAddr)
{
  float value;
  uint8_t data[4];
  data[0] = Utils.readEEPROM(startAddr);
  data[1] = Utils.readEEPROM(startAddr+1);
  data[2] = Utils.readEEPROM(startAddr+2);
  data[3] = Utils.readEEPROM(startAddr+3);
  memcpy(&value, &data, 4);
  return value;
}

/****************************** GENERAL XBEE FUNCTIONS ******************************/

bool xbeeInitChannel(uint8_t xbeeChannel)
{
  xbee802.setChannel(xbeeChannel);
  // check at commmand execution flag
  if(xbee802.error_AT == 0)
  {
    USB.print("Channel set OK to: 0x");
    USB.printHex(xbee802.channel);
    USB.println();
    return true;
  }
  else
  {
    USB.println("Error calling 'setChannel()'");
    return false;
  }
    USB.print("Channel set OK to: 0x");
    USB.printHex(xbee802.channel);
    USB.println();
}

bool xbeeInitPanID(uint8_t xbeePanID[])
{
  
  xbee802.setPAN(xbeePanID);
  // check the AT commmand execution flag
  if(xbee802.error_AT == 0)
  {
    USB.print("PAN ID set OK to: 0x");
    USB.printHex(xbee802.PAN_ID[0]);
    USB.printHex(xbee802.PAN_ID[1]);
    USB.println();
    return true;
    }
  else
  {
    USB.println(" Error calling 'setPAN ()'");
    USB.println(xbee802.error_AT);
    return false;
  }
}

bool xbeeSetNodeID(char NODE_ID[])
{
  xbee802.setNodeIdentifier(NODE_ID);
  
  // check at commmand execution flag
  if( xbee802.error_AT == 0 ) 
  {
    USB.println(F("Node ID set OK"));
  }
  else 
  {
    USB.println(F("Error setting Node ID"));
  }
}

bool xbeeSetOwnNetworkAddress(char NODE_ADDRESS[])
{
  xbee802.setOwnNetAddress(NODE_ADDRESS);
  // check the AT commmand execution flag
  if(xbee802.error_AT == 0)
  {
    USB.println("NETWORK ADDR set OK");
    return true ;
  }
  else
  {
    USB.println("Error calling 'setOwnNetAddress()'");
    USB.println(xbee802.error_AT);
    return false;
  }
}

bool xbeeSaveToModuleMemory()
{
  xbee802.writeValues();
  // check the AT commmand execution flag
  if(xbee802.error_AT == 0)
  {
    USB.println("Changes stored OK");
    return true ;
  }
  else
  {
    USB.println("Error calling 'writeValues ()'");
    USB.println(xbee802.error_AT);
    return false ;
  }
}

bool xbeeEnableEncryption(bool status)
{
  uint8_t encryptionMode = (status == true) ? 1 : 0; // 1: enabled , 0: disabled
  char encryptionKey [] = " WaspmoteLinkKey !";
  xbee802.setEncryptionMode(encryptionMode);

  if(xbee802.error_AT == 0)
  {
    if(status == true)
    {
      xbee802.setLinkKey(encryptionKey);
      
      if(xbee802.error_AT == 0)
      {
        USB.println("AES encryption key set OK");
        return true;
      }
      else
      {
        USB.println("AES encryption enable ERROR");
        return true;
      }
    }
    else
    {
      USB.println("AES encryption disable OK");
      return true;
    }
  }
  else
  {
    USB.println("AES encryption disable ERROR");
    return false;
  }
}

char* xbeeGetSendErrorCode(uint8_t errorCode)
{
  switch(errorCode)
  {
    case 6:
      return "ERROR: Error escaping character within payload bytes";
      break;
      
    case 5:
      return "ERROR: Error escaping character in checksum byte";
      break;
      
    case 4:
      return "ERROR: Checksum is not correct";
      break;
      
    case 3:
      return "ERROR: Checksum byte is not available";
      break;
      
    case 2: 
      return "ERROR: Frame Type is not valid";
      break;
      
    case 1:
      return "ERROR: timeout when receiving answer";
      break;
      
    case 0:
      return "OK: The command has been executed with no errors";
      break;

    default:
      return "UNKNOWN ERROR CODE";
  }
  return "UNKNOWN ERROR CODE";
}

/****************************** HMS FRAME FUNCTIONS ******************************/

void encodeFrame(GeneralHMSFrame* encFrame)
{
  char frameData[0xFF] = {0};

  frame.createFrame(ASCII);
  
  char payload[200] = {0};
  
  strncpy(payload, (char*) encFrame->payload, encFrame->payloadLen);
  
  sprintf(frameData, "%d;%d;%d;%d;%d;%d;%s;%d;", encFrame->seqNum,
                                              encFrame->nodeId,
                                              encFrame->srcAddr,
                                              encFrame->dstAddr,
                                              encFrame->msgType,
                                              encFrame->payloadLen,
                                              payload,
                                              encFrame->cksum);

  frame.addSensor(SENSOR_STR, frameData);
}

void decodeFrame(GeneralHMSFrame* decFrame, char* receivedData)
{
  uint8_t tokenIdx = 0;
  char* token = strtok(receivedData, ";");
        
  while (token != NULL) {
    switch(tokenIdx)
    {
      case SEQ_NUM_IDX:
        decFrame->seqNum = atoi(token);
        break;
      case NODE_ID_IDX:
        decFrame->nodeId = atoi(token);
        break;
      case SOURCE_ADDR_IDX:
        decFrame->srcAddr = atoi(token);
        break;
      case DEST_ADDR_IDX:
        decFrame->dstAddr = atoi(token);
        break;
      case MSG_TYPE_IDX:
        decFrame->msgType = atoi(token);
        break;
      case PAYLOAD_LEN_IDX:
        decFrame->payloadLen = atoi(token);
        break;
      case PAYLOAD_IDX:
        strcpy((char*) decFrame->payload, token);
        break;
      case CKSUM_IDX:
        decFrame->cksum = atoi(token);
        break;
      default:
        break;
    }
    token = strtok(NULL, ";");
    tokenIdx++;
  }
}

int8_t sendFrame(GeneralHMSFrame* txFrame, uint8_t msgMode, uint8_t waitForAck)
{  
  uint8_t errorResp = -1;

  txFrame->seqNum = sequenceNum;
  uint8_t seqNumToAck = sequenceNum;
  encodeFrame(txFrame);
  
  errorResp = xbee802.send("000000000000FFFF", frame.buffer, frame.length);

  sequenceNum++;
    
  if(errorResp != 0)
    USB.printf("SENDING FRAME ERR: %s\n\n", xbeeGetSendErrorCode(errorResp));

  return seqNumToAck;
}

int8_t receiveFrame(GeneralHMSFrame* rxFrame)
{
  uint8_t errorResp = -1;
  
  errorResp = xbee802.receivePacketTimeout(REC_PACKET_TIMEOUT);
  
  if(errorResp == 0)
  {
    xbee802.getRSSI();
    
    int lastRSSI = xbee802.valueRSSI[0];
    lastRSSI*=-1;
    storeIntInEEPROM(EEPROM_START_IDX+6, lastRSSI);
    
    char recData[0xFF] = {0};
    for(int i=0; i<0xFF; i++)
      recData[i] = (char) xbee802._payload[i];

    decodeFrame(rxFrame, recData);
      
    switch(rxFrame->msgType)
    {
      case ACKN:
        USB.println("ACKN RECEIVED");
        return ACKN;
      case SYNC:
        USB.println("SYNC RECEIVED");
        return SYNC;
      case UPDA:
        USB.println("UPDA RECEIVED");
        return UPDA;
      case SYNACK:
        USB.println("SYNACK RECEIVED");
        return SYNACK;
      default:
        USB.println("Unknown MSG TYPE");
        return -1;
    }
  }
  else
    USB.printf("RECEIVING FRAME ERR: %s\n\n", xbeeGetSendErrorCode(errorResp));

  return -1;
}


/****************************** HMS FRAME PAYLOAD FUNCTIONS ******************************/

// --------------- UPDATE DATA ---------------

uint8_t encodeUpdatePayload(GeneralHMSFrame* updateFrame, UpdatePayload* payload)
{
  sprintf((char*) updateFrame->payload, "%d|%d|%d|%d|%d|", payload->lightIntensity, payload->temperature, payload->batteryLevel, payload->rssiToGateway, payload->motionDetected);
  return strlen((char*) updateFrame->payload);
}

int8_t decodeUpdatePayload(GeneralHMSFrame* updateFrame, UpdatePayload* updatePayload)
{
  uint8_t tokenIdx = 0;
  char* token = strtok((char*) updateFrame->payload, "|");

  while (token != NULL) {
    switch(tokenIdx)
    {
      case LIGHT_IDX:
        updatePayload->lightIntensity = atoi(token);
        break;
      case TEMP_IDX:
        updatePayload->temperature = atoi(token);
        break;
      case BATT_IDX:
        updatePayload->batteryLevel = atoi(token);
        break;
      case RSSI_IDX:
        updatePayload->rssiToGateway = atoi(token);
      case MTN_IDX:
        updatePayload->motionDetected = atoi(token);
      default:
        USB.println("Unknown DATA IDX");
    }
    token = strtok(NULL, "|");
    tokenIdx++;
  }
}

// --------------- ACK DATA ---------------

uint8_t encodeAckPayload(GeneralHMSFrame* ackFrame, AcknPayload* ackPayload)
{
  sprintf((char*) ackFrame->payload, "%d|", ackPayload->seqNumToAck);
  return strlen((char*) ackFrame->payload);
}

int8_t decodeAckPayload(GeneralHMSFrame* ackFrame, AcknPayload* ackPayload)
{
  uint8_t tokenIdx = 0;
  char* token = strtok((char*) ackFrame->payload, "|");

  while (token != NULL) {
    switch(tokenIdx)
    {
      case SEQ_NUM_TO_ACK_IDX:
        ackPayload->seqNumToAck = atoi(token);
        break;
      default:
        USB.println("Unknown DATA IDX");
        return -1;
    }
    token = strtok(NULL, "|");
    tokenIdx++;
  }
  return 0;
}

// --------------- SYNACK DATA ---------------

uint8_t encodeSynAckPayload(GeneralHMSFrame* synAckFrame, SynAckPayload* synAckPayload)
{
  sprintf((char*) synAckFrame->payload, "%d|%d|%d|", synAckPayload->nodeId, synAckPayload->utcSec, synAckPayload->defaultSleep);
  return strlen((char*) synAckFrame->payload);
}

int8_t decodeSynAckPayload(GeneralHMSFrame* synAckFrame, SynAckPayload* synAckPayload)
{
  uint8_t tokenIdx = 0;
  uint8_t nodeId = 0;
  char* token = strtok(synAckFrame->payload, "|");
  
  while (token != NULL) {
    switch(tokenIdx)
    {
      case SYN_NODE_ID_IDX:
        synAckPayload->nodeId = atoi(token);
        break;
      case UTC_SEC_IDX:
        strcpy(synAckPayload->utcSec, token);
        break;
      case DEFAULT_SLEEP_IDX:
        synAckPayload->defaultSleep = atoi(token);
        break;
      default:
        USB.println("Unknown DATA IDX");
        return -1;
    }
    token = strtok(NULL, "|");
    tokenIdx++;
  }
  return 0;
}

/****************************** MSG SEND FUNCTION ******************************/

int8_t sendMsgAndWaitForResponse(GeneralHMSFrame* txFrame)
{
  GeneralHMSFrame rxFrame;
  uint8_t retry = 0;
  int8_t seqNumToAck = 0;
  int8_t ret = -1;

  while(retry < NUM_SEND_RETRIES){
    seqNumToAck = sendFrame(txFrame, TX_BROADCAST, false);
    
    ret = receiveFrame(&rxFrame);
    
    if(rxFrame.dstAddr == txFrame->srcAddr)
    {
      switch(ret)
      {
        case ACKN:
          AcknPayload ackPayload;
          if(decodeAckPayload(&rxFrame, &ackPayload) == 0){
            if(ackPayload.seqNumToAck == seqNumToAck)
              return ACKN;
          }
          break;
        case SYNACK:
          SynAckPayload synAckPayload;
          if(decodeSynAckPayload(&rxFrame, &synAckPayload) == 0){
            GeneralHMSFrame ackFrame;
            AcknPayload ackPayload;
            
            ackPayload.seqNumToAck = rxFrame.seqNum;
    
            ackFrame.nodeId = storedNodeID;
            ackFrame.srcAddr = txFrame->srcAddr;
            ackFrame.dstAddr = 0;
            ackFrame.msgType = ACKN;
            ackFrame.cksum = 0;

            ackFrame.payloadLen = encodeAckPayload(&ackFrame, &ackPayload);

            sendFrame(&ackFrame, TX_BROADCAST, false);
          
            processSynAckFrame(&synAckPayload);
            return SYNACK;
          }
      default:
          USB.println("No useful msg received");
      }
    }
    retry++;
    ret = -1;
    delay(200);
    USB.println("RESENDING MESSAGE");
  }

}

/****************************** UTIL FUNCTIONS ******************************/

void collectUpdateData(UpdatePayload* payload)
{
  int   acc_light = 0;
  float acc_temperature = 0;

  for(int i=0; i<SAMPLE_SIZE; i++)
  {
    acc_light       += Utils.readLight();
    acc_temperature += Utils.readTemperature();
  }

  payload->lightIntensity = acc_light/SAMPLE_SIZE;
  payload->temperature    = acc_temperature/SAMPLE_SIZE;
  payload->batteryLevel   = PWR.getBatteryLevel();
  payload->rssiToGateway  = loadIntFromEEPROM(EEPROM_START_IDX+6);
  payload->motionDetected = digitalRead(DIGITAL7);

  USB.printf("RSSI: %d, MOTION: %d\n", payload->rssiToGateway, payload->motionDetected);
}

void processSynAckFrame(SynAckPayload* payload)
{
  storedNodeIsSynced  = 0xFF;
  storedNodeID        = payload->nodeId;
  storedDefaultSleep  = payload->defaultSleep;
  
  storeIntInEEPROM(EEPROM_START_IDX, storedNodeIsSynced);
  storeIntInEEPROM(EEPROM_START_IDX+2, storedNodeID);
  storeIntInEEPROM(EEPROM_START_IDX+4, storedDefaultSleep);

  RTC.setTime(payload->utcSec);
  USB.println(RTC.getTime());
  USB.println("TIME SET");
  
}

void letSensorNodeSleep()
{
  char hibernateTime[11] = { 0 };
  uint16_t secForNode = (storedNodeID - 1) * 30;
  uint8_t minutes = (storedDefaultSleep + secForNode) / 60;
  uint8_t seconds = (storedDefaultSleep + secForNode) - (minutes * 60);
  sprintf (hibernateTime, "00:00:%02d:%02d", minutes, seconds);
  USB.printf("NODE %d is going to sleep for min: %d, sec: %d\n", storedNodeID, minutes, seconds);
  PWR.hibernate(hibernateTime,RTC_OFFSET,RTC_ALM1_MODE2);
}

/****************************** UTIL FUNCTIONS ******************************/

void setup()
{
  USB.printf("\n\nHome Monitoring System\n\n");
  USB.println("SENSOR NODE");
  PWR.ifHibernate();
  USB.ON();
  RTC.ON();
  pinMode(DIGITAL7, INPUT);
  
  // Uncomment so sync NODE
  //storeIntInEEPROM(EEPROM_START_IDX, 0x00);

  storedNodeIsSynced        = loadIntFromEEPROM(EEPROM_START_IDX);
  storedNodeID              = loadIntFromEEPROM(EEPROM_START_IDX+2);
  storedDefaultSleep        = loadIntFromEEPROM(EEPROM_START_IDX+4);

  USB.println("PARAMETERS STORED IN DB");
  USB.println(storedNodeIsSynced);
  USB.println(storedNodeID);
  USB.println(storedDefaultSleep);

  xbee802.ON(); 
  
  USB.println("----- XBEE SETUP\n");
  
  USB.println("--- Setting channel");
  xbeeInitChannel(XBEE_CHANNEL);
  
  USB.println("\n--- Setting pan ID");
  xbeeInitPanID(XBEE_PANID);
  
  USB.println("\n--- Disabling encryption");
  xbeeEnableEncryption(false);

  USB.println("\n--- Setting node address");
  xbeeSetOwnNetworkAddress(XBEE_NODE_ADDR);
  
  USB.println("\n--- Setting node ID");
  xbeeSetNodeID(NODE_ID);
  
  USB.println("\n--- Saving settings");
  xbeeSaveToModuleMemory();

  USB.println("\n----- XBEE SETUP COMPLETED\n");
 
}

void loop()
{ 
  uint8_t ret = 0;
  if(storedNodeIsSynced == 0x00)
  { 
    Utils.readSerialID();
    uint8_t tempSrcAddr = 0;
    for(uint8_t i=0; i<8; i++)
      tempSrcAddr += _serial_id[i];
      
    USB.println("NODE NOT SYNCHRONIZED - ASK GATEWAY TO SYNC");
    GeneralHMSFrame syncFrame;
    
    syncFrame.nodeId = 0xFF;
    syncFrame.srcAddr = tempSrcAddr;
    syncFrame.dstAddr = 0;
    syncFrame.msgType = SYNC;
    syncFrame.cksum = 0;
    
    if(sendMsgAndWaitForResponse(&syncFrame) == SYNACK)
      letSensorNodeSleep();
    delay(5);
  }
  else
  {
    if(intFlag & HIB_INT )
      hibInterrupt();
    
    USB.println("NODE SYNCHRONIZED - SEND UPDATE TO GATEWAY");
    
    GeneralHMSFrame updaFrame;
    UpdatePayload payload;
    
    uint8_t tempSrcAddr = 0;
    for(uint8_t i=0; i<8; i++)
      tempSrcAddr += _serial_id[i];
      
    updaFrame.nodeId = storedNodeID;
    updaFrame.srcAddr = tempSrcAddr;
    updaFrame.dstAddr = 0;
    updaFrame.msgType = UPDA;
    updaFrame.cksum = 0;
    
    collectUpdateData(&payload);
    updaFrame.payloadLen = encodeUpdatePayload(&updaFrame, &payload);

    sendMsgAndWaitForResponse(&updaFrame);
    letSensorNodeSleep();
  }
}
