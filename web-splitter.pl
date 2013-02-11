#!/usr/bin/perl -w


# Copyright (C) Carlo Contavalli - 2002-2013
# This script is free software, please refer to the LICENSE file for
# terms and conditions.

=head1 NAME

web-splitter.pl - splits apache logs per virtual host.

=head1 DESCRIPTION

web-splitter reads log lines from apache in standard input, and splits
the logs in multiple files. It creates a hierarchy based on day, month,
year and the virtual host the log line belongs to.

It is meant to be used in conjunction with web-rewriter.pl, and allows
to configure a single CustomLog directive for the whole apache installation
while still splitting the log files per virtual host.

The script tries to be smart in not opening too many file descriptors
while keeping the most frequently used ones open with buffering.

It is similar in purpose to cronolog, http://www.cronolog.org, the main
difference is related to having less configurable options, and integration
with web-rewriter or massive virtual hosting solutions.

=head1 CONFIGURATION

In apache, you need to:

=over 2

=item 0. Edit web-splitter.pl to have the configuration you need.

The parameters you care about are:

I<cfg_logdir>: Set this to the directory where you want your logs to be kept.

I<cfg_maxfd>: How many file descriptors (log files) to keep open at most at
the same time.

I<cfg_prefix>: A prefix to give to each log file.

I<cfg_uid, cfg_gid>: The uid and gid this script should run as. Do not use
root (0)! The privileges of the log directory should be set such as this user
(and this user only!) can write to that directory. If untrusted users can write
in the log directories, they can create symlinks or similar to overwrite
arbitrary files on your system!  So, be careful.

I<cfg_dir>: The working directory of this script. You don't normally
need to worry about this parameter.

=item 1. Have mod_log_config enabled in apache.

On most distributions this is compiled into the apache binary already, so nothing to do.
You can verify by using 'apache2 -l' and checking the presence of 'mod_log_config' in
the output.

=item 2. Configure logging in apache.

The default in apache is generally:

    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined

Adding a line like this one will be sufficient:

    LogFormat "B<%V> %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" vcombined

But it's generally better to use:

    LogFormat "B<%V> %h %l %u B<%{[%d/%m/%Y:%H:%M:%S %z]}t> \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" vcombined

The problem is the %t, which changes depending on the locale being used. For example,
with the default %t months are expressed as a 3 letter string, which means that if your linux
system is configured to use the IT locale, January may end up as Gen instead of Jan in your
log file, and day and month may end up inverted.

By modifying %t as described above, months are expressed as a number (%m instead of %b), and
the order is well defined.

=item 3. Send your logs to web-splitter.

To do so, you just need a line like:

  CustomLog "|/opt/scripts/web-splitter.pl" vcombined

in your apache configuration files. Note that for debugging and backup purposes, and
to still have an aggregated log file to feed to tools like analog, it is handy to
keep a single log file somewhere, which means I generally keep a line like:

  CustomLog "/var/log/apache2/access.log" vcombined

=back

=cut

use strict;
use Sys::Syslog;
use POSIX;

  # cfg_logdir: directory where logs are kept
  # cfg_maxfd: maximum number of file descriptors to keep open at a given time
  # cfg_prefix: prefix to use for created log files
my ($cfg_logdir, $cfg_maxfd, $cfg_prefix) = ('/opt/log', 32, 'web-');
  # cfg_uid: userid to use to write logs.
  # cfg_gid: group to use to write logs.
my ($cfg_uid, $cfg_gid, $cfg_dir) = (105, 4, $cfg_logdir);

openlog('apache-logger', 'pid', 'daemon');

setgid($cfg_gid) or syslog('warning', "setgid to $cfg_gid failed - $!\n");
setuid($cfg_uid) or syslog('warning', "setuid to $cfg_uid failed - $!\n");
chdir($cfg_dir) or syslog('warning', "chdir to $cfg_dir failed - $!\n");

my (%fdcache, @fdindex, $fd);

