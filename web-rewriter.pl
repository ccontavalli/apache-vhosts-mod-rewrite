#!/usr/bin/perl -w

# Copyright (C) Carlo Contavalli - 2002-2013
# This script is free software, please refer to the LICENSE file for
# terms and conditions.

=head1 NAME

web-rewriter.pl - massive virtual hosting with apache mod-rewrite.

=head1 DESCRIPTION

web-rewriter allows to add and remove virtual hosts without changing a single line of
apache configuration, and without restarting or reloading apache. It works with any
version of apache from 1.3, and is similar in purpose to mod_vhost_alias.

Once configured, any request received by apache will be passed to web-rewriter
which will take care of remapping it to a physical directory on your server for a
specific virtual host.


=head2 Simple configuration

You configure web-rewriter by:

=over 2

=item 1. Editing the script. You need to specify a root directory in cfg_dir, for example '/opt/sites'. You also need to specify a default web site in cfg_default, for example 'mysite.com'. Optionally, you can also specify cfg_uid and cfg_gid.

=item 2. Change the configuration of apache as described below.

=back

=head2 Sample behavior

What happens next is more easily described by example than by explaining it.
If your web server receives a request for...

=over 2

=item www.testsite.com/test.html

web-rewriter will direct apache to load /opt/sites/testiste.com/http/test.html.
Same if the request was for testsite.com (instead of www.test...)

=item 1.2.3.4/test.html

web-rewriter will direct apache to load /opt/sites/1.2.3.4/http/test.html. The
usual way to handle IP addresses is to create a symlink to the site you'd like
displayed when users access the naked IP address.

=item test.mysite.com/fuffa.html

web-rewriter will direct apache to load
/opt/sites/mysite.com/sub/test/http/fuffa.html.

=item my.own.site.mysite.com/fuffa.html

As above, directing apache to load
/opt/sites/mysite.com/sub/site/sub/own/sub/my/http/fuffa.html.

=back

Some tricks can be played by using symlinks, and by providing 404 handlers.

=head2 Notes

This allows for:

=over 2

=item 1. Owners of domains to freely create and manage subdomains.

=item 2. Adding a virtual host just means creating a new directory in /opt/sites.

=back

Note that these directories can be easily created by using a database
and by configuring PAM to use LDAP or MySQL authentication and to create 
the directory the first time the user tries to upload the web pages via ssh / scp / sftp.

Note also that web-rewriter tries to be as conservative as possible by
rejecting hosts that look invalid (example: containing ../ or similar) and returning a default
whenever a suspicious configuration is received.


=head1 CONFIGURATION

=over 2

=item 0. Edit web-rewriter.pl. In particular:

Change I<cfg_dir> to point to the directory where you plan to keep all virtual hosts. For example, /opt/sites.

Change I<cfg_default> to have the name of the site you want loaded in case of errors.

Change I<cfg_uid> and I<cfg_gid> to point to the uid and gid used by nobody. This script really needs no privileges on your system.

=item 1. Enable mod-rewrite in apache

On Debian based systems, run:

    a2enmod rewrite

On other systems, add something like:

LoadModule rewrite_module /usr/lib/apache2/modules/mod_rewrite.so

to your httpd.conf, and restart apache with:

  apachectl restart

=item 2. Configure web-rewriter in apache.

Add the following parameters in the httpd.conf file:

  RewriteEngine On
  RewriteMap web-rewriter prg:/opt/scripts/web-rewriter.pl

  # This rewrite rule has to be last, see below.
  RewriteRule ^/(.*)$ /${web-rewriter:%{REMOTE_ADDR}\ %{SERVER_ADDR}\ %{HTTP_HOST}}/http/$1 [E=TRANS_HOST:%1]

Note that /opt/scripts/ has to be changed with the path where you
installed the web-rewriter script.

Let's also say you provide an admin interface for each virtual host,
and this admin interface is reachable by going to:

  www.any-virtual-host-1.com/admin/
  www.any-virtual-host-2.com/admin/
  www.....com/admin/

You can easily configure rewrite exceptions by adding a line like this
one before the RewriteRule with web-rewriter:

  RewriteCond %{REQUEST_URI} !^/admin/.*$

Let's also say you allow virtual hosts to have cgi-bin scripts outside
the web root, you can add a rule like:

  RewriteRule (.*)/http/cgi-bin/(.*)$ $1/cgi-bin/$2

=back

=head1 HIERARCHY

A typical configuration has:

=over 2

=item /opt/sites/mysite.com/http/

Static / dynamic web pages, html files.

=item /opt/sites/mysite.com/cgi-bin/

Scripts, cgi-bin.

=item /opt/sites/mysite.com/sub/test/

Same hierarchy as described above, sub/test/http/, sub/test/cgi-bin/, ... for the 'test' subdomain.

=back

If you use php or have other dynamic content, we also suggest to provide:

=over 2

=item /opt/sites/mysite.com/lib

Libraries, generally not containing any html or code that should be directly exposed to the user.
Files here are only imported / included by other scripts.

=item /opt/sites/mysite.com/data

This is the only directory where apache can write in every virtual host. This directory is
also not accessible directly by end users. There is generally no good reason to allow arbitrary
uploads that are exposed directly to the user, and it is good practice to enforce the policy
by using unix privileges.

=head1 DEBUGGING

An easy way to debug mod-rewrite is to enable debugging, something
like this will help:

  RewriteLog /var/log/apache2/rewrite.log
  RewriteLogLevel 3

=cut

use strict;
use Sys::Syslog;
use POSIX;

my ($cfg_uid, $cfg_gid) = (65534, 65534);
my ($cfg_debug, $cfg_dir) = (0, '/opt/http');
my ($cfg_default) = ("www.pigeonair.net");

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
