use 5.010;
use strict;
use warnings;
use utf8;

package App::Ylastic::CostsAgent;
# ABSTRACT: Perl port of the Ylastic Costs Agent for Amazon Web Services

# Dependencies
use autodie 2.00;
use Archive::Zip qw( :CONSTANTS );
use Carp qw/croak/;
use Config::Tiny;
use File::Spec::Functions qw/catfile/;
use File::Temp ();
use Log::Dispatchouli 2;
use IO::Socket::SSL; # force dependency to trigger SSL support
use Time::Piece;
use Time::Piece::Month;
use WWW::Mechanize;

use Object::Tiny qw(
  accounts
  config_file
  dir
  logger
  mech
  upload
  ylastic_id
);

my %URL = (
  ylastic_service_list  => "http://ylastic.com/cost_services.list",
  ylastic_upload_form   => "http://ylastic.com/usage_upload.html",
  aws_usage_report_form => "https://aws-portal.amazon.com/gp/aws/developer/account/index.html?ie=UTF8&action=usage-report",
);

sub new {
  my $class = shift;
  my $self = $class->SUPER::new( @_ );

  croak __PACKAGE__ . " requires a valid 'config_file' argument\n"
    unless $self->config_file && -r $self->config_file;

  $self->_parse_config;
  $self->{dir} ||= File::Temp::tempdir();
  $self->{logger} ||= Log::Dispatchouli({ident => __PACKAGE__, to_self => 1});

  return $self;
}

sub run {
  my $self = shift;

  for my $account ( @{ $self->accounts } ) {
    my $zipfile = $self->_download_usage( $account );
    $self->_upload_usage( $account, $zipfile )
      if $self->upload;
  }

  return 0;
}

#--------------------------------------------------------------------------#
# private
#--------------------------------------------------------------------------#

sub _do_aws_login {
  my ($self, $id,$user, $pass) = @_;
  $self->mech->get($URL{aws_usage_report_form});
  $self->mech->submit_form(
    form_name => 'signIn',
    fields => {
      email => $user,
      password => $pass,
    }
  );
  $self->logger->log_debug(["Logged into AWS for account %s as %s", $id, $user]);
}

sub _download_usage {
  my ($self, $account) = @_;
  my ($id, $user, $pass) = @$account;
  $self->_initialize_mech;
  $self->_do_aws_login( $id, $user, $pass );

  my $zip = Archive::Zip->new;

  for my $service ( @{ $self->_service_list } ) {
#    print "Getting $service for $id\n";
    eval {
      my $usage = $self->_get_service_usage($id, $service);
      if ( length $usage > 70 ) {
        my $filename = sprintf("%s_%s_%s\.csv", $self->ylastic_id, $id, $service);
        my $member = $zip->addString( $usage => $filename );
        $member->desiredCompressionLevel( 9 );
      }
    };
    warn "Warning: $@\n" if $@;
  }

  # write zipfile
  my $zipname = sprintf("%s_%s_aws_usage.zip", $self->ylastic_id, $id);
  my $zippath = catfile($self->dir, $zipname);
  $zip->writeToFileNamed( $zippath );

  $self->logger->log(["Downloaded AWS usage reports for account %s", $id]);

  return $zippath;
}

sub _end_date {
  state $end_date =  Time::Piece::Month->new(
    Time::Piece->new()
  )->next_month->start;
  return $end_date;
}

sub _get_service_usage {
  my ($self, $id, $service) = @_;

  $self->mech->get($URL{aws_usage_report_form});

  $self->mech->submit_form(
    form_name => 'usageReportForm',
    fields => {
      productCode => $service,
    }
  );

  my $action = 'download-usage-report-csv';
  my $form = $self->mech->form_name('usageReportForm');
  return unless $form && $form->find_input($action);

  $self->mech->submit_form(
    form_name => 'usageReportForm',
    button => $action,
    fields => {
      productCode => $service,
      timePeriod  => 'aws-portal-custom-date-range',
      startYear   => $self->_start_date->year,
      startMonth  => $self->_start_date->mon,
      startDay    => $self->_start_date->mday,
      endYear     => $self->_end_date->year,
      endMonth    => $self->_end_date->mon,
      endDay      => $self->_end_date->mday,
      periodType  => 'days',
    }
  );

  $self->logger->log_debug("Got $service data for account $id");
  return $self->mech->content;
}

sub _initialize_mech {
  my $self = shift;
  $self->{mech} = WWW::Mechanize->new(
    quiet => 0,
    on_error => \&Carp::croak
  );
  $self->mech->ssl_opts( verify_hostname => 0 );
  $self->mech->agent_alias("Linux Mozilla");
  $self->mech->default_header('Accept' => 'text/html, application/xml, */*');
}

sub _parse_config {
  my $self = shift;
  my $config = Config::Tiny->read( $self->config_file )
    or croak Config::Tiny->errstr;

  $self->{ylastic_id} = $config->{_}{ylastic_id}
    or croak $self->config_file . " does not define 'ylastic_id'";

  my @accounts;
  for my $k ( keys %$config ) {
    next if $k eq "_"; # ski config root
    unless ( $k =~ /^(?:\d{12}|\d{4}-\d{4}-\d{4})$/ ) {
      warn "Invalid AWS ID '$k'.  Skipping it.";
      next;
    }
    my ($user, $pass) = map { $config->{$k}{$_} } qw/user pass/;
    unless ( length $user && length $pass ) {
      warn "Invalid user/password for $k. Skipping it.";
      next;
    }
    push @accounts, [$k, $user, $pass];
  }
  $self->{accounts} = \@accounts;
  $self->logger->log_debug(["Parsed config_file %s", $self->config_file]);
  return;
}

sub _service_list {
  my $self = shift;
  return $self->{services} if $self->{services};
  my $list = $self->mech->get($URL{ylastic_service_list})->decoded_content;
  chomp $list;
  return $self->{services} = [split q{,}, $list];
}

sub _start_date {
  state $start_date = Time::Piece::Month->new("2010-01-01")->start;
  return $start_date;
}

sub _upload_usage {
  my ($self, $account, $zipfile) = @_;
  $self->_initialize_mech;
  $self->mech->get($URL{ylastic_upload_form});
  $self->mech->submit_form(
    form_name => 'upload',
    fields => {
      file1 => $zipfile,
    }
  );
  $self->logger->log(["Uploaded usage reports to Ylastic for account %s",$account->[0]]);
  return;
}

1;

__END__

=for Pod::Coverage method_names_here

=begin wikidoc

= SYNOPSIS

  use App::Ylastic::CostsAgent;

= DESCRIPTION

This module might be cool, but you'd never know it from the lack
of documentation.

= USAGE

Good luck!

== Automation with cron

  # download raw usage data every 12 hours
  # PERL5LIB=... (if needed)
  PATH=/usr/local/bin:/usr/bin:/bin
  0 */12 * * * ylastic-costagent -C /etc/ylastic.config > /tmp/ylastic_aws_costs_agent.log 2>&1

= SEE ALSO

Maybe other modules do related things.

=end wikidoc

=cut

