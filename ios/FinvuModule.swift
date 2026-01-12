import ExpoModulesCore
import FinvuSDK

/**
 * Maps error code to standardized error code string
 * Handles both backend error codes and SDK error codes
 */
func mapErrorCode(_ error: NSError?) -> String {
    guard let error = error else {
        return "9999" // GENERIC_ERROR
    }
    
    // Check if error has a string code in userInfo
    if let codeString = error.userInfo["code"] as? String {
        return codeString
    }
    
    // Map numeric SDK error codes to string codes
    switch error.code {
    case 1001:
        return "1001" // AUTH_LOGIN_RETRY
    case 1002:
        return "1002" // AUTH_LOGIN_FAILED
    case 1003:
        return "1003" // AUTH_FORGOT_PASSWORD_FAILED
    case 1004:
        return "1004" // AUTH_LOGIN_VERIFY_MOBILE_NUMBER
    case 1005:
        return "1005" // AUTH_FORGOT_HANDLE_FAILED
    case 8000:
        return "8000" // SESSION_DISCONNECTED
    case 8001:
        return "8001" // SSL_PINNING_FAILURE_ERROR
    case 8002:
        return "8002" // RECORD_NOT_FOUND
    case 9000:
        return "9000" // LOGOUT
    case 9999:
        return "9999" // GENERIC_ERROR
    default:
        // Try to extract from domain or description
        if let domain = error.domain as String?, domain.contains("Finvu") {
            // Check if it's a backend error code (F400, A001, etc.)
            if let codeFromDomain = extractErrorCode(from: error) {
                return codeFromDomain
            }
        }
        return "9999" // GENERIC_ERROR
    }
}

/**
 * Extracts error code from error object
 * Tries to find backend error codes like F400, A001, D001, C001, etc.
 */
func extractErrorCode(from error: NSError) -> String? {
    // Check userInfo for error code
    if let code = error.userInfo["code"] as? String {
        return code
    }
    
    // Check localizedDescription for error codes
    if let description = error.localizedDescription as String? {
        // Pattern: F400, A001, D001, C001, etc.
        let pattern = #"([FADC]\d{3})"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: description, options: [], range: NSRange(location: 0, length: description.count)) {
            let codeRange = Range(match.range(at: 1), in: description)
            if let codeRange = codeRange {
                return String(description[codeRange])
            }
        }
    }
    
    return nil
}


class FinvuClientConfig: FinvuConfig {
    var finvuEndpoint: URL
    var certificatePins: [String]?
    var finvuSnaAuthConfig: FinvuSnaAuthConfig?
    
    public init(finvuEndpoint: URL, certificatePins: [String]?, finvuSnaAuthConfig: FinvuSnaAuthConfig?) {
        self.finvuEndpoint = finvuEndpoint
        self.certificatePins = certificatePins ?? []
        self.finvuSnaAuthConfig = finvuSnaAuthConfig
    }
}

public class FinvuModule: Module {
    private let sdkInstance = FinvuManager.shared
    private let eventTracker = FinvuEventTracker.shared
    private lazy var eventListener: FinvuEventListener = {
        let listener = EventListener { [weak self] event in
            guard let self = self else { return }
            let eventDict: [String: Any] = [
                "eventName": event.eventName,
                "eventCategory": event.eventCategory,
                "timestamp": event.timestamp,
                "aaSdkVersion": event.aaSdkVersion,
                "params": event.params
            ]
            self.sendEvent("onEvent", eventDict)
        }
        return listener
    }()
    
    // Helper class to bridge FinvuEventListener protocol
    private class EventListener: NSObject, FinvuEventListener {
        private let callback: (FinvuEvent) -> Void
        
        init(callback: @escaping (FinvuEvent) -> Void) {
            self.callback = callback
            super.init()
        }
        
        func onEvent(_ event: FinvuEvent) {
            callback(event)
        }
    }

