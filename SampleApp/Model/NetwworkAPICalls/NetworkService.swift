

import Foundation



fileprivate let oauthBase = "https://api.us-east-2.test.wiliot.cloud" //"https://api.us-east-2.prod.wiliot.cloud"


let kTempTokenString = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IjFJbThxS1hTcTk2a2czZTc2RndaNEt4UThTcyJ9.eyJhdWQiOiIyMWZmZDQ0NC03NmUyLTRjM2YtOTMxNy0zOGM1ZmRkYjE2OWQiLCJleHAiOjE2ODkyODU3NTcsImlhdCI6MTY4OTI0MjU1NywiaXNzIjoiYWNtZS5jb20iLCJzdWIiOiI5ZDQ3NzFiNi00ZDNkLTQ5NGUtYTgzMS04MTBiZmIxMjI1YzIiLCJqdGkiOiJkZDBiODk1NC04YjlmLTRlN2QtYTAyYy05ZmRlZjg4ZTg0MGIiLCJhdXRoZW50aWNhdGlvblR5cGUiOiJQQVNTV09SRCIsImVtYWlsIjoiaXZhbi55YXZvcmluQHdpbGlvdC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwicHJlZmVycmVkX3VzZXJuYW1lIjoiaXZhbi55YXZvcmluQHdpbGlvdC5jb20iLCJhcHBsaWNhdGlvbklkIjoiMjFmZmQ0NDQtNzZlMi00YzNmLTkzMTctMzhjNWZkZGIxNjlkIiwicm9sZXMiOlsiYWRtaW4iLCJwcm9mZXNzaW9uYWwtc2VydmljZXMiLCJnYXRld2F5Il0sImF1dGhfdGltZSI6MTY4OTI0MjU1NywidGlkIjoiMzg2MjM1NjItMzQzNS0zNjMyLTY1MzgtNjUzNTYzMzUzNTY0IiwibGFzdE5hbWUiOiJXaWxpb3QiLCJmdWxsTmFtZSI6Ikl2YW4gV2lsaW90Iiwib3duZXJzIjp7IjM2NTMyMDM1NDIxOSI6eyJyb2xlcyI6WyJhZG1pbiJdfSwid2lsaW90MSI6eyJyb2xlcyI6WyJlZGl0b3IiXX0sIjMxODExMTExMjUxMCI6eyJyb2xlcyI6WyJhZG1pbiJdfSwiMzMzOTcxMTAxNzI2Ijp7InJvbGVzIjpbImFkbWluIl19LCJ3aWxpb3QiOnsicm9sZXMiOlsiYWRtaW4iXX0sIjk0NTY4MzcwODUzNyI6eyJyb2xlcyI6WyJhZG1pbiJdfSwiYXV0b3Rlc3QiOnsicm9sZXMiOlsiZWRpdG9yIl19LCI0NTY3NzQ3MDgwNjciOnsicm9sZXMiOlsiYWRtaW4iXX0sIjI1NDM1MDg1MzY0NiI6eyJyb2xlcyI6WyJhZG1pbiJdfSwiNjUwNzkzOTg3NDEyIjp7InJvbGVzIjpbImFkbWluIl19fSwiZmlyc3ROYW1lIjoiSXZhbiIsInVzZXJuYW1lIjoiaXZhbi55YXZvcmluQHdpbGlvdC5jb20ifQ.zKcpJJp1WaNEtkTWxPJCr-2a94KgJ1evt4_cYfyoQLIKZoJZVFwILONzDUHqAPu7f6Q_N9o9gQejOmTnBFxzPzpK8s7-5xZKESUUdlV8Aeahj4NbcmKtbQS9IHAWVJq9MRVrFpp4ycq23imyq2NjDObSaCW2evasn0zEYPZHepDAUw2R99q0xeR2TOVQPa17hu3ovJiFXstkxjoDGJ8IgTD5EQaB7TNJwpATbB9Fz2hjNDWlIHvRzNgio7d5ZiQ8WQ4wfcZC26H3Vk9YZPeSX1nDOha-iNsJZPXpw6VSq_ZR2UrBNM3WnIG1G3urAeR_xKnRWyanIpEMAFzfzk426w"

