import Foundation

private let oauthBase = "https://api.wiliot.com"

enum APIPath {
    case receiveAuthToken
    case registerGW(ownerId: String, gatewayId: String)
    case refreshGWToken(refresh_token: String)
}

extension APIPath {
    var path: String {
        switch self {
        case .receiveAuthToken:
            return "/v1/auth/token/api"
        case .registerGW(let ownerId, let gatewayId):
            return "/v1/owner/\(ownerId)/gateway/\(gatewayId)/mobile"
        case .refreshGWToken:
            return "/v1/gateway/refresh"
        }
    }
}

private let kGatewayRefreshTokenKey = "refresh_token"
private let kGatewayAuthTokenKey = "access_token"

// MARK: -
class NetworkService {

    let appKey: String
    let ownerId: String

    init(appKey: String, ownerId: String) {
        self.appKey = appKey
        self.ownerId = ownerId
    }

    private func postRequestWithToken(_ token: String, isBearer: Bool = true, path: String) -> URLRequest {

        let url = URL(string: path)!

        var request = URLRequest(url: url)

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UTF-8", forHTTPHeaderField: "Encoding")
        if !token.isEmpty {
            if isBearer {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                request.setValue("\(token)", forHTTPHeaderField: "Authorization")
            }
        }

        return request
    }

    private func handleBadResponseScenario(error: Error?, data: Data?, response: URLResponse?) -> Error? {
        if let anError = error {

            return anError
        }

        guard let response = response,
              let data = data,
              let httpResponse = response as? HTTPURLResponse else {
            return ValueReadingError.invalidValue("Wrong response received")

        }

        if httpResponse.statusCode != 200 {
            print("Status Code: \(httpResponse.statusCode) for \(response.url!.path)")
            return BadServerResponse.badStatusCode(httpResponse.statusCode, "Unhandled server response")

        }

        if data.isEmpty {
            return ValueReadingError.invalidValue("Response data is empty")
        }

        return nil
    }
}

// MARK: AuthTokenRequester

extension NetworkService: AuthTokenRequester {

    func getAuthToken(completion: @escaping ((AuthTokenResult) -> Void)) {

        let path = APIPath.receiveAuthToken.path

        let request = postRequestWithToken(appKey, isBearer: false, path: oauthBase + path)
        print("getAuthToken: \(request.url!)")
        let authTokenRequestTask = URLSession.shared.dataTask(with: request) {[weak self] data, urlResponse, error in

            guard let self = self else { return }

            if let error = self.handleBadResponseScenario(error: error, data: data, response: urlResponse) {
                completion( .failure(error))
                return
            }

            guard let responseData = data else {
                completion( .failure(ValueReadingError.missingRequiredValue("No Auth Token response data")))
                return
            }

            do {
                // let dict = try JSONSerialization.jsonObject(with: responseData)

                let authData = try JSONDecoder().decode(FusionAuthResponseModel.self, from: responseData)
                completion( .success(authData.accessToken))
            } catch {
                completion( .failure(error))
            }
        }

        authTokenRequestTask.resume()
    }
}

// MARK: GatewayRegistrator

extension NetworkService: GatewayRegistrator {

    func registerGatewayFor(owner ownerId: String, gatewayId: String, authToken: String, completion: @escaping ((TokensResult) -> Void)) {
        let path = APIPath.registerGW(ownerId: ownerId, gatewayId: gatewayId).path

        var request = postRequestWithToken(authToken, path: oauthBase + path)

        let bodyDict = ["gatewayName": Device.deviceId, "gatewayType": "mobile"]
        do {
            let data = try JSONSerialization.data(withJSONObject: bodyDict)
            request.httpBody = data
        } catch {
            completion(.failure(error))
            return
        }

        print("Register gateway Request: \(request.url!.absoluteString), \n Header:\(request.allHTTPHeaderFields), \nbody: \(request.httpBody)")

        let registerTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in

            guard let self = self else {
                return
            }

            if let error = self.handleBadResponseScenario(error: error, data: data, response: response) {
                completion(.failure(error))
                return
            }

            guard let responseData = data else {
                completion( .failure(ValueReadingError.invalidValue("Wrong response received") ) )
                return
            }

            do {
                let tokensInfo = try JSONSerialization.jsonObject(with: responseData)
                guard let tokensDictContainer = tokensInfo as? [String: Any],
                      let tokensDict = tokensDictContainer["data"] as? [String: Any] else {
                    completion( .failure(ValueReadingError.invalidValue("Wrong response format.") ) )
                    return
                }

                self.handleTokensResponse(tokensDict, completion: completion)
            } catch {
                completion( .failure(error))
            }

        }

        registerTask.resume()
    }

    func refreshGatewayTokensWith(refreshToken: String, completion: @escaping ((TokensResult) -> Void)) {

        var path = APIPath.refreshGWToken(refresh_token: refreshToken).path
        path.append("?refresh_token=\(refreshToken)")

        let request = postRequestWithToken("", path: path)

        let refreshTask =
        URLSession.shared.dataTask(with: request) {[weak self] data, urlResponse, error in

            guard let self = self else { return }

            if let error = self.handleBadResponseScenario(error: error,
                                                          data: data,
                                                          response: urlResponse) {
                completion(.failure(error))
                return
            }

            guard let responseData = data else {
                completion( .failure(ValueReadingError.missingRequiredValue("No Response Data")))
                return
            }
            do {
                let tokensInfo = try JSONSerialization.jsonObject(with: responseData)
                guard let tokensDict = tokensInfo as? [String: String] else {
                    completion( .failure(ValueReadingError.invalidValue("Wrong response format.") ) )
                    return
                }

                self.handleTokensResponse(tokensDict, completion: completion)

            } catch {
                completion( .failure(error))
            }
        }

        refreshTask.resume()
    }

    private func handleTokensResponse(_ tokensData: [String: Any], completion: @escaping ((TokensResult) -> Void)) {
            // handle success response
            var tokens = GatewayTokens()

            if let authToken = tokensData[kGatewayAuthTokenKey] as? String {
                tokens.setAuth(authToken)
            }

            if let refresh = tokensData[kGatewayRefreshTokenKey] as? String {
                tokens.setRefresh(refresh)
            }

            if tokens.isEmpty {
                completion(.failure(ValueReadingError.missingRequiredValue("No required tokens to start connection") ) )
                return
            }

            completion( .success(tokens))
    }

}
