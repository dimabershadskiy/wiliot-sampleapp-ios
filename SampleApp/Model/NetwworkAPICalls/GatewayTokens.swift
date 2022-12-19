import Foundation

// MARK: -

struct FusionAuthResponseModel: Codable {
    let accessToken: String
    let expiresIn: Int?
    let idToken: String?
    let refreshToken: String?
    let tokenType: String?
    let userId: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case userId
        case scope
    }
}

// MARK: -
struct GatewayTokens: Codable {

    let auth: String?
    let refresh: String?

    var isEmpty: Bool {
        return auth == nil && refresh == nil
    }

    var isFull: Bool {
        auth != nil && refresh != nil
    }

    init(authToken: String?, refresh: String?) {
        self.auth = authToken
        self.refresh = refresh
    }
}
