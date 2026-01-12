export type ChangeEventPayload = {
    value: string;
};
export type FinvuViewProps = {
    name: string;
};
export declare enum FinvuEnviornment {
    PRODUCTION = "PRODUCTION",
    UAT = "UAT"
}
export type FinvuAuthSNAConfig = {
    environment: FinvuEnviornment;
};
export type FinvuConfig = {
    finvuEndpoint: string;
    certificatePins?: string[];
    finvuAuthSNAConfig?: FinvuAuthSNAConfig;
};
export interface LoginWithUsernameOrMobileNumberResponse {
    authType: string;
    reference: string;
    snaToken?: string;
}
export interface DiscoveredAccount {
    fiType: string;
    accountReferenceNumber: string;
    accountType: string;
    maskedAccountNumber: string;
}
export interface TypeIdentifier {
    category: string;
    type: string;
}
export interface FipFiTypeIdentifier {
    fiType: string;
    identifiers: TypeIdentifier[];
}
export interface FipDetails {
    fipId: string;
    typeIdentifiers: FipFiTypeIdentifier[];
    linkingOtpLength?: number | null;
}
export interface UserInfo {
    userId: string;
    mobileNumber: string;
    emailId: string;
}
export interface FipDetails {
    fipId: string;
    typeIdentifiers: FipFiTypeIdentifier[];
    linkingOtpLength?: number | null;
}
export interface FipFiTypeIdentifier {
    fiType: string;
    identifiers: TypeIdentifier[];
}
export interface TypeIdentifier {
    category: string;
    type: string;
}
export interface LinkedAccount {
    accountReferenceNumber: string;
    customerAddress: string;
    linkReferenceNumber: string;
    status: string;
}
export interface LinkedAccountDetails {
    userId: string;
    fipId: string;
    fipName: string;
    maskedAccountNumber: string;
    accountReferenceNumber: string;
    linkReferenceNumber: string;
    consentIdList: string[] | null;
    fiType: string;
    accountType: string;
    linkedAccountUpdateTimestamp: Date | null;
    authenticatorType: string;
}
export interface ConsentDetail {
    consentId: string | null;
    consentHandle: string;
    statusLastUpdateTimestamp: Date | null;
    financialInformationUser: FinancialInformationEntity;
    consentPurpose: ConsentPurpose;
    consentDisplayDescriptions: string[];
    dataDateTimeRange: DateTimeRange;
    consentDateTimeRange: DateTimeRange;
    consentDataLife: ConsentDataLifePeriod;
    consentDataFrequency: ConsentDataFrequency;
    fiTypes: string[] | null;
}
export interface DateTimeRange {
    from: Date;
    to: Date;
}
export interface ConsentDataFrequency {
    unit: string;
    value: number;
}
export interface ConsentDataLifePeriod {
    unit: string;
    value: number;
}
export interface FinancialInformationEntity {
    id: string;
    name: string;
}
export interface ConsentPurpose {
    code: string;
    text: string;
}
export interface ConsentAccountDetails {
    fiType: string;
    fipId: string;
    accountType: string;
    accountReferenceNumber: string | null;
    maskedAccountNumber: string;
    linkReferenceNumber: string;
}
export interface ConsentInfoDetails {
    consentHandle: string | null;
    consentId: string | null;
    consentStatus: string;
    statusLastUpdateTimestamp: string;
    financialInformationProvider: FinancialInformationEntity | null;
    financialInformationUser: FinancialInformationEntity | null;
    consentPurpose: ConsentPurpose;
    consentDisplayDescriptions: string[];
    dataDateTimeRange: DateTimeRange;
    consentDateTimeRange: DateTimeRange;
    consentDataLife: ConsentDataLifePeriod;
    consentDataFrequency: ConsentDataFrequency;
    accounts: ConsentAccountDetails[];
    fiTypes: string[] | null;
    accountAggregator: AccountAggregatorView;
}
export interface AccountAggregatorView {
    id: string;
}
export interface FIPReferenceView {
    fipId: string;
    fipName?: string;
}
/**
 * Consent Handle Status enum
 */
