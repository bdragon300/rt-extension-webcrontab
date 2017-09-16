package RT::Extension::WebCrontab;

use 5.010;
use strict;
use warnings;

use Config::Crontab;
use File::Find;
use Text::ParseWords;
use Clone qw(clone);
use Data::Dumper qw{Dumper};
use String::Escape qw(qprintable unquote printable);
use IPC::Open3;
use Symbol; # for gensym
use utf8;

our $VERSION = '0.1';


=head1 NAME

RT::Extension::WebCrontab - Manage crontab in the Admin UI

=head1 DESCRIPTION

This extension allows RT administrator to manage RT's user crontab in the Admin UI.

Features:

=over

=item * Manipulating the events rt-crontool command and its parameters

=item * Manipulating the environment variables inside crontab

=item * Manual launch of the rt-crontool event with printing results

=item * Showing the other (non rt-crontool) events as read-only

=back

Web interface is only available for users with SuperUser right.

=head1 DEPENDENCIES

=over

=item RT E<gt>= 4.0.0

=item Config::Crontab E<gt>= 1.33

=item String::Escape

=back

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=back

=head1 CONFIGURATION

The extension has no configuration itself.

To use the extension write in RT_SiteConfig.pm following:

For RT E<gt>= 4.2:

C<Plugin( "RT::Extension::WebCrontab" );>

For RT E<gt> 4.2:

C<Set(@Plugins, qw(RT::Extension::WebCrontab));>

After installing you may need to clear Mason cache and restart webserver.

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

=head2 get_available_values() -> \%values

Returns available values for each rt-crontool parameter

Returns:

HASHREF with following data:

    {
    search => \@search_classes,
    condition => \@condition_classes,
    action => \@action_classes,
    template => \@template_names,
    transaction => \@transaction,
    transaction-type => \@transaction_types
    }

=cut

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


=head2 get_available_env_vars() -> \@available_vars

Returns available environmental variables

=cut

sub get_available_env_vars {
    return clone(\@available_env_vars);
}


=head2 get_classes() -> \@classes

Returns rt-crontool available parameters

=cut

sub get_classes {
    return clone(\@classes);
}


=head2 load_crontab() -> \%crontab_structure

Loads current user crontab and returns its contents in structured view

Returns:

HASHREF with following data:

    {
    'events' => \@events,
    'env' => \%variables,
    'dump' => 'crontab dump as string'
    }

=cut

sub load_crontab {
    my $ct = new Config::Crontab;

    $ct->read || RT::Logger->warning("[RT::Extension::WebCrontab]: User crontab does not exist and will be created");
    if ($ct->error) {
        RT::Logger->error("[RT::Extension::WebCrontab]: Cannot read crontab: " . $ct->error);
        $ct->error('');
        return (undef);
    }
    my %crontab = (
        'events' => _read_events($ct),
        'env'    => _read_env($ct),
        'dump'   => $ct->dump
    );

    return \%crontab;
}

=head2 exec_event(\@shwords) -> \%results

Execute given command and return results

Parameters:

=over

=item shwords - ARRAYREF with command shellwords

=back

Returns:

HASHREF with following information:
{
        'stderr' => 'command STDERR',
        'stdout' => 'command STDOUT',
        'failed' => 'error msg when failed or undef if all ok',
        'pid' => 'PID of child process'
        'command' => 'command string that was executed'
}

=cut

sub exec_event {
    my $shwords = shift;

    my %cmd_result = (
        'stderr' => undef,
        'stdout' => undef,
        'failed' => undef,
        'pid' => undef,
        'command' => join ' ', map { qprintable($_) } @$shwords  # Quotation
    );

    my ($infh, $outfh, $errfh);
    $errfh = gensym();
    my $pid;

    eval{
        $pid = open3($infh, $outfh, $errfh, @$shwords);
    };
    if ($@) {
        $cmd_result{'failed'} = 'Launch has failed, see logs for details';
        $infh && close($infh);
        $outfh && close($outfh);
        $errfh && close($errfh);
        return \%cmd_result;
    }
    $cmd_result{'pid'} = $pid;
    $cmd_result{'stdout'} = join "", <$outfh>;
    $cmd_result{'stderr'} = join "", <$errfh>;

    $infh && close($infh);
    $outfh && close($outfh);
    $errfh && close($errfh);

    return \%cmd_result;
}


=head2 save_events(\@events) -> (success, error_msg)

Save given events

Parameters:

=over

=item events - ARRAYREF to events structure

=back

=cut

sub save_events {
    my $e = shift;
    save_crontab(load_crontab(), events => $e);
}


=head2 save_env(\%env_vars) -> (success, error_msg)

Save given environmental variables

Parameters:

=over

=item env_vars - HASHREF with variables

=back

=cut

sub save_env {
    my $e = shift;
    save_crontab(load_crontab(), env => $e);
}


=head2 save_crontab(old_crontab, \@events=>undef, \%env=>undef) -> (success, error_msg)

Saves crontab. Omitted optional parameters will be replaces the same ones from old_crontab.

Parameters:

=over

=item old_crontab - crontab structure, see load_crontab() docs

=item events - ARRAYREF, Optional. Events structure to be save. If undef the old ones will be used

=item env - HASHREF, Optional. Env vars to be save. If undef the old ones will be used

=back

=cut

