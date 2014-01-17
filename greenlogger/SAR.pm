package SAR;
use strict;
use Data::Dumper;
use IO::Handle;
use SARParse;
use IPC::Open2;

sub new {
	my($class,%args) = @_;        
	my $self = {};
	bless($self, $class);
	$self->{command} = $args{command} || "sar -bBur -n DEV 1";
	$self->{sarparser} = SARParse->new();
	return $self;
}

sub start {
	my ($self) = @_;
	my $cmd = $self->{command};
	#open(my $fd, $self->{command} . " |");
	my ($fd,$fdw);
	my $pid = open2($fd,$fdw, "$cmd") || die "Could not open [$cmd]!";
	#open($fd, "$cmd |") || die "Could not open [$cmd]!";
	close($fdw);
	$self->{fd} = IO::Handle->new_from_fd( $fd, "r" );
	$self->{fd}->autoflush( 1 );
	$self->{fd}->blocking( 0 );
        $self->{pid} = $pid;
}

sub fd {
	my ($self) = @_;
	$self->{fd};
}

sub end {
	my ($self) = @_;
	$self->{fd}->close() if defined $self->{fd};
	$self->{fd} = undef;
        if ($self->{pid}) {
            kill("TERM",$self->{pid});
            $self->{pid} = undef;
        }
}

sub process {
	my ($self) = @_;
	#my @lines = $self->{fd}->getlines();
	my @lines = ();
	while($_=$self->{fd}->getline()) {
		#warn "Got line: $_";
		push @lines, $_;
	}
	chomp(@lines);
	#my @lines = $self->{fd}->getlines();
	#my $lines = $self->{fd}->getline();
	$self->{sarparser}->collectLines( @lines ) if @lines;
	# possible bug if we read too much, we really want an iterator :(
	my $ret = undef;
	eval {
		my $last = $self->{sarparser}->getLastRecord();
		#warn $last->{utime};
		if ($self->{lasttime} eq $last->{'utime'}) {
			$ret = undef;
		} else {
			$self->{lasttime} = $last->{'utime'};
			$ret = $last;
		}
	};
	return $ret;
}

sub name { return "SAR" }
1;
