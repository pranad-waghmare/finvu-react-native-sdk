package expo.modules.finvu

import android.app.Activity
import com.finvu.android.FinvuManager
import com.finvu.android.publicInterface.*
import com.finvu.android.types.FinvuEnvironment
import com.finvu.android.utils.FinvuConfig
import com.finvu.android.utils.FinvuSNAAuthConfig
import com.finvu.android.events.EventDefinition
import com.finvu.android.events.FinvuEventTracker
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.JsonNull
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope

/**
 * Maps FinvuException error code to standardized error code string
 * Handles both backend error codes and SDK error codes
 */
fun mapErrorCode(exception: FinvuException?): String {
    if (exception == null) {
        return "9999" // GENERIC_ERROR
    }
    
    val code = exception.code
    
    // Check if it's already a string error code (backend codes like F400, A001, etc.)
    if (code is String) {
        return code
    }
    
    // Map numeric SDK error codes to string codes
    return when (code) {
        FinvuErrorCode.AUTH_LOGIN_RETRY.code -> "1001"
        FinvuErrorCode.AUTH_LOGIN_FAILED.code -> "1002"
        FinvuErrorCode.AUTH_FORGOT_PASSWORD_FAILED.code -> "1003"
        FinvuErrorCode.AUTH_LOGIN_VERIFY_MOBILE_NUMBER.code -> "1004"
        FinvuErrorCode.AUTH_FORGOT_HANDLE_FAILED.code -> "1005"
        FinvuErrorCode.SESSION_DISCONNECTED.code -> "8000"
        FinvuErrorCode.SSL_PINNING_FAILURE_ERROR.code -> "8001"
        FinvuErrorCode.RECORD_NOT_FOUND.code -> "8002"
        FinvuErrorCode.LOGOUT.code -> "9000"
        FinvuErrorCode.GENERIC_ERROR.code -> "9999"
        else -> code.toString()
    }
}

class FinvuModule : Module() {

  data class FinvuClientConfig(
    override val finvuEndpoint: String,
    override val certificatePins: List<String>?,
    override val finvuSNAAuthConfig: FinvuSNAAuthConfig?
  ) : FinvuConfig

  data class FinvuSNAAuthClientConfig(
    override val activity: Activity,
    override val env: FinvuEnvironment,
    override var scope: CoroutineScope
  ) : FinvuSNAAuthConfig

  private val sdkInstance: FinvuManager = FinvuManager.shared
  private val eventTracker: FinvuEventTracker = FinvuEventTracker.shared
  private val eventListener = object : FinvuEventListener {
    override fun onEvent(event: FinvuEvent) {
      val eventMap = mapOf(
        "eventName" to event.eventName,
        "eventCategory" to event.eventCategory,
        "timestamp" to event.timestamp,
        "aaSdkVersion" to event.aaSdkVersion,
        "params" to event.params
      )
      sendEvent("onEvent", eventMap)
    }
  }

