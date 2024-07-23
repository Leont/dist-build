package Dist::Build::XS;

use strict;
use warnings;

use parent 'ExtUtils::Builder::Planner::Extension';

use File::Basename qw/basename dirname/;
use File::Spec::Functions qw/catfile curdir/;
use Text::ParseWords 'shellwords';

sub get_flags {
	my ($raw) = @_;
	return $raw if not defined($raw) or ref($raw);
	return [ shellwords($raw) ]
}

sub add_methods {
	my ($self, $planner, %args) = @_;

	$planner->add_delegate('add_xs', sub {
		my ($planner, %args) = @_;

		my $pureperl_only = $args{pureperl_only} // $planner->pureperl_only;
		die "Can't build xs files under --pureperl-only\n" if $pureperl_only;

		my $module_name = $args{module_name} // do {
			(my $dist_name = $planner->dist_name) =~ s/-/::/g;
			$dist_name;
		};
		my $module_version = $args{module_version} // $planner->dist_version;

		$planner = $planner->new_scope;

		$planner->load_module('ExtUtils::Builder::ParseXS');
		$planner->load_module('ExtUtils::Builder::AutoDetect::C');

		my $xs_file = $args{file} // catfile('lib', split /::/, $module_name) . '.xs';
		my $xs_dir = dirname($xs_file);
		my $c_file = $planner->c_file_for_xs($xs_file, $xs_dir);

		$planner->parse_xs($xs_file, $c_file, %args);

		my $o_file = $planner->obj_file(basename($c_file, '.c'), $xs_dir);

		my %defines = (
			%{ $args{defines} || {} },
			VERSION    => qq/"$module_version"/,
			XS_VERSION => qq/"$module_version"/,
		);
		my @include_dirs = (curdir, dirname($xs_file), 'include', @{ $args{include_dirs} || [] });

		my $compiler_flags = get_flags($args{extra_compiler_flags});
		$planner->compile($c_file, $o_file,
			type         => 'loadable-object',
			profile      => '@Perl',
			defines      => \%defines,
			include_dirs => \@include_dirs,
			extra_args   => $compiler_flags,
		);

		my @objects = ($o_file, @{ $args{extra_objects} || [] });

		for my $source (@{ $args{extra_sources} }) {
			my $dirname = dirname($source);
			my $object = $planner->obj_file(basename($source, '.c'), $dirname);
			$planner->compile($source, $object,
				type         => 'loadable-object',
				profile      => '@Perl',
				defines      => $args{defines},
				include_dirs => \@include_dirs,
				extra_args   => $compiler_flags,
			);
			push @objects, $object;
		}

		my $lib_file = $planner->extension_filename($module_name);
		$planner->link(\@objects, $lib_file,
			type         => 'loadable-object',
			profile      => '@Perl',
			module_name  => $module_name,
			mkdir        => 1,
			extra_args   => get_flags($args{extra_linker_flags}),
			library_dirs => $args{library_dirs},
			libraries    => $args{libraries},
		);

		$planner->create_phony('dynamic', $lib_file);
	});
}

1;

# ABSTRACT: An XS implementation for Dist::Build

=head1 SYNOPSIS

 # planner/xs.pl

 load_module('Dist::Build::XS');
 add_xs(
   module_name   => 'Foo::Bar',
   extra_sources => [ glob 'src/*.c' ],
   libraries     => [ 'foo' ],
 );

=head1 DESCRIPTION

This module implements support for XS for Dist::Build.

=method add_xs

This method takes the following named arguments, all optional:

=over 4

=item * module_name

The name of the module to be compiled. This defaults to C<$dist_name =~ s/-/::/gr>.

=item * module_version

The version of the module, defaulting to the dist version.

=item * file

The name of the XS file. By default it's derived from the C<$module_name>, e.g. C<lib/Foo/Bar.xs> for C<Foo::Bar>.

=item * defines

This hash contains defines for the C files. E.g. C<< { DEBUG => 1 } >>.

=item * include_dirs

A list of directories to add to the include path. The root directory of the distribution, the directory the XS file is in and C<include/> are automatically in this list.

=item * extra_sources

A list of C files to compile with this module.

=item * extra_objects

A list of object files to link with the module.

=item * extra_compiler_flags

Additional flags to feed to the compiler. This can either be an array or a (shell-quoted) string.

=item * extra_sources

Extra C files to compile with this module.

=item * library_dirs

Extra libraries to find libraries in.

=item * libraries

Libraries to link to.

=item * extra_linker_flags

Additional flags to feed to the compiler. This can either be an array or a (shell-quoted) string.

=back
