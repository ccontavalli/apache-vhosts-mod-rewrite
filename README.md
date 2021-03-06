Massive virtual hosting with apache mod\_rewrite
===============================================

The scripts in this directory allow to easily configure
massive virtual hosting in any version of apache, from
1.3 to 2.4. They were written some time in 2002, but still
work well with recent version of apache.

They are similar in approach to mod\_vhost\_alias, but
allow a more flexible setup that does not require any
apache reload or restart to add virtual hosts.

All you have to do is create a directory, which can easily
be automated using PAM modules when the user first accesses
your web server via FTP or SSH.

In this repository, you can find two scripts:

- web-rewrite.pl - implementing the necessary machinery for
  apache to magically handle virtual hosts.

- web-splitter.pl - to split log files per virtual host.

The two scripts are orthogonal, you are free to use one but
not the other, or both at the same time.

You can find out how to use and configure each by reading:

  - [README.web-rewriter](README.web-rewriter)
  - [README.web-splitter](README.web-splitter)

Setting them up should not require more than 15 minutes.

CREDITS
=======

Most of those scripts were written and tweaked a long time
ago (around 2002 - 2004) by:

- Carlo Contavalli &lt;ccontavalli at gmail.com&gt;
- Andrea Ciancone &lt;aciancone at gmail.com&gt;

