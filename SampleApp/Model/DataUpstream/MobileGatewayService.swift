import Foundation
import UIKit

class Device {
    static var deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
}

class MobileGatewayService {
    private(set) var authToken: String?
    private(set) var gatewayAccessToken: String?
    private(set) var gatewayRefreshToken: String?
    /// send event outside for interested client (for debug or some UI updates like blink some indicator
    private(set) var sendEventSignal: (()->Void)?
    var didConnectCompletion: ((Bool) ->Void)?
    /// completio on Did Disconnect message from the MQTTClient
    var didStopCompletion: (()->Void)?
    var authTokenCallback: ((Error?) ->Void)?
    var gatewayTokensCallBack: ((Error?) -> Void)?
    var isConnected: Bool = false

    let gatewayType: String = "Wiliot iPhone"

    private let currentOwnerId: String

    private lazy var gatewayId: String = {
        let anID = Device.deviceId
        return anID
    }()

    private var isConnecting = false
    private var mqttClient: MQTTClient?
    private let gatewayRegistrator: GatewayRegistrator
    private let authTokenRequester: AuthTokenRequester

    private enum Topic: String {
        case data
        case status
        case bridgeStatus = "bridge-status"
    }

    // MARK: - Init

    init(ownerId: String, authTokenRequester: AuthTokenRequester, gatewayRegistrator: GatewayRegistrator) {

        self.currentOwnerId = ownerId

        self.gatewayRegistrator = gatewayRegistrator
        self.authTokenRequester = authTokenRequester
    }

    deinit {
        mqttClient = nil
        print("+ MobileGatewayService deinit +")
    }

    // MARK: - Authorization

    func obtainAuthToken() {

        authTokenRequester.getAuthToken {[weak self] tokenResult in
            guard let self = self else {
                return
            }

            switch tokenResult {
            case .failure(let error):
                self.authTokenCallback?(error)
            case .success(let authToken):
                self.authToken = authToken
                self.authTokenCallback?(nil)
            }
        }
    }

    func registerAsGateway(userAuthToken token: String, ownerId: String) {
        gatewayRegistrator.registerGatewayFor(owner: ownerId, gatewayId: gatewayId, authToken: token) { [weak self] gatewayTokensResult in
            guard let self = self else {
                return
            }

            switch gatewayTokensResult {
            case .failure(let error):
                self.gatewayTokensCallBack?(error)
            case .success(let tokens):
                self.gatewayAccessToken = tokens.auth
                self.gatewayRefreshToken = tokens.refresh
                self.gatewayTokensCallBack?(nil)
            }

        }
    }

    func refreshRegistration(gatewayRefreshToken refreshToken: String) {
        gatewayRegistrator.refreshGatewayTokensWith(refreshToken: refreshToken) { [weak self] gatewayTokensResult in
            guard let self = self else {
                return
            }

            switch gatewayTokensResult {
            case .failure(let error):
                self.gatewayTokensCallBack?(error)
            case .success(let tokens):
                self.gatewayAccessToken = tokens.auth
                self.gatewayRefreshToken = tokens.refresh
                self.gatewayTokensCallBack?(nil)
            }
        }
    }

    // MARK: - Connection
    func startConnection(withGatewayToken gwAuthToken: String) -> Bool {

        guard !isConnecting else {
            return false
        }

        isConnecting = true

        do {
            let client = try MQTTClient(clientId: gatewayId,
                                         connectionToken: gwAuthToken,
                                         endpoint: MQTTEndpoint.defaultEndpoint,
                                         delegate: self)
            let started = try client.start()
            self.mqttClient = client
            return started
        } catch {
            isConnecting = false
            isConnected = false
            didConnectCompletion?(false)
            return false
        }
    }

    func stop() {
        self.mqttClient?.stopAndDisconnect()
        // self.mqttClient = nil
    }

    func setSendEventSignal(_ eventHandler: @escaping(()->Void)) {
        self.sendEventSignal = eventHandler
    }

    // MARK: - Topic
    private func getTopicString(topic: Topic) -> String? {

        guard let clientId = mqttClient?.clientId else {
            return nil
        }

        let topicName = topic.rawValue
        let ownerId = currentOwnerId

        let toReturn = "\(topicName)-prod/\(ownerId)/\(clientId)"
        return toReturn
    }

    // MARK: - MQTT transmissions
    // MARK: TagPacketsSender
}

extension MobileGatewayService: TagPacketsSender {
    func sendPacketsInfo(_ info: [TagPacketData]?) {
            guard let topicToPublish = getTopicString(topic: .data) else {
                return
            }

            let gatewayPacketsData = GatewayPacketsData(location: nil, packets: info)

            do {
                let messageData = try GatewayDataEncoder.encode(gatewayPacketsData)
                let messageString = try GatewayDataEncoder.encodeDataToString(messageData)
//                #if DEBUG
//                var debugStr = ""
//                let jsonTransObject = try JSONSerialization.jsonObject(with: messageData,
//                                                                       options: .fragmentsAllowed)
//
//                let jsonDataPretty = try JSONSerialization.data(withJSONObject: jsonTransObject,
//                                                                options: .prettyPrinted)
//                if let prettyString = String(data: jsonDataPretty, encoding: .utf8) {
//                    debugStr.append("\(prettyString),\n")
//                }
//                print("MobileGatewayService sendPacketsInfo: \(debugStr)")
//                #endif
                try mqttClient?.sendMessage(messageString, topic: topicToPublish)
                sendEventSignal?()
            } catch {
                print("MobileGatewayService sendPacketsInfo. Error sending message:\(error)")
            }
        }
}

// MARK: - MQTTClientDelegate
extension MobileGatewayService: MQTTClientDelegate {
    func mqttClientDidConnect() {
        isConnecting = false
        self.isConnected = true
        didConnectCompletion?(true)
    }

    func mqttClientDidDisconnect() {
        isConnecting = false
        self.isConnected = false
        self.isConnected = false
        self.mqttClient = nil
        didStopCompletion?()
    }

    func mqttClientDidEncounterError(_ error: Error) {
        print("MobileGatewayService mqttClientDidEncounterError() Error:\(error)")
        isConnecting = false
        self.isConnected = false
        self.isConnected = false

    }
}

// MARK: -
extension MQTTEndpoint {
    static var defaultEndpoint: MQTTEndpoint {
        MQTTEndpoint(host: "mqttv2.wiliot.com", port: 8883)
    }
}
