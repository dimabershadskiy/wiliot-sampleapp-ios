//
//  WiliotMQTTClient.swift
//  WiliotMQTTClient
//
//  Created by Ivan Yavorin on 06.05.2022.
//

import Foundation
import CocoaMQTT

public struct MQTTEndpoint {
    let host:String
    let port:UInt16
    public init(host:String, port:UInt16) {
        self.host = host
        self.port = port
    }
}

public protocol MQTTClientDelegate:AnyObject {
    func mqttClientDidConnect()
    func mqttClientIsConnecting()
    func mqttClientDidDisconnect()
    func mqttClientDidEncounterError(_ error:Error, willAttemptToReconnect:Bool)
}

public protocol MQTTClientMessageEventDelegate:AnyObject {
    func mqttClientDidPublishMessage(messageId:UInt16, clientId:String)
    func mqttClientDidReceiveMessage(message:String?, topic:String)
}

public enum MQTTClientError : Error, CaseIterable {
    case mqttClientNotSet
    case mqttClientConnectionNotEstablished
}

public enum MQTTCredentialsError:Error {
    case clientIdInvalid
    case usernameInvalid
    case passwordInvalid
    case endpointInvalid
}

fileprivate let keepAliveSeconds: UInt16 = 30

public final class WiliotMQTTClient {
    
    public private(set) var clientId:String
    public private(set) var userName:String
    public private(set) var password:String
    public private(set) var endpoint:MQTTEndpoint
    private weak var delegate: MQTTClientDelegate?
    private weak var messageEventDelegate:MQTTClientMessageEventDelegate?
    private var cocoaMQTTDelegate:CocoaMQTTDelegateObject?
    
    private var mqtt:CocoaMQTT?
    
    private var delegateQueue:DispatchQueue = DispatchQueue(label: "com.MQTTClient.delegateQueue",
                                                            qos: .default,
                                                            attributes: [],
                                                            autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem,
                                                            target: nil)
    
    deinit {
        #if DEBUG
        print("+ MQTTClient DEINIT +")
        #endif
    }
    
    public init(clientId:String, userName:String, password:String, endpoint:MQTTEndpoint, delegate:MQTTClientDelegate?, eventDelegate:MQTTClientMessageEventDelegate?) throws {
        
        guard !clientId.isEmpty else {
            throw MQTTCredentialsError.clientIdInvalid
        }
        
        guard !userName.isEmpty else {
            throw MQTTCredentialsError.usernameInvalid
        }
        
        guard !password.isEmpty else {
            throw MQTTCredentialsError.passwordInvalid
        }
        
        guard !endpoint.host.isEmpty && endpoint.port != 0 else {
            throw MQTTCredentialsError.endpointInvalid
        }
        
        #if DEBUG
        print("+ MQTTClient INIT+")
        #endif
        self.clientId = clientId
        self.userName = userName
        self.password = password
        self.endpoint = endpoint
        self.delegate = delegate
        self.messageEventDelegate = eventDelegate
        self.cocoaMQTTDelegate = CocoaMQTTDelegateObject()
        
        //prepareMQTT()
    }
    
    private func prepareMQTT() {
        #if DEBUG
        print("MQTTClient preparing MQTT CLIENT with clientId: \(clientId), userName: \(userName), password: \(password)")
        #endif
        if let client = mqtt {
            client.delegate = nil
            client.disconnect()
        }
       
        let mqtt = CocoaMQTT(clientID: clientId,
                         host: endpoint.host,
                         port: endpoint.port)
        
    
        mqtt.username = self.userName
        mqtt.password =  self.password
        mqtt.keepAlive = keepAliveSeconds //30 secs
        mqtt.autoReconnect = true
        mqtt.autoReconnectTimeInterval = 1
        mqtt.maxAutoReconnectTimeInterval = 10 //default is 128
        mqtt.messageQueueSize = 50
//        mqtt.allowUntrustCACertificate = true
        mqtt.cleanSession = true
        mqtt.enableSSL = true
        mqtt.logLevel = .off//.debug
        mqtt.backgroundOnSocket = true
        self.cocoaMQTTDelegate?.target = self
        mqtt.delegate = self.cocoaMQTTDelegate
        mqtt.delegateQueue = delegateQueue
        
        self.mqtt = mqtt
    }
    
    @discardableResult
    public func start() throws -> Bool {
        if let _ = mqtt {
            return connectMQTT()
        }
        else {
            prepareMQTT()
        }
        
        return connectMQTT()
    }
    
