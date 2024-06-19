//
//  WiliotMQTTCLient.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 28.09.2022.
//

import Foundation

import WiliotCore

import MQTTClient

fileprivate let logger = bleuCreateLogger(subsystem: "BLEUpstream", category: "BLEUMQTTClient")

protocol WiliotMQTTClientDelegate {
    func mqttClientDidConnect()
    func mqttClientIsConnecting()
    func mqttClientDidDisconnect()
    func mqttClientDidEncounterError(_ error:Error, willAttemptToReconnect:Bool)
}

enum WiliotMQTTClientError:Error {
    case expiringToken
    case invalidTokenUsername
    case mttClientInitializationCredentialsError(MQTTCredentialsError)
}


class BLEUMQTTClient {
    
    private(set) var connectionStateDelegate: (any WiliotMQTTClientDelegate)?
    
    private(set) var connectionState:String = "Unknown" {
        didSet {
            #if DEBUG
            print("\\* BLEUMQTTClient \\* connectionState: \(connectionState)")
            #endif
        }
    }
    
    private var mqttClient:WiliotMQTTClient?
    
    init(clientId:String, userName:String, connectionToken:String, endpointInfo:BLEUpstreamEndpoint, delegate:(any WiliotMQTTClientDelegate)?) throws {
        
        guard !clientId.isEmpty, !userName.isEmpty, !connectionToken.isEmpty  else {
            throw ValueReadingError.missingRequiredValue("mqtt clientId, username, password or token missing")
        }
        
        
        self.connectionStateDelegate = delegate
        let endpoint = MQTTEndpoint(host: endpointInfo.host, port: endpointInfo.port)
        
        do {
            let lvMQTT:WiliotMQTTClient = try WiliotMQTTClient(clientId: clientId,
                                                   userName: userName,
                                                   password: connectionToken,
                                                   endpoint: endpoint,
                                                   delegate: self,
                                                   eventDelegate: self)
            //printDebug("_ WiliotMQTTClient Init with Ednpoint: '\(endpoint)'")
            self.mqttClient = lvMQTT
        }
        catch (let error) {
            if let mqttInitError = error as? MQTTCredentialsError {
                throw WiliotMQTTClientError.mttClientInitializationCredentialsError(mqttInitError)
            }
            else {
                throw error
            }
        }
    }

    @discardableResult
    func start() throws -> Bool {
        guard let mqttCLient = self.mqttClient else {
            return false
        }
        
        return try mqttCLient.start()
    }
    
    func close() throws {
        logger.notice(" \(#function) ")
        guard let _ = self.mqttClient,
              self.connectionState != "connected" else {
            
            throw ValueReadingError.invalidValue("Close connection before close.")
        }
        
        self.mqttClient = nil
    }
    
    func removeConnectionStateDelegate() {
        self.connectionStateDelegate = nil
    }
    
    func stopAndDisconnect() {
        logger.notice(" \(#function) ")
        
        guard let mqttCLient = self.mqttClient else {
            connectionStateDelegate?.mqttClientDidDisconnect()
            return
        }
        mqttCLient.stopAndDisconnect()
    }
    
    func sendMessage(_ message:String, topic:String) throws {
        guard let mqttCLient = self.mqttClient, self.connectionState.lowercased() == "connected" else {
            return
        }
        
        try mqttCLient.sendMessage(message, topic: topic)
    }
//

//
//    private func logToCrachlytics(_ message:String) {
//        #if targetEnvironment(simulator)
//        return
//        #endif
//        DispatchQueue.global(qos:.utility).async {
//            Crashlytics.crashlytics().log(message)
//        }
//    }
//    
//    private func errorToCrashLytics(_ error:Error) {
//        #if targetEnvironment(simulator)
//        return
//        #endif
//
//        Crashlytics.crashlytics().record(error: error)
//    }

}
// MARK: - Date extension
private extension Date {
func secondsFrom(anotherDate:Date) -> Int {
       let seconds = Calendar.current.dateComponents([.second], from: anotherDate, to: self).second ?? 0
       return seconds
   }
}

        
//MARK: -

        
//MARK: - MQTTClientDelegate
extension BLEUMQTTClient : MQTTClientDelegate {
    
    func mqttClientDidConnect() {
        connectionState = "Connected"
//        logToCrachlytics("MQTTClient did Connect")
        connectionStateDelegate?.mqttClientDidConnect()
    }
    
    func mqttClientIsConnecting() {
        connectionState = "Connecting"
        connectionStateDelegate?.mqttClientIsConnecting()
    }
    
    func mqttClientDidDisconnect() {
        connectionState = "Disconnected"
        
        connectionStateDelegate?.mqttClientDidDisconnect()
        
//        logToCrachlytics("MQTTClient did Disconnect")
    }
    
    func mqttClientDidEncounterError(_ error: Error, willAttemptToReconnect:Bool) {
        
        if !willAttemptToReconnect {
#if DEBUG
            print("WiliotMQTTClient DISCONNECTION ERROR:  \(error)\n")
#endif
            connectionState = "didDisconnect, Error(\(error.localizedDescription))"
//            let customError = NSError(domain: "com.MQTTCient",
//                                      code: 1,
//                                      userInfo: [NSLocalizedDescriptionKey: "MQTT connection lost with cause: \(connectionState)"])
            
//            errorToCrashLytics(customError)
            connectionState = "didDisconnect, Error - Unknown"
            connectionStateDelegate?.mqttClientDidEncounterError(error, willAttemptToReconnect: false)
        }
        else {
            connectionState = "didDisconnect, will reconnect"
            connectionStateDelegate?.mqttClientDidEncounterError(error, willAttemptToReconnect: true)
            //mqttClientIsConnecting()
        }
    }
    
    
}

//MARK: - MQTTClientMessageEventDelegate
extension BLEUMQTTClient:MQTTClientMessageEventDelegate {
    
    func mqttClientDidReceiveMessage(message: String?, topic: String) {
        logger.notice("\(#function) topic:'\(topic)', message:\(message ?? "Nil")")
    }
    
    func mqttClientDidPublishMessage(messageId: UInt16, clientId: String) {
        
    }
}
