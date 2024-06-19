//
//  Errors.swift
//  Wiliot Mobile
//
//  Created by Ivan Yavorin on 13.05.2022.
//

import Foundation

public enum CodingError:Error {
    case decodingFailed(Error?)
    case encodingFailed(Error?)
}


extension CodingError {
    public var description:String {
        switch self {
        case .decodingFailed(let optionalError):
            return "Decoding Failed. Error: \(optionalError?.localizedDescription ?? "Unknown")"
        case .encodingFailed(let optionalError):
            return "Encoding Failed. Error: \(optionalError?.localizedDescription ?? "Unknown")"
        }
    }
}

public enum ValueReadingError : LocalizedError {
    case notFound
    case invalidValue(String? = nil)
    case missingRequiredValue(String? = nil)
    
    public var errorDescription: String? {
        return description
    }
}

//MARK: - descriptions

extension ValueReadingError : CustomStringConvertible {
    public var description: String {
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
    
    public var descriptionMessage:String {
        var toReturn = ""
        
        switch self {
        case .notFound:
            toReturn = "Not Found"
        case .invalidValue(let optionalDetails):
            if let detail = optionalDetails {
                toReturn = detail
            }
        case .missingRequiredValue(let optionalDetails):
            if let detail = optionalDetails {
                toReturn = detail
            }
        }
        
        return toReturn
    }
}


public enum PixelResolverError:Error {
    case badStatusCode(Int)
    case badStatusCodeWithMessage(Int, String)
    case resolveDenied
}



public enum TokenRefreshError: Error {
    case failedToSaveUserToken
    case notFinishedCancelled
    case responseError
    case emptyResponse
}

public enum LoginError:Error {
    case invalidCredentials
    case twoFactorNeeded
}




