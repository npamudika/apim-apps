import ballerina/http;
import ballerina/log;
import ballerina/cache;
import ballerina/config;

@Description { value: "Representation of the Throttle filter" }
@Field { value: "filterRequest: request filter method which attempts to throttle the request" }
@Field { value: "filterRequest: response filter method (not used this scenario)" }
public type ThrottleFilter object {

    @Description { value: "Filter function implementation which tries to throttle the request" }
    @Param { value: "request: Request instance" }
    @Param { value: "context: FilterContext instance" }
    @Return { value: "FilterResult: Authorization result to indicate if the request can proceed or not" }
    public function filterRequest(http:Request request, http:FilterContext context) returns http:FilterResult {
        http:FilterResult requestFilterResult;
        boolean resourceLevelThrottled;
        boolean apiLevelThrottled;
        string resourceLevelThrottleKey;
        //apiLevelThrottleKey key is combination of {apiContext}:{apiVersion}
        string apiLevelThrottleKey;

        //Throttle Tiers
        string applicationLevelTier;
        string subscriptionLevelTier;
        TierConfiguration tier = getResourceLevelTier(reflect:getResourceAnnotations(context.serviceType,
                context.resourceName));
        string resourceLevelTier = tier.policy;
        string apiLevelTier;
        //Throttled decisions
        boolean isThrottled = false;
        boolean isResourceLevelThrottled = false;
        boolean apiLevelThrottledTriggered = false;
        boolean stopOnQuotaReach = true;
        string apiContext = getContext(context);
        string apiVersion = getVersionFromServiceAnnotation(reflect:getServiceAnnotations(context.serviceType)).
        apiVersion;
        if (context.attributes.hasKey(AUTHENTICATION_CONTEXT)){
            if (isRquestBlocked(request, context)){
                // request Blocked
                requestFilterResult = { canProceed: false, statusCode: 429, message: "Message blocked" };
            } else {
                requestFilterResult = { canProceed: true };
                // Request not blocked go to check throttling
                apiLevelThrottleKey = apiContext + ":" + apiVersion;
                AuthenticationContext keyvalidationResult = check <AuthenticationContext>context.attributes[
                AUTHENTICATION_CONTEXT];
                if (keyvalidationResult.apiTier != "" && keyvalidationResult.apiTier != UNLIMITED_TIER){
                    resourceLevelThrottleKey = apiLevelThrottleKey;
                    apiLevelThrottledTriggered = true;
                }
                if (resourceLevelTier == UNLIMITED_TIER && !apiLevelThrottledTriggered){

                } else {
                    // todo: need to handle resource Level throttling with condition groups
                }
                //boolean resourceLevelThrottled = isResourceLevelThrottled(keyvalidationResult);
                if (!apiLevelThrottled){
                    if (!resourceLevelThrottled){
                        if (!isSubscriptionLevelThrottled(context, keyvalidationResult)){
                            if (!isApplicationLevelThrottled(keyvalidationResult)){
                                if (!isHardlimitThrottled(getContext(context), getVersionFromServiceAnnotation
                                    (reflect:getServiceAnnotations(context.serviceType)).apiVersion)){
                                    // Send Throttle Event
                                    RequestStream throttleEvent = generateThrottleEvent(request, context,
                                        keyvalidationResult);
                                    publishNonThrottleEvent(throttleEvent);
                                }
                            } else {
                                // Application Level Throttled
                                requestFilterResult = { canProceed: false, statusCode: 429, message:
                                "You have exceeded your quota" };
                            }
                        } else {
                            // Subscription Level Throttled
                            if (keyvalidationResult.stopOnQuotaReach){
                                requestFilterResult = { canProceed: false, statusCode: 429, message:
                                "You have exceeded your quota" };
                            } else {
                                // set properties in order to publish into analytics for billing
                            }
                        }
                    } else {
                        //Resource level Throttled
                        requestFilterResult = { canProceed: false, statusCode: 429, message: "Message blocked" };
                    }
                } else {
                    //API level Throttled
                    requestFilterResult = { canProceed: false, statusCode: 429, message: "Message blocked" };
                }
            }
        } else {
            requestFilterResult = { canProceed: false, statusCode: 500, message: "Internal Error Occurred" };
        }
        return requestFilterResult;
    }
};
function isRquestBlocked(http:Request request, http:FilterContext context) returns (boolean) {
    AuthenticationContext keyvalidationResult = check <AuthenticationContext>context.attributes[AUTHENTICATION_CONTEXT];
    string apiLevelBlockingKey = getContext(context);
    string apiTenantDomain = getTenantDomain(context);
    string ipLevelBlockingKey = apiTenantDomain + ":" + getClientIp(request);
    string appLevelBlockingKey = keyvalidationResult.subscriber + ":" + keyvalidationResult.applicationName;
    if (isAnyBlockConditionExist() && (isBlockConditionExist(apiLevelBlockingKey) || isBlockConditionExist(
                                                                                         ipLevelBlockingKey) ||
            isBlockConditionExist(appLevelBlockingKey))|| isBlockConditionExist(keyvalidationResult.username)){
        return true;
    } else {
        return false;
    }
}