    public func definition() -> ModuleDefinition {
        Name("FinvuModule")
        
        Events("onConnectionStatusChange", "onLoginOtpReceived", "onLoginOtpVerified", "onEvent")

        Function("initializeWith", initializeWith)
        AsyncFunction("connect", connect)
        AsyncFunction("disconnect", disconnect)
        AsyncFunction("isConnected", isConnected)
        AsyncFunction("hasSession", hasSession)
        AsyncFunction("loginWithUsernameOrMobileNumber", loginWithUsernameOrMobileNumber)
        AsyncFunction("discoverAccounts", discoverAccounts)
        AsyncFunction("verifyLoginOtp", verifyLoginOtp)
        AsyncFunction("fetchFipDetails", fetchFipDetails)
        AsyncFunction("getEntityInfo", getEntityInfo)
        AsyncFunction("getConsentRequestDetails", getConsentRequestDetails)
        AsyncFunction("getConsentHandleStatus", getConsentHandleStatus)
        AsyncFunction("revokeConsent", revokeConsent)
        AsyncFunction("logout", logout)
        AsyncFunction("fipsAllFIPOptions", fipsAllFIPOptions)
        AsyncFunction("fetchLinkedAccounts", fetchLinkedAccounts)
        AsyncFunction("linkAccounts", linkAccounts)
        AsyncFunction("confirmAccountLinking", confirmAccountLinking)
        AsyncFunction("approveConsentRequest", approveConsentRequest)
        AsyncFunction("denyConsentRequest", denyConsentRequest)
        
        // Event Tracking Methods
        Function("setEventsEnabled", setEventsEnabled)
        Function("addEventListener", addEventListener)
        Function("removeEventListener", removeEventListener)
        Function("registerCustomEvents", registerCustomEvents)
        Function("track", track)
        Function("registerAliases", registerAliases)
    }
    