  override fun definition() = ModuleDefinition {
    Name("FinvuModule")
    Constants()

    Events("onConnectionStatusChange", "onLoginOtpReceived", "onLoginOtpVerified", "onEvent")

    Function("initializeWith") { config: Map<String, Any> ->
      try {
        val finvuEndpoint = config["finvuEndpoint"] as? String
          ?: throw IllegalArgumentException("finvuEndpoint is required")
        val certificatePins = (config["certificatePins"] as? List<*>)?.map { it.toString() }

        // Parse finvuAuthSNAConfig if present
        var finvuSNAAuthConfig: FinvuSNAAuthConfig? = null
        val snaConfigMap = config["finvuAuthSNAConfig"] as? Map<String, Any>
        if (snaConfigMap != null) {
          val environmentString = snaConfigMap["environment"] as? String
          if (environmentString != null) {
            val environment = if (environmentString == "UAT") {
              FinvuEnvironment.UAT
            } else {
              FinvuEnvironment.PRODUCTION
            }

            // Get current activity from appContext (available in ModuleDefinition scope)
            val currentActivity = appContext.currentActivity
              ?: throw IllegalStateException("No current activity available")

            val scope = MainScope()

            finvuSNAAuthConfig = FinvuSNAAuthClientConfig(
              currentActivity,
              environment,
              scope
            )
          }
        }

        val finvuClientConfig = FinvuClientConfig(finvuEndpoint, certificatePins, finvuSNAAuthConfig)
        sdkInstance.initializeWith(finvuClientConfig)
        "Initialized successfully"
      } catch (e: Exception) {
        e.printStackTrace()
        // For initialization errors, use a specific error code
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        throw RuntimeException(errorCode, e)
      }
    }

    AsyncFunction("connect") { promise: Promise ->
      sdkInstance.connect { result ->
        if (result.isSuccess) {
          sendEvent("onConnectionStatusChange", mapOf("status" to "Connected successfully"))
          promise.resolve(null)
        } else {
          val exception = result.exceptionOrNull() as? FinvuException
          val errorCode = mapErrorCode(exception)
          val errorMessage = exception?.message ?: "Connection failed"
          sendEvent("onConnectionStatusChange", mapOf("status" to errorCode))
          promise.reject(errorCode, errorMessage, null)
        }
      }
    } 

    AsyncFunction("disconnect") { promise: Promise ->
      try {
        sdkInstance.disconnect()
        sendEvent("onConnectionStatusChange", mapOf("status" to "Disconnected successfully"))
        promise.resolve(null)
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        sendEvent("onConnectionStatusChange", mapOf("status" to errorCode))
        promise.reject(errorCode, e.message ?: "Disconnect failed", null)
      }
    }
    

    AsyncFunction("isConnected") { promise: Promise ->
      try {
        val isConnected = sdkInstance.isConnected()
        promise.resolve(isConnected)
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to check connection status", null)
      }
    }

    AsyncFunction("hasSession") { promise: Promise ->
      try {
        val hasSession = sdkInstance.hasSession();
        promise.resolve(hasSession)
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to check session", null)
      }
    }

    AsyncFunction("loginWithUsernameOrMobileNumber") { username: String, mobileNumber: String, consentHandleId: String, promise: Promise ->
      try {
        sdkInstance.loginWithUsernameOrMobileNumber(username, mobileNumber, consentHandleId) { result ->
          if (result.isSuccess) {
            val loginResponse = result.getOrNull()
            val json = Gson().toJson(loginResponse)
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Login failed"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Login failed", null)
      }
    }

    AsyncFunction("verifyLoginOtp") { otp: String, otpReference: String, promise: Promise ->
      try {
        sdkInstance.verifyLoginOtp(otp, otpReference) { result ->
          if (result.isSuccess) {
            val userId = result.getOrNull()?.userId
            promise.resolve(mapOf("userId" to userId))
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "OTP verification failed"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "OTP verification failed", null)
      }
    }

    AsyncFunction("fetchFipDetails") { fipId: String, promise: Promise ->
      try {
        sdkInstance.fetchFipDetails(fipId) { result ->
          if (result.isSuccess) {
            val response = result.getOrNull()
            val gson = Gson()
            
            // Use reflection to safely get linkingOtpLength from the response object
            val linkingOtpLength = try {
              response?.javaClass?.let { clazz ->
                try {
                  val field = clazz.getDeclaredField("linkingOtpLength")
                  field.isAccessible = true
                  field.get(response) as? Int?
                } catch (e: NoSuchFieldException) {
                  try {
                    val field = clazz.getDeclaredField("linkingOTPLength")
                    field.isAccessible = true
                    field.get(response) as? Int?
                  } catch (e2: NoSuchFieldException) {
                    null
                  }
                }
              } ?: null
            } catch (e: Exception) {
              null
            }
            
            // Serialize to JSON string first
            val jsonString = gson.toJson(response)
            
            // Parse to JsonObject - use try-catch with fallback
            val jsonObject = try {
              JsonParser().parse(jsonString).asJsonObject
            } catch (e: Exception) {
              // Fallback: parse as Map and rebuild as JsonObject
              val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
              val newMap = mutableMapOf<String, Any?>()
              map.forEach { (k, v) -> newMap[k.toString()] = v }
              val tempJson = gson.toJson(newMap)
              JsonParser().parse(tempJson).asJsonObject
            }
            
            // ALWAYS ensure linkingOtpLength is present - remove existing and add our value
            jsonObject.remove("linkingOtpLength")
            if (linkingOtpLength != null) {
              jsonObject.addProperty("linkingOtpLength", linkingOtpLength)
            } else {
              // Explicitly add null value - JsonNull.INSTANCE ensures it's serialized as null
              jsonObject.add("linkingOtpLength", JsonNull.INSTANCE)
            }
            
            val finalJson = gson.toJson(jsonObject)
            promise.resolve(finalJson)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to fetch FIP details"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to fetch FIP details", null)
      }
    }

    AsyncFunction("getEntityInfo") { entityId: String, entityType: String, promise: Promise ->
      try {
        sdkInstance.getEntityInfo(entityId, entityType) { result ->
          if (result.isSuccess) {
            val response = result.getOrNull()
            val json = Gson().toJson(response)
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to get entity info"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to get entity info", null)
      }
    }

    AsyncFunction("getConsentRequestDetails") { consentHandleId: String, promise: Promise ->
      try {
        sdkInstance.getConsentRequestDetails(consentHandleId) { result ->
          if (result.isSuccess) {
            val response = result.getOrNull()
            val json = Gson().toJson(response)
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to get consent request details"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to get consent request details", null)
      }
    }

    AsyncFunction("getConsentHandleStatus") { handleId: String, promise: Promise ->
      try {
        sdkInstance.getConsentHandleStatus(handleId) { result ->
          if (result.isSuccess) {
            val response = result.getOrNull()
            val json = Gson().toJson(response)
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to get consent handle status"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to get consent handle status", null)
      }
    }

    AsyncFunction("revokeConsent") { consentId: String, accountAggregatorViewMap: Map<String, Any>?, fipDetailsMap: Map<String, Any>?, promise: Promise ->
      try {
        val gson = Gson()
        
        // Parse accountAggregatorView if provided
        var accountAggregatorView: AccountAggregatorView? = null
        if (accountAggregatorViewMap != null) {
          val accountAggregatorJson = gson.toJson(accountAggregatorViewMap)
          accountAggregatorView = gson.fromJson(accountAggregatorJson, AccountAggregatorView::class.java)
        }
        
        // Parse fipDetails if provided
        var fipDetails: FIPReferenceView? = null
        if (fipDetailsMap != null) {
          val fipDetailsJson = gson.toJson(fipDetailsMap)
          fipDetails = gson.fromJson(fipDetailsJson, FIPReferenceView::class.java)
        }
        
        sdkInstance.revokeConsent(consentId, accountAggregatorView, fipDetails) { result ->
          if (result.isSuccess) {
            promise.resolve(null) // `Unit` -> `null` in JS
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to revoke consent"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to revoke consent", null)
      }
    }

    AsyncFunction("logout") { promise: Promise ->
      try {
        sdkInstance.logout { result ->
          if (result.isSuccess) {
            promise.resolve(null) // `Unit` -> `null` in JS
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Logout failed"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Logout failed", null)
      }
    }

    AsyncFunction("fipsAllFIPOptions") { promise: Promise ->
      try {
        sdkInstance.fipsAllFIPOptions { result ->
          if (result.isSuccess) {
            val response = result.getOrNull()
            val json = Gson().toJson(response)
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to fetch FIP options"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to fetch FIP options", null)
      }
    }

    AsyncFunction("fetchLinkedAccounts") { promise: Promise ->
      try {
        sdkInstance.fetchLinkedAccounts { result ->
          if (result.isSuccess) {
            val response = result.getOrNull()
            val json = Gson().toJson(response)
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to fetch linked accounts"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to fetch linked accounts", null)
      }
    }

    AsyncFunction("discoverAccounts") { fipId: String, fiTypes: List<String>, identifiersMapList: List<Map<String, String>>, promise: Promise ->
        try {
            val identifiers = identifiersMapList.map {
                TypeIdentifierInfo(
                    category = it["category"] ?: "",
                    type = it["type"] ?: "",
                    value = it["value"] ?: ""
                )
            }
        sdkInstance.discoverAccountsAsync(fipId, fiTypes, identifiers) { result ->
          if (result.isSuccess) {
            val json = Gson().toJson(result.getOrNull())
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to discover accounts"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to discover accounts", null)
      }
    }

    AsyncFunction("linkAccounts") { finvuAccountsMap: List<Map<String, Any>>, finvuFipDetailsMap: Map<String, Any>, promise: Promise ->
      try {
        val gson = Gson()

        // Convert JS-passed Map/List into JSON and then into Kotlin data classes
        val finvuAccountsJson = gson.toJson(finvuAccountsMap)
        val finvuFipDetailsJson = gson.toJson(finvuFipDetailsMap)

        val discoveredAccounts = gson.fromJson(finvuAccountsJson, Array<DiscoveredAccount>::class.java).toList()
        val fipDetails = gson.fromJson(finvuFipDetailsJson, FipDetails::class.java)

        sdkInstance.linkAccounts(discoveredAccounts, fipDetails) { result ->
          if (result.isSuccess) {
            val json = gson.toJson(result.getOrNull())
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to link accounts"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to link accounts", null)
      }
    }

    AsyncFunction("confirmAccountLinking") { referenceNumber: String, otp: String, promise: Promise ->
      try {
        sdkInstance.confirmAccountLinking(referenceNumber, otp) { result ->
          if (result.isSuccess) {
            val json = Gson().toJson(result.getOrNull())
            promise.resolve(json)
          } else {
            val exception = result.exceptionOrNull() as? FinvuException
            val errorCode = mapErrorCode(exception)
            val errorMessage = exception?.message ?: "Failed to confirm account linking"
            promise.reject(errorCode, errorMessage, null)
          }
        }
      } catch (e: Exception) {
        e.printStackTrace()
        val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
        promise.reject(errorCode, e.message ?: "Failed to confirm account linking", null)
      }
    }

  AsyncFunction("approveConsentRequest") { consentDetailsMap: Map<String, Any>, finvuLinkedAccountsMap: List<Map<String, Any>>, promise: Promise ->
      try {
          // Convert maps to JSON strings
          val jsonConsentDetails = Gson().toJson(consentDetailsMap)
          val jsonFinvuLinkedAccounts = Gson().toJson(finvuLinkedAccountsMap)

          val ConsentDetails = Gson().fromJson(jsonConsentDetails, ConsentDetail::class.java)
          val LinkedAccounts = Gson().fromJson(jsonFinvuLinkedAccounts, Array<LinkedAccountDetails>::class.java).toList()

          sdkInstance.approveConsentRequest(ConsentDetails, LinkedAccounts) { result ->
              if (result.isSuccess) {
                  val json = Gson().toJson(result.getOrNull())
                  promise.resolve(json)
              } else {
                  val exception = result.exceptionOrNull() as? FinvuException
                  val errorCode = mapErrorCode(exception)
                  val errorMessage = exception?.message ?: "Failed to approve consent request"
                  promise.reject(errorCode, errorMessage, null)
              }
          }
      } catch (e: Exception) {
          e.printStackTrace()
          val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
          promise.reject(errorCode, e.message ?: "Failed to approve consent request", null)
      }
  }

    AsyncFunction("denyConsentRequest") { consentDetailsMap: Map<String, Any>, promise: Promise ->
        try {
            // Convert map to JSON
            val jsonConsentDetails = Gson().toJson(consentDetailsMap)

            val ConsentDetails = Gson().fromJson(jsonConsentDetails, ConsentDetail::class.java)
            sdkInstance.denyConsentRequest(ConsentDetails) { result ->
                if (result.isSuccess) {
                    val json = Gson().toJson(result.getOrNull())
                    promise.resolve(json)
                } else {
                    val exception = result.exceptionOrNull() as? FinvuException
                    val errorCode = mapErrorCode(exception)
                    val errorMessage = exception?.message ?: "Failed to deny consent request"
                    promise.reject(errorCode, errorMessage, null)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            val errorCode = if (e is FinvuException) mapErrorCode(e) else "9999"
            promise.reject(errorCode, e.message ?: "Failed to deny consent request", null)
        }
    }

    // Event Tracking Methods
    Function("setEventsEnabled") { enabled: Boolean ->
      try {
        sdkInstance.setEventsEnabled(enabled)
      } catch (e: Exception) {
        e.printStackTrace()
        throw RuntimeException("SET_EVENTS_ENABLED_ERROR", e)
      }
    }

    Function("addEventListener") {
      try {
        sdkInstance.addEventListener(eventListener)
      } catch (e: Exception) {
        e.printStackTrace()
        throw RuntimeException("ADD_EVENT_LISTENER_ERROR", e)
      }
    }

    Function("removeEventListener") {
      try {
        sdkInstance.removeEventListener(eventListener)
      } catch (e: Exception) {
        e.printStackTrace()
        throw RuntimeException("REMOVE_EVENT_LISTENER_ERROR", e)
      }
    }

    Function("registerCustomEvents") { eventsMap: Map<String, Map<String, Any?>> ->
      try {
        val customEvents = eventsMap.mapValues { (_, eventDefMap) ->
          EventDefinition(
            category = eventDefMap["category"] as? String ?: "",
            count = (eventDefMap["count"] as? Number)?.toInt() ?: 0,
            stage = eventDefMap["stage"] as? String,
            fipId = eventDefMap["fipId"] as? String,
            fips = (eventDefMap["fips"] as? List<*>)?.mapNotNull { it?.toString() }?.toMutableList() ?: mutableListOf(),
            fiTypes = (eventDefMap["fiTypes"] as? List<*>)?.mapNotNull { it?.toString() }?.toMutableList() ?: mutableListOf()
          )
        }
        eventTracker.registerCustomEvents(customEvents)
      } catch (e: Exception) {
        e.printStackTrace()
        throw RuntimeException("REGISTER_CUSTOM_EVENTS_ERROR", e)
      }
    }

    Function("track") { eventName: String, params: Map<String, Any?>? ->
      try {
        eventTracker.track(eventName, params ?: emptyMap())
      } catch (e: Exception) {
        e.printStackTrace()
        throw RuntimeException("TRACK_EVENT_ERROR", e)
      }
    }

    Function("registerAliases") { aliases: Map<String, String> ->
      try {
        eventTracker.registerAliases(aliases)
      } catch (e: Exception) {
        e.printStackTrace()
        throw RuntimeException("REGISTER_ALIASES_ERROR", e)
      }
    }
  }   
}