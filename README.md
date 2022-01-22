# NAME

boinc\_watchdog.pl - Detect and restart a hanging BOINC client, abort hanging BOINC tasks

# VERSION

This documentation refers to **boinc\_watchdog.pl** version **0.0.1**.

# USAGE

**boinc\_watchdog.pl** is written for the **Linux**-version of the **BOINC** client.

**boinc\_watchdog.pl** is intended to be called in regular intervals, for
example by a **cron** job. There are no arguments necessary.

**boinc\_watchdog.pl** has to be called with superuser rights, because it 
will possibly restart the service **boinc-client**.

# INSTALLATION

1. Install **Perl**

        sudo apt-get install perl

2. Install the Perl-modules **Algorithm::Backoff::Fibonacci** and **Capture::Tiny**

        sudo cpan Algorithm::Backoff::Fibonacci
        sudo cpan Capture::Tiny

3. Copy **boinc\_watchdog.pl** into your home directory
4. Add **boinc\_watchdog.pl** to the superuser crontab

        sudo crontab -e

    using a line such as

        0,30 * * * * /home/<username>/boinc_watchdog/boinc_watchdog.pl

    This will tell the system to call **boinc\_watchdog.pl** every 30 minutes.

5. Optional: Install f.e. **nullmailer** to get mail notifications about restarts and task aborts

        sudo apt-get install nullmailer 

# DESCRIPTION

**boinc\_watchdog.pl** checks for two problems with BOINC:

- no task is executing
- tasks that use very little CPU power and never terminate ("0 CPU")

## No task is executing

Sometimes, the BOINC-client processes several tasks, but none of them are
actually executing: all of them have a status such as

    Postponed: VM job unmanagable, restarting later.

In this case, it usually helps to restart the BOINC client.
**boinc\_watchdog.pl** does exactly that by calling the command:

    /usr/sbin/service boinc-client restart

This command needs superuser rights, therefore **boinc\_watchdog.pl** has
to be called with superuser rights.

## Tasks that use very little CPU power and never terminate ("0 CPU")

Sometimes, the BOINC-client gets a task that seems to progress, but
actually never terminates. In **BoincTasks Js** or with **ps** it can be seen
that while such tasks are executing, they use very litte CPU power
("0 CPU"). **boinc\_watchdog.pl** uses this behavior to detect tasks affected
by that problem and aborts them by calling

    boinccmd --task <URL> <task_name> abort

# DIAGNOSTICS

## Info: 'boinccmd --get\_tasks' returned '&lt;error>' with exit code &lt;exit code>, wait &lt;delay> s before retrying...

**boinc\_watchdog.pl** uses **boinccmd --get\_tasks** to find out details about
the tasks the BOINC client is currently processing. Sometimes, this command 
does not work: instead of the task details, it returns an error message, 
such as:

    Authorization failure: -102
    can't connect to local host
    Operation failed: read() failed

In this case, **boinc\_watchdog.pl** tries to call **boinccmd --get\_tasks**
again after a few seconds. If after 5 retries **boinccmd --get\_tasks** still
does not return a normal result, **boinc\_watchdog.pl** aborts with the
error message:

    Error: Maximum number of retries reached!

## Error: Maximum number of retries reached!

See above.

## Info: Too few (0) active tasks --> restarting boinc-client

**boinc\_watchdog.pl** counted not a single task that has an
_active\_task\_state_ of _EXECUTING_. Most likely, all tasks have a
status such as:

    Postponed: VM job unmanagable, restarting later.

Normally, after restarting the BOINC-client, these tasks are gone and
new tasks will be downloaded and processed. For this reason,
**boinc\_watchdog.pl** will restart the boinc-client.

## Info: Task '&lt;task\_name>': Too low CPU usage (0.xx%) --> aborting task

**boinc\_watchdog.pl** detected a task with a CPU usage below 1 %. This
indicates that this task hangs and will never finish ("0 CPU"-task).

It is not exactly clear why such tasks hang. Experience has shown that
such tasks can be processed successfully on other clients. For this
reason, it is best to abort such tasks. **boinc\_watchdog.pl** does
exactly that.

# DEPENDENCIES

- Perl (tested with version 5.32.1)
- Algorithm::Backoff::Fibonacci (tested with version 0.009)
- Capture::Tiny (tested with version 0.48)

# INCOMPATIBILITIES

**boinc\_watchdog.pl** is not compatible with **Microsoft Windows** and
**Apple Mac** BOINC clients.

# BUGS AND LIMITATIONS

**Ubuntu** versions before 21.10 use a version of **BOINC** where
**boinccmd --get\_tasks** does not return the elapsed time of a task.
For such versions, **boinc\_watchdog.pl** cannot detect "0 CPU"-tasks
and will not abort them. (See also: 
[https://github.com/BOINC/boinc/issues/3463](https://github.com/BOINC/boinc/issues/3463))

# AUTHOR

Günther Bayler <g.bayler@gmx.at>

# LICENSE AND COPYRIGHT

This program is released under the
[Artistic License 2.0](http://www.perlfoundation.org/artistic_license_2_0).

Copyright (c) 2022 Günther Bayler <g.bayler@gmx.at>. All rights reserved.
