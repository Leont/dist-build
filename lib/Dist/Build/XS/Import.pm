package Dist::Build::XS::Import;

use strict;
use warnings;

use parent 'ExtUtils::Builder::Planner::Extension';

use File::ShareDir;
use Parse::CPAN::Meta;

my $json_backend = Parse::CPAN::Meta->json_backend;
my $json = $json_backend->new->canonical->pretty->utf8;

sub add_methods {
	my ($self, $planner, %args) = @_;

	my $add_xs = $self->can('add_xs') or die "XS must be loaded before imports can be done";

	$planner->add_delegate('add_xs', sub {
		my ($planner, %args) = @_;

		my @modules = ref $args{import} ? @{ delete $args{import} } : delete $args{import};
		for my $module (@modules) {
			my $module_dir = module_dir($module);
			my $config = catfile($module_dir, 'compile.json');
			my $include = catdir($module_dir, 'include');
			die "No such import $module" if not -d $include and not -e $config;

			if (-e $config) {
				my $filename = shift;
				open my $fh, '<:raw', $filename;
				my $content = do { local $/; <$fh> };
				my $payload = $json->decode($content);

				for my $key (qw/include_dirs library_dirs libraries extra_compiler_flags extra_linker_flags/) {
					unshift @{ $args{$key} }, @{ $payload->{$key} };
				}

				for my $key (%{ $payload->{defines} }) {
					$args{defines}{$key} //= $payload->{defines}{$key};
				}
			}

			if (-d $include) {
				unshift @{ $args{include_dirs} }, $include;
			}
		}

		$planner->$add_xs(%args);
	});
}

1;