sub save_crontab {
    my $old_crontab = shift;
    my %args = (
        events => undef, # type: ARRAYREF
        env => undef,    # type: HASHREF
        @_
    );
    
    my $events = _build_events($args{events} // $old_crontab->{'events'} // []);

    my %vars = %{ $args{env} // $old_crontab->{'env'} // {} };
    my $env = _build_env(\%vars);

    my $cb = new Config::Crontab::Block( -lines => $events );
    $cb->first(@$env);
    my $ct = new Config::Crontab;
    $ct->blocks([$cb]);

    #print $ct->data;
    $ct->error('');
    return ($ct->write, $ct->error);
}


=head2 _read_events(crontab) -> \@events

Extract events from crontab object

Parameters:

=over

=item crontab - Config::Crontab object

=back

Returns:

ARRAYREF to array with hashes:

    {
    'active' => whether event is active (commented event means inactive state)
    'expression' => crontab expression,
    'shellwords' => ARRAYREF with extracted command shellwords (without comment)
    'comment' => comment (shellwords following the #)
    'skip' => 0,  # 1 event contains another command (not rt-crontool), skip it to manage
    arg => value, # rt-crontool parameters ('action'=>..., 'action-arg'=>..., etc.), see @classes package var
    ...
    }

=cut

sub _read_events {
    my $crontab = shift;
    my @events = ();

    foreach my $event ($crontab->select( -type => 'event' )) {
        my %e = (
            'active' => $event->active,
            'expression' => $event->datetime,
            'shellwords' => undef,  # ARRAYREF
            'comment' => undef,
            'skip' => 0,
        );
        my $cmd = $event->command;
        utf8::decode($cmd) unless utf8::is_utf8($cmd);
        my @shwords = shellwords(($cmd));

        # Mark as 'skip' non rt-crontool command
        if ($shwords[0] !~ /.*rt-crontool$/) {
            $RT::Logger->info("[RT::Extension::WebCrontab]: Skip event: " . $cmd);

            $e{'skip'} = 1;
            # push @events, clone(\%e);
            # next;
        }

        my @event_shellwords = (shift @shwords); # Cmd exe

        while (@shwords) {
            my $shword = shift @shwords;

            # If rt-crontool then parse parameters
            unless ($e{'skip'}) {
                if (my @c = grep { $shword eq ('--' . $_) } @classes) {
                    my $class = $c[0];

                    $e{$class} = '';
                    next if (exists($shwords[0]) && $shwords[0] =~ /^--/); # no value for current parameter

                    $e{$class} = unquote(shift @shwords); # unescape made by shellwords
                }
            }
            
            # Comment has met
            if ($shword =~ /^#/) {
                $shword =~ s/^#//;
                $e{'comment'} = join ' ', ($shword, @shwords);
                last;
            }
            push @event_shellwords, $shword;
        }

        $e{'shellwords'} = [@event_shellwords];
        push @events, clone(\%e);
    }

    return \@events;
}


=head2 _read_env(crontab) -> \%vars

Extract environment variables from crontab object

Parameters:

=over

=item crontab - Config::Crontab object

=back

Returns:

HASHREF with variables value: {'variable' => value}

=cut

sub _read_env {
    my $crontab = shift;
    my %vars = ();

    foreach my $env ($crontab->select( -type => 'env' )) {
        my $v = $env->value;
        utf8::decode($v) unless utf8::is_utf8($v);

        $vars{$env->name} = unquote($v);
    }

    return \%vars;
}


=head2 _build_events(\@events) -> \@event_objects

Builds Config::Crontab::Event objects from event structures. See also _read_events docs

Parameters:

=over

=item events - ARRAYREF to events structures

=back

Returns:

ARRAYREF to array with Config::Crontab::Event objects

=cut

sub _build_events {
    my $events = shift;

    my @res = ();

    for my $event (@$events) {
        my @cmd_params = ();

        unless ($event->{'skip'}) {
            my $cmd_exe = _get_crontool_path();
            push @cmd_params, $cmd_exe;

            for my $class (grep !/-arg$/, @classes) {
                next unless exists($event->{$class});

                push @cmd_params, '--' . $class;
                my $clean_val = $event->{$class} =~ s/\r|\n|\t/ /gr;
                push @cmd_params, qprintable($clean_val);

                if (exists($event->{$class . '-arg'})) {
                    push @cmd_params, '--' . $class . '-arg';
                    $clean_val = $event->{$class . '-arg'} =~ s/\r|\n|\t/ /gr;
                    push @cmd_params, qprintable($clean_val);
                }
            }
        } else {
            # Keep command as-is for non-rt-crontool event
            @cmd_params = @{$event->{'shellwords'}};
        }

        if (length $event->{'comment'}) {
            my $clean_val = $event->{'comment'} =~ s/\r|\n|\t/ /gr;
            push @cmd_params, '#' . printable($clean_val);
        }

        my $cmd = join(' ', @cmd_params);
        my $expression = $event->{'expression'};
        my $is_active = $event->{'active'} ? 1 : 0;
        push @res, new Config::Crontab::Event(
            -datetime => $expression,
            -command => $cmd,
            -active => $is_active
        );
    }

    return \@res;
}


=head2 _build_env(\%variables) -> \@env_objects

Builds Config::Crontab::Env objects from variables hash

Parameters:

=over

=item variables - HASHREF with variables values

=back

Returns:

ARRAYREF to array with Config::Crontab::Env objects

=cut

sub _build_env {
    my $vars = shift;
    my @env = ();

    for my $k (keys %$vars) {
        my $v = qprintable($vars->{$k});
        push @env, new Config::Crontab::Env( -name => $k, -value => $v );
    }

    return \@env;
}


=head2 _get_crontool_path() -> rt-crontool_path

Returns absolute path to the rt-crontool command

Returns:

"/path/to/the/rt-crontool"

=cut

sub _get_crontool_path {
    my $cmd_path = $RT::BinPath;
    $cmd_path =~ s/([^\/])$/$1\// if $cmd_path; # Add trailing slash if needed
    return $cmd_path . 'rt-crontool';
}

1;
