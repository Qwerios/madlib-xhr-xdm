# The XDM variant of the browser XHR. If an xdm settings section exists for the
# called url we will use the easyXDM based fall back
#
( ( factory ) ->
    if typeof exports is "object"
        module.exports = factory(
            require "madlib-console"
            require "q"
            require "madlib-xhr"
            require "madlib-shim-easyxdm"
            require "madlib-hostmapping"
            require "madlib-xmldom"
            require "madlib-promise-queue"
        )
    else if typeof define is "function" and define.amd
        define( [
            "madlib-console"
            "q"
            "madlib-xhr"
            "madlib-shim-easyxdm"
            "madlib-hostmapping"
            "madlib-xmldom"
            "madlib-promise-queue"
        ], factory )

)( ( console, Q, XHR, easyXDMShim, HostMapping, xmldom, Queue ) ->

    # The XDM variant of xhr uses our custom easyXDM based fall back for older
    # browsers that don't support CORS.
    # The XDM channel is also used if the service provider doesn't support CORS.
    #
    # Keep in mind you need a valid entry in the settings module and provider
    # files need to be deployed on the server. This module transparently supports
    # older v2 providers
    #
    class XDM extends XHR

        constructor: ( settings ) ->

            # Let the base XHR class setup itself first
            #
            super( settings )

            # Create our host mapping instance
            #
            @hostMapping = new HostMapping( settings )

            # XDM channels are managed and reused per host.
            # Because multiple versions of the XDM module may exist we need to expose
            # the shared channels on a global variable.
            # Since XDM is a browser only thing we can use the window object directly
            #
            if not window.xdmChannelPool?
                window.xdmChannelPool = {}

            if not window.xdmChannelQueue?
                window.xdmChannelQueue = new Queue( 1 )

            @xdmChannelPool = window.xdmChannelPool
            @xdmChannel
            @xdmSettings

        createXDMChannel: ( callback ) ->
            url          = @xdmSettings.xdmProvider
            hostName     = @hostMapping.extractHostName( url )
            hostBaseUrl  = url.substr( 0, url.lastIndexOf( "/" ) + 1 )
            swfUrl       = hostBaseUrl + "easyxdm.swf"

            # Check if there is an existing channel
            #
            if @xdmChannelPool[ hostName ]?
                console.log( "[XDM] Found existing channel for: #{@xdmSettings.xdmProvider}" )
                return @xdmChannelPool[ hostName ]

            console.log( "[XDM] Creating channel for: #{@xdmSettings.xdmProvider}" );

            # Create a new XDM channel
            #
            options =
                remote:     url
                swf:        swfUrl
                onReady:    callback

            rpcChannel =
                remote:
                    ping:           {}
                    request:        {}
                    getCookie:      {}
                    setCookie:      {}
                    deleteCookie:   {}

            # easyXDM is not a CommonJS module. The shim we required ensures
            # the global object is available
            #
            remote = new window.easyXDM.Rpc( options, rpcChannel )

            # Add the channel to the pool for future use
            #
            @xdmChannelPool[ hostName ] = remote

            return remote

        open: ( method, url, user, password ) ->
            # NOTE: We are not calling @createTransport here like the normal XHR does
            #
            # Retrieve the XDM settings for the target host
            #
            @xdmSettings = @hostMapping.getXdmSettings( url )

            # Check if the host is present in the xdm settings
            #
            if not @xdmSettings? or @isSameOrigin( url )
                # Not an XDM call
                # Use the super class to create an XHR transport
                # The existence of an @transport indicates a non XDM call
                #
                super( method, url, user, password )

            else
                # If the xdmSettings indicate the server should have CORS and if
                # the browser supports it we don't have to use the XDM channel.
                # In an application that uses different servers it can happen that
                # the xdm enabled xhr is used for some and not for others
                #
                if ( @xdmSettings.cors and ( new XMLHttpRequest() )[ "withCredentials" ]? )
                    console.log( "[XDM] Open using available CORS support" )

                    # Use CORS instead
                    #
                    super( method, url, user, password )
                else
                    # Clear @transport in case someone is reusing this XHR instance (bad boy!)
                    #
                    @transport = null

                    # Get or create the XML channel
                    #
                    @xdmChannel = @createXDMChannel()

                    @request =
                        headers:    {}
                        url:        url
                        method:     method
                        timeout:    @timeout

                    @request.username = username if username?
                    @request.password = password if password?

        send: ( data ) ->
            if @transport
                # Not an XDM call so let the base XHR handle the request
                #
                super( data )
            else
                @deferred     = Q.defer()
                @request.data = data

                # All calls using the XDM channel need to be marshalled as text
                # So when constructing an answer we need to handle the conversion
                # to what the caller expects (XML Document, Object, etc)
                #
                # Prepare the call using the parameters in @request
                #
                parameters =
                    url:            @request.url
                    accepts:        @request.accepts
                    contentType:    @request.contentType
                    headers:        @request.headers
                    data:           data
                    cache:          @request.cache
                    timeout:        @request.timeout
                    username:       @request.username
                    password:       @request.password

                # V2 XDM providers use jQuery style parameters
                # V3 XDM providers use MAD XHR parameters
                #
                # Translation from MAD to jQuery is:
                # * type   -> dataType
                # * method -> type
                #
                # NOTE: The use of headers requires a jQuery 1.5+ XDM provider
                #
                if ( @xdmSettings.xdmVersion < 3 )
                    parameters.dataType = "text"
                    parameters.type     = @request.method
                else
                    parameters.type     = @request.type
                    parameters.method   = @request.method

                # Wait for a spot in XDM queue
                #
                window.xdmChannelQueue.ready()
                .then( () =>
                    # Start the request timeout check
                    # This is our failsafe timeout check
                    # If timeout is set to 0 it means we will wait indefinitely
                    # XDM timout is half a second more then normal XHR because
                    # the XHR fallback timeout on the other side of the channel
                    # might also occur and there could be a small delay due to
                    # transport
                    #
                    if @timeout isnt 0
                        @timer = setTimeout( =>
                            # Free up our spot in the queue
                            #
                            window.xdmChannelQueue.done()

                            @createTimeoutResponse()
                        , @timeout + 1500 )

                    # Do the XHR call
                    #
                    try
                        @xdmChannel.request( parameters, ( response ) =>

                            # Free up our spot in the queue
                            #
                            window.xdmChannelQueue.done()

                            # Stop the timeout fall-back
                            #
                            clearTimeout( @timer )

                            console.log( "[XDM] consumer success", response )

                            # Convert XDM V2 response format
                            #
                            response = @convertV2Response( response ) if ( @xdmSettings.xdmVersion < 3 )

                            @createSuccessResponse( response )

                        ,   ( error ) =>

                            # Free up our spot in the queue
                            #
                            window.xdmChannelQueue.done()

                            # Stop the timeout fall-back
                            #
                            clearTimeout( @timer )

                            console.log( "[XDM] consumer error", error )

                            if ( @xdmSettings.xdmVersion < 3 )
                                # Convert XDM V2 response format
                                #
                                error = @convertV2Response( error )
                            else
                                error = error.message or error

                            @createErrorResponse( error )
                        )

                    catch xhrError
                        # Free up our spot in the queue
                        #
                        window.xdmChannelQueue.done()

                        # Stop the timeout fall-back
                        #
                        clearTimeout( @timer )

                        # NOTE: Consuming exceptions might not be the way to go here
                        # But this way the promise will be rejected as expected
                        #
                        console.error( "[XHR] Error during request", xhrError )
                        return
                )
                .done()

                return @deferred.promise

        isSameOrigin: ( url ) ->
            # Check if window.location exists
            # If it doesn't exist there should be no cross-domain restriction
            #
            isSameOrigin = true
            if window? and document?
                location    = window.location
                aLink       = document.createElement( "a" )
                aLink.href  = url

                isSameOrigin =
                    aLink.hostname   is location.hostname and
                    aLink.port       is location.port     and
                    aLink.protocol   is location.protocol

        convertV2Response: ( response ) ->
            xhr = response.xhr

            # The V2 provider has a different mapping for the response data
            # We will map it to the new V3 format here
            #
            newResponse =
                request:    @request
                response:   xhr.responseText
                status:     xhr.status
                statusText: xhr.statusText

        createSuccessResponse: ( xhrResponse ) ->
            if @transport
                # Not an XDM call
                #
                super( xhrResponse )

            else if ( @xdmSettings.cors and ( new XMLHttpRequest() )[ "withCredentials" ]? )
                # Using CORS isnstead of XDM
                #
                super( xhrResponse )

            else
                # Some XHR don't implement .response so fall-back to .responseText
                #
                response = xhrResponse.response || xhrResponse.responseText || xhrResponse.statusText
                status   = parseInt( xhrResponse.status, 10 )

                if @request.type is "json" and typeof response is "string"
                    # Try to parse the JSON response
                    # Can be empty for 204 no content response
                    #
                    if response
                        try
                            response = JSON.parse( response )

                        catch jsonError
                            console.warn( "[XHR] Failed JSON parse, returning plain text", @request.url )
                            response = xhrResponse.response || xhrResponse.responseText || xhrResponse.statusText

                else if @request.type is "xml" and typeof response is "string" and response.substr( 0, 5 ) is "<?xml"

                    # Try to parse the XML response
                    #
                    if response
                        try
                            response = xmldom.parse( response )

                        catch xmlError
                            console.warn( "[XHR] Failed XML parse, returning plain text", @request.url )
                            response = xhrResponse.responseText

                # A successful XDM channel response can still be an XHR error response
                #
                if ( status >= 200 and status < 300 ) or status is 1223

                    # Internet Explorer mangles the 204 no content status code
                    #
                    status = 204 if status is 1233

                    @deferred.resolve(
                        request:    @request
                        response:   response
                        status:     status
                        statusText: xhrResponse.statusText
                    )
                else
                    @deferred.reject(
                        request:    @request
                        response:   response
                        status:     status
                        statusText: xhrResponse.statusText
                    )

        createErrorResponse: ( xhrResponse ) ->
            if @transport
                # Not an XDM call
                #
                super( xhrResponse )

            else if ( @xdmSettings.cors and ( new XMLHttpRequest() )[ "withCredentials" ]? )
                # Using CORS instead of XDM
                #
                super( xhrResponse )

            else
                response = xhrResponse.response || xhrResponse.responseText || xhrResponse.statusText

                if @request.type is "json" and typeof response is "string"
                    # Try to parse the JSON response
                    # Can be empty for 204 no content response
                    #
                    if response
                        try
                            response = JSON.parse( response )

                        catch jsonError
                            console.warn( "[XHR] Failed JSON parse, returning plain text", @request.url )
                            response = xhrResponse.response || xhrResponse.responseText || xhrResponse.statusText

                @deferred.reject(
                    request:    @request
                    response:   response
                    status:     xhrResponse.status
                    statusText: xhrResponse.statusText
                )
)