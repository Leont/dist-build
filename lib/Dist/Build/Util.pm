package Dist::Build::Util;

use strict;
use warnings;

use Exporter 5.57 'import';
our @EXPORT_OK = qw/dist_dir module_dir/;
our %EXPORT_TAGS = (sharedir => \@EXPORT_OK);

use Carp 'croak';
use File::Spec::Functions 'catdir';

sub _search_inc_path {
	my $path = catdir(@_);

	for my $candidate (@INC) {
		next if ref $candidate;
		my $dir = catdir($candidate, $path);
		return $dir if -d $dir;
	}

	return undef;
}

sub dist_dir {
	my $dist = shift;

	croak 'No dist given' if not length $dist;
	my $dir = _search_inc_path('auto', 'share', 'dist', $dist);

	croak("Failed to find share dir for dist '$dist'") if not defined $dir;
	return $dir;
}

sub module_dir {
	my $module = shift;

	croak 'No module given' if not length $module;
	(my $module_dir = $module) =~ s/::/-/g;
	my $dir = _search_inc_path('auto', 'share', 'module', $module_dir);

	croak("Failed to find share dir for module '$module'") if not defined $dir;
	return $dir;
}

1;

# ABSTRACT: Utility functions for Dist::Build

=head1 SYNOPSIS

 use Dist::Build::Util 'module_dir';
 say module_dir('Dist::Build');

=head1 DESCRIPTION

This module contains a collection of utility functions for L<Dist::Build>. Currently it contains only sharedir functions, but in the future more functions may be added.

=func dist_dir

  # Get a distribution's shared files directory
  my $dir = dist_dir('My-Distribution');

The C<dist_dir> function takes a single parameter of the name of an
installed (CPAN or otherwise) distribution, and locates the shared
data directory created at install time for it.

Returns the directory path as a string, or dies if it cannot be
located or is not readable.

This is part of the C<:sharedir> export group.

=func module_dir

  # Get a module's shared files directory
  my $dir = module_dir('My::Module');

The C<module_dir> function takes a single parameter of the name of an
installed (CPAN or otherwise) module, and locates the shared data
directory created at install time for it.

Returns the directory path as a string, or dies if it cannot be
located or is not readable.

This is part of the C<:sharedir> export group.
