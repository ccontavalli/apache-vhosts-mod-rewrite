#!/usr/bin/perl -w

# Copyright Carlo Contavalli - 2002-2003
#
# Thu May 16 16:52:35 CEST 2002 -- Carlo
# 	Handles url rewriting for virtual domains

use strict;
use Sys::Syslog;
use POSIX;


my ($cfg_uid, $cfg_gid) = (65534, 65534);
my ($cfg_debug, $cfg_dir) = (0, '/opt/http');

  # Warning: changing this to a different value will
  #   break the pigeonair.net site.. there is a bug
  #   in mod-xslt, for apache-1.3 sub requests, where
  #   mod-rewrite does not handle them correctly and looks
  #   to the client headers to decide what to  do....
  #   instead of using the already parsed data
my ($cfg_default)=("www.pigeonair.net");


  # Open log file ...
openlog('apache-rewriter', 'pid', 'daemon');

  # And change userid and gid ...
setgid($cfg_gid) or syslog('warning', "setgid to $cfg_gid failed - $!\n");
setuid($cfg_uid) or syslog('warning', "setuid to $cfg_uid failed - $!\n");
chdir($cfg_dir) or syslog('warning', "chdir to $cfg_dir failed - $!\n");

  # Flush output immediately, do not cache it, otherwise apache will hang...
$|=1;

  # Loop over every input line...
while(<>) {
  chomp();

    # Split server addr and hostname
  if(!/^([^ ]*) ([^ ]*) ([^ ]*)$/o) {
    syslog('warning', "invalid line received - $_\n");
    next;
  }

    # Declare a couple useful variables
  my ($client, $server_addr, $host) =  ($1, $2, $3);

    # Log server_addr and host if debugging enabled
  syslog('warning', "$client: server_addr: $server_addr, host: $host\n") if($cfg_debug >= 2);

    # If hostname looks suspicious... reject it :)
  if(!$host || $host !~ /^[a-zA-Z][a-zA-Z0-9_.-]+\.[a-zA-Z]+$/o || $host =~ /\.\./o) {
    syslog('warning', "$client: rejecting invalid host - " . ($host ? $host : '(null)') . " falling back to $cfg_default\n");
    $host=$cfg_default;
  }

    # Directly handle IP addresses
  if($host =~ /^((2((5[0-5]{1})|([0-4]{1}[0-9]{1})))|([1]?[0-9]?[0-9]{1}))\.
  	        ((2((5[0-5]{1})|([0-4]{1}[0-9]{1})))|([1]?[0-9]?[0-9]{1}))\.
		((2((5[0-5]{1})|([0-4]{1}[0-9]{1})))|([1]?[0-9]?[0-9]{1}))\.
		((2((5[0-5]{1})|([0-4]{1}[0-9]{1})))|([1]?[0-9]?[0-9]{1}))/ox ) { 
    print $host . "\n";
    next;
  };

    # Remove the www from the beginning of the host, if there is one,
    # and check if there are subdomains specified... 
  $host =~ s/^www[0-9]*\.//io;
  if($host !~ /(.*)\.([^.]+\.[^.]+)/o) {
    print $host . "\n";
    next;
  }

    # Now, reverse the order of the subdomains and append them...
  $host = $2;
  $host .= ($_ ? '/sub/' . $_ : '') foreach (reverse((split(/\./, $1))));
  print $host . "\n";
}
