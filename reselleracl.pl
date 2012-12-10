#!/usr/bin/perl
use strict;
use LWP::UserAgent;
use XML::Simple;
use File::Copy;

# Which method (strip out or reset to standard acl):
my $modmethod = 1;	# 0 = set user acl to default standard.
			# 1 = use current acls and just remove args we want to remove.

# Check that standard acl exists if we default to resetting/replacing.
if ( ($modmethod != 1) && (!-e "/var/cpanel/acllists/standard") ) {
	die "Stopping! You selected default acl, but it doesn't exist!\n";
}

# Reseller file, (local) server IP, hashkey.
my $resf = '/var/cpanel/resellers';
my $svip = '127.0.0.1';
my $hash = '';

# Value we want to check for/remove
my $aclval = 'edit-account';

# Local hashkey for WHM
my $acchash = '/root/.accesshash';
my $hashkey = '';

my %users = (	);

# Check reseller acl file for offending value.
open(my $resacl, '<', $resf)	or die "Can't open $resf $!\n";
flock($resacl, 1)		or warn "Can't get sh lock on $resf $!\n";
	while (<$resacl>) {
		if (m/^\s*(\w+):.*${aclval}.*/) {
			chomp;
			$users{$1} = $_ if (! exists $users{$1});
		}
	}
close($resacl)			or warn "Can't close fh on $resf $!\n";

# If no reseller has $aclval, we stop and do no more work.
die "No resellers found with ${aclval}. Ending.\n" if (!keys %users);

# Here, before the work is performed, we can make a safe backup of the file, even we use the WHM API.
my $time = time;
my $bkfile = "${resf}-back-$time";
print "A safe backup file is kept safely at $bkfile.\n";
copy($resf, $bkfile)		or die "Backup copy failed: $!";

# Grab hashkey
open(my $whmkey, '<', $acchash)	or die "Can't open $acchash for read $!\n";
flock($whmkey, 1)		or warn "Can't get sh lck on $whmkey $!\n";
	while (<$whmkey>) {
		$hashkey .= $_;
	}
close($whmkey)			or warn "Can't close fh for $whmkey $!\n";
chomp $hashkey if $hashkey;
$hashkey =~ s/\n|\s+//g;
my $auth = "WHM root:" . $hashkey;

# If no hash key found:
die "Error: No WHM hashkey found!\n" if !$hashkey;

# Connect, do the work
my $ua  = LWP::UserAgent->new( 'ssl_opts' => { 'verify_hostname' => 0 } ); # We ignore invalid SSL since we're local.
my $xml = new XML::Simple;
# For each matching user, disable value from their current acl features, or reset (based on $modmethod).
while ( my ($username, $uval) = each(%users) ) {
	my $request = '';
	if ($modmethod != 1) { # If we reset to standard.
		print "Resetting ACL for $username (setting to standard acl feature list).\n";
		$request = HTTP::Request->new( GET => "https://${svip}:2087/xml-api/setacls?reseller=$username&acllist=standard");
	} else { # If we just strip $aclval.
		print "Disabling $aclval for $username (retaining other current acl features).\n";
		$uval =~ s/^\s*\w+://;
		my @resval = (split(/,/, $uval));
		my $aclargs = '';
		foreach my $rarg (sort @resval) {
			$aclargs .= "&acl-${rarg}=1" if (lc $rarg ne lc $aclval); # Add to array if not stripped arg.
		}
		$request = HTTP::Request->new( GET => "https://${svip}:2087/xml-api/setacls?reseller=${username}${aclargs}");
	}
	$request->header( Authorization => $auth );
	my $response = $ua->request($request);
	my $data = $xml->XMLin($response->content);
	# If we want to output the data:
	# print $response->content;
	# Or we can parse where needed for Synco.
}

# We can also output how many/which users had this disabled. (again, parsing where needed for Synco)
