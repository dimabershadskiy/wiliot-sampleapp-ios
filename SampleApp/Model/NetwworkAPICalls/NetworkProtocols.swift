

import Foundation

typealias AuthTokenResult = Result<String, Error>

protocol AuthTokenRequester {
    func getAuthToken(completion: @escaping ((AuthTokenResult) -> ()))
}

typealias TokensResult = Result<GatewayTokens, Error>

protocol GatewayRegistrator {
    func registerGatewayFor(owner ownerId:String, gatewayId:String, authToken:String, completion: @escaping ((TokensResult) ->()) )
    func refreshGatewayTokensWith(refreshToken:String, completion: @escaping ((TokensResult) ->()))
}