    private func getRootViewController() -> UIViewController? {
        // For iOS 13+
        if #available(iOS 13.0, *) {
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            return windowScene?.windows.first { $0.isKeyWindow }?.rootViewController
        } else {
            // Fallback for earlier versions
            return UIApplication.shared.keyWindow?.rootViewController
        }
    }

    private func initializeWith(config: [String: Any]) throws -> String {
        do {
            guard let finvuEndpointString = config["finvuEndpoint"] as? String,
                    let finvuEndpoint = URL(string: finvuEndpointString) else {
                throw NSError(domain: "FinvuModule", code: -1, userInfo: [NSLocalizedDescriptionKey: "finvuEndpoint is required and must be a valid URL"])
            }
            
            let certificatePins = (config["certificatePins"] as? [String])
            
            // Parse finvuAuthSNAConfig if present
            var finvuSnaAuthConfig: FinvuSnaAuthConfig? = nil
            if let snaConfigDict = config["finvuAuthSNAConfig"] as? [String: Any],
               let environmentString = snaConfigDict["environment"] as? String {
                let environment = environmentString == "UAT" ? FinvuEnvironment.uat : FinvuEnvironment.production
                
                // Get the root view controller
                guard let rootViewController = getRootViewController() else {
                    throw NSError(domain: "FinvuModule", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to get root view controller"])
                }
                
                finvuSnaAuthConfig = FinvuSnaAuthConfig(environment: environment, viewController: rootViewController)
            }
            
            let finvuClientConfig = FinvuClientConfig(finvuEndpoint: finvuEndpoint, certificatePins: certificatePins, finvuSnaAuthConfig: finvuSnaAuthConfig)
            
            sdkInstance.initializeWith(config: finvuClientConfig)
            return "Initialized successfully"
        } catch {
            print(error)
            // Use standard error code for initialization errors
            throw NSError(domain: "FinvuModule", code: 9999, userInfo: [
                NSLocalizedDescriptionKey: "Initialization failed",
                "code": "9999"
            ])
        }
    }

    private func connect(promise: Promise) {
        sdkInstance.connect { error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    // Convert NSError to React Native error
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    self.sendEvent("onConnectionStatusChange", ["status": errorCode])
                    promise.reject(errorCode, errorMessage)
                } else {
                    // No error means success
                    self.sendEvent("onConnectionStatusChange", ["status": "Connected successfully"])
                    promise.resolve(["status": "Connected successfully"])
                }
            }
        }
    }

    private func disconnect(promise: Promise) {
        DispatchQueue.main.async {
            do {
                self.sdkInstance.disconnect()
                self.sendEvent("onConnectionStatusChange", ["status": "Disconnected successfully"])
                promise.resolve(["status": "Disconnected successfully"])
            } catch let error as NSError {
                let errorCode: String = mapErrorCode(error)
                let errorMessage: String = error.localizedDescription
                self.sendEvent("onConnectionStatusChange", ["status": errorCode])
                promise.reject(errorCode, errorMessage)
            } catch {
                let errorCode = "9999"
                self.sendEvent("onConnectionStatusChange", ["status": errorCode])
                promise.reject(errorCode, "An unknown error occurred while disconnecting.")
            }
        }
    }

    private func isConnected(promise: Promise) {
        do {
            let status = self.sdkInstance.isConnected()
            promise.resolve(status)
        } catch let error as NSError {
            let errorCode: String = mapErrorCode(error)
            let errorMessage: String = error.localizedDescription
            promise.reject(errorCode, errorMessage)
        } catch {
            promise.reject("9999", "An unknown error occurred while checking connection status.")
        }
    }
    
    private func hasSession(promise: Promise) {
        do {
            let hasSession = self.sdkInstance.hasSession()
            promise.resolve(hasSession)
        } catch let error as NSError {
            let errorCode: String = mapErrorCode(error)
            let errorMessage: String = error.localizedDescription
            promise.reject(errorCode, errorMessage)
        } catch {
            promise.reject("9999", "An unknown error occurred while checking session.")
        }
    }
     
    private func loginWithUsernameOrMobileNumber(
        username: String,
        mobileNumber: String,
        consentHandleId: String,
        promise: Promise
    ) {
        sdkInstance.loginWith(
            username: username,
            mobileNumber: mobileNumber,
            consentHandleId: consentHandleId
        ) { result, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    var response: [String: Any] = [
                        "authType": result.authType ?? "",
                        "reference": result.reference
                    ]
                    
                    if let snaAuthToken = result.snaToken {
                        response["snaToken"] = snaAuthToken
                    }
                    
                    promise.resolve(response)
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }

    private func discoverAccounts(fipId: String, fiTypes: [String], identifiersMapList: [[String: String]], promise: Promise) {
        let identifiers = identifiersMapList.map { mapData in
            TypeIdentifierInfo(
                category: mapData["category"] ?? "",
                type: mapData["type"] ?? "",
                value: mapData["value"] ?? ""
            )
        }

        sdkInstance.discoverAccounts(fipId: fipId, fiTypes: fiTypes, identifiers: identifiers) { result, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    let accountsArray: [[String: Any]] = result.accounts.map { account in
                        return [
                            "accountType": account.accountType,
                            "accountReferenceNumber": account.accountReferenceNumber,
                            "maskedAccountNumber": account.maskedAccountNumber,
                            "fiType": account.fiType
                        ]
                    }

                    let resultDict: [String: Any] = [
                        "discoveredAccounts": accountsArray
                    ]

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: resultDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }

    private func verifyLoginOtp(otp: String, otpReference: String, promise: Promise) {
        sdkInstance.verifyLoginOtp(otp: otp, otpReference: otpReference) { result, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    // Convert NSError to React Native error
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    // Handle successful OTP verification
                    let userId = result.userId
                    promise.resolve(["userId": userId])
                } else {
                    // Handle case where there is no result and no error
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }
    
    private func fetchFipDetails(fipId: String, promise: Promise) {
        sdkInstance.fetchFIPDetails(fipId: fipId) { result, error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    var typeIdentifiersArray: [[String: Any]] = []

                    for typeIdentifier in result.typeIdentifiers {
                        var identifiersArray: [[String: String]] = []

                        for identifier in typeIdentifier.identifiers {
                            let identifierDict: [String: String] = [
                                "category": identifier.category,
                                "type": identifier.type
                            ]
                            identifiersArray.append(identifierDict)
                        }

                        let typeIdentifierDict: [String: Any] = [
                            "fiType": typeIdentifier.fiType,
                            "identifiers": identifiersArray
                        ]

                        typeIdentifiersArray.append(typeIdentifierDict)
                    }

                    // Use Mirror to safely access linkingOtpLength from native SDK
                    let mirror = Mirror(reflecting: result)
                    var linkingOtpLength: Any? = nil
                    for child in mirror.children {
                        if child.label == "linkingOtpLength" || child.label == "linkingOTPLength" {
                            linkingOtpLength = child.value
                            break
                        }
                    }
                    
                    // Build result dictionary - ALWAYS include linkingOtpLength
                    var resultDict: [String: Any] = [
                        "fipId": result.fipId,
                        "typeIdentifiers": typeIdentifiersArray
                    ]
                    
                    // ALWAYS add linkingOtpLength - remove any existing and set our value
                    if let length = linkingOtpLength as? Int {
                        resultDict["linkingOtpLength"] = length
                    } else {
                        // Explicitly use NSNull() to ensure null is serialized in JSON
                        resultDict["linkingOtpLength"] = NSNull()
                    }

                    do {
                        // Serialize to JSON - NSNull() will be serialized as null
                        let jsonData = try JSONSerialization.data(withJSONObject: resultDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }
    
    private func getEntityInfo(entityId: String, entityType: String, promise: Promise) {
        sdkInstance.getEntityInfo(entityId: entityId, entityType: entityType) { result, error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    // Inline dictionary conversion
                    let resultDict: [String: Any] = [
                        "entityId": result.entityId,
                        "entityName": result.entityName,
                        "entityIconUri": result.entityIconUri as Any,
                        "entityLogoUri": result.entityLogoUri as Any,
                        "entityLogoWithNameUri": result.entityLogoWithNameUri as Any
                    ]
                    
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: resultDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }
  
    private func getConsentRequestDetails(consentHandleId: String, promise: Promise) {
        sdkInstance.getConsentRequestDetails(consentHandleId: consentHandleId) { result, error in
                DispatchQueue.main.async {
                    if let error = error as NSError? {
                        let errorCode: String = mapErrorCode(error)
                        let errorMessage: String = error.localizedDescription
                        promise.reject(errorCode, errorMessage)
                    } else if let result = result {
                        let detail = result.detail
                        let formatter = ISO8601DateFormatter()

                        let financialUserDict: [String: Any] = [
                            "id": detail.financialInformationUser.id,
                            "name": detail.financialInformationUser.name
                        ]

                        let purposeInfoDict: [String: Any] = [
                            "code": detail.consentPurposeInfo.code,
                            "text": detail.consentPurposeInfo.text
                        ]

                        let dateTimeRangeDict: [String: Any] = [
                            "from": formatter.string(from : detail.consentDateTimeRange.from),
                            "to": formatter.string(from : detail.consentDateTimeRange.to)
                        ]

                        let dataTimeRangeDict: [String: Any] = [
                            "from": formatter.string(from : detail.dataDateTimeRange.from),
                            "to": formatter.string(from : detail.dataDateTimeRange.to)
                        ]

                        let dataLifePeriodDict: [String: Any] = [
                            "unit": detail.consentDataLifePeriod.unit,
                            "value": detail.consentDataLifePeriod.value
                        ]

                        let dataFrequencyDict: [String: Any] = [
                            "unit": detail.consentDataFrequency.unit,
                            "value": detail.consentDataFrequency.value
                        ]

                        let detailDict: [String: Any] = [
                            "consentId": detail.consentId ?? "",
                            "consentHandle": detail.consentHandle,
                            "statusLastUpdateTimestamp": detail.statusLastUpdateTimestamp.map { formatter.string(from: $0) } ?? "",
                            "financialInformationUser": financialUserDict,
                            "consentPurposeInfo": purposeInfoDict,
                            "consentDisplayDescriptions": detail.consentDisplayDescriptions,
                            "consentDateTimeRange": dateTimeRangeDict,
                            "dataDateTimeRange": dataTimeRangeDict,
                            "consentDataLifePeriod": dataLifePeriodDict,
                            "consentDataFrequency": dataFrequencyDict,
                            "fiTypes": detail.fiTypes ?? []
                        ]

                        let resultDict: [String: Any] = [
                            "consentDetail": detailDict
                        ]

                        do {
                            let jsonData = try JSONSerialization.data(withJSONObject: resultDict, options: [])
                            let jsonString = String(data: jsonData, encoding: .utf8)!
                            promise.resolve(jsonString)
                        } catch {
                            promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                        }
                    } else {
                        promise.reject("9999", "An unknown error occurred.")
                    }
            }
        }
    }
    
    private func getConsentHandleStatus(handleId: String, promise: Promise) {
        sdkInstance.getConsentHandleStatus(handleId: handleId) { result, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    let responseDict: [String: Any] = [
                        "status": result.status
                    ]
                    
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }
    
    private func revokeConsent(consentId: String, accountAggregatorMap: [String: Any]?, fipDetailsMap: [String: Any]?, promise: Promise) {
        // Parse accountAggregator if provided
        var accountAggregator: AccountAggregator? = nil
        if let accountAggregatorMap = accountAggregatorMap {
            if let id = accountAggregatorMap["id"] as? String {
                accountAggregator = AccountAggregator(id: id)
            }
        }
        
        // Parse fipDetails if provided
        var fipDetails: FIPReference? = nil
        if let fipDetailsMap = fipDetailsMap {
            if let fipId = fipDetailsMap["fipId"] as? String {
                let fipName = fipDetailsMap["fipName"] as? String ?? ""
                fipDetails = FIPReference(fipId: fipId, fipName: fipName)
            }
        }
        
        sdkInstance.revokeConsent(consentId: consentId, accountAggregator: accountAggregator, fipDetails: fipDetails) { error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else {
                    promise.resolve(nil)
                }
            }
        }
    }
    
    private func logout(promise: Promise) {
        sdkInstance.logout { error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    // Convert NSError to React Native error
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else {
                    promise.resolve(nil)
                }
            }
        }
    }
    
    private func fipsAllFIPOptions(promise: Promise) {
        sdkInstance.fipsAllFIPOptions { result, error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    // Convert FIPSearchResponse to Dictionary
                    let searchOptionsArray = result.searchOptions.map { fipInfo in
                        return [
                            "fipId": fipInfo.fipId,
                            "productName": fipInfo.productName ?? "",
                            "fipFiTypes": fipInfo.fipFitypes,
                            "fipFsr": fipInfo.fipFsr ?? "",
                            "productDesc": fipInfo.productDesc ?? "",
                            "productIconUri": fipInfo.productIconUri ?? "",
                            "enabled": fipInfo.enabled
                        ] as [String: Any]
                    }

                    let responseDict: [String: Any] = [
                        "searchOptions": searchOptionsArray
                    ]

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }
    
    private func fetchLinkedAccounts(promise: Promise) {
        sdkInstance.fetchLinkedAccounts { result, error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    let linkedAccountsArray: [[String: Any]] = result.linkedAccounts?.map { account in
                        let formatter = ISO8601DateFormatter()
                        let linkedAccountUpdateTimestampString = account.linkedAccountUpdateTimestamp.map { formatter.string(from: $0) }

                        return [
                            "userId": account.userId,
                            "fipId": account.fipId,
                            "fipName": account.fipName,
                            "maskedAccountNumber": account.maskedAccountNumber,
                            "accountReferenceNumber": account.accountReferenceNumber,
                            "linkReferenceNumber": account.linkReferenceNumber,
                            "consentIdList": account.consentIdList ?? [],
                            "fiType": account.fiType,
                            "accountType": account.accountType,
                            "linkedAccountUpdateTimestamp": linkedAccountUpdateTimestampString ?? "",
                            "authenticatorType": account.authenticatorType
                        ]
                    } ?? []

                    let responseDict: [String: Any] = [
                        "linkedAccounts": linkedAccountsArray
                    ]

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }

    private func linkAccounts(finvuAccountsMap: [[String: Any]], finvuFipDetailsMap: [String: Any], promise: Promise) {
        // Parse DiscoveredAccountInfo array
        let discoveredAccounts = finvuAccountsMap.map { accountDict -> DiscoveredAccountInfo in
            return DiscoveredAccountInfo(
                accountType: accountDict["accountType"] as? String ?? "",
                accountReferenceNumber: accountDict["accountReferenceNumber"] as? String ?? "",
                maskedAccountNumber: accountDict["maskedAccountNumber"] as? String ?? "",
                fiType: accountDict["fiType"] as? String ?? ""
            )
        }

        var parsedTypeIdentifiers: [FIPFiTypeIdentifier] = []
        if let typeIdentifiersArray = finvuFipDetailsMap["typeIdentifiers"] as? [[String: Any]] {
            parsedTypeIdentifiers = typeIdentifiersArray.compactMap { item -> FIPFiTypeIdentifier? in
                guard
                    let fiType = item["fiType"] as? String,
                    let identifiers = item["identifiers"] as? [[String: Any]]
                else {
                    return nil
                }

                let parsedIdentifiers = identifiers.compactMap { idDict -> TypeIdentifier? in
                    guard
                        let category = idDict["category"] as? String,
                        let type = idDict["type"] as? String
                    else {
                        return nil
                    }
                    return TypeIdentifier(category: category, type: type)
                }

                return FIPFiTypeIdentifier(fiType: fiType, identifiers: parsedIdentifiers)
            }
        }

        // Extract linkingOtpLength if provided - convert Int? to NSNumber?
        let linkingOtpLengthInt = finvuFipDetailsMap["linkingOtpLength"] as? Int
        let linkingOtpLength: NSNumber? = linkingOtpLengthInt != nil ? NSNumber(value: linkingOtpLengthInt!) : nil
        
        let fipDetails =  FIPDetails(fipId: finvuFipDetailsMap["fipId"] as? String ?? "", typeIdenifiers: parsedTypeIdentifiers, linkingOtpLength: linkingOtpLength)
        // Call SDK
        sdkInstance.linkAccounts(fipDetails: fipDetails, accounts: discoveredAccounts) { result, error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    let resultDict: [String: Any] = [
                        "referenceNumber": result.referenceNumber
                    ]

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: resultDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }

    private func confirmAccountLinking(referenceNumber: String, otp: String, promise: Promise) {
        let linkingReference = AccountLinkingRequestReference(referenceNumber: referenceNumber)
        
        sdkInstance.confirmAccountLinking(linkingReference: linkingReference, otp: otp) { result, error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    let linkedAccountsArray = result.linkedAccounts.map { account in
                        return [
                            "customerAddress": account.customerAddress,
                            "linkReferenceNumber": account.linkReferenceNumber,
                            "accountReferenceNumber": account.accountReferenceNumber,
                            "status": account.status
                        ] as [String: Any]
                    }

                    let responseDict: [String: Any] = [
                        "linkedAccounts": linkedAccountsArray
                    ]

                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }
    
    private func approveConsentRequest(consentDetailsMap: [String: Any], finvuLinkedAccountsMap: [[String: Any]], promise: Promise) {
        // Extract necessary information from consentDetailsMap to create ConsentRequestDetailInfo
        let consentHandle = consentDetailsMap["consentHandle"] as? String ?? ""
        
        // Extract FIU (Financial Information User) info
        let fiuMap = consentDetailsMap["financialInformationUser"] as? [String: Any] ?? [:]
        let fiuId = fiuMap["id"] as? String ?? ""
        
        // Create ConsentRequestDetailInfo object with minimal required fields
        let fiuInfo = FinancialInformationEntityInfo(
            id: fiuId,
            name: fiuMap["name"] as? String ?? ""
        )
        
        // Extract purpose info
        let purposeMap = consentDetailsMap["consentPurpose"] as? [String: Any] ?? [:]
        let purposeInfo = ConsentPurposeInfo(
            code: purposeMap["code"] as? String ?? "",
            text: purposeMap["text"] as? String ?? ""
        )
        
        // Create basic ConsentRequestDetailInfo
        let consentDetail = ConsentRequestDetailInfo(
            consentId: consentDetailsMap["consentId"] as? String,
            consentHandle: consentHandle,
            statusLastUpdateTimestamp: nil,
            financialInformationUser: fiuInfo,
            consentPurposeInfo: purposeInfo,
            consentDisplayDescriptions: consentDetailsMap["consentDisplayDescriptions"] as? [String] ?? [],
            consentDateTimeRange: DateTimeRange(from: Date(), to: Date()),
            dataDateTimeRange: DateTimeRange(from: Date(), to: Date()),
            consentDataLifePeriod: ConsentDataLifePeriod(unit: "", value: 0),
            consentDataFrequency: ConsentDataFrequency(unit: "", value: 0),
            fiTypes: consentDetailsMap["fiTypes"] as? [String]
        )
        
        // Create LinkedAccountDetailsInfo objects from dictionaries
        let linkedAccounts = finvuLinkedAccountsMap.map { accountDict -> LinkedAccountDetailsInfo in
            return LinkedAccountDetailsInfo(
                userId: accountDict["userId"] as? String ?? "",
                fipId: accountDict["fipId"] as? String ?? "",
                fipName: accountDict["fipName"] as? String ?? "",
                maskedAccountNumber: accountDict["maskedAccountNumber"] as? String ?? "",
                accountReferenceNumber: accountDict["accountReferenceNumber"] as? String ?? "",
                linkReferenceNumber: accountDict["linkReferenceNumber"] as? String ?? "",
                consentIdList: accountDict["consentIdList"] as? [String],
                fiType: accountDict["fiType"] as? String ?? "",
                accountType: accountDict["accountType"] as? String ?? "",
                linkedAccountUpdateTimestamp: nil,
                authenticatorType: accountDict["authenticatorType"] as? String ?? ""
            )
        }
        
        // Call the correct SDK method - note the different method name
        sdkInstance.approveAccountConsentRequest(consentDetail: consentDetail, linkedAccounts: linkedAccounts) { result, error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    // Convert NSError to React Native error
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    let consentsArray = result.consentsInfo?.map { consent in
                        return [
                            "fipId": consent.fipId ?? "",
                            "consentId": consent.consentId
                        ]
                    } ?? []

                    let responseDict: [String: Any] = [
                        "consentIntentId": result.consentIntentId ?? NSNull(),
                        "consentsInfo": consentsArray
                    ]
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }

    private func denyConsentRequest(consentDetailsMap: [String: Any], promise: Promise) {
        // Extract necessary information from consentDetailsMap to create ConsentRequestDetailInfo
        let consentHandle = consentDetailsMap["consentHandle"] as? String ?? ""
        
        // Extract FIU (Financial Information User) info
        let fiuMap = consentDetailsMap["financialInformationUser"] as? [String: Any] ?? [:]
        let fiuId = fiuMap["id"] as? String ?? ""
        
        // Create ConsentRequestDetailInfo object with minimal required fields
        let fiuInfo = FinancialInformationEntityInfo(
            id: fiuId,
            name: fiuMap["name"] as? String ?? ""
        )
        
        // Extract purpose info
        let purposeMap = consentDetailsMap["consentPurpose"] as? [String: Any] ?? [:]
        let purposeInfo = ConsentPurposeInfo(
            code: purposeMap["code"] as? String ?? "",
            text: purposeMap["text"] as? String ?? ""
        )
        
        // Create basic ConsentRequestDetailInfo
        let consentDetail = ConsentRequestDetailInfo(
            consentId: consentDetailsMap["consentId"] as? String,
            consentHandle: consentHandle,
            statusLastUpdateTimestamp: nil,
            financialInformationUser: fiuInfo,
            consentPurposeInfo: purposeInfo,
            consentDisplayDescriptions: consentDetailsMap["consentDisplayDescriptions"] as? [String] ?? [],
            consentDateTimeRange: DateTimeRange(from: Date(), to: Date()),
            dataDateTimeRange: DateTimeRange(from: Date(), to: Date()),
            consentDataLifePeriod: ConsentDataLifePeriod(unit: "", value: 0),
            consentDataFrequency: ConsentDataFrequency(unit: "", value: 0),
            fiTypes: consentDetailsMap["fiTypes"] as? [String]
        )
        
        // Call the correct SDK method - note the different method name
        sdkInstance.denyAccountConsentRequest(consentDetail: consentDetail) { result, error in
            DispatchQueue.main.async {
                if let error = error as? NSError {
                    // Convert NSError to React Native error
                    let errorCode: String = mapErrorCode(error)
                    let errorMessage: String = error.localizedDescription
                    promise.reject(errorCode, errorMessage)
                } else if let result = result {
                    let consentsArray = result.consentsInfo?.map { consent in
                        return [
                            "fipId": consent.fipId ?? "",
                            "consentId": consent.consentId
                        ]
                    } ?? []

                    let responseDict: [String: Any] = [
                        "consentIntentId": result.consentIntentId ?? "",
                        "consentsInfo": consentsArray
                    ]
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: responseDict, options: [])
                        let jsonString = String(data: jsonData, encoding: .utf8)!
                        promise.resolve(jsonString)
                    } catch {
                        promise.reject("JSON_ERROR", "Failed to serialize result to JSON")
                    }
                } else {
                    promise.reject("9999", "An unknown error occurred.")
                }
            }
        }
    }
    
    // MARK: - Event Tracking Methods
    
    private func setEventsEnabled(enabled: Bool) throws {
        sdkInstance.setEventsEnabled(enabled)
    }
    
    private func addEventListener() throws {
        sdkInstance.addEventListener(eventListener)
    }
    
    private func removeEventListener() throws {
        sdkInstance.removeEventListener(eventListener)
    }
    
    private func registerCustomEvents(eventsMap: [String: [String: Any]]) throws {
        let customEvents = eventsMap.mapValues { eventDefMap -> EventDefinition in
            let category = eventDefMap["category"] as? String ?? ""
            let count = (eventDefMap["count"] as? NSNumber)?.intValue ?? 0
            let stage = eventDefMap["stage"] as? String
            let fipId = eventDefMap["fipId"] as? String
            let fips = eventDefMap["fips"] as? [String]
            let fiTypes = eventDefMap["fiTypes"] as? [String]
            
            return EventDefinition(
                category: category,
                stage: stage,
                fipId: fipId,
                fips: fips ?? [""],
                fiTypes: fiTypes ?? [""]
            )
        }
        eventTracker.registerCustomEvents(customEvents)
    }
    
    private func track(eventName: String, params: [String: Any]?) throws {
        eventTracker.track(eventName, params: params ?? [:])
    }
    
    private func registerAliases(aliases: [String: String]) throws {
        eventTracker.registerAliases(aliases)
    }
}