function isApiLevelThrottled(AuthenticationContext keyValidationDto) returns (boolean) {
    if (keyValidationDto.apiTier != "" && keyValidationDto.apiTier != UNLIMITED_TIER){
    }
    return false;
}

function isResourceLevelThrottled(AuthenticationContext keyValidationDto) returns (boolean) {
    return false;
}

function isHardlimitThrottled(string context, string apiVersion) returns (boolean) {

    return false;
}


function isSubscriptionLevelThrottled(http:FilterContext context, AuthenticationContext keyValidationDto) returns (
            boolean) {
    string subscriptionLevelThrottleKey = keyValidationDto.applicationId + ":" + getContext
        (context) + ":" + getVersionFromServiceAnnotation(reflect:getServiceAnnotations(context.serviceType)).apiVersion
    ;
    if (isThrottled(subscriptionLevelThrottleKey)){
        return true;
    } else {
        return false;
    }
}

function isApplicationLevelThrottled(AuthenticationContext keyValidationDto) returns (boolean) {
    string applicationLevelThrottleKey = keyValidationDto.applicationId + ":" + keyValidationDto.username;
    if (isThrottled(applicationLevelThrottleKey)){
        return true;
    } else {
        return false;
    }
}
function generateThrottleEvent(http:Request req, http:FilterContext context, AuthenticationContext keyValidationDto)
             returns (
                     RequestStream) {
    RequestStream requestStream;
    string apiVersion = getVersionFromServiceAnnotation(reflect:getServiceAnnotations
        (context.serviceType)).apiVersion;
    requestStream.apiKey = getContext(context) + ":" + apiVersion;
    requestStream.appKey = keyValidationDto.applicationId + ":" + keyValidationDto.username;
    requestStream.subscriptionKey = keyValidationDto.applicationId + ":" + getContext(context) + ":" +
        apiVersion;
    requestStream.appTier = keyValidationDto.applicationTier;
    requestStream.apiTier = keyValidationDto.apiTier;
    requestStream.subscriptionTier = keyValidationDto.tier;
    requestStream.resourceKey = getContext(context) + "/" + getVersionFromServiceAnnotation(reflect:
            getServiceAnnotations(context.serviceType)).apiVersion;
    TierConfiguration tier = getResourceLevelTier(reflect:getResourceAnnotations(context.serviceType,
            context.resourceName));
    requestStream.resourceTier = tier.policy;
    requestStream.userId = keyValidationDto.username;
    requestStream.apiContext = getContext(context);
    requestStream.apiVersion = apiVersion;
    requestStream.appTenant = keyValidationDto.subscriberTenantDomain;
    requestStream.apiTenant = getTenantDomain(context);
    requestStream.apiName = getApiName(context);
    return requestStream;
}
