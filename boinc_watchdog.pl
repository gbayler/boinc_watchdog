#!/usr/bin/perl

# pragmas and modules
use warnings;
use strict;
use Algorithm::Backoff::Fibonacci;
use Capture::Tiny qw/capture/;
use File::Basename;

# constants
use version; my $VERSION = qv('0.0.2');
my $MIN_NR_ACTIVE_TASKS   = 1;
my $MIN_CPU_USAGE         = 0.01;
my $MIN_ELAPSED_TASK_TIME = 300;
my $BACKOFF_MAX_ATTEMPTS    = 5;
my $BACKOFF_INITIAL_DELAY_1 = 1;
my $BACKOFF_INITIAL_DELAY_2 = 2;

my %BOINC_WORKING_DIR_FOR = (
    'linux'   => '/usr/bin',
    'MSWin32' => 'C:\Program Files\BOINC',
);

MAIN:
{
    $0 = basename( $0 );

    # change into BOINC working directory
    chdir( $BOINC_WORKING_DIR_FOR{ $^O } );

    # read BOINC tasks into hash
    my $tasks_ref = get_boinc_tasks();

    # count active tasks
    my $nr_active_tasks = 0;
    for my $task (sort keys %{ $tasks_ref }) {
        if ($tasks_ref->{ $task }{'active_task_state'} eq 'EXECUTING') {
            $nr_active_tasks++;
        }
    }

    # restart boinc-client if there are no active tasks
    if ($nr_active_tasks < $MIN_NR_ACTIVE_TASKS) {
        print "$0: Info: Too few ($nr_active_tasks) active tasks --> restarting boinc-client\n";
        if ($^O eq 'linux') {
            `/usr/sbin/service boinc-client restart`;
        }
        else {
            print "$0: Info: Please restart BOINC client manually!\n";
        }
        exit;
    }

    # find and abort hanging ("0 CPU") tasks
    for my $task (sort keys %{ $tasks_ref }) {
        my $active_task_state = $tasks_ref->{ $task }{'active_task_state'};
        next if ($active_task_state ne 'EXECUTING');
        my $cpu_time          = $tasks_ref->{ $task }{'current CPU time'};
        my $elapsed_task_time = $tasks_ref->{ $task }{'elapsed task time'};
        next if (!defined $elapsed_task_time || $elapsed_task_time < $MIN_ELAPSED_TASK_TIME);
        my $cpu_usage = $cpu_time / $elapsed_task_time;
        if ($cpu_usage < $MIN_CPU_USAGE) {
            my $project_url = $tasks_ref->{ $task }{'project URL'};
            print "$0: Info: Task '$task': Too low CPU usage (", sprintf("%.2f", 100 * $cpu_usage), "%) --> aborting task\n";
            `boinccmd --task $project_url $task abort`;
        }
    }
}

# subroutines

# ------------------------------------------------------------------------------
# get_boinc_tasks
# ------------------------------------------------------------------------------
sub get_boinc_tasks {
    my $state = 'init';
    my $name;
    my %tasks;

    # configure backoff algorithm
    my $ab = Algorithm::Backoff::Fibonacci->new(
        #consider_actual_delay => 1,                        # optional, default 0
        #max_actual_duration   => 0,                        # optional, default 0 (retry endlessly)
        max_attempts           => $BACKOFF_MAX_ATTEMPTS,    # optional, default 0 (retry endlessly)
        #jitter_factor         => 0.25,                     # optional, default 0
        initial_delay1         => $BACKOFF_INITIAL_DELAY_1, # required
        initial_delay2         => $BACKOFF_INITIAL_DELAY_2, # required
        #max_delay             => 20,                       # optional
        #delay_on_success      => 0,                        # optional, default 0
    );

    # call 'boinccmd --get_tasks' to find out infos about running boinc tasks
    my $command = 'boinccmd --get_tasks';
    my ($stdout, $stderr, $exit_code) = capture { system( $command ); };
    chomp $stdout;
    chomp $stderr;

    # if boinccmd returns an error, retry several times after some backoff time
    while ($stderr) {
        my $delay = $ab->failure();
        die "$0: Error: Maximum number of retries reached!\n"   if ($delay == -1);

        print "$0: Info: '$command' returned '$stderr' with exit code $exit_code, wait $delay s before retrying...\n";
        sleep( $delay );
        ($stdout, $stderr, $exit_code) = capture { system( $command ); };
        chomp $stdout;
        chomp $stderr;
    }

    # store infos about boinc tasks in hash table
    for my $line (split(/\n/, $stdout)) {
        if ($state eq 'init') {
            next unless $line =~ /^\d+\) -----------/;
            $state = 'task_name';
        }
        elsif ($state eq 'task_name') {
            ($name) = $line =~ /name: (\S+)/;
            $state = 'task_body';
        }
        elsif ($state eq 'task_body') {
            if ($line =~ /^\s+(.+): (.+)$/) {
                my ($key, $value) = $line =~ /^\s+(.+): (.+)$/;
                $tasks{ $name }{ $key } = $value;
            }
            else {
                $state = 'task_name';
            }
        }
    }

    return (\%tasks);
}

__END__

=pod

=encoding UTF-8

=head1 NAME

boinc_watchdog.pl - Detect and restart a hanging BOINC client, abort hanging BOINC tasks

