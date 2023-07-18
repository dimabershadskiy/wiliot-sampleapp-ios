//
//  WeakObject.swift


import Foundation
final class WeakObject<T: AnyObject> {
    weak var object: T?
    
    init(_ object: T) {
        self.object = object
    }
}


extension WeakObject:AuthTokenRequester where T:AuthTokenRequester {
    func getAuthToken(completion: @escaping ((AuthTokenResult) -> ())) {
        object?.getAuthToken(completion: completion)
    }
}

extension WeakObject:GatewayRegistrator where T:GatewayRegistrator {
    
    func registerGatewayFor(owner ownerId: String, gatewayId: String, authToken: String, completion: @escaping ((TokensResult) -> ())) {
        object?.registerGatewayFor(owner: ownerId, gatewayId: gatewayId, authToken: authToken, completion: completion)
    }
    
    func refreshGatewayTokensWith(refreshToken: String, completion: @escaping ((TokensResult) -> ())) {
        object?.refreshGatewayTokensWith(refreshToken: refreshToken, completion: completion)
    }
}

extension WeakObject: LocationSource where T:LocationSource {
    func getLocation() -> Location? {
        object?.getLocation()
    }
}

extension WeakObject: BridgePayloadsReceiving where T:BridgePayloadsReceiving {
    func receiveBridgeMassagePayloadPacket(_ bridgeMessagePacket: BLEPacket) {
        object?.receiveBridgeMassagePayloadPacket(bridgeMessagePacket)
    }
}

extension WeakObject: MQTTClientEventDelegate where T:MQTTClientEventDelegate {
    func didPublishMessage() {
        object?.didPublishMessage()
    }
    
    func didReceivePong() {
        object?.didReceivePong()
    }
    
    func didPing() {
        object?.didPing()
    }
}
