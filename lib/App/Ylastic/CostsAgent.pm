use 5.008001;
use strict;
use warnings;
use utf8;

package App::Ylastic::CostsAgent;
# ABSTRACT: Perl port of the Ylastic Costs Agent for Amazon Web Services

# Dependencies
use autodie 2.00;
use Carp qw/croak/;
use Object::Tiny qw/config_file mech ylastic_id accounts/;
use IO::Socket::SSL; # force dependency to trigger SSL support
use WWW::Mechanize;
use Config::Tiny;

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

  my $config = Config::Tiny->read( $self->config_file )
    or croak Config::Tiny->errstr;

  $self->{ylastic_id} = $config->{_}{ylastic_id}
    or croak $self->config_file . " does not define 'ylastic_id'";

  my @accounts;
  for my $k ( keys %$config ) {
    next unless $k =~ /^(?:\d{12}|\d{4}-\d{4}-\d{4})$/;
    my ($user, $pass) = map { $config->{$k}{$_} } qw/user pass/;
    unless ( length $user && length $pass ) {
      warn "Invalid user/password for $k. Skipping it.";
      next;
    }
    push @accounts, [$k, $user, $pass];
  }
  $self->{accounts} = \@accounts;
  
  $self->{mech} = WWW::Mechanize->new();
  $self->mech->agent_alias("Linux Mozilla");

  return $self;
}

sub run {
  my $self = shift;

  for my $account ( @{ $self->accounts } ) {
    my $zipfile = $self->download_usage( $account );
    $self->upload_usage( $zipfile );
  }

  return 0;
}

sub service_list {
  my $self = shift;
  my $list = $self->mech->get($URL{ylastic_service_list})->decoded_content;
  chomp $list;
  return split q{,}, $list;
}

sub download_usage {
  my ($self, $account) = @_;

}

sub upload_usage {
  my ($self, $zipfile) = @_;

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