enum APIPath {
    case receiveAuthToken
    case registerGW(ownerId: String, gatewayId: String)
    case refreshGWToken(refresh_token: String)
}

extension APIPath {
    var path:String {
        switch self{
        case .receiveAuthToken:
            return "/v1/auth/token/api"
        case .registerGW(let ownerId, let gatewayId):
            return "/v1/owner/\(ownerId)/gateway/\(gatewayId)/mobile"
        case .refreshGWToken( _):
            return "/v1/gateway/refresh"
        }
    }
}


fileprivate let kGatewayRefreshTokenKey = "refresh_token"
fileprivate let kGatewayAuthTokenKey = "access_token"


//MARK: -
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
            }
            else {
                request.setValue("\(token)", forHTTPHeaderField: "Authorization")
            }
        }
        
        return request
    }
    
    private func handleBadResponseScenario(error:Error?, data:Data?, response:URLResponse?) -> Error? {
        if let anError = error {
            
            return anError
        }
        
        guard let response = response,
              let data = data,
              let httpResponse = response as? HTTPURLResponse else {
            return ValueReadingError.invalidValue("Wrong response received")
            
        }
        let code = httpResponse.statusCode
        
        if code != 200 {
            print("Status Code: \(code) for \(response.url!.path)")
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

//MARK: AuthTokenRequester

extension NetworkService : AuthTokenRequester {
    
    
    func getAuthToken(completion: @escaping ((AuthTokenResult) -> ())) {
        
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
            
            if let error = self.handleBadResponseScenario(error: error, data: data, response: urlResponse) {
                #if DEBUG
                completion(.success(kTempTokenString))
                #else
                completion( .failure(error))
                #endif
                self.tempTokenRequestDataTask = nil
                return
            }
            
            guard let responseData = data else {
                completion( .failure(ValueReadingError.missingRequiredValue("No Auth Token response data")))
                self.tempTokenRequestDataTask = nil
                return
            }

            do {
                
                let authData = try JSONDecoder().decode(FusionAuthResponseModel.self, from: responseData)
                completion( .success(authData.accessToken))
            }
            catch {
                completion( .failure(error))
            }
            self.tempTokenRequestDataTask = nil
        }
        
        self.tempTokenRequestDataTask = authTokenRequestTask
        authTokenRequestTask.resume()
    }
}

//MARK: GatewayRegistrator

extension NetworkService:GatewayRegistrator {
    
    func registerGatewayFor(owner ownerId: String, gatewayId:String, authToken: String, completion: @escaping ((TokensResult) -> ())) {
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
        }
        catch {
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
                guard let tokensDictContainer = tokensInfo as? [String:Any],
                      let tokensDict = tokensDictContainer["data"] as? [String:Any] else {
                    completion( .failure(ValueReadingError.invalidValue("Wrong response format.") ) )
                    return
                }
                
                self.handleTokensResponse(tokensDict, completion:completion)
            }
            catch{
                completion( .failure(error))
            }
 
        }
        
        registerTask.resume()
    }
    
    func refreshGatewayTokensWith(refreshToken: String, completion : @escaping ((TokensResult) -> ())) {
        
        var path = APIPath.refreshGWToken(refresh_token: refreshToken).path
        path.append("?refresh_token=\(refreshToken)")
        
        guard let request = postRequestWithToken("", path: path) else {
            completion(.failure(ValueReadingError.invalidValue("No URL Request for Refresh gateway token")))
            return
        }
        
        let refreshTask =
        URLSession.shared.dataTask(with: request)  {[weak self] data, urlResponse, error in
            
            guard let self = self else { return }
            
            if let error = self.handleBadResponseScenario(error: error,
                                                          data: data,
                                                          response:urlResponse) {
                completion (.failure(error))
                return
            }
            
            guard let responseData = data else {
                completion( .failure(ValueReadingError.missingRequiredValue("No Response Data")))
                return
            }
            do {
                let tokensInfo = try JSONSerialization.jsonObject(with: responseData)
                guard let tokensDict = tokensInfo as? [String:String] else {
                    completion( .failure(ValueReadingError.invalidValue("Wrong response format.") ) )
                    return
                }
                
                self.handleTokensResponse(tokensDict, completion: completion)
                
            }
            catch {
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
