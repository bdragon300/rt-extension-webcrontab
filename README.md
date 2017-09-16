# Summary

RT::Extension::WebCrontab - Manage crontab in the Admin UI

# Description

This extension allows RT administrator to manage RT's user crontab in the Admin UI.

Features:

* Manipulating the events rt-crontool command and its parameters
* Manipulating the environment variables inside crontab
* Manual launch of the rt-crontool event with printing results
* Showing the other (non rt-crontool) events as read-only

Web interface is only available for users with SuperUser right.

# Dependencies:

* RT >= 4.0.0
* Config::Crontab >= 1.33
* String::Escape

# Installation

Execute this command:

$ perl Makefile.PL && make && make install

# Configuration

The extension has no configuration itself.

To use the extension write in RT_SiteConfig.pm following:

For RT>=4.2:

```
Plugin( "RT::Extension::WebCrontab" );
```

For RT<4.2:

```
Set(@Plugins, qw(RT::Extension::WebCrontab));
```

After installing you may need to clear Mason cache and restart webserver.
