package Dist::Build;

use strict;
use warnings;

use Exporter 5.57 'import';
our @EXPORT = qw/Build Build_PL/;

use Carp qw/croak/;
use CPAN::Meta;
use ExtUtils::Config;
use ExtUtils::Helpers 0.007 qw/split_like_shell detildefy make_executable/;
use ExtUtils::InstallPaths;
use File::Find ();
use File::Spec::Functions qw/catfile catdir abs2rel /;
use Getopt::Long 2.36 qw/GetOptionsFromArray/;
use Parse::CPAN::Meta;

use ExtUtils::Builder::Planner 0.008;
use ExtUtils::Builder::Util 'get_perl';
use Dist::Build::Serializer;

my $json_backend = Parse::CPAN::Meta->json_backend;
my $json = $json_backend->new->canonical->pretty->utf8;
my $serializer = 'Dist::Build::Serializer';

sub load_json {
	my $filename = shift;
	open my $fh, '<:raw', $filename;
	my $content = do { local $/; <$fh> };
	return $json->decode($content);
}

sub save_json {
	my ($filename, $content) = @_;
	open my $fh, '>:raw', $filename;
	print $fh $json->encode($content);
	return;
}

my @options = qw/install_base=s install_path=s% installdirs=s destdir=s prefix=s config=s% uninst:1 verbose:1 dry_run:1 pureperl_only|pureperl-only:1 create_packlist=i jobs=i allow_mb_mismatch:1/;

sub get_config {
	my ($meta_name, @arguments) = @_;
	my %options;
	GetOptionsFromArray($_, \%options, @options) or die "Could not parse arguments" for @arguments;

	$options{$_} = detildefy($options{$_}) for grep { exists $options{$_} } qw/install_base destdir prefix/;
	if ($options{install_path}) {
		$_ = detildefy($_) for values %{ $options{install_path} };
	}
	$options{config} = ExtUtils::Config->new($options{config});
	$options{install_paths} = ExtUtils::InstallPaths->new(%options, dist_name => $meta_name);

	return %options;
}

sub Build_PL {
	my ($args, $env) = @_;

	my $meta = CPAN::Meta->load_file('META.json', { lazy_validation => 0 });

	my @env = defined $env->{PERL_MB_OPT} ? split_like_shell($env->{PERL_MB_OPT}) : ();
	my %options = get_config($meta->name, [ @{$args} ], [ @env ]);

	my $planner = ExtUtils::Builder::Planner->new;
	$planner->load_module('Dist::Build::Core');

	my @blibs = map { catfile('blib', $_) } qw/lib arch bindoc libdoc script bin/;
	$planner->mkdir($_) for @blibs;
	$planner->create_phony('config', @blibs);
	$planner->create_phony('code', 'config');
	$planner->create_phony('manify', 'config');
	$planner->create_phony('dynamic');
	$planner->create_phony('pure_all', 'code', 'manify', 'dynamic');
	$planner->create_phony('build', 'pure_all');

	$planner->tap_harness('test', dependencies => [ 'pure_all' ], test_dir => 't');
	$planner->install('install', dependencies => [ 'pure_all' ], install_map => $options{install_paths}->install_map);

	$planner->add_delegate('meta', sub { $meta });
	$planner->add_delegate('distribution', sub { $meta->name });
	$planner->add_delegate('distribution_version', sub { $meta->version });
	(my $main_module = $meta->name) =~ s/-/::/g;
	$planner->add_delegate('main_module', sub { $main_module });
	$planner->add_delegate('release_status', sub { $meta->release_status });
	$planner->add_delegate('perl_path', sub { get_perl(config => $options{config}, %options) });

	for my $variable (qw/config install_paths verbose uninst jobs pureperl_only/) {
		$planner->add_delegate($variable, sub { $options{$variable} });
	}

	$planner->add_delegate('new_planner', sub {
		my $inner = ExtUtils::Builder::Planner->new;
		$inner->add_delegate('config', sub { $options{config} });
		return $inner;
	});

	my @meta_fragments;
	$planner->add_delegate('add_meta', sub {
		my (undef, @fragments) = @_;
		push @meta_fragments, @fragments;
	});

	$planner->lib_dir('lib');
	$planner->script_dir('script');

	for my $file (glob 'planner/*.pl') {
		my $inner = $planner->new_scope;
		$inner->add_delegate('self', sub { $inner });
		$inner->add_delegate('outer', sub { $planner });
		$inner->run_dsl($file);
	}

	$planner->autoclean;

	my $plan = $planner->materialize;

	mkdir '_build' if not -d '_build';
	save_json(catfile(qw/_build graph/), $serializer->serialize_plan($plan));
	save_json(catfile(qw/_build params/), [ $args, \@env ]);

	if (@meta_fragments) {
		require CPAN::Meta::Merge;
		my $merger = CPAN::Meta::Merge->new(default_version => '2');
		my $metahash = $merger->merge($meta, @meta_fragments);
		$metahash->{dynamic_config} = 0;
		$meta = CPAN::Meta->create($metahash, { lazy_validation => 0 });
	}
	$meta->save('MYMETA.json');

	printf "Creating new 'Build' script for '%s' version '%s'\n", $meta->name, $meta->version;
	my $dir = $meta->name eq 'Dist-Build' ? 'lib' : 'inc';
	open my $fh, '>:utf8', 'Build';
	print $fh "#!perl\nuse lib '$dir';\nuse Dist::Build;\nBuild(\\\@ARGV, \\\%ENV);\n";
	close $fh;
	make_executable('Build');

	return;
}

