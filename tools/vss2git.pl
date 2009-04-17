#!/usr/bin/perl
#
# VSS-to-git migration script, Sitaram Chamarty
# based on:
# VSS-to-Subversion migration script
# Original Brett Wooldridge (brettw@riseup.com)
#
# Contributions:
#   Daniel Dragnea

# my modifications should be easy enough to spot if you have the original, but
# larger blocks or critical changes are marked "(Sita)"

# (Sita)
use Cwd;
use Time::Local;
our $atomic_buffer = 60;
# commits within 60 seconds of each other are clubbed into an "atom"

# (Sita)
sub mychdir
{
    # uncomment lines below to debug chdir problems, if any...
    my $target = shift;
    my $current = "canary";
    $current = cwd();
    print  STDERR "chdir from $current to $target\n";
    chdir ($target) or die "$!";
    $current = "canary";
    $current = cwd();
    print  STDERR "chdir SUCCESS, $current\n";
}

$DEBUG = 1;

$SSREPO = "";
$SSPROJ = "";
$SSHOME = "";
$SSCMD = "";

if ($DEBUG == 1)
{
    open( STDERR, "> migrate.log");
}

$PHASE = 0;
&parse_args(@ARGV);
&setup();
if ($RESTART)
{
    &restart();
}

if ($PHASE < 1)
{
    &build_hierarchy();
}
if ($PHASE < 2)
{
    &build_filelist();
}
if ($PHASE < 3)
{
    &build_histories();
}
if ($PHASE < 4)
{
    &create_directories;
}

&extract_and_import;

if ($DEBUG)
{
    close(DEBUG);
}
exit;


##############################################################
# Parse Command-line arguments
#
sub parse_args
{
    $argc = @ARGV;
    if ($argc < 1)
    {
        print "migrate: missing command arguments\n";
        print "Try 'migrate --help' for more information\n\n";
        exit -1;
    }

    if ($ARGV[0] eq '--help')
    {
        print "Usage: migrate [options] project\n\n";
        print "Migrate a Visual SourceSafe project to Subversion.\n\n";
        print "  --restart\t\trestart the migration from last checkpoint\n";
        print "  --ssrepo=<dir>\trepository path, e.g. \\\\share\\vss\n";
        print "  --sshome=<dir>\tVSS installation directory\n";
        print "  --force-user=<user>\tforce the files to be checked into Subversion as\n";
        print "\t\t\tas user <user>\n";
        exit -1;
    }

    for ($i = 0; $i < $argc; $i++)
    {
        $arg = $ARGV[$i];
        if ($arg eq '--restart')
        {
            $RESTART = 1;
        }
        elsif ($arg =~ /\-\-ssrepo\=/)
        {
            $SSREPO = $';
        }
        elsif ($arg =~ /\-\-sshome\=/)
        {
            $SSHOME = $';
        }
        elsif ($arg =~ /\-\-force\-user\=/)
        {
            $FORCEUSER = $';
        }
        else
        {
            $SSPROJ = $arg;
        }
    }

    if ($SSPROJ !~ /^\$\/\w+/)
    {
        print "Error: missing project specification, must be of the form \$/project\n\n";
        exit -1;
    }
}


