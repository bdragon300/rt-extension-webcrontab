use inc::Module::Install;

RTx 'RT-Extension-WebCrontab';
license 'perl';
author 'Igor Derkach <gosha753951@gmail.com>';
version '0.1';

requires 'Config::Crontab' => '1.33';
requires 'String::Escape';
requires_rt('4.0.0');
auto_install();

sign;
&WriteAll;