sub Build {
	my ($args, $env) = @_;
	my $meta = CPAN::Meta->load_file('MYMETA.json', { lazy_validation => 0 });

	my ($bpl, $mbopts) = @{ load_json(catfile(qw/_build params/)) };
	my %options = get_config($meta->name, $bpl, $mbopts, $args);
	my $action = @{$args} ? shift @{$args} : 'build';

	my $preplan = load_json(catfile(qw/_build graph/));
	my $plan = $serializer->deserialize_plan($preplan, %options);
	return $plan->run($action);
}

1;

# ABSTRACT: A modern module builder, author tools not included!

=head1 SYNOPSIS

 use Dist::Build;
 Build_PL(\@ARGV, \%ENV);

=head1 DESCRIPTION

C<Dist::Build> is a Build.PL implementation. Unlike L<Module::Build::Tiny> it is extensible, unlike L<Module::Build> it uses a build graph internally which makes it easy to combine different customizations. It's typically extended by adding a C<.pl> script in C<planner/>. E.g.

 load_module("Dist::Build::ShareDir");
 dist_sharedir('share', 'Foo-Bar');
 
 load_module("Dist::Build::XS");
 add_xs(
   libraries     => [ 'foo' ],
   extra_sources => [ glob 'src/*.c' ],
 );

=head1 DELEGATES

By default, the following delegates are defined on your L<planner|ExtUtils::Builder::Planner>:

=over 4

=item * meta

A L<CPAN::Meta|CPAN::Meta> object representing the C<META.json> file.

=item * distribution

The name of the distribution

=item * distribution_version

The version of the distribution

=item * main_module

The main module of the distribution.

=item * release_status

The release status of the distribution (e.g. C<'stable'>).

=item * perl_path

The path to the perl executable.

=item * config

The L<ExtUtils::Config|ExtUtils::Config> object for this build

=item * install_paths

The L<ExtUtils::InstallPaths|ExtUtils::InstallPaths> object for this build.

=item * verbose

The value of the C<verbose> command line argument.

=item * uninst

The value of the C<uninst> command line argument.

=item * jobs

The value of the C<jobs> command line argument.

=item * pureperl_only

The value of the C<pureperl_only> command line argument.

=back
