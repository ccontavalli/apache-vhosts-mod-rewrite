#!/usr/bin/perl -w

use strict;

my $line_pattern = q{(.*) \- \- \[(.*)\] \"(.*)\" ([0-9-]*) ([0-9-]*) \"(.*)\" \"(.*)\"};
my $request_pattern = q{^GET (.*) HTTP/.*$};

my %referrers;
my %urls;

my $file = "";
while (<>) {
  if ($ARGV ne $file) {
    # print "scanning: $ARGV - $.\n";
    $file = $ARGV;
  }

  my @match = m/$line_pattern/o;
  if (!@match) {
    print "$ARGV: $. - $_: does not match pattern, skipping;\n";
    last;
  }

  my ($client, $time, $request, $code, $size, $referrer, $browser) = @match;

  my @request = $request =~ m/$request_pattern/o;
  if (!@request) { next; }

  my $url = $request[0];
  next if ($url =~ /\.css$/ or $url =~ /\.js$/ or $url =~ /\.ico$/ or $url =~ /\.png$/ or $url =~ /\.jpeg$/ or $url =~ /\.jpg$/);

  $urls{$url}++;
  $referrers{$referrer}++;
}

sub PrintHash(\%) {
  my $hash = shift;

  my @keys = sort { $hash->{$b} <=> $hash->{$a} } keys(%$hash);
  foreach my $key (@keys) {
    print "$key: $hash->{$key}\n";
  }
}

print "====== TOP REFERRERS =====\n";
PrintHash(%referrers);
print "\n";

print "====== TOP REQUESTS =====\n";
PrintHash(%urls);
print "\n";

print "$.\n";
