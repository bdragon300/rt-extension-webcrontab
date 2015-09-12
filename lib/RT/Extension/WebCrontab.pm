package RT::Extension::WebCrontab;

use 5.010;
use strict;
use warnings;

our $VERSION = '0.1';

=head1 NAME

RT::Extension::WebCrontab allows to manage RT's crontab via web-interface

=head1 DESCRIPTION

This extension can manage rt-crontool starting and its parameters in RT's system user crontab. Also you can define environment variables in crontab.

Web interface only available for users with SuperUser right.

=head1 DEPENDENCIES

=over

=item RT >= 4.0.0

=item Config::Crontab >= 1.33

=back

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=back

=head1 CONFIGURATION

To use the extension write in RT_SiteConfig.pm following:

For RT>=4.2:

C<Plugin( "RT::Extension::WebConfig" );>

For RT<4.2:

C<Set(@Plugins, qw(RT::Extension::WebConfig));>

After installing you may need to clean Mason cache and restart RT process.

Web interface will be available for users with SuperUser right in Admin->Tools->Crontab.

=cut

1;