package Dist::Build::XS::Conf;

use strict;
use warnings;

use parent 'ExtUtils::Builder::Planner::Extension';

sub add_methods {
	my ($self, $planner, %args) = @_;

	my $add_xs = $planner->can('add_xs') or die "XS must be loaded before imports can be done";

	$planner->load_extension('ExtUtils::Builder::Conf');

	$planner->add_delegate('add_xs', sub {
		my ($planner, %args) = @_;

		for my $key (qw/include_dirs library_dirs libraries extra_compiler_flags extra_linker_flags/) {
			push @{ $args{$key} }, $planner->$key;
		}

		my %defines = $planner->defines;
		for my $key (keys %defines) {
			$args{defines}{$key} //= $defines{$key};
		}

		$planner->$add_xs(%args);
	});
}

# ABSTRACT: Configure-time utilities for Dist::Build for using C headers, libraries, or OS features

=head1 SYNOPSIS

 load_extension("Dist::Build::XS");
 
 find_libs_for(source => <<'EOF', libs => [ ['socket'], ['moonlaser'] ]);
 #include <stdio.h>
 #include <sys/socket.h>
 int main(int argc, char *argv[]) {
   printf("PF_MOONLASER is %d\n", PF_MOONLASER);
   return 0;
 }
 EOF

 add_xs(module_name => 'Socket::MoonLaser');

=head2 DESCRIPTION

This module integrates L<ExtUtils::Builder::Conf|ExtUtils::Builder::Conf> into L<Dist::Build::XS|Dist::Build::XS>. Any arguments found with any of the C<find_*> or C<try_find_*> functions will be automatically added to the build when calling C<add_xs>.
