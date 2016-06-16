use strict;
use warnings;

use lib 'xt/lib';
use RT::Extension::AssetSQL::Test;

my $laptops = create_catalog(Name => 'Laptops');
my $servers = create_catalog(Name => 'Servers');
my $keyboards = create_catalog(Name => 'Keyboards');

my $manufacturer = create_cf(Name => 'Manufacturer');
apply_cfs($manufacturer);

my $blank = create_cf(Name => 'Blank');
apply_cfs($blank);

my $shawn = RT::User->new(RT->SystemUser);
my ($ok, $msg) = $shawn->Create(Name => 'shawn', EmailAddress => 'shawn@bestpractical.com');
ok($ok, $msg);

my $bloc = create_asset(
    Name                       => 'bloc',
    Description                => "Shawn's BPS office media server",
    Catalog                    => 'Servers',
    Owner                      => $shawn->PrincipalId,
    Contact                    => $shawn->PrincipalId,
    'CustomField-Manufacturer' => 'Raspberry Pi',
);
my $deleted = create_asset(
    Name                       => 'deleted',
    Description                => "for making sure we don't search deleted",
    Catalog                    => 'Servers',
);
my $ecaz = create_asset(
    Name                       => 'ecaz',
    Description                => "Shawn's BPS laptop",
    Catalog                    => 'Laptops',
    Owner                      => $shawn->PrincipalId,
    Contact                    => $shawn->PrincipalId,
    'CustomField-Manufacturer' => 'Apple',
);
my $kaitain = create_asset(
    Name                       => 'kaitain',
    Description                => "unused BPS laptop",
    Catalog                    => 'Laptops',
    Owner                      => $shawn->PrincipalId,
    'CustomField-Manufacturer' => 'Apple',
);
my $morelax = create_asset(
    Name                       => 'morelax',
    Description                => "BPS in the data center",
    Catalog                    => 'Servers',
    'CustomField-Manufacturer' => 'Dell',
);
my $stilgar = create_asset(
    Name                       => 'stilgar',
    Description                => "English layout",
    Catalog                    => 'Keyboards',
    Owner                      => $shawn->PrincipalId,
    Contact                    => $shawn->PrincipalId,
    'CustomField-Manufacturer' => 'Apple',
);

($ok, $msg) = $bloc->SetStatus('stolen');
ok($ok, $msg);

($ok, $msg) = $deleted->SetStatus('deleted');
ok($ok, $msg);

($ok, $msg) = $ecaz->SetStatus('in-use');
ok($ok, $msg);

($ok, $msg) = $kaitain->SetStatus('in-use');
ok($ok, $msg);
($ok, $msg) = $kaitain->SetStatus('recycled');
ok($ok, $msg);

($ok, $msg) = $morelax->SetStatus('in-use');
ok($ok, $msg);

($ok, $msg) = $ecaz->AddLink(Type => 'RefersTo', Target => $kaitain->URI);
ok($ok, $msg);

($ok, $msg) = $stilgar->AddLink(Type => 'MemberOf', Target => $ecaz->URI);
ok($ok, $msg);

my $ticket = RT::Ticket->new(RT->SystemUser);
($ok, $msg) = $ticket->Create(Queue => 'General', Subject => "reboot the server please");

($ok, $msg) = $morelax->AddLink(Type => 'RefersTo', Target => $ticket->URI);
ok($ok, $msg);

sub assetsql {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $sql = shift;
    my @expected = @_;

    my $count = scalar @expected;

    my $assets = RT::Assets->new(RT->SystemUser);
    $assets->FromSQL($sql);
    $assets->OrderBy( FIELD => 'Name', ORDER => 'ASC' );

    is($assets->Count, $count, "number of assets from [$sql]");
    my $i = 0;
    while (my $asset = $assets->Next) {
        my $expected = shift @expected;
        if (!$expected) {
            fail("got more assets (" . $asset->Name . ") than expected from [$sql]");
            next;
        }
        ++$i;
        is($asset->Name, $expected->Name, "asset ($i/$count) from [$sql]");
    }
    while (my $expected = shift @expected) {
        fail("got fewer assets than expected (" . $expected->Name . ") from [$sql]");
    }
}

assetsql("id = 1" => $bloc);
assetsql("id != 1" => $ecaz, $kaitain, $morelax, $stilgar);
assetsql("id = 2" => ()); # deleted
assetsql("id < 3" => $bloc);
assetsql("id >= 3" => $ecaz, $kaitain, $morelax, $stilgar);

