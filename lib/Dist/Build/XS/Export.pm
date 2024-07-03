package Dist::Build::XS::Export;

use strict;
use warnings;

use parent 'ExtUtils::Builder::Planner::Extension';

use ExtUtils::Builder::Node;

use File::Find 'find';
use File::Spec::Functions qw/abs2rel catfile/;
use Parse::CPAN::Meta;

my $json_backend = Parse::CPAN::Meta->json_backend;
my $json = $json_backend->new->canonical->pretty->utf8;

my @allowed_flags = qw/include_dirs defines library_dirs libraries extra_compiler_flags extra_linker_flags/;
my %allowed_flag = map { $_ => 1 } @allowed_flags;

sub copy_header {
	my ($planner, $module_dir, $filename, $base) = @_;

	my $output = catfile(qw/blib lib auto share module/, $module_dir, 'include', abs2rel($filename, $base));
	$planner->copy_file(abs2rel($filename), $output);

	return $output;
}

sub add_methods {
	my ($self, $planner) = @_;

	$self->add_delegate($planner, 'export_headers', sub {
		my (%args) = @_;
		my $module_name = $args{module_name} // $planner->dist_name;
		(my $module_dir = $module_name) =~ s/::/-/g;

		my @outputs;
		find(sub {
			return unless -f;
			push @outputs, copy_header($planner, $module_name, $File::Find::name, $args{dir});
		}, $args{dir}) if $args{dir};

		push @outputs, copy_header($planner, $module_name, $args{file}, '.') if $args{file};

		return ExtUtils::Builder::Node->new(
			target       => 'code',
			dependencies => \@outputs,
			phony        => 1,
		);
	});

	$self->add_delegate($planner, 'export_flags', sub {
		my (%args) = @_;
		my %flags;
		$flags{$_} = $args{$_} for grep { $allowed_flag{$_} } keys %args;

		my $module_name = $args{module_name} // $planner->module_name;
		(my $module_dir = $module_name) =~ s/::/-/g;
		my $filename = catfile(qw/blib lib auto share module/, $module_dir, 'compile.json');

		$planner->dump_json($filename, \%flags);

		push @nodes, ExtUtils::Builder::Node->new(
			target       => 'code',
			dependencies => [ $filename ],
			phony        => 1,
		);

		return @nodes;
	});
}

1;
