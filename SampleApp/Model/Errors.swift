import Foundation

enum CodingError: Error {
    case decodingFailed(Error?)
    case encodingFailed(Error?)
}

extension CodingError {
    var description: String {
        switch self {
        case .decodingFailed(let optionalError):
            return "Decoding Failed. Error: \(optionalError?.localizedDescription ?? "Unknown")"
        case .encodingFailed(let optionalError):
            return "Encoding Failed. Error: \(optionalError?.localizedDescription ?? "Unknown")"
        }
    }
}

enum ValueReadingError: LocalizedError {
    case notFound
    case invalidValue(String? = nil)
    case missingRequiredValue(String? = nil)

    var errorDescription: String? {
        return description
    }
}

extension ValueReadingError: CustomStringConvertible {
    var description: String {
        var toReturn = ""

        switch self {
        case .notFound:
            toReturn = "Not Found"
        case .invalidValue(let optionalDetails):

            toReturn = "Invalid value"
            if let detail = optionalDetails {
                toReturn.append(": \(detail)")
            }
        case .missingRequiredValue(let optionalDetails):
            toReturn = "Missing Required value"
            if let detail = optionalDetails {
                toReturn.append(": \(detail)")
            }
        }

        return toReturn
    }
}

enum BadServerResponse: LocalizedError {
    case badStatusCode(Int? = nil, String? = nil)
    case badResponse(String? = nil)
}

extension BadServerResponse: CustomStringConvertible {
    var description: String {
        var descriptionString = ""

        switch self {
        case .badStatusCode(let code, let message):
            descriptionString = "Bad Status Code"
            if let code = code {
                descriptionString.append(": \(code)")
            }
            if let message = message {
                descriptionString.append(", message: \(message)")
            }

        case .badResponse(let message):
            descriptionString = "Bad Response"
            if let message = message {
                descriptionString.append(", message: \(message)")
            }
        }

        return descriptionString
    }
}