=head1 VERSION

This documentation refers to B<boinc_watchdog.pl> version B<0.0.2>.

=head1 USAGE

B<boinc_watchdog.pl> is written for the B<Linux>-version of the B<BOINC> client.

B<boinc_watchdog.pl> is intended to be called in regular intervals, for
example by a B<cron> job. There are no arguments necessary.

B<boinc_watchdog.pl> has to be called with superuser rights, because it 
will possibly restart the service B<boinc-client>.

=head1 INSTALLATION

=over 4

=item 1. Install B<Perl>

    sudo apt-get install perl

=item 2. Install the Perl-modules B<Algorithm::Backoff::Fibonacci> and B<Capture::Tiny>

    sudo cpan Algorithm::Backoff::Fibonacci
    sudo cpan Capture::Tiny

=item 3. Copy B<boinc_watchdog.pl> into your home directory

=item 4. Add B<boinc_watchdog.pl> to the superuser crontab

    sudo crontab -e

using a line such as

    0,30 * * * * /home/<username>/boinc_watchdog/boinc_watchdog.pl

This will tell the system to call B<boinc_watchdog.pl> every 30 minutes.

=item 5. Optional: Install f.e. B<nullmailer> to get mail notifications about restarts and task aborts

    sudo apt-get install nullmailer 

=back

=head1 DESCRIPTION

B<boinc_watchdog.pl> checks for two problems with BOINC:

=over 4

=item * no task is executing

=item * tasks that use very little CPU power and never terminate ("0 CPU")

=back

=head2 No task is executing

Sometimes, the BOINC-client processes several tasks, but none of them are
actually executing: all of them have a status such as

    Postponed: VM job unmanagable, restarting later.

In this case, it usually helps to restart the BOINC client.
B<boinc_watchdog.pl> does exactly that by calling the command:

    /usr/sbin/service boinc-client restart

This command needs superuser rights, therefore B<boinc_watchdog.pl> has
to be called with superuser rights.

=head2 Tasks that use very little CPU power and never terminate ("0 CPU")

Sometimes, the BOINC-client gets a task that seems to progress, but
actually never terminates. In B<BoincTasks Js> or with B<ps> it can be seen
that while such tasks are executing, they use very litte CPU power
("0 CPU"). B<boinc_watchdog.pl> uses this behavior to detect tasks affected
by that problem and aborts them by calling

    boinccmd --task <URL> <task_name> abort


=head1 DIAGNOSTICS

=head2 Info: 'boinccmd --get_tasks' returned '<error>' with exit code <exit code>, wait <delay> s before retrying...

B<boinc_watchdog.pl> uses B<boinccmd --get_tasks> to find out details about
the tasks the BOINC client is currently processing. Sometimes, this command 
does not work: instead of the task details, it returns an error message, 
such as:

    Authorization failure: -102
    can't connect to local host
    Operation failed: read() failed

In this case, B<boinc_watchdog.pl> tries to call B<boinccmd --get_tasks>
again after a few seconds. If after 5 retries B<boinccmd --get_tasks> still
does not return a normal result, B<boinc_watchdog.pl> aborts with the
error message:

    Error: Maximum number of retries reached!

=head2 Error: Maximum number of retries reached!

See above.

=head2 Info: Too few (0) active tasks --> restarting boinc-client

B<boinc_watchdog.pl> counted not a single task that has an
I<active_task_state> of I<EXECUTING>. Most likely, all tasks have a
status such as:

    Postponed: VM job unmanagable, restarting later.

Normally, after restarting the BOINC-client, these tasks are gone and
new tasks will be downloaded and processed. For this reason,
B<boinc_watchdog.pl> will restart the boinc-client.

=head2 Info: Task '<task_name>': Too low CPU usage (0.xx%) --> aborting task

B<boinc_watchdog.pl> detected a task with a CPU usage below 1 %. This
indicates that this task hangs and will never finish ("0 CPU"-task).

It is not exactly clear why such tasks hang. Experience has shown that
such tasks can be processed successfully on other clients. For this
reason, it is best to abort such tasks. B<boinc_watchdog.pl> does
exactly that.

=head1 DEPENDENCIES

=over 4

=item * Perl (tested with version 5.32.1)

=item * Algorithm::Backoff::Fibonacci (tested with version 0.009)

=item * Capture::Tiny (tested with version 0.48)

=back

=head1 INCOMPATIBILITIES

B<boinc_watchdog.pl> is not compatible with B<Microsoft Windows> and
B<Apple Mac> BOINC clients.

=head1 BUGS AND LIMITATIONS

B<Ubuntu> versions before 21.10 use a version of B<BOINC> where
B<boinccmd --get_tasks> does not return the elapsed time of a task.
For such versions, B<boinc_watchdog.pl> cannot detect "0 CPU"-tasks
and will not abort them. (See also: 
L<https://github.com/BOINC/boinc/issues/3463>)

=head1 AUTHOR

Günther Bayler <g.bayler@gmx.at>

=head1 LICENSE AND COPYRIGHT

This program is released under the
L<Artistic License 2.0|http://www.perlfoundation.org/artistic_license_2_0>.

Copyright (c) 2022 Günther Bayler <g.bayler@gmx.at>. All rights reserved.

=cut
