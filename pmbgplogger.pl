#!/usr/bin/perl
# pmbgplogger - receiving BGP updates from RabbitMQ server and save to file
# v.01
# TODO: mozna nake hlasky od rabbit serveru do logu deamona ?
use strict;
use warnings;
use Getopt::Long;
use Data::Dump qw(pp);
use Log::Log4perl qw(:levels);
use Net::AMQP::RabbitMQ;
use IO::File;

# Daemon config
my $daemon_name = "pmbgplogger";
my $work_dir = "/root/devel/rabbitmq/";
my $pid_file = "$work_dir/$daemon_name.pid";
my $bgp_updates_log = "$work_dir/bgpupdates.log";
my $daemon_log = "$work_dir/$daemon_name.log";

# RabbitMQ config
my $channel       = 1;
my $exchange      = 'pmacct';      # This exchange must exist already
my $routing_key   = 'pmacct';
my $rabbit_server = 'localhost';
my $rabbit_user   = 'guest';
my $rabbit_passwd = 'guest';

my $isServiceOn = 0;
my $logger      = undef;
my $fh          = undef;           # Filehandle for datafile

$SIG{INT}  = \&signal_handler;
$SIG{TERM} = \&signal_handler;
$SIG{HUP}  = \&signal_hup;

sub signal_handler { # Clean up Handles and connections here {{{
    $logger->info("$daemon_name service is shutting down ");
    $isServiceOn = 0;
} # }}}

sub signal_hup {    # Clean up Handles and connections here {{{
    $logger->info("$daemon_name HUP signal received ");
    undef $fh;
    $fh = open_data_log();
}    # }}}

use Proc::Daemon;
my $daemon = Proc::Daemon->new(
    work_dir     => $work_dir,
    #child_STDOUT => "$work_dir/$daemon_name.stdout", 
    #child_STDERR => "+>>$work_dir/$daemon_name.stderr",
    #pid_file     => $pid_file,
);

my $option = new Getopt::Long::Parser;
$option->configure("bundling");
$option->getoptions( \%{ $option->{'switch'} },
    'daemon|d', 'help|h', 'verbose|v', );

my $switch = $option->{'switch'};
help() if $switch->{'help'};

if ( not defined $switch->{daemon} ) {
    help();
    exit;
}

# Fork and detach
my $pid = $daemon->Init();
$isServiceOn = 1;

my $conf = qq(
        log4perl.logger                    = INFO, FileApp
        log4perl.appender.FileApp          = Log::Log4perl::Appender::File
        log4perl.appender.FileApp.filename = $daemon_log
        log4perl.appender.FileApp.layout   = PatternLayout
        log4perl.appender.FileApp.layout.ConversionPattern = %d> %m%n
    );

Log::Log4perl->init( \$conf );    # Inicializace logovani
$logger = Log::Log4perl->get_logger();

if ($pid) {
    $logger->info("$daemon_name started...");
    exit 0;
}

my $mq = Net::AMQP::RabbitMQ->new();
$mq->connect( $rabbit_server, { user => $rabbit_user, password => $rabbit_passwd } );
$mq->channel_open($channel);

my $queuename = $mq->queue_declare( $channel, "" );
$mq->queue_bind( $channel, $queuename, $exchange, $routing_key );
$mq->consume( $channel, $queuename );

$fh = open_data_log();

$mq->consume( $channel, $queuename, {} );
$mq->purge( $channel, $queuename );


while ( my $message = $mq->recv(0) and $isServiceOn ) {
    my $body = $message->{body};
    print $fh "$body\n";
}



$logger->info("$daemon_name is shutted down");
$mq->disconnect();
close $fh;

exit 0;

sub open_data_log {    # {{{

    my $handle =
      IO::File->new( $bgp_updates_log,
        O_WRONLY | O_CREAT | O_APPEND | O_NONBLOCK );
    return $handle;
}    # }}}

sub help {    # ### {{{
    print <<EOT;

Usage: $0  [OPTIONS]
      Usage: $0  -d
           
     -d, --daemon     run as daemon
     -h, --help       print this help message
           
EOT
    exit;
}    # }}}

__END__

 The Proc::Daemon::Init function does the following:

    1 Forks a child and exits the parent process.
    2 Becomes a session leader (which detaches the program from the controlling terminal).
    3 Forks another child process and exits first child. This prevents the potential of acquiring a controlling terminal.
    4 Changes the current working directory to "/".
    5 Clears the file creation mask.
    6 Closes all open file descriptors. 