##############################################################
# Check environment and setup globals
#
sub setup
{
    $SSREPO = $ENV{'SSDIR'} unless length($SSREPO) > 0;
    if ($SSREPO eq '' || length($SSREPO) == 0)
    {
        die "Environment variable SSDIR must point to a SourceSafe repository.";
    }
    $SSHOME = $ENV{'SS_HOME'} unless length($SSHOME) > 0;
    if ($SSHOME eq '' || length($SSHOME) == 0)
    {
        die "Environment variable SS_HOME must point to where SS.EXE is located.";
    }

    $ENV{'SSDIR'} = $SSREPO;
    $SSCMD = "$SSHOME";
    if ($SSCMD !~ /^\".*/)
    {
        $SSCMD = "\"$SSCMD\"";
    }
    $SSCMD =~ s/\"(.*)\"/\"$1\\ss.exe\"/;

    my $banner = "Visual SourceSafe to Subversion Migration Tool.\n" .
    "Brett Wooldridge (brettw\@riseup.com)\n\n" .
    "SourceSafe repository: $SSREPO\n" .
    "SourceSafe directory : $SSHOME\n" .
    "SourceSafe project   : $SSPROJ\n";
    print "$banner";
    if ($DEBUG)
    {
        print  STDERR "$banner";
    }
}


##############################################################
# Build project directory hierarchy
#
sub build_hierarchy
{
    if ($DEBUG)
    {
        print  STDERR "\n#############################################################\n";
        print  STDERR "#                    Subroutine: build_hierarchy            #\n";
        print  STDERR "#############################################################\n";
    }

    my ($cmd, $blank, $dir, @lines);

    $blank = 1;
    $dir = "";

    print "Building directory hierarchy...";

    $/ = ':';
    $cmd = $SSCMD . " Dir $SSPROJ -I-Y -R -F-";
    $_ = `$cmd`;
    # (Sita) added to fix problems in the wrapping code below
    s/\r\n/\n/g;

    if ($DEBUG)
    {
        print  STDERR "Build Hierarchy: raw data";
        print  STDERR "$_";
        print  STDERR "#####################################################\n";
    }

    # what this next expression does is to merge wrapped lines like:
    #    $/DeviceAuthority/src/com/eclyptic/networkdevicedomain/deviceinterrogator/excep
    #    tion:
    # into:
    #    $/DeviceAuthority/src/com/eclyptic/networkdevicedomain/deviceinterrogator/exception:
    # (Sita) original was quite a different regex, possibly wrong, and
    # definitely missed >1 continuation lines
    1 while s/\n([- \(\)\w.\/]+\:)/ $1/mg;

    if ($DEBUG)
    {
        print  STDERR "Build Hierarchy: post process";
        print  STDERR "$_";
    }

    $/ = "";
    @lines = split('\n');
    foreach $line (@lines)
    {
        if ($line =~ /(.*)\:/)
        {
            chop($line);
            push(@projects, $line);
        }
    }

    @projects = sort(@projects);    
    open(DIRS, "> directories.txt");
    foreach $line (@projects)
    {
        print DIRS "$line\n";
    }
    close(DIRS);

    my $count = @lines;
    print "\b\b\b:\tdone ($count dirs)\n";

    $PHASE = 1;
}


##############################################################
# Build a list of files from the list of directories
#
sub build_filelist
{
    if ($DEBUG)
    {
        print  STDERR "\n#############################################################\n";
        print  STDERR "#                    Subroutine: build_filelist             #\n";
        print  STDERR "#############################################################\n";
    }

    my ($proj, $cmd, $i, $j, $count);

    print "Building file list (  0%):      ";

    $count = @projects;

    $i = 0;
    $j = 0.0;
    foreach $proj (@projects)
    {
        $/ = ':';

        $cmd = $SSCMD . " Dir -I-Y \"$proj\"";
        print  STDERR "cmd=$cmd\n";
        $_ = `$cmd`;
        print  STDERR "length ================== ", length(), "\n";
        s/\r\n/\n/g;
        print  STDERR "length ================== ", length(), "\n";

        # what this next expression does is to merge wrapped lines like:
        #    $/DeviceAuthority/src/com/eclyptic/networkdevicedomain/deviceinterrogator/excep
        #    tion:
        # into:
        #    $/DeviceAuthority/src/com/eclyptic/networkdevicedomain/deviceinterrogator/exception:
        # (Sita) see above for similar line
        1 while s/\n([- \(\)\w.\/]+\:)/ $1/mg;

        $/ = "";
        @lines = split('\n');
        foreach $line (@lines)
        {
            if ($line eq '' || length($line) == 0)
            {
                last;
            }
            elsif ($line !~ /(.*)\:/ && $line !~ /^\$.*/ &&
                $line !~ /^([0-9]+) item.*/ && $line !~ /^No items found.*/)
            {
                push(@filelist, "$proj/$line");
                printf("\b\b\b\b\b\b\b\b\b\b\b\b\b(%3d%%): %5d", (($j / $count) * 100), $i);
                if ($DEBUG)
                {
                    print  STDERR "$proj/$line\n";
                }
                $i++;
            }
        }
        $j++;
    }
    print "\b\b\b\b\b\b\b\b\b\b\b\b\b(100%):\tdone ($i files)\n";
}


##############################################################
# Build complete histories for all of the files in the project
#
sub build_histories
{
    if ($DEBUG)
    {
        print  STDERR "\n#############################################################\n";
        print  STDERR "#                    Subroutine: build_histories            #\n";
        print  STDERR "#############################################################\n";
    }

    my ($file, $pad, $padding, $oldname, $shortname, $diff);
    my ($i, $count);

    print "Building file histories (  0%): ";

    $versioncount = 0;
    $count = @filelist;
    $i = 0.0;
    $diff = 0;
    $pad = "                                                     ";
    $oldname = "";
    $shortname = "";
    foreach $file (@filelist)
    {
        # display sugar
        $oldname =~ s/./\b/g;
        $shortname = substr($file, rindex($file,'/')+1);
        $diff = length($oldname) - length($shortname);
        $padding = ($diff > 0) ? substr($pad, 0, $diff) : "";
        print "$oldname";
        $tmpname = substr("$shortname$padding", 0, 45);
        printf("\b\b\b\b\b\b\b\b(%3d%%): %s", (($i / $count) * 100), $tmpname);
        $padding =~ s/./\b/g;
        print "$padding";
        $oldname = substr($shortname, 0 , 45);

        # real work
        $cmd = $SSCMD . " History -I-Y \"$file\"";
        print  STDERR "cmd=$cmd\n";
        $_ = `$cmd`;
        # (Sita) 
        s/\r\n/\n/g;

        &proc_history($file, $_);

        $i++;
    }

    @sortedhist = sort(@histories);
    open(HIST, ">histories.txt");
    foreach $hist (@sortedhist)
    {
        print HIST "$hist\n";
    }
    close(HIST);

    $oldname =~ s/./\b/g;
    print "$oldname\b\b\b\b\b\b\b\b(100%):\tdone ($versioncount versions)" . substr($pad, 0, 20) . "\n"; 
}


##############################################################
# Restart from previously generated parsed project data
#
sub proc_history
{
    my $file = shift(@_);
    my $hist = shift(@_);
    my $timestamp;

    $hist =~ s/Checked in\n/Checked in /g;

    # print "Starting processing of history file\n";

    use constant STATE_FILE    => 0;
    use constant STATE_VERSION => 1;
    use constant STATE_USER    => 2;
    use constant STATE_ACTION  => 3;
    use constant STATE_COMMENT => 5;
    use constant STATE_FINAL   => 6;

    my $state = STATE_VERSION;

    local $proj = $SSPROJ;
    $proj =~ s/(\$)/\\$1/g;
    $proj =~ s/(\/)/\\$1/g;

    my ($version, $junk, $user, $date, $time, $month, $day, $year);
    my ($hour, $minute, $path, $action);

    $comment = "";
    my @lines = split('\n', $hist);
    my $line_count = @lines;
    my $i = 0;
    foreach $line (@lines)
    {
        if ($state == STATE_VERSION && $line =~ /^\*+  Version ([0-9]+)/)
        {
            $versioncount++;
            $version = $1;
            $state = STATE_USER;
        }
        elsif ($state == STATE_USER && $line =~ /^User: /)
        {
            ($junk, $user, $junk, $date, $junk, $time) = split(' ', $line);

            ($month,$day,$year) = split('/', $date);
            ($hour,$minute) = split(':', $time);
            $year = ($year < 80) ? 2000+$year : 1900+$year;
            # (Sita) need timestamp in seconds since epoch for GIT_AUTHOR_DATE
            $hour = 0 if $hour == 12;     # work though "12:46p" and "12:46a"
            $hour += 12 if ($minute =~ /p/);
            $minute =~ s/[ap]$//;
            $month--;
            $timestamp = timelocal(0,$minute,$hour,$day,$month,$year);
            $state = STATE_ACTION;
        }
        elsif ($state == STATE_ACTION)
        {
            if ($line =~ /^Checked in /)
            {
                if ($' =~ /^$proj/)
                {
                    $path = $';
                    $action = 'checkin';
                    $state = STATE_COMMENT;
                }
                else
                {
                    $proj = $';
                    $action = 'checkin';
                    $state = STATE_COMMENT;
                }
            }
            elsif ($line =~ /^Created/)
            {
                $action = 'created';
                $state = STATE_COMMENT;
            }
            elsif ($line =~ / added/)
            {
                $path = $`;
                $action = 'added';
                $state = STATE_COMMENT;
            }
            elsif ($line =~ / deleted/)
            {
                $path = $`;
                $action = 'deleted';
                $state = STATE_COMMENT;
            }
        }
        elsif ($state == STATE_COMMENT)
        {
            if ($line =~ /^Comment\:/)
            {
                $comment = $';
            }
            elsif (length($comment) > 0 && length($line) > 0)
            {
                $comment = $comment . "\n" . $line;
            }
            elsif (length($line) == 0)
            {
                $comment =~ s/^\s+(.*)/$1/g;
                $comment =~ s/\"/\\\"/g;
                $state = STATE_FINAL;
            }
        }

        $i++;
        if ($state == STATE_FINAL || $i == $line_count)
        {
            $hist = join(',', $timestamp, $file, sprintf("%04d", $version),
                $user, $action, "\"$comment\"");
            $comment = "";
            if ($DEBUG)
            {
                print  STDERR "$hist\n";
            }
            push(@histories, $hist);
            $state = STATE_VERSION;
        }
    }
}


##############################################################
# Restart from previously generated parsed project data
#
sub restart
{
    local($i) = 0;

    if (-f "directories.txt")
    {
        print "Loading directories:      ";

        open(DIRS, "< directories.txt");
        while (<DIRS>)
        {
            $line = $_;
            chop($line);
            push(@projects, $line);
            $i++;
            printf("\b\b\b\b\b%5d", $i);
        }
        close(DIRS);
        print "\b\b\b\b\b\t\tdone ($i dirs)\n";
        $PHASE = 1;
    }

    if (-f "histories.txt")
    {
        print "Loading file histories:      ";
        $i = 0;
        open(HIST, "< histories.txt");
        while (<HIST>)
        {
            $line = $_;
            chop($line);
            push(@sortedhist, $line);
            $i++;
            printf("\b\b\b\b\b%5d", $i);
        }
        close(HIST);
        print "\b\b\b\b\b\tdone ($i versions)\n";
        $PHASE = 3;
    }

    if (-f "extract_progress.txt")
    {
        local ($file, $version);
        print "Calculating extract progress:";
        open(EXTRACT, "< extract_progress.txt");
        while (<EXTRACT>)
        {
            $RESTARTFILE = $_;
            chop($RESTARTFILE);
            ($file, $version) = split(',', $RESTARTFILE);
        }
        close(EXTRACT);

        $RESTARTFILE =~ s/(\$)/\\$1/g;
        $RESTARTFILE =~ s/(\/)/\\$1/g;
        if ($DEBUG)
        {
            print  STDERR "Restart from: $RESTARTFILE\n";
        }
        $file =~ s/^$proj(.*)/$1/g;
        $file = substr($file, rindex($file, '/')+1);
        print "\trestart from $file (v.$version)\n";
        $PHASE = 4;
    }
}


##############################################################
# Create the directory hierarchy in the local filesystem
#
sub create_directories
{
    if ($DEBUG)
    {
        print  STDERR "\n#############################################################\n";
        print  STDERR "#                    Subroutine: create_directories         #\n";
        print  STDERR "#############################################################\n";
    }

    my $proj = $SSPROJ;
    $proj =~ s/(\$)/\\$1/g;
    $proj =~ s/(\/)/\\$1/g;

    my ($basedir) = $SSPROJ;
    $basedir =~ s/^\$\///g;

    print "Creating local directories: ";
    &recursive_delete('./work');
    mkdir('./work');

    my @dircomponents = split('/', $basedir . '/');
    my $buildupdir = './work';
    foreach $dir (@dircomponents)
    {
        $buildupdir = $buildupdir . '/' . $dir;
        if ($DEBUG)
        {
            print  STDERR "Creating base dir '$buildupdir'\n";
        }
        mkdir($buildupdir) or system("cmd");
    }

    foreach $dir (@projects)
    {
        if ($dir =~ /^$proj\//)
        {
            my $rawdir = "./work/$basedir/$'";
            if ($DEBUG)
            {
                print  STDERR "Creating project dir '$rawdir'\n";
            }
            mkdir($rawdir) or system("cmd");
        }
    }
    print "\tdone\n";
}


##############################################################
# Delete a directory tree and all of its files recursively
#
sub recursive_delete
{
    my ($parent) = @_;    
    my (@dirs, $dir);

    opendir(DIR, $parent);
    @dirs = readdir(DIR);
    closedir(DIR);
    foreach $dir (@dirs)
    {
        if ($dir ne '.' && $dir ne '..')
        {
            recursive_delete("$parent/$dir");
        }
    }

    if (-d $parent)
    {
        rmdir($parent);
    }
    elsif (-f $parent)
    {
        unlink($parent);
    }
}


##############################################################
# This is the meat.  Extract each version of each file in the
# project from VSS and check it into Subversion
#
sub extract_and_import
{
    # (Sita) this WHOLE sub has been changed heavily

    my $oldpwd;
    if ($DEBUG)
    {
        print  STDERR "\n#############################################################\n";
        print  STDERR "#                    Subroutine: extract_and_import         #\n";
        print  STDERR "#############################################################\n";
    }

    my ($padding);
    my ($cmd);

    print "Extracting and creating (  0%%): ";

    open(EXTRACT, "> extract_progress.txt");

    if (defined($RESTARTFILE))
    {
        # (Sita)
        die "I don't want to do this RESTART stuff right now; need to test it...";
        while ($#sortedhist > 0)
        {
            $hist = shift(@sortedhist);
            last if ($hist =~ /^$RESTARTFILE(.*)/);
            if ($DEBUG)
            {
                print  STDERR "$hist\n";
            }
        }
    }

    my $proj = $SSPROJ;
    $proj =~ s/(\$)/\\$1/g;
    $proj =~ s/(\/)/\\$1/g;

    my ($basedir) = $SSPROJ;
    $basedir =~ s/^\$\///g;

    my $count = @sortedhist;
    my $i = 0.0;
    my $diff = 0;
    my $pad = "                                                     ";
    my $shortname = "";
    my $oldname = "";

    mychdir('./work');

    $oldpwd = cwd();
    mychdir($basedir);
    system("git init >&2");
    mychdir($oldpwd);

    my $saved_ts = 0;
    my $saved_user = '';
    my $saved_comment = '';
    foreach $hist (@sortedhist)
    {
        my ($timestamp, $file, $version, $user, $action, $comment) = split(',', $hist, 6);
        die "we don't handle deletes yet..." if $action =~ /deleted/;
        if (defined($FORCEUSER))
        {
            $user = $FORCEUSER;
        }
        # do we have a previous commit to flush?
        if ($saved_ts and
            $saved_ts + $atomic_buffer < $timestamp ||
            # same time stamp by chance; different user/comment means not the
            # same commit:
            $saved_user ne $user || $saved_comment ne $comment )
        {
            $oldpwd = cwd();
            mychdir($basedir);

            $ENV{GIT_AUTHOR_NAME} = $ENV{GIT_AUTHOR_EMAIL} = $saved_user;
            $ENV{GIT_AUTHOR_DATE} = $saved_ts;
            $saved_comment =~ s/"/'/g;    # paranoia?
            print STDERR `git add -A .; echo ADD... EXITCODE $?; git commit -m "$saved_comment"; echo COMMIT EXITCODE $?`;

            mychdir($oldpwd);
        }

        $saved_ts = $timestamp;
        $saved_user = $user;
        $saved_comment = $comment;

        # display sugar
        $oldname =~ s/./\b/g;
        $shortname = substr($file, &min(rindex($file,'/')+1, 40)) . ' (v.' . int($version) . ')';
        $diff = length($oldname) - length($shortname);
        $padding = ($diff > 0) ? substr($pad, 0, $diff) : "";
        print "$oldname";
        $tmpname = substr("$shortname$padding", 0, 46);
        printf("\b\b\b\b\b\b\b\b(%3d%%): %s", (($i / $count) * 100), $tmpname);
        $padding =~ s/./\b/g;
        print "$padding";
        $oldname = substr($shortname, 0 , 46);

        # chdir to the proper directory      
        $path = substr($file, 0, rindex($file, '/'));
        $path =~ s/^$proj(.*)/$1/g;
        $path = "$basedir$path";

        # extract the file from VSS
        $ver = int($version);
        $cmd = $SSCMD . " get -GTM -W -I-Y -GL\"$path\" -V" . int($ver) . " \"$file\"";
        $out = "DID NOT RUN!\n";
        $out = `$cmd`;
        # system("cmd");
        $out =~ s/\r\n/\n/g;
        if ($DEBUG)
        {
            print  STDERR "$cmd\n";
            print  STDERR "$out";
        }

        $i++;
    }
    if ($saved_ts)
    {
        $oldpwd = cwd();
        mychdir($basedir);

        $ENV{GIT_AUTHOR_NAME} = $ENV{GIT_AUTHOR_EMAIL} = $saved_user;
        $ENV{GIT_AUTHOR_DATE} = $saved_ts;
        # chdir???
        $saved_comment =~ s/"/'/g;    # paranoia?
        print STDERR `git add -A .; echo ADD... EXITCODE $?; git commit -m "$saved_comment"; echo COMMIT EXITCODE $?`;

        mychdir($oldpwd);
    }
    close(EXTRACT);
    $oldname =~ s/./\b/g;
    print "$oldname\b\b\b\b\b\b\b\b(100%):\t" . substr("done$pad", 46) . "\n";
}


##############################################################
# Find the minimum value between two integers
#
sub min
{
    local $one = shift(@_);
    local $two = shift(@_);

    return ($one < $two ? $one : $two);
}