assetsql("Name = 'ecaz'" => $ecaz);
assetsql("Name != 'ecaz'" => $bloc, $kaitain, $morelax, $stilgar);
assetsql("Name = 'no match'" => ());
assetsql("Name != 'no match'" => $bloc, $ecaz, $kaitain, $morelax, $stilgar);

assetsql("Status = 'new'" => $stilgar);
assetsql("Status = 'allocated'" => ());
assetsql("Status = 'in-use'" => $ecaz, $morelax);
assetsql("Status = 'recycled'" => $kaitain);
assetsql("Status = 'stolen'" => $bloc);
assetsql("Status = 'deleted'" => ());

assetsql("Status = '__Active__'" => $ecaz, $morelax, $stilgar);
assetsql("Status != '__Inactive__'" => $ecaz, $morelax, $stilgar);
assetsql("Status = '__Inactive__'" => $bloc, $kaitain);
assetsql("Status != '__Active__'" => $bloc, $kaitain);

assetsql("Catalog = 'Laptops'" => $ecaz, $kaitain);
assetsql("Catalog = 'Servers'" => $bloc, $morelax);
assetsql("Catalog = 'Keyboards'" => $stilgar);
assetsql("Catalog != 'Servers'" => $ecaz, $kaitain, $stilgar);
assetsql("Catalog != 'Laptops'" => $bloc, $morelax, $stilgar);
assetsql("Catalog != 'Keyboards'" => $bloc, $ecaz, $kaitain, $morelax);

assetsql("Description LIKE 'data center'" => $morelax);
assetsql("Description LIKE 'Shawn'" => $bloc, $ecaz);
assetsql("Description LIKE 'media'" => $bloc);
assetsql("Description NOT LIKE 'laptop'" => $bloc, $morelax, $stilgar);
assetsql("Description LIKE 'deleted'" => ());
assetsql("Description LIKE 'BPS'" => $bloc, $ecaz, $kaitain, $morelax);

assetsql("Lifecycle = 'assets'" => $bloc, $ecaz, $kaitain, $morelax, $stilgar);
assetsql("Lifecycle != 'assets'" => ());
assetsql("Lifecycle = 'default'" => ());
assetsql("Lifecycle != 'default'" => $bloc, $ecaz, $kaitain, $morelax, $stilgar);

assetsql("Linked IS NOT NULL" => $ecaz, $kaitain, $morelax, $stilgar);
assetsql("Linked IS NULL" => $bloc);
assetsql("RefersTo = 'asset:" . $kaitain->id . "'" => $ecaz);
assetsql("RefersTo = " . $ticket->Id => $morelax);
assetsql("HasMember = 'asset:" . $stilgar->id . "'" => $ecaz);
assetsql("MemberOf = 'asset:" . $stilgar->id . "'" => ());

assetsql("Owner.Name = 'shawn'" => $bloc, $ecaz, $kaitain, $stilgar);
assetsql("Owner.EmailAddress LIKE 'bestpractical'" => $bloc, $ecaz, $kaitain, $stilgar);
assetsql("Owner.Name = 'Nobody'" => $morelax);

assetsql("Contact.Name = 'shawn'" => $bloc, $ecaz, $stilgar);

assetsql("CustomField.{Manufacturer} = 'Apple'" => $ecaz, $kaitain, $stilgar);
assetsql("CF.{Manufacturer} != 'Apple'" => $bloc, $morelax);
assetsql("CustomFieldValue.{Manufacturer} = 'Raspberry Pi'" => $bloc);
assetsql("CF.{Manufacturer} IS NULL" => ());

assetsql("CF.{Blank} IS NULL" => $bloc, $ecaz, $kaitain, $morelax, $stilgar);
assetsql("CF.{Blank} IS NOT NULL" => ());

assetsql("Status = '__Active__' AND Catalog = 'Servers'" => $morelax);
assetsql("Status = 'in-use' AND Catalog = 'Laptops'" => $ecaz);
assetsql("Catalog != 'Servers' AND Catalog != 'Laptops'" => $stilgar);
assetsql("Description LIKE 'BPS' AND Contact.Name IS NULL" => $kaitain, $morelax);
assetsql("CF.{Manufacturer} = 'Apple' AND Catalog = 'Laptops'" => $ecaz, $kaitain);
assetsql("Catalog = 'Servers' AND Linked IS NULL" => $bloc);
assetsql("Catalog = 'Servers' OR Linked IS NULL" => $bloc, $morelax);
assetsql("(Catalog = 'Keyboards' AND CF.{Manufacturer} = 'Apple') OR (Catalog = 'Servers' AND CF.{Manufacturer} = 'Raspberry Pi')" => $bloc, $stilgar);

