# Summary

RT::Extension::WebCrontab allows to manage RT's crontab via web-interface

# Description

This extension can manage rt-crontool starting and its parameters in RT's system user crontab. Also you can define environment variables in crontab.

Web interface only available for users with SuperUser right.

# Installation

Dependencies:

* RT >= 4.0.0
* Config::Crontab >= 1.33

Commands to install:

  perl Makefile.PL
  make
  make install

# Configuration

To use the extension write in RT_SiteConfig.pm following:

For RT>=4.2:

```
Plugin( "RT::Extension::WebConfig" );
```

For RT<4.2:

```
Set(@Plugins, qw(RT::Extension::WebConfig));
```

After installing you may need to clean Mason cache and restart RT process.

Web interface will be available for users with SuperUser right in Admin->Tools->Crontab.