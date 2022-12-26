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

public final class MQTTClient: NSObject {

    public private(set) var clientId: String
    var connectionToken: String
    var endpoint: MQTTEndpoint
    weak var delegate: MQTTClientDelegate?
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

        super.init()

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
        mqtt.delegate = self

        self.mqtt = mqtt
    }

    @discardableResult
    public func start() throws -> Bool {
        if mqtt == nil {
            try prepareMQTT()
        }
        return connectMQTT()
    }

    private func connectMQTT() -> Bool {
        return mqtt?.connect() ?? false
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
        guard let mqtt else {
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

// MARK: - CocoaMQTTDelegate
extension MQTTClient: CocoaMQTTDelegate {
    public func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    public func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        trace("did Connect Acknowledgements")
    }

    public func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
//        trace("didPublishMessage: \(message), id: \(id)")
    }

    public func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16) {
        trace("didPublishComplete: \(id)")
    }

    public func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
//        trace("didPublishAck: \(id)")
    }

    public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        trace("didReceiveMessage: \( String(data: Data(message.payload), encoding: .utf8) ?? "-unparsed-")")
    }

    public func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        trace("didSubscribeTopics: \(success) \nfalied: \(failed)")
    }

    public func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        trace("didUnsubscribeTopics: [\(topics)]")
    }

    public func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        if let error = err {
            trace("did disconnect: \(err.debugDescription)")
            print("MQTT DISCONNECTION ERROR:\n \(error)\n")
            connectionState = "didDisconnect, Error(\(error.localizedDescription)"

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

    public func mqttDidPing(_ mqtt: CocoaMQTT) {
        trace("did ping")
    }

    public func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        trace("did recieve pong")
    }

    public func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        trace("didStateChange To: \(state.description)")
        switch state {
        case .connected:
            connectionState = state.description
            delegate?.mqttClientDidConnect()
        case .disconnected:
            connectionState = state.description
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
        return Calendar.current.dateComponents([.second], from: anotherDate, to: self).second ?? 0
    }
}
