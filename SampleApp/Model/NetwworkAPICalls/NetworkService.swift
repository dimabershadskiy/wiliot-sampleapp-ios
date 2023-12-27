import Foundation



fileprivate let oauthBase = "https://api.us-east-2.prod.wiliot.cloud"


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
    
    let appKey:String
    let ownerId:String
    
    private var tempTokenRequestDataTask:URLSessionDataTask?
    
    init(appKey:String, ownerId:String) {
        #if DEBUG
        print("Network Requests will be spawned with AppKey:'\(appKey)', ownerId:'\(ownerId)'")
        #endif
        self.appKey = appKey
        self.ownerId = ownerId
    }
    
    
    private func postRequestWithToken(_ token:String, isBearer:Bool = true, path:String) -> URLRequest? {
        
        guard let url = URL(string:path) else {
            return nil
        }
        
        #if DEBuG
        print("POST URL: \(url)")
        #endif
        
        var request = URLRequest(url:url)
        
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
    
    private func handleBadResponseScenario(_ response:DataTaskResponse) -> Error? {
        if let anError = response.error {
            
            return anError
        }
        
        
        guard let urlResponse = response.urlResponse,
              let data = response.data,
              let httpResponse = urlResponse as? HTTPURLResponse else {
            return ValueReadingError.invalidValue("Wrong response received")

        }
        let code = httpResponse.statusCode
        
        if code != 200 {
            #if DEBUG
            print("Status Code: \(code) for \(urlResponse.url?.path ?? "--")")
            #endif
            
            if code == 401 {
                return BadServerResponse.badStatusCode(httpResponse.statusCode, "Unauthorized. check tokens..")
            }
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
        
        guard var request = postRequestWithToken(appKey, isBearer: false, path: oauthBase + path) else {
            completion(.failure(ValueReadingError.invalidValue("NO URL Request for get auth token")))
            return
        }
        
        request.timeoutInterval = 15
        
        #if DEBUG
        print("getAuthToken(completion: \(request.url?.path ?? "----")")
        #endif
        
        let authTokenRequestTask = URLSession.shared.dataTask(with: request) {[weak self] data, urlResponse, error in
            
            guard let self = self else {
                return
            }
            let response = DataTaskResponse(data: data, urlResponse: urlResponse, error: error)
            
            self.handleAuthTokenResponse(response, completionBlock: completion)
        }
        
        self.tempTokenRequestDataTask = authTokenRequestTask
        authTokenRequestTask.resume()
    }
    
    private func handleAuthTokenResponse(_ response:DataTaskResponse, completionBlock completion: @escaping ((AuthTokenResult) -> ()) ) {
        defer {
            self.tempTokenRequestDataTask = nil
        }
        
        if let error = self.handleBadResponseScenario(response) {
            completion( .failure(error))
            return
        }
        
        guard let responseData = response.data else {
            completion( .failure(ValueReadingError.missingRequiredValue("No Auth Token response data")))
            return
        }

        do {
            
            let authData = try JSONDecoder().decode(FusionAuthResponseModel.self, from: responseData)
            completion( .success(authData.accessToken))
        }
        catch {
            completion( .failure(error))
        }
    }
}

// MARK: GatewayRegistrator

extension NetworkService: GatewayRegistrator {

    func registerGatewayFor(owner ownerId: String, gatewayId: String, authToken: String, completion: @escaping ((TokensResult) -> Void)) {
        let path = APIPath.registerGW(ownerId: ownerId, gatewayId: gatewayId).path
        
        guard let urlRequest = postRequestWithToken(authToken, path: oauthBase + path) else {
            completion(.failure(ValueReadingError.invalidValue("No URL Request for registering gateway")))
            return
        }
                
        var request = urlRequest
       
        let bodyDict = ["gatewayName": Device.deviceId, "gatewayType": "mobile"]
        do {
            let data = try JSONSerialization.data(withJSONObject: bodyDict)
            request.httpBody = data
        } catch {
            completion(.failure(error))
            return
        }
        #if DEBUG
        print("Register gateway Request: \(request.url!.absoluteString), \n Header:\(String(describing: request.allHTTPHeaderFields)), \nbody: \(String(describing: request.httpBody))")
        #endif
        
        let registerTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in

            guard let self = self else {
                return
            }
            
            let dtResponse = DataTaskResponse(data: data, urlResponse: response, error: error)
            if let error = self.handleBadResponseScenario(dtResponse) {
                completion(.failure(error))
                return
            }
            
            
            guard let responseData = dtResponse.data else {
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
        
        guard let request = postRequestWithToken("", path: path) else {
            completion(.failure(ValueReadingError.invalidValue("No URL Request for Refresh gateway token")))
            return
        }
        
        let refreshTask =
        URLSession.shared.dataTask(with: request) {[weak self] data, urlResponse, error in

            guard let self = self else { return }
            
            let dtResponse = DataTaskResponse(data: data, urlResponse: urlResponse, error: error)
            
            if let error = self.handleBadResponseScenario(dtResponse) {
                completion (.failure(error))
                return
            }
            
            guard let responseData = dtResponse.data else {
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
    
    private func handleTokensResponse(_ tokensData:[String:Any], completion: @escaping ((TokensResult) -> ())) {
            //handle success response
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