export declare enum ConsentHandleStatus {
    ACCEPT = "ACCEPT",
    DENY = "DENY",
    PENDING = "PENDING"
}
/**
 * Response for getConsentHandleStatus
 */
export interface ConsentHandleStatusResponse {
    status: ConsentHandleStatus;
}
export interface DiscoveredAccount {
    accountReferenceNumber: string;
    accountType: string;
    fiType: string;
    maskedAccountNumber: string;
}
export interface DiscoverAccountsResponse {
    discoveredAccounts: DiscoveredAccount[];
}
export interface TypeIdentifier {
    category: string;
    type: string;
}
export interface FipFiTypeIdentifier {
    fiType: string;
    identifiers: TypeIdentifier[];
}
export interface FipDetails {
    fipId: string;
    typeIdentifiers: FipFiTypeIdentifier[];
    linkingOtpLength?: number | null;
}
/**
 * FIP information interface matching Kotlin data class
 */
export interface FIPInfo {
    fipId: string;
    productName?: string;
    fipFiTypes: string[];
    fipFsr?: string;
    productDesc?: string;
    productIconUri?: string;
    enabled: boolean;
}
/**
 * Response for all FIP options matching Kotlin data class
 */
export interface FipsAllFIPOptionsResponse {
    searchOptions: FIPInfo[];
}
/**
 * Event Definition for custom events
 */
export interface EventDefinition {
    category: string;
    count?: number;
    stage?: string;
    fipId?: string;
    fips?: string[];
    fiTypes?: string[];
}
/**
 * Finvu Event structure
 */
export interface FinvuEvent {
    eventName: string;
    eventCategory: string;
    timestamp: string;
    aaSdkVersion: string;
    params: Record<string, any>;
}
/**
 * Event Listener callback type
 */
export type FinvuEventListener = (event: FinvuEvent) => void;
/**
 * Standard SDK Event Types (matching native enum)
 */
export declare enum FinvuEventType {
    WEBSOCKET_CONNECTED = "WEBSOCKET_CONNECTED",
    WEBSOCKET_DISCONNECTED = "WEBSOCKET_DISCONNECTED",
    CONSENT_REQUEST_VALID = "CONSENT_REQUEST_VALID",
    CONSENT_REQUEST_INVALID = "CONSENT_REQUEST_INVALID",
    LOGIN_INITIATED = "LOGIN_INITIATED",
    LOGIN_OTP_GENERATED = "LOGIN_OTP_GENERATED",
    LOGIN_OTP_FAILED = "LOGIN_OTP_FAILED",
    LOGIN_OTP_LOCKED = "LOGIN_OTP_LOCKED",
    LOGIN_OTP_VERIFIED = "LOGIN_OTP_VERIFIED",
    LOGIN_OTP_NOT_VERIFIED = "LOGIN_OTP_NOT_VERIFIED",
    LOGIN_FALLBACK_INITIATED = "LOGIN_FALLBACK_INITIATED",
    DISCOVERY_INITIATED = "DISCOVERY_INITIATED",
    ACCOUNTS_DISCOVERED = "ACCOUNTS_DISCOVERED",
    DISCOVERY_FAILED = "DISCOVERY_FAILED",
    ACCOUNTS_NOT_DISCOVERED = "ACCOUNTS_NOT_DISCOVERED",
    LINKING_INITIATED = "LINKING_INITIATED",
    LINKING_OTP_GENERATED = "LINKING_OTP_GENERATED",
    LINKING_OTP_FAILED = "LINKING_OTP_FAILED",
    LINKING_SUCCESS = "LINKING_SUCCESS",
    LINKING_FAILURE = "LINKING_FAILURE",
    LINKED_ACCOUNTS_SUMMARY = "LINKED_ACCOUNTS_SUMMARY",
    CONSENT_APPROVED = "CONSENT_APPROVED",
    CONSENT_DENIED = "CONSENT_DENIED",
    APPROVE_CONSENT_FAILED = "APPROVE_CONSENT_FAILED",
    CONSENT_HANDLE_FAILED = "CONSENT_HANDLE_FAILED",
    GET_CONSENT_STATUS_FAILED = "GET_CONSENT_STATUS_FAILED",
    SESSION_ERROR = "SESSION_ERROR",
    SESSION_FAILURE = "SESSION_FAILURE"
}
/**
 * Backend Error Codes
 * These error codes are returned directly from the backend API.
 */
