import os.log
import Alamofire
import Foundation

enum NetworkError: Error {
    case decodingError(Error)
    case timeoutError
    case noConnection
    case invalidRequest
    case clientError(statusCode: Int)
    case serverError(statusCode: Int)
    case unexpectedResponse(underlyingError: Error?)
    case unknownError(error: Error)
    case customValidationError(String)
}

protocol EnvironmentProtocol {
    var apiBaseURL: URL { get }
    var apiKey: String { get }
}

protocol EndpointProvider {
    var baseURL: URL { get }
    var path: String { get }
    var method: String { get }
    var headers: [String: String]? { get }
    var queryParams: [URLQueryItem]? { get }
    var body: [String: Any]? { get } // Define body property for request body parameters
}


protocol NetworkManagerProtocol {
    /// Makes an asynchronous network request to a specified endpoint and decodes the response into the given type.
    /// - Parameters:
    ///   - endpoint: The endpoint provider specifying the details of the request.
    /// - Returns: A decoded object of type `T` representing the response data.
    /// - Throws: A `NetworkError` if there's an issue with the request or response handling.
    func request<T: Decodable>(endpoint: EndpointProvider) async throws -> T
}

class NetworkManager: NetworkManagerProtocol {
    private var environment: EnvironmentProtocol
    private let loggingEnabled: Bool
    private var certificates: [String : PinnedCertificatesTrustEvaluator]
    
    init(environment: EnvironmentProtocol, loggingEnabled: Bool = true, certificates: [String : PinnedCertificatesTrustEvaluator] = [:]) {
        self.environment = environment
        self.loggingEnabled = loggingEnabled
        self.certificates = certificates
    }
    
    func request<T: Decodable>(endpoint: EndpointProvider) async throws -> T {
        // Access the `apiBaseURL` property directly from the environment
        var url = environment.apiBaseURL.appendingPathComponent(endpoint.path)
        var parameters: [String: Any]? = nil
        var headers: HTTPHeaders = HTTPHeaders(endpoint.headers ?? [:])
        
        handleQueryItems(endpoint.queryParams, &url)
        handleBodyParams(endpoint, parameters: &parameters, &headers)
        
        let alamofireMethod = Alamofire.HTTPMethod(rawValue: endpoint.method)
        
        logNetworkEvent(type: .debug, message: "⬆️ Network Request:", url: url.absoluteString, method: endpoint.method, requestHeaders: headers, requestBody: parameters)
        
        let session = Session(serverTrustManager: .init(allHostsMustBeEvaluated: false, evaluators: certificates))
        
        let response = await session.request(url, method: alamofireMethod, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
            .serializingDecodable(T.self)
            .response
        
        switch response.result {
        case .success(let decodedObject):
            // Custom Validation
            if !isValidResponse(decodedObject) {
                throw NetworkError.customValidationError("Specific validation failure message")
            }
            return decodedObject
        case .failure(let error):
            logNetworkEvent(type: .error, message: "❌ Network Error:", url: url.absoluteString, error: error, data: response.data)
            throw mapAFErrorToNetworkError(error)
        }
    }
    
    private func mapAFErrorToNetworkError(_ error: AFError) -> NetworkError {
            switch error {
            case .responseSerializationFailed(reason: .decodingFailed(error: let decodingError)):
                logNetworkEvent(type: .error, message: "Response decoding failed:", error: decodingError)
                return .decodingError(decodingError)
            case .sessionTaskFailed(error: let taskError as URLError):
                switch taskError.code {
                case .timedOut:
                    return .timeoutError
                case .notConnectedToInternet:
                    return .noConnection
                default:
                    return .unknownError(error: taskError)
                }
            case .urlRequestValidationFailed:
                return .invalidRequest
            case .responseValidationFailed(reason: let reason):
                logNetworkEvent(type: .error, message: "Response validation failed:", error: AFError.responseValidationFailed(reason: reason).underlyingError)
                if case let .unacceptableStatusCode(code) = reason {
                    switch code {
                    case 400..<500:
                        return .clientError(statusCode: code)
                    case 500...:
                        return .serverError(statusCode: code)
                    default:
                        return .unexpectedResponse(underlyingError: error) // Use generic unexpectedResponse for other status codes
                    }
                } else {
                    return .unexpectedResponse(underlyingError: error) // Catch other response validation failures
                }
            default:
                logNetworkEvent(type: .error, message: "Unexpected AFError:", error: error)
                return .unknownError(error: error)
            }
        }
    
    /// Helper methods
    private func handleQueryItems(_ queryItems: [URLQueryItem]?, _ url: inout URL) {
        if let queryItems {
            let components = NSURLComponents(string: url.absoluteString)!
            components.queryItems = queryItems
            url = components.url!
        }
    }
    
    private func handleBodyParams(_ endpoint: EndpointProvider, parameters: inout [String : Any]?, _ headers: inout HTTPHeaders) {
        if endpoint.method == "POST" || endpoint.method == "PUT" || endpoint.method == "PATCH" {
            parameters = endpoint.body
        }
    }
    
    /// A generic logging function that handles network request, response, and error logs using OSLog.
    ///
    /// - Parameters:
    ///   - type: The log type (`.debug` or `.error`).
    ///   - message: The log message.
    ///   - url: The URL of the network request (optional).
    ///   - statusCode: The status code of the network response (optional).
    ///   - error: The network error, if any (optional).
    ///   - data: The response data or error data, if available (optional).
    private func logNetworkEvent(
        type: OSLogType,
        message: String,
        url: String? = nil,
        method: String? = nil,
        statusCode: Int? = nil,
        error: Error? = nil,
        data: Any? = nil,
        requestHeaders: HTTPHeaders? = nil,
        requestBody: Any? = nil
    ) {
        guard loggingEnabled else { return }
        var logMessage = "[NetworkManager] " + message

        if let url = url {
            logMessage += "\n 🌐 URL: \(url)"
            if let components = URLComponents(string: url), let queryItems = components.queryItems {
                let queryParams = queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
                logMessage += "\n 📝 Query Parameters: \(queryParams)"
            }
        }

        if let method = method {
            logMessage += "\n ⚙️ Method: \(method)"
        }

        if let statusCode = statusCode {
            var statusEmoji = ""
            switch statusCode {
            case 200...299:
                statusEmoji = "✅" // Success
            case 300...399:
                statusEmoji = "🔄" // Redirection
            case 400...499:
                statusEmoji = "⚠️" // Client Error
            case 500...599:
                statusEmoji = "❌" // Server Error
            default:
                statusEmoji = "❓" // Unknown
            }
            logMessage += "\n \(statusEmoji) Status Code: \(statusCode)"
        }

        if let error = error {
            logMessage += "\n ❌ Error: \(error)"
        }

        if let requestHeaders = requestHeaders {
            logMessage += "\n 📥 Request Headers:"
            requestHeaders.forEach { header in
                logMessage += "\n  \(header)"
            }
        }

        if let requestBody = requestBody {
            logMessage += "\n 📦 Request Body: \(requestBody)"
        }

        if let data = data {
            logMessage += "\n 📄 Data: \(data)"
        }

        os_log(type, log: .default, "%@", logMessage)
    }

    private func isValidResponse<T>(_ response: T) -> Bool {
        // Custom validation logic here
        return true
    }
}
