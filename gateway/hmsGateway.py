import regex as re
import requests

from time import sleep
from digi.xbee.devices import XBeeDevice, RemoteXBeeDevice, XBee64BitAddress
from digi.xbee.exception import TimeoutException
from datetime import datetime


class MSG_TYPES:
    ACKN = 0
    SYNC = 1
    UPDA = 2
    SYNACK = 3

class UpdatePayload:
    lightIntensity = 0
    temperature    = 0
    batteryLevel   = 0
    rssiToGateway  = 0
    motionDetected = 0

class AckPayload:
    seqNumToAck = 0

class SynAckPayload:
    nodeId = 0
    utcSec = ""
    defaultSleep = 0

class HMSFrame:
    seqNum = 0
    nodeId = 0
    srcAddr = 0
    dstAddr = 0
    msgType = 0
    payloadLen = 0
    payload = ""
    cksum = 0

class HMSGateway():

    SENSOR_NODE_ID = "SENSOR_NODE"
    SENSOR_NODE_ADDR = "0013A200416B4BA2"
    #SENSOR_NODE_ADDR = "0000000000000001"

    nodeUrl = "http://127.0.0.1:8000/rest/node/"
    dataUrl = "http://127.0.0.1:8000/rest/data/"

    defaultSleep = 30

    ACKS = []
    LAST_UPDA = []
    lastSyncedAt = []
    src_node = None
    sequenceNum = 0
    nodeID = 0
    nodeAddr = 0
    SYNC_IN_PROGRESS = False
    NODE_ID_WITH_ADDRESS = []


    def postNodeInfo(self, nodeID, rssi, motionDetected):
        postData =  {
            "nodeId": nodeID,
            "rssi": rssi,
            "motionDetected": motionDetected,
            "updated_at": "{}".format(datetime.now())
        }

        requests.post(self.nodeUrl, data = postData)

    def postNodeData(self, nodeID, updatePayload):
        postData = {
            "fromNodeID": nodeID,
            "lightIntensity": updatePayload.lightIntensity,
            "temperature": updatePayload.temperature,
            "batteryLevel": updatePayload.batteryLevel
        }

        requests.post(self.dataUrl, data = postData)

    def encode_hms_frame(self, txFrame):
        txFrame.payloadLen, txFrame.payload = self.encode_hmsframe_payload(txFrame)
        frameAsStr = ''.join((
            str(txFrame.seqNum) + ";",
            str(txFrame.nodeId) + ";",
            str(txFrame.srcAddr) + ";",
            str(txFrame.dstAddr) + ";",
            str(txFrame.msgType) + ";",
            str(txFrame.payloadLen) + ";",
            str(txFrame.payload) + ";",
            str(txFrame.cksum) + ";",
        ))
        print(frameAsStr)
        return bytearray(frameAsStr, 'utf-8')

    def decode_hms_frame(self, rxMsg):
        frameData = rxMsg.split(";")
        if len(frameData) != 9:
            return None

        rxFrame = HMSFrame()

        rxFrame.seqNum = int(frameData[0])
        rxFrame.nodeId = int(frameData[1])
        rxFrame.srcAddr = int(frameData[2])
        rxFrame.dstAddr = int(frameData[3])
        rxFrame.msgType = int(frameData[4])
        rxFrame.payloadLen = int(frameData[5])
        rxFrame.payload = frameData[6]
        rxFrame.cksum = int(frameData[7])

        # check cksum

        rxFrame.payload = self.decode_hmsframe_payload(rxFrame)
        return rxFrame

    def encode_hmsframe_payload(self, txFrame):
        if txFrame.payload == "":
            print("No payload in frame")
            return 0, ""

        if txFrame.msgType == MSG_TYPES.ACKN:
            print("ACK payload")
            ackPayloadAsStr = str(txFrame.payload.seqNumToAck) + "|"
            return len(ackPayloadAsStr), ackPayloadAsStr

        elif txFrame.msgType == MSG_TYPES.SYNACK:
            print("SYNACK payload")
            synAckPayloadAsStr = ''.join((
                            str(txFrame.payload.nodeId) + "|",
                            str(txFrame.payload.utcSec) + "|",
                            str(txFrame.payload.defaultSleep) + "|",
                        ))
            return len(synAckPayloadAsStr), synAckPayloadAsStr

        else:
            print("Payload not known")
            return 0, ""


    def decode_hmsframe_payload(self, rxFrame):
        if rxFrame.payloadLen == 0:
            return ""

        payload = rxFrame.payload.split("|")

        if rxFrame.msgType == MSG_TYPES.ACKN:
            if len(payload) != 2:
                return ""
            acknPayload = AckPayload()
            acknPayload.seqNumToAck = int(payload[0])
            return acknPayload

        elif rxFrame.msgType == MSG_TYPES.UPDA:
            if len(payload) != 6:
                return ""
            print("Updating")
            updatePayload = UpdatePayload()
            updatePayload.lightIntensity = int(payload[0])
            updatePayload.temperature = int(payload[1])
            updatePayload.batteryLevel = int(payload[2])
            updatePayload.rssiToGateway = int(payload[3])
            updatePayload.motionDetected = int(payload[4])
            return updatePayload

        elif rxFrame.msgType == MSG_TYPES.SYNC:
            return ""

        else:
            print("Unknown msg type to decode")
            return ""

    def process_received_frame(self, rxFrame):
        if rxFrame.dstAddr == 0:
            if rxFrame.msgType == MSG_TYPES.ACKN and rxFrame.payload != "":
                self.ACKS.append(rxFrame.payload.seqNumToAck)
                print("ACK RECEVIED")

            elif rxFrame.msgType == MSG_TYPES.SYNC:
                print("SYNC RECEVIED")
                self.handle_sync_request(rxFrame)

            elif rxFrame.msgType == MSG_TYPES.UPDA:
                print("UPDA RECEVIED")
                if rxFrame.nodeId != self.getNextSensorIdOrSync(rxFrame)[1]:
                    self.NODE_ID_WITH_ADDRESS = [item for item in self.NODE_ID_WITH_ADDRESS if item[1] != rxFrame.srcAddr]
                    self.handle_sync_request(rxFrame)
                else:
                    if self.store_node_sync_if_needed(rxFrame) == True:
                        self.handle_sync_request(rxFrame)
                    else:
                        txFrame = HMSFrame()
                        txFrame.msgType = MSG_TYPES.ACKN
                        txFrame.dstAddr = rxFrame.srcAddr
                        acknPayload = AckPayload()
                        acknPayload.seqNumToAck = rxFrame.seqNum
                        txFrame.payload = acknPayload
                        print("SENDING ACK")
                        self.send_HMS_Frame(txFrame)

                        sleep(0.2)
                        current = int((datetime.utcnow()-datetime(1970,1,1)).total_seconds())
                        nodeNotFound = True
                        for i in range(0, len(self.LAST_UPDA)):
                            if self.LAST_UPDA[i][0] == rxFrame.nodeId: 
                                nodeNotFound = False
                                if self.LAST_UPDA[i][1] < current - self.defaultSleep:
                                    self.LAST_UPDA[i] = (rxFrame.nodeId, current)
                                    self.postNodeData(rxFrame.nodeId, rxFrame.payload)
                                    self.postNodeInfo(rxFrame.nodeId, rxFrame.payload.rssiToGateway, rxFrame.payload.motionDetected)
                    
                        if nodeNotFound == True:
                            self.LAST_UPDA.append((rxFrame.nodeId, current))
                            self.postNodeData(rxFrame.nodeId, rxFrame.payload)
                            self.postNodeInfo(rxFrame.nodeId, rxFrame.payload.rssiToGateway, rxFrame.payload.motionDetected)

            elif rxFrame.msgType == MSG_TYPES.SYNACK:
                print("SYNACK RECEVIED")
        else:
            print("Msg not for Gateway")

    def store_node_sync_if_needed(self, rxFrame):
        nodeNotFound = True
        syncNode = False
        current = int((datetime.utcnow()-datetime(1970,1,1)).total_seconds())
        for i in range(0, len(self.lastSyncedAt)):
            if self.lastSyncedAt[i][0] == rxFrame.nodeId and self.lastSyncedAt[i][1] < (current - 600):
                self.lastSyncedAt[i] = (rxFrame.nodeId, current)
                nodeNotFound = False
                syncNode = True
    
        if nodeNotFound == True:
            self.lastSyncedAt.append((rxFrame.nodeId, current))
        
        return syncNode

    def send_HMS_Frame(self, txFrame):
        txFrame.nodeId = self.nodeID
        txFrame.seqNum = self.sequenceNum
        txFrame.cksum  = 0
        txFrame.srcAddr = self.nodeAddr

        encodedFrame = self.encode_hms_frame(txFrame)
        self.src_node.set_sync_ops_timeout(0.8)
        for i in range(0, 5):
            try:
                self.src_node.send_data_broadcast(encodedFrame)
            except Exception as e:
                pass
            self.sequenceNum += 1
        return txFrame.seqNum

    def handle_sync_request(self, rxFrame):
        self.SYNC_IN_PROGRESS = True
        txFrame = HMSFrame()
        txFrame.msgType = MSG_TYPES.SYNACK
        txFrame.dstAddr = rxFrame.srcAddr
        synAckPayload = SynAckPayload()
        synAckPayload.nodeId = self.getNextSensorIdOrSync(rxFrame)[1]
        now = datetime.now() 
        synAckPayload.utcSec = now.strftime("%y:%m:%d:0%w:%H:%M:%S")
        synAckPayload.defaultSleep = self.defaultSleep

        txFrame.payload = synAckPayload
        self.send_frame_and_wait_for_ack(txFrame, synAckPayload)

    def getNextSensorIdOrSync(self, rxFrame):
        for item in self.NODE_ID_WITH_ADDRESS:
            if item[1] == rxFrame.srcAddr:
                return True, item[0]
        
        maxNodeId = len(self.NODE_ID_WITH_ADDRESS) + 1
        self.NODE_ID_WITH_ADDRESS.append((maxNodeId, rxFrame.srcAddr))
        return False, maxNodeId        

    def data_receive_callback(self, frame):
        if frame is not None:
            rx_data = frame.data.decode(errors='replace')
            if rx_data != "":
                rxMsg = rx_data.split("STR:")[1]
                if rxMsg != "":
                    rxMsg = rxMsg.replace("#", "")
                    print(rxMsg)
                    hmsFrame = self.decode_hms_frame(rxMsg)
                    self.process_received_frame(hmsFrame)

    def send_frame_and_wait_for_ack(self, txFrame, payload, waitForAck=False):
        max_retries = 5
        num_retry   = 0

        while(num_retry < max_retries):
            seqNumToAck = self.send_HMS_Frame(txFrame)
            sleep(1)
            if seqNumToAck in self.ACKS:
                self.ACKS.remove(seqNumToAck)
                break
            num_retry += 1
            txFrame.payload = payload
            print("RETRYING - NO ACK RECEIVED")
        
      


    def init_and_open_xbee_device(self):

        serialPort = input("Serial Port [COM4]: ")
        if serialPort == "":
            serialPort = "COM4"

        bdrate = input("Baudrate [115200]: ")
        if bdrate == "":
            bdrate = 115200
        else:
            bdrate = int(bdrate)

        try:
            self.src_node = XBeeDevice(serialPort, bdrate)
            self.src_node.open()
            return True
        except Exception as e:
            pass
            return True



    ####################################


    def runApp(self):
        print("\n\n### HOME MONITORING SYSTEM - GATEWAY ###\n\n")

        ret = self.init_and_open_xbee_device()
        if not ret:
            print("Initialization failed -> check log\n")

        print("XBEE Device initialized\n")
        self.src_node.add_data_received_callback(self.data_receive_callback)
        
        print("# CALLBACK ADDED #\n")
        while(1):
            sleep(1)

