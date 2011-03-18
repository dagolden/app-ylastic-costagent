use strict;
use warnings;
use Test::More 0.88;
use File::Spec::Functions qw/catfile/;

use App::Ylastic::CostsAgent;

my @cases = (
  {
    label => 'Valid config', 
    file => 'config.ini',
  },
  {
    label => 'Valid with dashed AWS account numbers', 
    file => 'config-dashes.ini',
  },
);

for my $c ( @cases ) {
  my $file = catfile( 't', 'data', $c->{file} );
  my $obj = new_ok( 'App::Ylastic::CostsAgent', [config_file => $file], $c->{label} );
}

done_testing;