    private func connectMQTT() -> Bool {
        guard let mqtt = self.mqtt else {
            return false
        }
        
        return mqtt.connect(timeout: TimeInterval(30))
    }
    
    public func stopAndDisconnect() {
        #if DEBUG
        print("+ MQTTClient stopAndDisconnect() --")
        #endif
        guard let client = self.mqtt else {
            delegate?.mqttClientDidDisconnect()
            return
        }
        client.autoReconnect = false
        
        client.disconnect()
    }
    
    public func sendMessage(_ message:String, topic:String) throws {
//        #if DEBUG
//        print("+ MQTTClient TRYING sendMessage. Date: \(Date()), topic: \(topic)")
//        #endif
        guard let mqtt = self.mqtt else {
            throw MQTTClientError.mqttClientNotSet
        }
        
        guard mqtt.connState == .connected else {
            throw MQTTClientError.mqttClientConnectionNotEstablished
        }
//        #if DEBUG
//        print("+ MQTTClient sendMessage. Date: \(Date()), topic: \(topic), message:\(message)")
//        #endif
        mqtt.publish(topic, withString: message, qos: .qos1)
    }
    
    
}

extension WiliotMQTTClient {
    //MARK: -
    private func trace(_ name: String) {
        #if DEBUG
        print("MQTTClient \(#function) TRACE: \(name)")
        #endif
    }
}

//MARK: - CocoaMQTTDelegateObjectTarget
extension WiliotMQTTClient : CocoaMQTTDelegateObjectTarget {
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        trace("did Connect Acknowledgements")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
//        #if DEBUG
//        let messagePayloadBytesCount = message.payload.count
//        print("MQTTClient sent bytes: \(messagePayloadBytesCount)")
//        #endif
        messageEventDelegate?.mqttClientDidPublishMessage(messageId: id, clientId: self.clientId)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16) {
        trace("didPublishComplete: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
//        trace("didPublishAck: \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        trace("didReceiveMessage: \( String(data:Data(message.payload), encoding:.utf8) ?? "-unparsed-")")
        messageEventDelegate?.mqttClientDidReceiveMessage(message: message.string, topic: message.topic)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        trace("didSubscribeTopics: \(success) \nfalied: \(failed)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        trace("didUnsubscribeTopics: [\(topics)]")
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        
        if let error = err {
            trace("did disconnect: \(error)")
           
            if !mqtt.autoReconnect {
                delegate?.mqttClientDidEncounterError(error, willAttemptToReconnect: false)
                self.mqtt = nil
            }
            delegate?.mqttClientDidEncounterError(error, willAttemptToReconnect: true)
        }
        else {
            trace("did disconnect: No Error.")
           
            if !mqtt.autoReconnect {
                if let delegate = self.delegate {
                    delegate.mqttClientDidDisconnect()
                }
                self.mqtt = nil
            }
        }
    }

    func mqttDidPing(_ mqtt: CocoaMQTT) {
        trace("did ping")
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        trace("did recieve pong")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        trace("didStateChange To: \(state.description)")
        switch state {
        case .connected:
            delegate?.mqttClientDidConnect()
        case .disconnected:
            break
            //delegate?.mqttClientDidDisconnect()
        case .connecting:
            delegate?.mqttClientIsConnecting()
        @unknown default:
            break
        }
    }
}


protocol CocoaMQTTDelegateObjectTarget:AnyObject {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck)
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16)
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16)
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16)
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16)
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String])
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String])
    
    func mqttDidPing(_ mqtt: CocoaMQTT)
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT)
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?)
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState)
    
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void)
}

class CocoaMQTTDelegateObject:NSObject, CocoaMQTTDelegate {
    
    weak var target:CocoaMQTTDelegateObjectTarget?
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        target?.mqtt(mqtt, didConnectAck: ack)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        target?.mqtt(mqtt, didPublishMessage: message, id: id)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        target?.mqtt(mqtt, didPublishAck: id)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        target?.mqtt(mqtt, didReceiveMessage: message, id: id)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        target?.mqtt(mqtt, didSubscribeTopics: success, failed: failed)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        target?.mqtt(mqtt, didUnsubscribeTopics: topics)
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        target?.mqttDidPing(mqtt)
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        target?.mqttDidReceivePong(mqtt)
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        target?.mqttDidDisconnect(mqtt, withError: err)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        target?.mqtt(mqtt, didReceive: trust, completionHandler: completionHandler)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        target?.mqtt(mqtt, didStateChangeTo: state)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16) {
        target?.mqtt(mqtt, didPublishComplete: id)
    }
    
}

