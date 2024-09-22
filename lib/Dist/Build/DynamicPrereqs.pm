package Dist::Build::DynamicPrereqs;

use strict;
use warnings;

use parent 'ExtUtils::Builder::Planner::Extension';

sub add_methods {
	my ($self, $planner) = @_;

	$planner->add_delegate('evaluate_dynamic_prereqs', sub {
		my ($planner, %options) = @_;

		my $meta = $options{meta} // $planner->meta;

		if (my $dynamic = $meta->custom('x_dynamic_prereqs')) {
			require CPAN::Requirements::Dynamic;
			$options{config}        //= $planner->config;
			$options{pureperl_only} //= $planner->pureperl_only;

			my $dynamic_parser = CPAN::Requirements::Dynamic->new(%options);
			my $prereq = $dynamic_parser->evaluate($dynamic);
			$planner->add_meta({ prereqs => $prereq->as_string_hash });
		}
	});

	$planner->add_delegate('add_prereq', sub {
		my ($planner, $module, $version, %options) = @_;
		$version   //= 0;
		my $phase    = $options{phase}    // 'runtime';
		my $relation = $options{relation} // 'requires';

		$planner->add_meta({ prereqs => { $phase => { $relation => { $module => $version }}}});
	});
}

1;

# ABSTRACT: Support dynamic prerequisites in Dist::Build

=head1 SYNOPSIS

 load_module("Dist::Build::DynamicPrereqs");
 evaluate_dynamic_prereqs();

=head1 DESCRIPTION

This extension adds support for configure-time dynamic prerequisites to C<Dist::Build>.

=head1 DELEGATES

This adds the following delegates to the planner:

=head2 evaluate_dynamic_prereqs()

This evaluates the dynamic prerequisites (as L<CPAN::Requirements::Dynamic|CPAN::Requirements::Dynamic>) in the metadata, and adds them to the prerequisites.

=head2 add_prereq($module, $version = 0, %args)

This adds a specific prerequisite. It takes the following (optional) named arguments:

=over 4

=item * phase

A CPAN::Meta requirement phase: runtime (default), build or test

=item * relation

A CPAN::Meta requirement relation: requires (default, recommends or suggests

=back
