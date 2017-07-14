package RT::Extension::WebCrontab;

use 5.010;
use strict;
use warnings;

use Config::Crontab;
use File::Find;
use Text::ParseWords;
use Clone qw(clone);
use Data::Dumper qw{Dumper};
use utf8;

our $VERSION = '0.1';


=head1 NAME

RT::Extension::WebCrontab allows to manage RT's crontab via web-interface

=head1 DESCRIPTION

This extension can manage rt-crontool starting and its parameters in RT's system
user crontab. Also you can define environment variables in crontab.

Web interface only available for users with SuperUser right.

=head1 DEPENDENCIES

=over

=item RT E<gt>= 4.0.0

=item Config::Crontab E<gt>= 1.33

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

For RT E<gt>= 4.2:

C<Plugin( "RT::Extension::WebCrontab" );>

For RT E<gt> 4.2:

C<Set(@Plugins, qw(RT::Extension::WebCrontab));>

After installing you may need to clean Mason cache and restart RT process.

Web interface will be available for users with SuperUser right in 
AdminE<nbsp>-E<gt>E<nbsp>ToolsE<nbsp>-E<gt>E<nbsp>Crontab.

=cut

my @classes = qw(search search-arg condition condition-arg action action-arg template transaction transaction-type);
my @available_env_vars = qw(MAILTO);

# Fill available values for each command arg
my %module_list = (
    'transaction' => [qw! first last all !],

    'transaction-type' => [qw! 
        CommentEmailRecord
        EmailRecord
        Correspond
        Comment
        CustomField
        Untake
        Take
        Force
        Steal
        Give
        AddWatcher
        DelWatcher
        Subject
        Addlink
        DeleteLink
        Told
        Set
        PurgeTransaction
        AddReminder
        OpenReminder
        ResolveReminder !]
);


sub get_available_values {
    my $vals = clone(\%module_list);

    # Modules
    foreach my $class (qw( Search Condition Action )) {
        File::Find::find(sub {
            push @{$vals->{lc $class}}, "RT::${class}::$1" if /^(?!Generic|UserDefined)(\w+)\.pm$/i;
        }, grep -d, map "$_/RT/$class", @INC);
    }

    # Templates
    my $tpls = RT::Templates->new( $RT::SystemUser );
    $tpls->LimitToGlobal();
    while (my $tpl = $tpls->Next) {
        push @{$vals->{'template'}}, $tpl->Name;
    }

    return $vals;
}

sub get_available_env_vars {
    return clone(\@available_env_vars);
}

sub get_classes {
    return clone(\@classes);
}

sub load_events {
    my $e = load_crontab();
    return $e->{'events'};
}

sub load_env {
    my $e = load_crontab();
    return $e->{'env'};
}

sub load_crontab {
    my $crontab = {
        'events' => [],
        'env'    => {},
        'dump' => []
    };

    my $ct = new Config::Crontab;
    $ct->read || RT::Logger->warning("[RT::Extension::WebCrontab]: User crontab does not exist and will be created");
    if ($ct->error) {
        RT::Logger->error("[RT::Extension::WebCrontab]: Cannot read crontab: " . $ct->error);
        $ct->error('');
        return (undef);
    }

    foreach my $event ($ct->select( -type => 'event' )) {
        my $e = {};
        my $cmd = $event->command;
        utf8::decode($cmd) unless utf8::is_utf8($cmd);
        my @shwords = shellwords(($cmd));

        if ($shwords[0] !~ /.*rt-crontool$/) {
            $RT::Logger->warning("[RT::Extension::WebCrontab]: Skip event: " . $cmd);

            $e->{'skip'} = 1;
            $e->{'obj'} = $event;
            push @{$crontab->{'events'}}, clone($e);

            next;
        } else {
            shift @shwords;
        }
        
        $e->{'expression'} = $event->datetime;
        while (@shwords) {
            my $shword = shift @shwords;

            if (my @c = grep { $shword eq ('--' . $_) } @classes) {
                my $class = $c[0];

                $e->{$class} = '';
                next if (exists($shwords[0]) && $shwords[0] =~ /^--/); # no value for current parameter

                my $v = shift @shwords;
                $v =~ s/^"(.*)"$/$1/g; # unquote
                $v =~ s/\\([\\"])/$1/g; # unescape

                $e->{$class} = $v;
            }
        }

        push @{$crontab->{'events'}}, clone($e);
    }

    foreach my $env ($ct->select( -type => 'env' )) {
        my $v = $env->value;
        utf8::decode($v) unless utf8::is_utf8($v);
        $v =~ s/^"(.*)"$/$1/g; # unquote
        $v =~ s/\\([\\"])/$1/g; # unescape

        $crontab->{'env'}->{$env->name} = $v;
    }
    $crontab->{'dump'} = $ct->dump;

    return $crontab;
}

sub save_events {
    my $e = shift;
    save_crontab({'events' => $e});
}

sub save_env {
    my $e = shift;
    save_crontab({'env' => $e});
}

sub save_crontab {
    my $crontab = shift;
    my @events;
    my @env;
    my $old_crontab = load_crontab();
    
    # Events
    ## rt-crontool command
    my $cmd_path = $RT::BinPath;
    $cmd_path =~ s/([^\/])$/$1\// if $cmd_path; #Add trailing slash
    my $cmd_exe = $cmd_path . 'rt-crontool';

    $crontab->{'events'} = $old_crontab->{'events'} unless (exists($crontab->{'events'}));

    for my $event (@{$crontab->{'events'}}) {

        my @cmd_params = ();
        # Non-rt-crontool call
        if ($event->{'skip'}
            && ref($event->{'obj'}))
        {
            push @events, $event->{'obj'};
            next;
        }

        for my $class (grep !/-arg$/, @classes) {
            next unless exists($event->{$class});

            # escape and quote
            $event->{$class} =~ s/(["\\])/\\$1/g;
            $event->{$class} = '"' . $event->{$class} . '"';

            push @cmd_params, '--' . $class;
            push @cmd_params, $event->{$class};

            if (exists($event->{$class . '-arg'})) {
                # escape and quote
                $event->{$class . '-arg'} =~ s/(["\\])/\\$1/g;
                $event->{$class . '-arg'} = '"' . $event->{$class . '-arg'} . '"';

                push @cmd_params, '--' . $class . '-arg';
                push @cmd_params, $event->{$class . '-arg'};
            }
        }

        my $cmd = join(' ', ($cmd_exe, @cmd_params));
        my $expression = $event->{'expression'};
        push @events, new Config::Crontab::Event( -datetime => $expression, -command => $cmd );
    }

    # Environment variables
    $crontab->{'env'} = $old_crontab->{'env'} unless (exists($crontab->{'env'}));
    for my $e (@available_env_vars) {
        next unless exists($crontab->{'env'}->{$e});

        # escape and quote
        my $v = $crontab->{'env'}->{$e};
        $v =~ s/(["\\])/\\$1/g;
        $v = '"' . $v . '"';

        push @env, new Config::Crontab::Env( -name => $e, -value => $v );
    }


    my $cb = new Config::Crontab::Block( -lines => \@events );
    $cb->first(@env);
    my $ct = new Config::Crontab;
    $ct->blocks([$cb]);

    #print $ct->data;
    $ct->error('');
    return ($ct->write, $ct->error);
}

1;
