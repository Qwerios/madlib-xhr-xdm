(function() {
  var __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  (function(factory) {
    if (typeof exports === "object") {
      return module.exports = factory(require("madlib-console"), require("q"), require("madlib-xhr"), require("madlib-shim-easyxdm"), require("madlib-hostmapping"), require("madlib-xmldom"), require("madlib-promise-queue"));
    } else if (typeof define === "function" && define.amd) {
      return define(["madlib-console", "q", "madlib-xhr", "madlib-shim-easyxdm", "madlib-hostmapping", "madlib-xmldom", "madlib-promise-queue"], factory);
    }
  })(function(console, Q, XHR, easyXDMShim, HostMapping, xmldom, Queue) {
    var XDM;
    return XDM = (function(_super) {
      __extends(XDM, _super);

      function XDM(settings) {
        XDM.__super__.constructor.call(this, settings);
        this.hostMapping = new HostMapping(settings);
        if (window.xdmChannelPool == null) {
          window.xdmChannelPool = {};
        }
        if (window.xdmChannelQueue == null) {
          window.xdmChannelQueue = new Queue(1);
        }
        this.xdmChannelPool = window.xdmChannelPool;
        this.xdmChannel;
        this.xdmSettings;
      }

      XDM.prototype.isXDMCall = function() {
        return this.transport == null;
      };

      XDM.prototype.createXDMChannel = function(callback) {
        var hostBaseUrl, hostName, options, remote, rpcChannel, swfUrl, url;
        url = this.xdmSettings.xdmProvider;
        hostName = this.hostMapping.extractHostName(url);
        hostBaseUrl = url.substr(0, url.lastIndexOf("/") + 1);
        swfUrl = hostBaseUrl + "easyxdm.swf";
        if (this.xdmChannelPool[hostName] != null) {
          console.log("[XDM] Found existing channel for: " + this.xdmSettings.xdmProvider);
          return this.xdmChannelPool[hostName];
        }
        console.log("[XDM] Creating channel for: " + this.xdmSettings.xdmProvider);
        options = {
          remote: url,
          swf: swfUrl,
          onReady: callback
        };
        rpcChannel = {
          remote: {
            ping: {},
            request: {},
            getCookie: {},
            setCookie: {},
            deleteCookie: {}
          }
        };
        remote = new window.easyXDM.Rpc(options, rpcChannel);
        this.xdmChannelPool[hostName] = remote;
        return remote;
      };

      XDM.prototype.open = function(method, url, user, password) {
        this.xdmSettings = this.hostMapping.getXdmSettings(url);
        if (this.xdmSettings == null) {
          return XDM.__super__.open.call(this, method, url, user, password);
        } else {
          if (this.xdmSettings.cors && ((new XMLHttpRequest())["withCredentials"] != null)) {
            console.log("[XDM] Open using available CORS support");
            return XDM.__super__.open.call(this, method, url, user, password);
          } else {
            this.transport = null;
            this.xdmChannel = this.createXDMChannel();
            this.request = {
              headers: {},
              url: url,
              method: method,
              timeout: this.timeout
            };
            if (typeof username !== "undefined" && username !== null) {
              this.request.username = username;
            }
            if (password != null) {
              return this.request.password = password;
            }
          }
        }
      };

      XDM.prototype.send = function(data) {
        var parameters,
          _this = this;
        if (!this.isXDMCall()) {
          return XDM.__super__.send.call(this, data);
        } else {
          this.deferred = Q.defer();
          this.request.data = data;
          parameters = {
            url: this.request.url,
            accepts: this.request.accepts,
            contentType: this.request.contentType,
            headers: this.request.headers,
            data: data,
            cache: this.request.cache,
            timeout: this.request.timeout,
            username: this.request.username,
            password: this.request.password
          };
          if (this.xdmSettings.xdmVersion < 3) {
            parameters.dataType = "text";
            parameters.type = this.request.method;
          } else {
            parameters.type = this.request.type;
            parameters.method = this.request.method;
          }
          window.xdmChannelQueue.ready().then(function() {
            var xhrError;
            if (_this.timeout !== 0) {
              _this.timer = setTimeout(function() {
                window.xdmChannelQueue.done();
                return _this.createTimeoutResponse();
              }, _this.timeout + 1500);
            }
            try {
              return _this.xdmChannel.request(parameters, function(response) {
                window.xdmChannelQueue.done();
                clearTimeout(_this.timer);
                console.log("[XDM] consumer success", response);
                if (_this.xdmSettings.xdmVersion < 3) {
                  response = _this.convertV2Response(response);
                }
                return _this.createSuccessResponse(response);
              }, function(error) {
                window.xdmChannelQueue.done();
                clearTimeout(_this.timer);
                console.log("[XDM] consumer error", error);
                if (_this.xdmSettings.xdmVersion < 3) {
                  error = _this.convertV2Response(error);
                } else {
                  error = error.message || error;
                }
                return _this.createErrorResponse(error);
              });
            } catch (_error) {
              xhrError = _error;
              window.xdmChannelQueue.done();
              clearTimeout(_this.timer);
              console.error("[XHR] Error during request", xhrError);
            }
          }).done();
          return this.deferred.promise;
        }
      };

      XDM.prototype.convertV2Response = function(response) {
        var newResponse, xhr;
        xhr = response.xhr;
        return newResponse = {
          request: this.request,
          response: xhr.responseText,
          status: xhr.status,
          statusText: xhr.statusText
        };
      };

      XDM.prototype.createSuccessResponse = function(xhrResponse) {
        var jsonError, response, status, xmlError;
        if (this.xdmSettings.cors && ((new XMLHttpRequest())["withCredentials"] != null)) {
          return XDM.__super__.createSuccessResponse.call(this, xhrResponse);
        } else {
          response = xhrResponse.response || xhrResponse.responseText;
          status = parseInt(xhrResponse.status, 10);
          if (this.request.type === "json" && typeof response === "string") {
            if (response) {
              try {
                response = JSON.parse(response);
              } catch (_error) {
                jsonError = _error;
                console.warn("[XHR] Failed JSON parse, returning plain text", this.request.url);
                response = xhrResponse.responseText;
              }
            }
          } else if (this.request.type === "xml" && typeof response === "string" && response.substr(0, 5) === "<?xml") {
            if (response) {
              try {
                response = xmldom.parse(response);
              } catch (_error) {
                xmlError = _error;
                console.warn("[XHR] Failed XML parse, returning plain text", this.request.url);
                response = xhrResponse.responseText;
              }
            }
          }
          if ((status >= 200 && status < 300) || status === 1223) {
            if (status === 1233) {
              status = 204;
            }
            return this.deferred.resolve({
              request: this.request,
              response: response,
              status: status,
              statusText: xhrResponse.statusText
            });
          } else {
            return this.deferred.reject({
              request: this.request,
              response: response,
              status: status,
              statusText: xhrResponse.statusText
            });
          }
        }
      };

      XDM.prototype.createErrorResponse = function(xhrResponse) {
        if (this.xdmSettings.cors && ((new XMLHttpRequest())["withCredentials"] != null)) {
          return XDM.__super__.createErrorResponse.call(this, xhrResponse);
        } else {
          return this.deferred.reject({
            request: this.request,
            response: xhrResponse.responseText || xhrResponse.statusText,
            status: xhrResponse.status,
            statusText: xhrResponse.statusText
          });
        }
      };

      return XDM;

    })(XHR);
  });

}).call(this);