export declare enum FinvuBackendErrorCode {
    F200 = "F200",// Success
    F400 = "F400",// Bad request
    F401 = "F401",// Unauthorized
    F402 = "F402",// Session Error
    F403 = "F403",// User Mismatched
    F404 = "F404",// Record not found
    F405 = "F405",// Invalid FIU
    F406 = "F406",// Invalid FIP
    F407 = "F407",// FIP Failure
    F408 = "F408",// User Mismatched
    F429 = "F429",// Max attempts exceeded
    F500 = "F500"
}
/**
 * Auth Flow Error Codes
 */
export declare enum FinvuAuthErrorCode {
    A001 = "A001",// Invalid login user format
    A002 = "A002",// User session not found
    A003 = "A003",// OTP Initiation Failed
    A004 = "A004",// Login OTP verification failed
    A005 = "A005",// Invalid OTP
    A006 = "A006"
}
/**
 * Discovery & Linking Flow Error Codes
 */
export declare enum FinvuDiscoveryErrorCode {
    D001 = "D001",// User ID mismatch with the requested user
    D002 = "D002",// Unsupported financial information type
    D003 = "D003",// Device not authenticated
    D004 = "D004",// Email not authenticated
    D005 = "D005",// Aadhar not authenticated
    D006 = "D006",// Authenticator required for this operation
    D007 = "D007",// Invalid Financial Information Provider (FIP)
    D008 = "D008",// FIP operation failed
    D009 = "D009",// Account already linked
    D010 = "D010",// No linked accounts found
    D011 = "D011"
}
/**
 * Consent Flow Error Codes
 */
export declare enum FinvuConsentErrorCode {
    C001 = "C001",// Consent expired
    C002 = "C002",// Consent already actioned
    C003 = "C003",// Record not found
    C004 = "C004",// Consent denied by user
    C005 = "C005",// Invalid or malformed consent
    C006 = "C006",// User mismatch
    C007 = "C007",// FIU mismatch
    C008 = "C008",// Invalid linked account
    C009 = "C009",// Consent handle not found
    C010 = "C010"
}
/**
 * SDK Error Codes
 * These error codes are generated by the SDK itself when the backend returns a null error code or for SDK-specific errors.
 */
export declare enum FinvuSDKErrorCode {
    AUTH_LOGIN_RETRY = "1001",// Triggered when the login attempt fails, and the system retries the login process.
    AUTH_LOGIN_FAILED = "1002",// Occurs when the login attempt fails permanently (incorrect credentials, etc.).
    AUTH_FORGOT_PASSWORD_FAILED = "1003",// Raised when the request to reset the password fails.
    AUTH_LOGIN_VERIFY_MOBILE_NUMBER = "1004",// Indicates the need to verify the mobile number during the login process.
    AUTH_FORGOT_HANDLE_FAILED = "1005",// Raised when the handle (email/username) for the forgot password process fails.
    SESSION_DISCONNECTED = "8000",// Occurs when the user session is unexpectedly disconnected.
    SSL_PINNING_FAILURE_ERROR = "8001",// Triggered when SSL pinning fails during the network request.
    RECORD_NOT_FOUND = "8002",// Raised when the requested record is not found in the database.
    LOGOUT = "9000",// Triggered when the user successfully logs out of the application.
    GENERIC_ERROR = "9999"
}
/**
 * Union type of all error codes
 */
export type FinvuErrorCode = FinvuBackendErrorCode | FinvuAuthErrorCode | FinvuDiscoveryErrorCode | FinvuConsentErrorCode | FinvuSDKErrorCode | string;
/**
 * Finvu Error interface
 */
export interface FinvuError {
    code: FinvuErrorCode;
    message: string;
}
/**
 * Helper function to check if an error code is a specific type
 */
export declare function isBackendError(code: string): boolean;
export declare function isAuthError(code: string): boolean;
export declare function isDiscoveryError(code: string): boolean;
export declare function isConsentError(code: string): boolean;
export declare function isSDKError(code: string): boolean;
//# sourceMappingURL=Finvu.types.d.ts.map