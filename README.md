# madlib-xhr-xdm

The Cross Domain barrier breaking version of madlib-xhr. Needs an xdm provider to be placed on the target server. This is the third (V3) iterations of our jXDM solution. This client should be backwards compatible with V2 providers.

## acknowledgments
The Marviq Application Development library (aka madLib) was developed by me when I was working at Marviq. They were cool enough to let me publish it using my personal github account instead of the company account. We decided to open source it for our mutual benefit and to ensure future updates should I decide to leave the company.


## philosophy
JavaScript is the language of the web. Wouldn't it be nice if we could stop having to rewrite (most) of our code for all those web connected platforms running on JavaScript? That is what madLib hopes to achieve. The focus of madLib is to have the same old boring stuff ready made for multiple platforms. Write your core application logic once using modules and never worry about the basics stuff again. Basics including XHR, XML, JSON, host mappings, settings, storage, etcetera.

Currently madLib is focused on the following platforms:

* Web browsers (IE6+, Chrome, Firefox, Opera)
* Appcelerator/Titanium
* PhoneGap
* NodeJS


## installation
```bash
$ npm install madlib-xhr-xdm --save
```

## usage
