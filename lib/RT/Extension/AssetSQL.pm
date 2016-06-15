use strict;
use warnings;
package RT::Extension::AssetSQL;
use 5.010_001;

our $VERSION = '0.01';

require RT::Extension::AssetSQL::Assets;

RT->AddStyleSheets("assetsql.css");

sub RT::Interface::Web::QueryBuilder::Tree::GetReferencedCatalogs {
    my $self = shift;

    my $catalogs = {};

    $self->traverse(
        sub {
            my $node = shift;

            return if $node->isRoot;
            return unless $node->isLeaf;

            my $clause = $node->getNodeValue();
            return unless $clause->{ Key } eq 'Catalog';
            return unless $clause->{ Op } eq '=';

            $catalogs->{ $clause->{ Value } } = 1;
        }
    );

    return $catalogs;
}

sub RT::Interface::Web::QueryBuilder::Tree::ParseAssetSQL {
    my $self = shift;
    my %args = (
        Query       => '',
        CurrentUser => '',    #XXX: Hack
        @_
    );
    my $string = $args{ 'Query' };

    my @results;

    my %field = %{ RT::Assets->new( $args{ 'CurrentUser' } )->FIELDS };
    my %lcfield = map { ( lc( $_ ) => $_ ) } keys %field;

    my $node = $self;

    my %callback;
    $callback{ 'OpenParen' } = sub {
        $node = RT::Interface::Web::QueryBuilder::Tree->new( 'AND', $node );
    };
    $callback{ 'CloseParen' } = sub { $node = $node->getParent };
    $callback{ 'EntryAggregator' } = sub { $node->setNodeValue( $_[ 0 ] ) };
    $callback{ 'Condition' } = sub {
        my ( $key, $op, $value ) = @_;

        my ($main_key, $subkey) = split /[.]/, $key, 2;

        unless( $lcfield{ lc $main_key} ) {
            push @results, [ $args{ 'CurrentUser' }->loc( "Unknown field: [_1]", $key ), -1 ];
        }
        $main_key = $lcfield{ lc $main_key };

        # Hardcode value for IS / IS NOT
        $value = 'NULL' if $op =~ /^IS( NOT)?$/i;

        my $clause = { Key => $main_key, Subkey => $subkey,
                       Meta => $field{ $main_key },
                       Op => $op, Value => $value };
        $node->addChild( RT::Interface::Web::QueryBuilder::Tree->new( $clause ) );
    };
    $callback{ 'Error' } = sub { push @results, @_ };

    require RT::SQL;
    RT::SQL::Parse( $string, \%callback );
    return @results;
}

=head1 NAME

RT-Extension-AssetSQL - SQL search builder for Assets

=cut

=head1 INSTALLATION

RT-Extension-AssetSQL requires version RT 4.4.0 or later. Note that AssetSQL
is incompatible with RT 4.2 running L<RT::Extension::Assets>.

=over

=item perl Makefile.PL

=item make

=item make install

This step may require root permissions.

=item Patch your RT

AssetSQL requires a patch for your RT isntance. The specific patch to apply
depends on which version of RT you're running.

If you're on RT 4.4.0, use rt-4.4.0.patch:

    patch -d /opt/rt4 -p1 < patches/rt-4.4.0.patch

If you're on RT 4.4.1, use rt-4.4.1.patch:

    patch -d /opt/rt4 -p1 < patches/rt-4.4.1.patch

If you're on RT 4.4.2 or later, use rt-4.4.2-later.patch:

    patch -d /opt/rt4 -p1 < patches/rt-4.4.2-later.patch

=item Edit your /opt/rt4/etc/RT_SiteConfig.pm

Add this line:

    Plugin( "RT::Extension::AssetSQL" );

If you wish to hide the legacy Asset Simple Search, add the following line
as well:

    Set($AssetSQL_HideSimpleSearch, 1);

=item Clear your mason cache

    rm -rf /opt/rt4/var/mason_data/obj

=item Restart your webserver

=back

=head1 AUTHOR

Best Practical Solutions, LLC E<lt>modules@bestpractical.comE<gt>

=head1 BUGS

All bugs should be reported via email to

    L<bug-RT-Extension-AssetSQL@rt.cpan.org|mailto:bug-RT-Extension-AssetSQL@rt.cpan.org>

or via the web at

    L<rt.cpan.org|http://rt.cpan.org/Public/Dist/Display.html?Name=RT-Extension-AssetSQL>.

=head1 COPYRIGHT

This extension is Copyright (C) 2016 Best Practical Solutions, LLC.

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

1;
