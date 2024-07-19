//
//  main.swift
//
//  Created by Samil Abud on 7/17/24.
//

import Foundation

struct ProductData: Decodable {
    let generation: String
    let price: Int
}

// Define a struct to match each dictionary in the response array
struct Product: Decodable {
    let id: String
    let name: String
    let data: ProductData
}

// Mock EndpointProvider for testing
struct MockEndpoint: EndpointProvider {
    var baseURL: URL
    var path: String
    var method: String
    var headers: [String: String]?
    var queryParams: [URLQueryItem]?
    var body: [String: Any]? // Implement body property for mock request body parameters
}

// Mock Environment for testing
struct MockEnvironment: EnvironmentProtocol {
    var apiBaseURL: URL
    var apiKey: String
}

// Example test function
func testNetworkManagerCustomValidation() {
    // Create mock data
    let baseURL = URL(string: "https://6698464402f3150fb6708339.mockapi.io/api/test")!
    //let path = "/testdata"; // Path with good data
    let path = "/failuretestdata"; // Path with wrong data
    
    let endpoint = MockEndpoint(baseURL: baseURL, path: path, method: "GET", headers: nil, queryParams: nil, body: nil)
    let environment = MockEnvironment(apiBaseURL: baseURL, apiKey: "mock_api_key")
    let networkManager = NetworkManager(environment: environment)

    // Perform asynchronous request (assuming testing in an async context)
        Task {
            do {
                let products: [Product] = try await networkManager.request(endpoint: endpoint) // Assuming the expected type is an array of Product
                print("Test",products)
            } catch {
                print(error)
            }
        }
}
testNetworkManagerCustomValidation()
sleep(5)
