import Foundation

// MARK: -

struct FusionAuthResponseModel: Codable {
    var accessToken: String
    var expiresIn: Int?
    var idToken: String?
    var refreshToken: String?
    var tokenType: String?
    var userId: String?
    var scope: String?

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

    private(set)var auth: String?
    private(set)var refresh: String?

    var isEmpty: Bool {
        return auth == nil && refresh == nil
    }

    var isFull: Bool {
        auth != nil && refresh != nil
    }

    mutating func setAuth(_ token: String) {
        auth = token
    }

    mutating func setRefresh(_ token: String) {
        refresh = token
    }
}

extension GatewayTokens {
    init(authToken: String) {
        self.auth = authToken
    }
}
