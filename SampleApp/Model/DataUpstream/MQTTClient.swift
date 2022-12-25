import Foundation
import CocoaMQTT
import JWTDecode

public struct MQTTEndpoint {
    let host: String
    let port: UInt16
    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public protocol MQTTClientDelegate: AnyObject {
    func mqttClientDidConnect()
    func mqttClientDidDisconnect()
    func mqttClientDidEncounterError(_ error: Error)
}

public enum MQTTClientError: Error, CaseIterable {
    case expiringToken
    case invalidTokenUsername
    case mqttClientNotSet
    case mqttClientConnectionNotEstablished
}

private let keepAliveSeconds: UInt16 = 60

public final class MQTTClient {

    public private(set) var clientId: String
    var connectionToken: String
    var endpoint: MQTTEndpoint
    weak var delegate: MQTTClientDelegate?
    var cocoaMQTTDelegate: CocoaMQTTDelegateObject?
    private(set) var connectionState: String = "Unknown"

    private var mqtt: CocoaMQTT?

    // MARK: - Initialization
    deinit {
        #if DEBUG
        print("+ MQTTClient DEINIT +")
        #endif
    }

    public init(clientId: String, connectionToken: String, endpoint: MQTTEndpoint, delegate: MQTTClientDelegate?) throws {
        #if DEBUG
        print("+ MQTTClient INIT+")
        #endif
        self.clientId = clientId
        self.connectionToken = connectionToken
        self.endpoint = endpoint
        self.delegate = delegate
        self.cocoaMQTTDelegate = CocoaMQTTDelegateObject()
        try prepareMQTT()
    }

    // MARK: -
    public func prepareMQTT() throws {
        #if DEBUG
        print("MQTTClient preparing MQTT CLIENT with clientId: \(clientId), token: \(connectionToken)")
        #endif
        if let client = mqtt {
            client.delegate = nil
            client.disconnect()
        }

        let mqtt = CocoaMQTT(clientID: clientId,
                         host: endpoint.host,
                         port: endpoint.port)

        do {
            let jwt: JWT = try decode(jwt: connectionToken) // Gateway Auth token
            if let expDate = jwt.expiresAt {
                let currentDate = Date()
                let tokenExpirationSeconds = expDate.secondsFrom(anotherDate: currentDate)
                print(" - Gateway Token: Time to expire: \(tokenExpirationSeconds) seconds")
                if tokenExpirationSeconds < 100 {
                    throw MQTTClientError.expiringToken
                }
            }

            guard let username = jwt.claim(name: "username").string else {
                throw MQTTClientError.invalidTokenUsername
            }

           // let username: String = jwt.username ?? ""
            mqtt.username = username
            mqtt.password = connectionToken
            mqtt.keepAlive = keepAliveSeconds
            mqtt.autoReconnect = true
            mqtt.autoReconnectTimeInterval = 1
            mqtt.maxAutoReconnectTimeInterval = 10
            mqtt.allowUntrustCACertificate = true // this is bad.
            mqtt.cleanSession = true
            mqtt.enableSSL = true
            mqtt.logLevel = .off// .debug
            mqtt.backgroundOnSocket = true
            self.cocoaMQTTDelegate?.target = self
            mqtt.delegate = self.cocoaMQTTDelegate

        } catch {
            throw error
        }

        self.mqtt = mqtt
    }

    @discardableResult
    public func start() throws -> Bool {
        if let _ = mqtt {
            return connectMQTT()
//            return mqtt.connect()
        } else {
            try prepareMQTT()
        }

        return connectMQTT()
    }

    private func connectMQTT() -> Bool {
        guard let mqtt = self.mqtt else {
            return false
        }

        return mqtt.connect()
    }

    public func stopAndDisconnect() {
        print("+ MQTTClient stopAndDisconnect() --")
        mqtt?.autoReconnect = false
        mqtt?.disconnect()
    }

    public func sendMessage(_ message: String, topic: String) throws {
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
//        print("+ MQTTClient sendMessage. Date: \(Date()), topic: \(topic)")
//        #endif
        mqtt.publish(topic, withString: message, qos: .qos1)
    }

}

extension MQTTClient {
    // MARK: -
    private func trace(_ name: String) {
        #if DEBUG
        print("MQTTClient \(#function) TRACE: \(name)")
        #endif
    }
}

// MARK: - CocoaMQTTDelegateObjectTarget
extension MQTTClient: CocoaMQTTDelegateObjectTarget {
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        trace("did Connect Acknowledgements")
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
//        trace("didPublishMessage: \(message), id: \(id)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16) {
        trace("didPublishComplete: \(id)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
//        trace("didPublishAck: \(id)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        trace("didReceiveMessage: \( String(data: Data(message.payload), encoding: .utf8) ?? "-unparsed-")")
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        trace("didSubscribeTopics: \(success) \nfalied: \(failed)")
    }

    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        trace("didUnsubscribeTopics: [\(topics)]")
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        if let error = err {
            trace("did disconnect: \(err.debugDescription)")
            print("MQTT DISCONNECTION ERROR:\n \(error)\n")
            connectionState = "didDisconnect, Error(\(error.localizedDescription)"
            let customError = NSError(domain: "com.MQTTCient",
                                      code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "MQTT connection lost with cause: \(connectionState)"])

            delegate?.mqttClientDidEncounterError(error)
        } else {
            trace("did disconnect: \(err.debugDescription)")
            print("MQTT DISCONNECTED")
            connectionState = "didDisconnect"

            if !mqtt.autoReconnect {
                self.mqtt = nil
            }
            delegate?.mqttClientDidDisconnect()
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
            connectionState = state.description
            delegate?.mqttClientDidConnect()

        case .disconnected:
            connectionState = state.description

            // stopAndDisconnect()
            delegate?.mqttClientDidDisconnect()

        case .connecting:
            connectionState = state.description
            return
        }
    }
}

 // MARK: - Date extension
private extension Date {
func secondsFrom(anotherDate: Date) -> Int {
        let seconds = Calendar.current.dateComponents([.second], from: anotherDate, to: self).second ?? 0
        return seconds
    }
}

protocol CocoaMQTTDelegateObjectTarget: AnyObject {
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

class CocoaMQTTDelegateObject: NSObject, CocoaMQTTDelegate {

    weak var target: CocoaMQTTDelegateObjectTarget?

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
