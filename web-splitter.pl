#!/usr/bin/perl -w


# Copyright (C) Carlo Contavalli - 2002-2013
# This script is free software, please refer to the LICENSE file for
# terms and conditions.
#
# Should be used with something like:
#   LogFormat "%V %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" vcombined
#   CustomLog "/var/log/apache2/access.log" vcombined

use strict;
use Sys::Syslog;
use POSIX;


  # cfg_logdir: directory where logs are kept
  # cfg_maxfd: maximum number of file descriptor to keep open at a given time
  # cfg_prefix: prefix to use for created log files
my ($cfg_logdir, $cfg_maxfd, $cfg_prefix) = ('/opt/log', 32, 'web-');
  # cfg_uid: userid to change to, while dropping root privileges
  # cfg_gid: group to change to, while dropping root privileges
my ($cfg_uid, $cfg_gid, $cfg_dir) = (105, 4, '/opt/log');

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