sub getfd($) {
  my ($file) = @_;
  my ($tmp);
  my (@array);

    # IF file has not already been opened, open it
  if(!$fdcache{$file}) {

    if($#fdindex+1 >= $cfg_maxfd) {
      @array=@{pop(@fdindex)};
      #print "Closing: " . $array[0] . " size fdcache: " . keys(%fdcache) . "\n";
      close($array[1]) or syslog('warning', "couldn't close file $array[1].\n");
      undef($array[2]);
      delete($fdcache{$array[0]});
      undef($array[0]);
      undef(@array);
    }

      # Remember file name
    $array[0]="$file";

      # Open file. In case of problems, try to create
      # missing directories
    open($array[1], ">>$cfg_logdir/$file") or do {
      $tmp = "$cfg_logdir/";

      foreach ($file =~ /([^\/]+)\//g) {
        $tmp = $tmp . "$_/";
	mkdir "$tmp";
      }
      open($array[1], ">>$cfg_logdir/$file") or syslog('warning', "couldn't open file for writing $cfg_logdir/$file - $!.\n");
    };

      # Disable buffering in case of failure
    select((select($array[1]), $| = 1)[0]);

      # Index file descriptor by filename
    $fdcache{$file}=\@array;

      # Index file descriptor by its position
    $array[2]=push(@fdindex, \@array)-1;

    #print "Not cached: $file, size fdcache: " . keys(%fdcache) . ", position: " . $array[2] . "\n";

    return $array[1];
  } 

  #print "Cached: $file, size fdcache: " . keys(%fdcache) . ", prev-position: " . ${$fdcache{$file}}[2] . 
  #	" chances: 1/" . (($#fdindex+1) - ${$fdcache{$file}}[2]) . "\n";

    # Entry was in cache, increase it position
    # (unless it already is the first one)
  if(${$fdcache{$file}}[2] > 0 && int(rand(($#fdindex+1)-${$fdcache{$file}}[2])) == 0) {
    #print "Switching: " . $file . " with " . ${$fdindex[(${$fdcache{$file}}[2])-1]}[0] . "\n";

      # next element = prev element
    $fdindex[${$fdcache{$file}}[2]]=$fdindex[(${$fdcache{$file}}[2])-1];
      # Increase prev element count 
    ${$fdindex[(${$fdcache{$file}}[2])]}[2]+=1;

      # prev element = current element
    $fdindex[${$fdcache{$file}}[2]-1]=\@{$fdcache{$file}};
      # decrease current element count 
    ${$fdcache{$file}}[2]=${$fdcache{$file}}[2]-1;
  }

  return ${$fdcache{$file}}[1];
}

my %map = (
	'Jan' => '01',
	'Feb' => '02',
	'Mar' => '03',
	'Apr' => '04',
	'May' => '05',
	'Jun' => '06',
	'Jul' => '07',
	'Aug' => '08',
	'Sep' => '09',
	'Oct' => '10',
	'Nov' => '11',
	'Dec' => '12',
);

while(<>) {
  s/^www\.//i;

  if(!/^([^ ]+) [^ ]+ [^ ]+ [^ ]+ \[([0-9][0-9])\/([A-Z][a-z]+)\/([0-9][0-9][0-9][0-9])/o) {
    syslog('warning', "skipping bogous line: $_");
    next;
  }

  if(!$map{$3}) {
    syslog('warning', "unknown month: '$3' - cannot map it back to number\n");
    next;
  }

  my ($file) = $4 . '/' . $map{$3} . '/' . $2 . '/' . $cfg_prefix . lc($1);

  if($1 !~ /^[a-zA-Z0-9_-]+[a-zA-Z0-9_.-]*$/o) {
    syslog('warning', "ignoring to write entry for host $1 - does not match regular expression\n");
    next;
  }

#  print {getfd($file)} (/[^ ]+ (.*)/)[0] . "\n" or 
  $fd=getfd($file);
  print $fd (/[^ ]+ (.*)/)[0] . "\n" or
    syslog('warning', "error while writing '$file' - $!\n");
#  print STDOUT $file . ' ' . (/[^ ]+ (.*)/)[0] . "\n" or die("Couldn't write on file: ");
}
