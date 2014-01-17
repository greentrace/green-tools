package GreenLogger;
use PerlIO::via::gzip;
use autodie qw(open close);
use File::Basename;
use File::Spec;
use strict;
use Statistics::Descriptive;

sub getAllData {
    my @files = @_;
    my @out = ();
    foreach my $file (@files) {    
        warn $file;
        my $timeseries = interpretFile( $file );
        my $fdate = parseFileName( $file );
        push @out, { %$fdate, ts => $timeseries }
    }
    return \@out;
}

sub forEachFile {
    my ($callback,@files) = @_;
    foreach my $file (@files) {    
        warn $file;
        my $timeseries = interpretFile( $file );
        my $fdate = parseFileName( $file );
	my $input = { %$fdate, ts => $timeseries };
	&$callback($input);
    }
}

sub wattageSummary {
    my ($elm) = @_;
    my $ts = $elm->{ts};
    my $stat = Statistics::Descriptive::Full->new();
    my @watts = map { $_->{Power}->{watts} } @$ts;
    my @time = map { $_->{utime} } @$ts;
    @time = sort { $a <=> $b } @time;
    my $mintime = $time[0];
    my $maxtime = $time[$#time];
    my $time = $maxtime - $mintime; # seconds
    $stat->add_data( @watts );
    my $mean = $stat->mean();
    my @watthours = map { $_->{Power}->{"watt hours"} } @$ts;
    @watthours = sort {$a<=>$b} @watthours;    
    my $kwatthours = $watthours[$#watthours] / 1000;
    my $kwh = ($mean * $time / 3600) / 1000 ; #Kwh
    return {
            type       => "wattageSummary",
            startTime  => $mintime,
            endTime    => $maxtime,
            seconds    => $time,
            kwatthours => $kwatthours,
            kwh        => $kwh,
            mean       => $mean,
            var        => $stat->variance(),
            sum        => $stat->sum(),
            std        => $stat->standard_deviation,
            max        => $stat->max(),
            min        => $stat->min(),
    };
}

sub parseFileName {
    my ($filename) = @_;
    my ($file, $dirs, $suffix) = fileparse($filename);
    my @dirs = File::Spec->splitdir( $dirs );
    @dirs = grep { /./ } @dirs; # remove empties
    my $label = $dirs[$#dirs];
    # now parse label for
    # greenmining-gedit-3.4.1-1342236293-test0
    my ($machine,$app,$version,$utime,$test) = ($label =~ /^([^-]+)-([^-]+)-([^-]+)-([^-]+)-([^-]+)$/);
 #   my ($date) = ($package =~ /_([12]\d\d\d-\d\d-\d\d)/);
 #   my ($ffversion) = ($package =~ /firefox-([\d\.ba]+(pre)?)\./);
    return {
            testID  => "$machine-$utime",
            machine => $machine,
            utime   => $utime,
            #sURI    => $package,
            path    => $filename,
            file    => $file,
            #date    => $date,
            version => "$app-$version"
           };
}

sub interpretFile {
    my ($file) = @_;
    my $fd = openForReading($file);
    my @lines = <$fd>;
    my $VAR1;
    my @OUT;
    eval join("",@lines);
    return \@OUT;
}

sub openForReading {
    my ($file) = @_;
    my $fd;
    my $openstr = ($file =~ /\.gz$/i)?"<:via(gzip)":"<";
    open($fd, $openstr, $file);
    return $fd;
}

1;
