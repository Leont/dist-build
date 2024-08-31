package Dist::Build::XS::Export;

use strict;
use warnings;

use parent 'ExtUtils::Builder::Planner::Extension';

use Carp 'croak';
use File::Find 'find';
use File::Spec::Functions qw/abs2rel catfile/;

sub copy_header {
	my ($planner, $module_dir, $filename, $target) = @_;

	my $output = catfile(qw/blib lib auto share module/, $module_dir, 'include', $target);
	$planner->copy_file(abs2rel($filename), $output);

	return $output;
}

sub add_methods {
	my ($self, $planner) = @_;

	$planner->add_delegate('export_headers', sub {
		my ($self, %args) = @_;
		my $module_name = $args{module} // $planner->main_module_name;
		(my $module_dir = $module_name) =~ s/::/-/g;
		croak 'No directory or file given to share' if not $args{dir} and not $args{file};

		my @outputs;
		find(sub {
			return unless -f;
			my $target = abs2rel($File::Find::name, $args{dir});
			push @outputs, copy_header($planner, $module_dir, $File::Find::name, $target);
		}, $args{dir}) if $args{dir};

		my @files = ref $args{file} ? @{ $args{file} } : defined $args{file} ? $args{file} : ();
		for my $file (@files) {
			push @outputs, copy_header($planner, $module_dir, $file, $file);
		}

		$planner->create_phony('code', @outputs);
	});
}

1;

# ABSTRACT: Dist::Build extension to export headers for other XS modules

=head1 SYNOPSIS

 load_module('Dist::Build::Export');
 export_headers(
     module => 'Foo::Bar',
     dir    => 'include',
 );

=head1 DESCRIPTION

This C<Dist::Build> extension will export headers for your module, so they can be used by other modules using C<Dist::Build::Import>.

=method export_headers

This copies the given header for the appropriate module to the approriate sharedir.

=over 4

=item * module

The name of the module to export. This defaults to the main module.

=item * dir

The directory to export (e.g. C<'include'>).

=item * file

A file (or a list of files) to export (e.g. C<'foo.h'>).

=back

At least one of C<dir> and C<file> must be defined. Note that this function can be called multiple times (e.g. for multiple modules).