package Power;
use strict;
use Data::Dumper;
use IO::Handle;
use IPC::Open2;

sub new {
	my($class,%args) = @_;        
	my $self = {};
	bless($self, $class);
	$self->{command} = $args{command} || "./fakepower";
	if ($args{wattsup}) {
		$self->{command} = "$ENV{HOME}/greenlogger/wattsup/wattsup -T ttyUSB0";
	}
	return $self;
}

sub start {
	my ($self) = @_;
	my $cmd = $self->{command};
	my ($fd,$fdw);
	my $pid = open2($fd,$fdw, "$cmd") || die "Could not open [$cmd]!";
	#open($fd, "$cmd |") || die "Could not open [$cmd]!";
	close($fdw);
	$self->{fd} = IO::Handle->new_from_fd( $fd, ">" );
	$self->{fd}->autoflush( 1 );
	$self->{fd}->blocking( 0 );
        $self->{pid} = $pid;
}

sub fd {
	my ($self) = @_;
	return $self->{fd};
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
sub headers {
	my @headers = (
                        "watts",
                        "volts",
                        "amps",
                        "watt hours",
                        "cost",
                        "mo. kWh",
                        "mo. cost",
                        "max watts",
                        "max volts",
                        "max amps",
                         "min watts",
                         "min volts",
                         "min amps",
                         "power factor",
                         "duty cycle",
                         "power cycle",
			 "hz",
			 "w2"
	);
	return @headers;
}
sub name { return "Power" }
sub process {
	my ($self) = @_;
	my $line = $self->{fd}->getline();
	chomp($line);
	my ($time, @rest) = split(/,\s+/, $line);
	my @headers = headers();
	my %h = ( 
		'name' => "Power",
		'time' => $time,
		'utime' => $time 
	);
	for (my $i = 0 ; $i <= $#rest; $i++) {
		$h{$headers[$i]} = $rest[$i];
		#warn "$headers[$i] $rest[$i]";
	}
	return \%h;
}
1;
