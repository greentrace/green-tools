#!/usr/bin/perl
use strict;
use SAR;
use Power;
use IO::Select;
use Data::Dumper;
use Getopt::Long;
$|=1;
our %closers;
my $output = \*STDOUT;
my $outputfile = undef;
my $result = GetOptions (
  "o=s"   => \$outputfile,      # string
);
if ($outputfile) {
	warn "Output to $outputfile";
	$output = undef;
	open($output, ">", $outputfile) or die "Could not output $outputfile";
}


# signal handling
$SIG{TERM} = sub { die "TERM Signal Hit"; };
$SIG{QUIT} = sub { die "QUIT Signal Hit"; };
$SIG{CHLD} = 'IGNORE';
# die will let us run the end block
END {
    while (my ($key,$val) = each %closers) {
        $val->end();
    }
    close($output);
}



my $sar = SAR->new();
my $power = Power->new(wattsup=>$ENV{WATTSUP});
$sar->start;
$power->start;
my $sfd = $sar->fd;
my $pfd = $power->fd;
my %fds = (
	$sfd => $sar,
	$pfd => $power,
);
my %lag = (
	$sfd => 0,
	$pfd => -1,
);
$closers{sar} = $sar;
$closers{power} = $power;

my $select = IO::Select->new( $sfd, $pfd );
#my $select = IO::Select->new( $sfd );#, $pfd );
#my $select = IO::Select->new(  $pfd );
my %t = ();
for(;;) {
	my @ready = $select->can_read(1);
	#if (@ready) { warn "READY! ".scalar(@ready) } else { warn "Not ready..".time() }
	foreach my $fd (@ready) {
		my $obj = $fds{$fd}->process();
		my $name = $fds{$fd}->name();
		my $lag = $lag{$fd};
		#my $obj = $power->process();
		#my $name = $power->name();
		if (ref($obj)) {
			my $utime = $obj->{utime} + $lag;
			$t{$utime}->{$name} = $obj;
			if (keys %{$t{$utime}} == keys %fds) {
				$t{$utime}->{utime} = $utime;
				$t{$utime}->{now} = time;
				print $output Dumper($t{$utime});
                                print $output "push \@OUT, \$VAR1; $/";
				delete $t{$utime};
			}
		}
	}
}

