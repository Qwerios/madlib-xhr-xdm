# madlib-xhr-xdm [![Build Status](https://travis-ci.org/Qwerios/madlib-xhr-xdm.svg?branch=master)](https://travis-ci.org/Qwerios/madlib-xhr-xdm)
The Cross Domain barrier breaking version of madlib-xhr. Needs an xdm provider to be placed on the target server. This is the third (V3) iterations of our jXDM solution. This client should be backwards compatible with V2 providers.

## acknowledgments
The Marviq Application Development library (aka madlib) was developed by me when I was working at Marviq. They were cool enough to let me publish it using my personal github account instead of the company account. We decided to open source it for our mutual benefit and to ensure future updates should I decide to leave the company.

The Cross Domain barrier is breached using [easyXDM](https://github.com/oyvindkinsey/easyXDM). I've created [shim-easyxdm](https://github.com/Qwerios/madlib-shim-easyxdm) for easier inclusion with npm.


## philosophy
JavaScript is the language of the web. Wouldn't it be nice if we could stop having to rewrite (most) of our code for all those web connected platforms running on JavaScript? That is what madLib hopes to achieve. The focus of madLib is to have the same old boring stuff ready made for multiple platforms. Write your core application logic once using modules and never worry about the basics stuff again. Basics including XHR, XML, JSON, host mappings, settings, storage, etcetera. The idea is to use the tried and proven frameworks where available and use madlib based modules as the missing link.

Currently madLib is focused on supporting the following platforms:

* Web browsers (IE6+, Chrome, Firefox, Opera)
* Appcelerator/Titanium
* PhoneGap
* NodeJS


## installation
```bash
$ npm install madlib-xhr-xdm --save
```

## usage
The Cross Domain version of the madlib XHR requires knowledge of the following other madlib modules:
* [xhr](https://github.com/Qwerios/madlib-xhr)
* [hostmapping](https://github.com/Qwerios/madlib-hostmapping)
* [settings](https://github.com/Qwerios/madlib-settings)
* [xdm-provider](https://github.com/Qwerios/madlib-xdm-provider)

The basic premise of using the xdm variant is as that you declare where the cross domain bridge for a certain host can be found.
You declare this with the madlib-settings module which in turn is picked up by the hostmapping module. The xhr-xdm module will pick-up on these settings when it detect the target host for you call has an xdm configuration.

NOTE: You need an [xdm provider](https://github.com/Qwerios/madlib-xdm-provider) installed on your server for this module to function.

First we setup the host mapping and xdm configuration using madlib-settings:

```javascript
var settings    = require( "madlib-settings"    );
var HostMapping = require( "madlib-hostmapping" );

settings.set( "hostMapping", {
    "www.myhost.com":   "production",
    "acc.myhost.com":   "acceptance",
    "tst.myhost.com":   "testing",
    "localhost":        "development"
} );

settings.set( "hostConfig", {
    "production": {
        "api":      "https://api.myhost.com"
        "content":  "http://www.myhost.com"
    },
    "acceptance": {
        "api":      "https://api-acc.myhost.com"
        "content":  "http://acc.myhost.com"
    },
    "testing": {
        "api":      "https://api-tst.myhost.com"
        "content":  "http://tst.myhost.com"
    },
    "development": {
        "api":      "https://api-tst.myhost.com"
        "content":  "http://localhost"
    }
} );

settings.set( "xdmConfig", {
    "api.myhost.com":
    {
        cors:               false,
        xdmVersion:         3,
        xdmProvider:        "https://api.myhost.com/xdm/v3/index.html"
    },
    "api-acc.myhost.com":
    {
        cors:               true,
        xdmVersion:         3,
        xdmProvider:        "https://api-acc.myhost.com/xdm/v3/index.html"
    }
    ...
} );

var hostMapping = new HostMapping( settings )
```

With all the configuration out of the way we can use the xdm variant of the xhr as a drop-in replacement for the normal madlib-xhr:

```javascript
var XHR = require( "madlib-xhr-xdm" );

// targetHost is determined based on your environment (production, testing, etc)
//
var targetHost = hostMappig.getHostName( "api" );

var xhr = new XHR( settings );
xhr.call( {
    url:            "https://" + targetHost + "/myservice",
    method:         "GET",
    type:           "json"
} )
.then( ... )
.done()
```

Remember that you can use the browser field in your package.json to transparently upgrade the xhr to the xhr-xdm when bundling with for instance [browserify](http://browserify.org/).
The advantage of this approach is that you can still run your code (and unit tests) on nodejs without any modifications. In the above code example you would require "madlib-xhr" instead of directly requiring the xdm variant.
Remember to add both madlib-xhr and madlib-xhr-xdm to your dependencies.

```json
...
"browser": {
    "madlib-xhr": "madlib-xhr-xdm"
},
...
"dependencies": {
    "q": "~1.0.0",
    "madlib-object-utils": "~0.1.0",
    "madlib-xml-objectifier": "~0.1.2",
    "madlib-console": "~0.1.1",
    "madlib-hostmapping": "~0.1.3",
    "madlib-xmldom": "~0.1.1",
    "madlib-xhr-xdm": "~0.1.0",
    "madlib-xhr": "~0.1.0",
    "underscore": "~1.5.2",
    "moment": "~2.5.1"
},
...
```