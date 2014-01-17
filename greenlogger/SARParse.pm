package SARParse;
use strict;
use Data::Dumper;
use Time::Local;
sub new {
	my($class) = @_;        
	my $self = {};
	bless($self, $class);
	$self->{idtime} = "";
	$self->{arr} = [];
	$self->{collect} = [];
	$self->{curr} = {};
	$self->{done} = 1; # this means are we collecting a block or not
	return $self;
}

sub getLastRecord {
	my ($self)  = @_;
	my @arr = @{$self->{arr}};
	if (@arr) {
		return $arr[$#arr];
	}
	die "No records";
}

# have we collected any blocks?
sub hasCollection {
	my ($self) = @_;
	my $collect = $self->{collect};
	return (scalar(@$collect) > 0);
}
sub mergehash {
	my ($curr,$h) = @_;
	while (my ($key,$val) = each %$h) {
		if (ref($val) eq 'HASH') {
			mergehash($curr->{$key}, $val);
			#while (my ($key2,$val2) = each %$val) {
			#	$curr->{$key}->{$key2} = $val2;
			#}
		} else {
			warn "REPLACING A REF" if ref($curr->{$key});
			$curr->{$key} = $val;
		}
	}
	return $curr;
}

# deal with the block we collected
sub handleTheCollection {
	my ($self) = @_;
	#warn "Handling: ".@{$self->{collect}};
	my %h = parseCollection(@{$self->{collect}});
	$self->{collect} = [];
	my %curr = %{$self->{curr}};
	if (!$curr{'time'} || $curr{'time'} eq $h{'time'}) {
		mergehash(\%curr, \%h);
		#%curr = (%curr,%h);
	} else {
		if (%curr) {
			push @{$self->{arr}}, { %curr };
		}
		%curr = %h;
	}
	$self->{curr} = \%curr;
}
# call this to finish up
sub noMoreLines {
	my ($self) = @_;
	$self->handleTheCollection();
}
# we can leave this at any time, blocks could not be complete
# parse a set of lines in object form
sub collectLines {
	my ($self, @lines) = @_;
	#warn "We have ".scalar(@{$self->{arr}})." ".scalar(keys(%{$self->{curr}}));
	while(@lines) {
		my $line = shift @lines;
		# find a line
		if ($line =~ /^$/) {
			#warn "^\$";
			$self->{done} = 0;
			if ($self->hasCollection) {
				# clean up the collection
				#warn "Has Collection";
				$self->handleTheCollection();
				$self->{collect} = [];
			}
		} elsif ($line =~ /^Linux.*$/) {
			#do nothing
		} elsif (!$self->{done}) {
			#my $line = shift @lines;
			if ($line =~ /^$/) { # basically jump to the top and handle the
					     # collection..
				$self->{done} = 1;
				unshift @lines, $line;
			} else {
				push @{$self->{collect}}, $line;
			}
		}
	}
	if ($self->{done} && $self->hasCollection) {
		warn 'Done and HasCollection';
		$self->handleTheCollection();
		$self->{collect} = [];
	}
}

# test for parseLines
sub dataTest {
	my @lines = <DATA>;
	chomp(@lines);
	my $out = parseLines(@lines);
	print Dumper($out);
}

# parse an entire file basically
sub parseLines {
	my (@lines) = @_;
	die "This is a function, not a method" if (ref($lines[0]));
	my $idtime = "";
	my @arr = ();
	my %curr = ();
	while(@lines) {
		my $line = shift @lines;
		# find a line
		if ($line =~ /^$/) {
			my $done = 0;
			my @collect = ();
			while(!$done && @lines) {
				my $line = shift @lines;
				if ($line =~ /^$/) {
					$done = 1;
					unshift @lines, $line;
				} else {
					push @collect, $line;
				}
			}
			if (@collect) {
				# we're done and collected
				my %h = parseCollection(@collect);
				if (!$curr{'time'} || $curr{'time'} eq $h{'time'}) {
					#%curr = (%curr,%h);
					mergehash(\%curr,\%h);
				} else {
					push @arr, { %curr };
					%curr = %h;
				}
			}
		} elsif ($line =~ /^Linux.*$/) {
			#do nothing
		}
	}
	if (%curr) {
		push @arr, { %curr };
	}
	return \@arr;
}

# parse both
# 04:35:33 PM kbhugfree kbhugused  %hugused
# 04:35:35 PM         0         0      0.00
# 
# 04:35:33 PM     CPU    wghMHz
# 04:35:35 PM     all   1596.00
# 04:35:35 PM       0   1596.00
# 04:35:35 PM       1   1596.00
# 04:35:35 PM       2   1596.00
# 04:35:35 PM       3   1596.00

sub parseCollection {
	my @lines = @_;
	my @headers = tabsplit(shift @lines);
	my $timeh = shift @headers; # drop time
	my $timehAMPM = shift @headers; # drop AM PM
	$timeh = $timeh." ".$timehAMPM;
	my $timed = $timeh;
	my %h;
	if (@lines == 1) { #scalar
		my ($time,$ampm,@values) = tabsplit($lines[0]);
		$time = "$time $ampm";
		$timed = (reltimecmp($time,$timed)==1)?$time:$timed;
		foreach my $header (@headers) {
			$h{$header} = trim(shift @values);
		}
	} else { #vector
		my $head = $headers[0];
		foreach my $line (@lines) {
			my ($time,$ampm,$id,@values) = tabsplit($line);
			$time = "$time $ampm";
			$timed = (reltimecmp($time,$timed)==1)?$time:$timed;
			foreach my $header (@headers[1..$#headers]) {
				$h{$head}->{$id}->{$header} = trim(shift @values);
			}
		}
	}
	$h{'time'} = $timed;
	my @time = localtime(time());
	my ($s,$m,$h) = smh($timed);
	#warn "$h $m $s";
	$time[0]=$s;
	$time[1]=$m;
	$time[2]=$h;
	$h{'utime'} = timelocal(@time);
	return %h;
}
sub tabsplit {
	return split(/[\s\t]+/, $_[0]);
}
sub trim {
	my ($trimit) = @_;
	$trimit =~ s/^\s*//;
	$trimit =~ s/\s*$//;
	return $trimit;
}
sub secs {
	my ($time) = @_;
	my ($h,$m,$s,$d) = ($time =~ /^\s*(\d\d):(\d\d):(\d\d) ([AP]M)\s$/);
	my $mod = 3600*12 * (($d eq "PM")?1:0);
	return ($h%12)*3600 + $m*60 + $s + $mod;
}
sub smh {
	my ($time) = @_;
	my ($h,$m,$s,$d) = ($time =~ /^\s*(\d\d):(\d\d):(\d\d) ([AP]M)\s*$/);
	my $mod = (($d eq "PM")?12:0);
	my $h = $h%12 + $mod;
	return ($s,$m,$h);
}
# we have to deal with stupid wrap arounds and AM & PM
sub reltimecmp {
	my ($a,$b) = @_;
	return 0 if $a eq $b;
	my $as = secs($a);
	my $bs = secs($b);
	if ($as < 100 && $bs > 23*3600) {
		return 1;
	}
	if ($bs < 100 && $as > 23*3600) {
		return -1;
	}
	return ($as <=> $bs);
}

1;
__DATA__
Linux 2.6.38-12-generic (burn) 	11/16/2011 	_x86_64_	(4 CPU)

04:34:51 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:34:53 PM     all      2.51      0.00      1.13      0.00      0.00      0.00      0.00      0.00     96.37
04:34:53 PM       0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00    100.00
04:34:53 PM       1      3.52      0.00      1.01      0.00      0.00      0.00      0.00      0.00     95.48
04:34:53 PM       2      6.50      0.00      3.00      0.00      0.00      0.00      0.00      0.00     90.50
04:34:53 PM       3      0.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.50

04:34:51 PM    proc/s   cswch/s
04:34:53 PM      0.00   2017.50

04:34:51 PM      INTR    intr/s
04:34:53 PM       sum    620.50
04:34:53 PM         0      0.00
04:34:53 PM         1      0.00
04:34:53 PM         2      0.00
04:34:53 PM         3      0.00
04:34:53 PM         4      0.00
04:34:53 PM         5      0.00
04:34:53 PM         6      0.00
04:34:53 PM         7      0.00
04:34:53 PM         8      0.00
04:34:53 PM         9      0.00
04:34:53 PM        10      0.00
04:34:53 PM        11      0.00
04:34:53 PM        12      0.00
04:34:53 PM        13      0.00
04:34:53 PM        14      0.00
04:34:53 PM        15      0.00
04:34:53 PM        16      1.00
04:34:53 PM        17      2.50
04:34:53 PM        18      0.00
04:34:53 PM        19      7.00
04:34:53 PM        20      0.00
04:34:53 PM        21      0.00
04:34:53 PM        22      0.00
04:34:53 PM        23      0.50
04:34:53 PM        24      0.00
04:34:53 PM        25      0.00
04:34:53 PM        26      0.00
04:34:53 PM        27      0.00
04:34:53 PM        28      0.00
04:34:53 PM        29      0.00
04:34:53 PM        30      0.00
04:34:53 PM        31      0.00
04:34:53 PM        32      0.00
04:34:53 PM        33      0.00
04:34:53 PM        34      0.00
04:34:53 PM        35      0.00
04:34:53 PM        36      0.00
04:34:53 PM        37      0.00
04:34:53 PM        38      0.00
04:34:53 PM        39      0.00
04:34:53 PM        40      0.00
04:34:53 PM        41      0.00
04:34:53 PM        42      0.00
04:34:53 PM        43      0.00
04:34:53 PM        44      1.00
04:34:53 PM        45      1.00
04:34:53 PM        46      0.00
04:34:53 PM        47      0.00
04:34:53 PM        48      0.00
04:34:53 PM        49      0.00
04:34:53 PM        50      0.00
04:34:53 PM        51      0.00
04:34:53 PM        52      0.00
04:34:53 PM        53      0.00
04:34:53 PM        54      0.00
04:34:53 PM        55      0.00
04:34:53 PM        56      0.00
04:34:53 PM        57      0.00
04:34:53 PM        58      0.00
04:34:53 PM        59      0.00
04:34:53 PM        60      0.00
04:34:53 PM        61      0.00
04:34:53 PM        62      0.00
04:34:53 PM        63      0.00
04:34:53 PM        64      0.00
04:34:53 PM        65      0.00
04:34:53 PM        66      0.00
04:34:53 PM        67      0.00
04:34:53 PM        68      0.00
04:34:53 PM        69      0.00
04:34:53 PM        70      0.00
04:34:53 PM        71      0.00
04:34:53 PM        72      0.00
04:34:53 PM        73      0.00
04:34:53 PM        74      0.00
04:34:53 PM        75      0.00
04:34:53 PM        76      0.00
04:34:53 PM        77      0.00
04:34:53 PM        78      0.00
04:34:53 PM        79      0.00
04:34:53 PM        80      0.00
04:34:53 PM        81      0.00
04:34:53 PM        82      0.00
04:34:53 PM        83      0.00
04:34:53 PM        84      0.00
04:34:53 PM        85      0.00
04:34:53 PM        86      0.00
04:34:53 PM        87      0.00
04:34:53 PM        88      0.00
04:34:53 PM        89      0.00
04:34:53 PM        90      0.00
04:34:53 PM        91      0.00
04:34:53 PM        92      0.00
04:34:53 PM        93      0.00
04:34:53 PM        94      0.00
04:34:53 PM        95      0.00
04:34:53 PM        96      0.00
04:34:53 PM        97      0.00
04:34:53 PM        98      0.00
04:34:53 PM        99      0.00
04:34:53 PM       100      0.00
04:34:53 PM       101      0.00
04:34:53 PM       102      0.00
04:34:53 PM       103      0.00
04:34:53 PM       104      0.00
04:34:53 PM       105      0.00
04:34:53 PM       106      0.00
04:34:53 PM       107      0.00
04:34:53 PM       108      0.00
04:34:53 PM       109      0.00
04:34:53 PM       110      0.00
04:34:53 PM       111      0.00
04:34:53 PM       112      0.00
04:34:53 PM       113      0.00
04:34:53 PM       114      0.00
04:34:53 PM       115      0.00
04:34:53 PM       116      0.00
04:34:53 PM       117      0.00
04:34:53 PM       118      0.00
04:34:53 PM       119      0.00
04:34:53 PM       120      0.00
04:34:53 PM       121      0.00
04:34:53 PM       122      0.00
04:34:53 PM       123      0.00
04:34:53 PM       124      0.00
04:34:53 PM       125      0.00
04:34:53 PM       126      0.00
04:34:53 PM       127      0.00
04:34:53 PM       128      0.00
04:34:53 PM       129      0.00
04:34:53 PM       130      0.00
04:34:53 PM       131      0.00
04:34:53 PM       132      0.00
04:34:53 PM       133      0.00
04:34:53 PM       134      0.00
04:34:53 PM       135      0.00
04:34:53 PM       136      0.00
04:34:53 PM       137      0.00
04:34:53 PM       138      0.00
04:34:53 PM       139      0.00
04:34:53 PM       140      0.00
04:34:53 PM       141      0.00
04:34:53 PM       142      0.00
04:34:53 PM       143      0.00
04:34:53 PM       144      0.00
04:34:53 PM       145      0.00
04:34:53 PM       146      0.00
04:34:53 PM       147      0.00
04:34:53 PM       148      0.00
04:34:53 PM       149      0.00
04:34:53 PM       150      0.00
04:34:53 PM       151      0.00
04:34:53 PM       152      0.00
04:34:53 PM       153      0.00
04:34:53 PM       154      0.00
04:34:53 PM       155      0.00
04:34:53 PM       156      0.00
04:34:53 PM       157      0.00
04:34:53 PM       158      0.00
04:34:53 PM       159      0.00
04:34:53 PM       160      0.00
04:34:53 PM       161      0.00
04:34:53 PM       162      0.00
04:34:53 PM       163      0.00
04:34:53 PM       164      0.00
04:34:53 PM       165      0.00
04:34:53 PM       166      0.00
04:34:53 PM       167      0.00
04:34:53 PM       168      0.00
04:34:53 PM       169      0.00
04:34:53 PM       170      0.00
04:34:53 PM       171      0.00
04:34:53 PM       172      0.00
04:34:53 PM       173      0.00
04:34:53 PM       174      0.00
04:34:53 PM       175      0.00
04:34:53 PM       176      0.00
04:34:53 PM       177      0.00
04:34:53 PM       178      0.00
04:34:53 PM       179      0.00
04:34:53 PM       180      0.00
04:34:53 PM       181      0.00
04:34:53 PM       182      0.00
04:34:53 PM       183      0.00
04:34:53 PM       184      0.00
04:34:53 PM       185      0.00
04:34:53 PM       186      0.00
04:34:53 PM       187      0.00
04:34:53 PM       188      0.00
04:34:53 PM       189      0.00
04:34:53 PM       190      0.00
04:34:53 PM       191      0.00
04:34:53 PM       192      0.00
04:34:53 PM       193      0.00
04:34:53 PM       194      0.00
04:34:53 PM       195      0.00
04:34:53 PM       196      0.00
04:34:53 PM       197      0.00
04:34:53 PM       198      0.00
04:34:53 PM       199      0.00
04:34:53 PM       200      0.00
04:34:53 PM       201      0.00
04:34:53 PM       202      0.00
04:34:53 PM       203      0.00
04:34:53 PM       204      0.00
04:34:53 PM       205      0.00
04:34:53 PM       206      0.00
04:34:53 PM       207      0.00
04:34:53 PM       208      0.00
04:34:53 PM       209      0.00
04:34:53 PM       210      0.00
04:34:53 PM       211      0.00
04:34:53 PM       212      0.00
04:34:53 PM       213      0.00
04:34:53 PM       214      0.00
04:34:53 PM       215      0.00
04:34:53 PM       216      0.00
04:34:53 PM       217      0.00
04:34:53 PM       218      0.00
04:34:53 PM       219      0.00
04:34:53 PM       220      0.00
04:34:53 PM       221      0.00
04:34:53 PM       222      0.00
04:34:53 PM       223      0.00
04:34:53 PM       224      0.00
04:34:53 PM       225      0.00
04:34:53 PM       226      0.00
04:34:53 PM       227      0.00
04:34:53 PM       228      0.00
04:34:53 PM       229      0.00
04:34:53 PM       230      0.00
04:34:53 PM       231      0.00
04:34:53 PM       232      0.00
04:34:53 PM       233      0.00
04:34:53 PM       234      0.00
04:34:53 PM       235      0.00
04:34:53 PM       236      0.00
04:34:53 PM       237      0.00
04:34:53 PM       238      0.00
04:34:53 PM       239      0.00
04:34:53 PM       240      0.00
04:34:53 PM       241      0.00
04:34:53 PM       242      0.00
04:34:53 PM       243      0.00
04:34:53 PM       244      0.00
04:34:53 PM       245      0.00
04:34:53 PM       246      0.00
04:34:53 PM       247      0.00
04:34:53 PM       248      0.00
04:34:53 PM       249      0.00
04:34:53 PM       250      0.00
04:34:53 PM       251      0.00
04:34:53 PM       252      0.00
04:34:53 PM       253      0.00
04:34:53 PM       254      0.00
04:34:53 PM       255      0.00

04:34:51 PM  pswpin/s pswpout/s
04:34:53 PM      0.00      0.00

04:34:51 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:34:53 PM      0.00     12.00   1022.00      0.00   1228.00      0.00      0.00      0.00      0.00

04:34:51 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:34:53 PM      3.50      0.00      3.50      0.00     40.00

04:34:51 PM   frmpg/s   bufpg/s   campg/s
04:34:53 PM   -158.00      0.00      3.00

04:34:51 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:34:53 PM     81328   8114232     99.01       176   5018540   4689464      8.34   4225304   2971832

04:34:51 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:34:53 PM  48016452       948      0.00       224     23.63

04:34:51 PM dentunusd   file-nr  inode-nr    pty-nr
04:34:53 PM    158622      9888    134011       110

04:34:51 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:34:53 PM         0       475      0.00      0.01      0.05         0

04:34:51 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:34:53 PM    dev8-0      1.50      0.00     16.00     10.67      0.03     20.00     20.00      3.00
04:34:53 PM   dev8-16      1.50      0.00     16.00     10.67      0.03     16.67     16.67      2.50
04:34:53 PM    dev9-0      0.50      0.00      8.00     16.00      0.00      0.00      0.00      0.00
04:34:53 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:34:53 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:53 PM      eth0      0.50      0.50      0.07      0.12      0.00      0.00      0.00
04:34:53 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:53 PM      tun0      0.50      0.50      0.03      0.08      0.00      0.00      0.00

04:34:51 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:34:53 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:53 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:53 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:53 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:34:53 PM       882        32         9         0         0         0

04:34:51 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:34:53 PM      1.00      0.00      1.00      1.00      0.00      0.00      0.00      0.00

04:34:51 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM  active/s passive/s    iseg/s    oseg/s
04:34:53 PM      0.00      0.00      0.50      0.50

04:34:51 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00

04:34:51 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:34:53 PM      0.50      0.50      0.00      0.00

04:34:51 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:34:53 PM         2         2         0         0

04:34:51 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:34:53 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:51 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:34:53 PM      0.00      0.00      0.00      0.00

04:34:51 PM     CPU       MHz
04:34:53 PM     all   1596.00
04:34:53 PM       0   1596.00
04:34:53 PM       1   1596.00
04:34:53 PM       2   1596.00
04:34:53 PM       3   1596.00

04:34:51 PM     FAN       rpm      drpm                   DEVICE
04:34:53 PM       1   2616.00   2016.00           atk0110-acpi-0
04:34:53 PM       2      0.00   -800.00           atk0110-acpi-0
04:34:53 PM       3      0.00   -800.00           atk0110-acpi-0
04:34:53 PM       4      0.00   -800.00           atk0110-acpi-0

04:34:51 PM    TEMP      degC     %temp                   DEVICE
04:34:53 PM       1     47.00     78.33           atk0110-acpi-0
04:34:53 PM       2     43.00     95.56           atk0110-acpi-0

04:34:51 PM      IN       inV       %in                   DEVICE
04:34:53 PM       0      1.10     33.87           atk0110-acpi-0
04:34:53 PM       1      3.25     42.12           atk0110-acpi-0
04:34:53 PM       2      5.02     51.70           atk0110-acpi-0
04:34:53 PM       3     12.20     55.44           atk0110-acpi-0

04:34:51 PM kbhugfree kbhugused  %hugused
04:34:53 PM         0         0      0.00

04:34:51 PM     CPU    wghMHz
04:34:53 PM     all   1596.00
04:34:53 PM       0   1596.00
04:34:53 PM       1   1596.00
04:34:53 PM       2   1596.00
04:34:53 PM       3   1596.00

04:34:53 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:34:55 PM     all      3.26      0.00      1.13      0.00      0.00      0.00      0.00      0.00     95.61
04:34:55 PM       0      0.50      0.00      0.00      0.00      0.00      0.00      0.00      0.00     99.50
04:34:55 PM       1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00    100.00
04:34:55 PM       2      3.50      0.00      0.50      0.00      0.00      0.00      0.00      0.00     96.00
04:34:55 PM       3      9.00      0.00      4.00      0.00      0.00      0.00      0.00      0.00     87.00

04:34:53 PM    proc/s   cswch/s
04:34:55 PM      0.00   2015.00

04:34:53 PM      INTR    intr/s
04:34:55 PM       sum    620.50
04:34:55 PM         0      0.00
04:34:55 PM         1      0.00
04:34:55 PM         2      0.00
04:34:55 PM         3      0.00
04:34:55 PM         4      0.00
04:34:55 PM         5      0.00
04:34:55 PM         6      0.00
04:34:55 PM         7      0.00
04:34:55 PM         8      0.00
04:34:55 PM         9      0.00
04:34:55 PM        10      0.00
04:34:55 PM        11      0.00
04:34:55 PM        12      0.00
04:34:55 PM        13      0.00
04:34:55 PM        14      0.00
04:34:55 PM        15      0.00
04:34:55 PM        16      1.00
04:34:55 PM        17      2.50
04:34:55 PM        18      0.00
04:34:55 PM        19      0.00
04:34:55 PM        20      0.00
04:34:55 PM        21      0.00
04:34:55 PM        22      0.00
04:34:55 PM        23      0.50
04:34:55 PM        24      0.00
04:34:55 PM        25      0.00
04:34:55 PM        26      0.00
04:34:55 PM        27      0.00
04:34:55 PM        28      0.00
04:34:55 PM        29      0.00
04:34:55 PM        30      0.00
04:34:55 PM        31      0.00
04:34:55 PM        32      0.00
04:34:55 PM        33      0.00
04:34:55 PM        34      0.00
04:34:55 PM        35      0.00
04:34:55 PM        36      0.00
04:34:55 PM        37      0.00
04:34:55 PM        38      0.00
04:34:55 PM        39      0.00
04:34:55 PM        40      0.00
04:34:55 PM        41      0.00
04:34:55 PM        42      0.00
04:34:55 PM        43      0.00
04:34:55 PM        44     12.00
04:34:55 PM        45      1.00
04:34:55 PM        46      0.00
04:34:55 PM        47      0.00
04:34:55 PM        48      0.00
04:34:55 PM        49      0.00
04:34:55 PM        50      0.00
04:34:55 PM        51      0.00
04:34:55 PM        52      0.00
04:34:55 PM        53      0.00
04:34:55 PM        54      0.00
04:34:55 PM        55      0.00
04:34:55 PM        56      0.00
04:34:55 PM        57      0.00
04:34:55 PM        58      0.00
04:34:55 PM        59      0.00
04:34:55 PM        60      0.00
04:34:55 PM        61      0.00
04:34:55 PM        62      0.00
04:34:55 PM        63      0.00
04:34:55 PM        64      0.00
04:34:55 PM        65      0.00
04:34:55 PM        66      0.00
04:34:55 PM        67      0.00
04:34:55 PM        68      0.00
04:34:55 PM        69      0.00
04:34:55 PM        70      0.00
04:34:55 PM        71      0.00
04:34:55 PM        72      0.00
04:34:55 PM        73      0.00
04:34:55 PM        74      0.00
04:34:55 PM        75      0.00
04:34:55 PM        76      0.00
04:34:55 PM        77      0.00
04:34:55 PM        78      0.00
04:34:55 PM        79      0.00
04:34:55 PM        80      0.00
04:34:55 PM        81      0.00
04:34:55 PM        82      0.00
04:34:55 PM        83      0.00
04:34:55 PM        84      0.00
04:34:55 PM        85      0.00
04:34:55 PM        86      0.00
04:34:55 PM        87      0.00
04:34:55 PM        88      0.00
04:34:55 PM        89      0.00
04:34:55 PM        90      0.00
04:34:55 PM        91      0.00
04:34:55 PM        92      0.00
04:34:55 PM        93      0.00
04:34:55 PM        94      0.00
04:34:55 PM        95      0.00
04:34:55 PM        96      0.00
04:34:55 PM        97      0.00
04:34:55 PM        98      0.00
04:34:55 PM        99      0.00
04:34:55 PM       100      0.00
04:34:55 PM       101      0.00
04:34:55 PM       102      0.00
04:34:55 PM       103      0.00
04:34:55 PM       104      0.00
04:34:55 PM       105      0.00
04:34:55 PM       106      0.00
04:34:55 PM       107      0.00
04:34:55 PM       108      0.00
04:34:55 PM       109      0.00
04:34:55 PM       110      0.00
04:34:55 PM       111      0.00
04:34:55 PM       112      0.00
04:34:55 PM       113      0.00
04:34:55 PM       114      0.00
04:34:55 PM       115      0.00
04:34:55 PM       116      0.00
04:34:55 PM       117      0.00
04:34:55 PM       118      0.00
04:34:55 PM       119      0.00
04:34:55 PM       120      0.00
04:34:55 PM       121      0.00
04:34:55 PM       122      0.00
04:34:55 PM       123      0.00
04:34:55 PM       124      0.00
04:34:55 PM       125      0.00
04:34:55 PM       126      0.00
04:34:55 PM       127      0.00
04:34:55 PM       128      0.00
04:34:55 PM       129      0.00
04:34:55 PM       130      0.00
04:34:55 PM       131      0.00
04:34:55 PM       132      0.00
04:34:55 PM       133      0.00
04:34:55 PM       134      0.00
04:34:55 PM       135      0.00
04:34:55 PM       136      0.00
04:34:55 PM       137      0.00
04:34:55 PM       138      0.00
04:34:55 PM       139      0.00
04:34:55 PM       140      0.00
04:34:55 PM       141      0.00
04:34:55 PM       142      0.00
04:34:55 PM       143      0.00
04:34:55 PM       144      0.00
04:34:55 PM       145      0.00
04:34:55 PM       146      0.00
04:34:55 PM       147      0.00
04:34:55 PM       148      0.00
04:34:55 PM       149      0.00
04:34:55 PM       150      0.00
04:34:55 PM       151      0.00
04:34:55 PM       152      0.00
04:34:55 PM       153      0.00
04:34:55 PM       154      0.00
04:34:55 PM       155      0.00
04:34:55 PM       156      0.00
04:34:55 PM       157      0.00
04:34:55 PM       158      0.00
04:34:55 PM       159      0.00
04:34:55 PM       160      0.00
04:34:55 PM       161      0.00
04:34:55 PM       162      0.00
04:34:55 PM       163      0.00
04:34:55 PM       164      0.00
04:34:55 PM       165      0.00
04:34:55 PM       166      0.00
04:34:55 PM       167      0.00
04:34:55 PM       168      0.00
04:34:55 PM       169      0.00
04:34:55 PM       170      0.00
04:34:55 PM       171      0.00
04:34:55 PM       172      0.00
04:34:55 PM       173      0.00
04:34:55 PM       174      0.00
04:34:55 PM       175      0.00
04:34:55 PM       176      0.00
04:34:55 PM       177      0.00
04:34:55 PM       178      0.00
04:34:55 PM       179      0.00
04:34:55 PM       180      0.00
04:34:55 PM       181      0.00
04:34:55 PM       182      0.00
04:34:55 PM       183      0.00
04:34:55 PM       184      0.00
04:34:55 PM       185      0.00
04:34:55 PM       186      0.00
04:34:55 PM       187      0.00
04:34:55 PM       188      0.00
04:34:55 PM       189      0.00
04:34:55 PM       190      0.00
04:34:55 PM       191      0.00
04:34:55 PM       192      0.00
04:34:55 PM       193      0.00
04:34:55 PM       194      0.00
04:34:55 PM       195      0.00
04:34:55 PM       196      0.00
04:34:55 PM       197      0.00
04:34:55 PM       198      0.00
04:34:55 PM       199      0.00
04:34:55 PM       200      0.00
04:34:55 PM       201      0.00
04:34:55 PM       202      0.00
04:34:55 PM       203      0.00
04:34:55 PM       204      0.00
04:34:55 PM       205      0.00
04:34:55 PM       206      0.00
04:34:55 PM       207      0.00
04:34:55 PM       208      0.00
04:34:55 PM       209      0.00
04:34:55 PM       210      0.00
04:34:55 PM       211      0.00
04:34:55 PM       212      0.00
04:34:55 PM       213      0.00
04:34:55 PM       214      0.00
04:34:55 PM       215      0.00
04:34:55 PM       216      0.00
04:34:55 PM       217      0.00
04:34:55 PM       218      0.00
04:34:55 PM       219      0.00
04:34:55 PM       220      0.00
04:34:55 PM       221      0.00
04:34:55 PM       222      0.00
04:34:55 PM       223      0.00
04:34:55 PM       224      0.00
04:34:55 PM       225      0.00
04:34:55 PM       226      0.00
04:34:55 PM       227      0.00
04:34:55 PM       228      0.00
04:34:55 PM       229      0.00
04:34:55 PM       230      0.00
04:34:55 PM       231      0.00
04:34:55 PM       232      0.00
04:34:55 PM       233      0.00
04:34:55 PM       234      0.00
04:34:55 PM       235      0.00
04:34:55 PM       236      0.00
04:34:55 PM       237      0.00
04:34:55 PM       238      0.00
04:34:55 PM       239      0.00
04:34:55 PM       240      0.00
04:34:55 PM       241      0.00
04:34:55 PM       242      0.00
04:34:55 PM       243      0.00
04:34:55 PM       244      0.00
04:34:55 PM       245      0.00
04:34:55 PM       246      0.00
04:34:55 PM       247      0.00
04:34:55 PM       248      0.00
04:34:55 PM       249      0.00
04:34:55 PM       250      0.00
04:34:55 PM       251      0.00
04:34:55 PM       252      0.00
04:34:55 PM       253      0.00
04:34:55 PM       254      0.00
04:34:55 PM       255      0.00

04:34:53 PM  pswpin/s pswpout/s
04:34:55 PM      0.00      0.00

04:34:53 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:34:55 PM      0.00      0.00     47.50      0.00    279.00      0.00      0.00      0.00      0.00

04:34:53 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00

04:34:53 PM   frmpg/s   bufpg/s   campg/s
04:34:55 PM      0.00      0.00      1.50

04:34:53 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:34:55 PM     81328   8114232     99.01       176   5018552   4689464      8.34   4225368   2971828

04:34:53 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:34:55 PM  48016452       948      0.00       224     23.63

04:34:53 PM dentunusd   file-nr  inode-nr    pty-nr
04:34:55 PM    158622      9888    134011       110

04:34:53 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:34:55 PM         0       475      0.00      0.01      0.05         0

04:34:53 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:34:55 PM    dev8-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:55 PM   dev8-16      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:55 PM    dev9-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:55 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:34:55 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:55 PM      eth0      6.50      7.00      0.86      8.93      0.00      0.00      0.00
04:34:55 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:55 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:34:53 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:34:55 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:55 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:55 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:55 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:34:55 PM       882        32         9         0         0         0

04:34:53 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:34:55 PM     13.00      0.00     13.00     13.50      0.00      0.00      0.00      0.00

04:34:53 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM  active/s passive/s    iseg/s    oseg/s
04:34:55 PM      0.00      0.00      6.50      6.50

04:34:53 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00

04:34:53 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:34:55 PM      6.50      7.00      0.00      0.00

04:34:53 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:34:55 PM         2         2         0         0

04:34:53 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:34:55 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:53 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:34:55 PM      0.00      0.00      0.00      0.00

04:34:53 PM     CPU       MHz
04:34:55 PM     all   1596.00
04:34:55 PM       0   1596.00
04:34:55 PM       1   1596.00
04:34:55 PM       2   1596.00
04:34:55 PM       3   1596.00

04:34:53 PM     FAN       rpm      drpm                   DEVICE
04:34:55 PM       1   2576.00   1976.00           atk0110-acpi-0
04:34:55 PM       2      0.00   -800.00           atk0110-acpi-0
04:34:55 PM       3      0.00   -800.00           atk0110-acpi-0
04:34:55 PM       4      0.00   -800.00           atk0110-acpi-0

04:34:53 PM    TEMP      degC     %temp                   DEVICE
04:34:55 PM       1     47.00     78.33           atk0110-acpi-0
04:34:55 PM       2     43.00     95.56           atk0110-acpi-0

04:34:53 PM      IN       inV       %in                   DEVICE
04:34:55 PM       0      1.10     33.87           atk0110-acpi-0
04:34:55 PM       1      3.25     42.12           atk0110-acpi-0
04:34:55 PM       2      5.02     51.70           atk0110-acpi-0
04:34:55 PM       3     12.20     55.44           atk0110-acpi-0

04:34:53 PM kbhugfree kbhugused  %hugused
04:34:55 PM         0         0      0.00

04:34:53 PM     CPU    wghMHz
04:34:55 PM     all   1596.00
04:34:55 PM       0   1596.00
04:34:55 PM       1   1596.00
04:34:55 PM       2   1596.00
04:34:55 PM       3   1596.00

04:34:55 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:34:57 PM     all      2.48      0.00      0.87      0.00      0.00      0.00      0.00      0.00     96.65
04:34:57 PM       0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00    100.00
04:34:57 PM       1      5.91      0.00      0.99      0.00      0.00      0.00      0.00      0.00     93.10
04:34:57 PM       2      0.50      0.00      1.50      0.00      0.00      0.00      0.00      0.00     98.00
04:34:57 PM       3      3.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     95.50

04:34:55 PM    proc/s   cswch/s
04:34:57 PM      0.00   2092.00

04:34:55 PM      INTR    intr/s
04:34:57 PM       sum    678.00
04:34:57 PM         0      0.00
04:34:57 PM         1      0.00
04:34:57 PM         2      0.00
04:34:57 PM         3      0.00
04:34:57 PM         4      0.00
04:34:57 PM         5      0.00
04:34:57 PM         6      0.00
04:34:57 PM         7      0.00
04:34:57 PM         8      0.00
04:34:57 PM         9      0.00
04:34:57 PM        10      0.00
04:34:57 PM        11      0.00
04:34:57 PM        12      0.00
04:34:57 PM        13      0.00
04:34:57 PM        14      0.00
04:34:57 PM        15      0.00
04:34:57 PM        16      1.00
04:34:57 PM        17      2.50
04:34:57 PM        18      0.00
04:34:57 PM        19      0.00
04:34:57 PM        20      0.00
04:34:57 PM        21      0.00
04:34:57 PM        22      0.00
04:34:57 PM        23      0.50
04:34:57 PM        24      0.00
04:34:57 PM        25      0.00
04:34:57 PM        26      0.00
04:34:57 PM        27      0.00
04:34:57 PM        28      0.00
04:34:57 PM        29      0.00
04:34:57 PM        30      0.00
04:34:57 PM        31      0.00
04:34:57 PM        32      0.00
04:34:57 PM        33      0.00
04:34:57 PM        34      0.00
04:34:57 PM        35      0.00
04:34:57 PM        36      0.00
04:34:57 PM        37      0.00
04:34:57 PM        38      0.00
04:34:57 PM        39      0.00
04:34:57 PM        40      0.00
04:34:57 PM        41      0.00
04:34:57 PM        42      0.00
04:34:57 PM        43      0.00
04:34:57 PM        44     11.50
04:34:57 PM        45      1.00
04:34:57 PM        46      0.00
04:34:57 PM        47      0.00
04:34:57 PM        48      0.00
04:34:57 PM        49      0.00
04:34:57 PM        50      0.00
04:34:57 PM        51      0.00
04:34:57 PM        52      0.00
04:34:57 PM        53      0.00
04:34:57 PM        54      0.00
04:34:57 PM        55      0.00
04:34:57 PM        56      0.00
04:34:57 PM        57      0.00
04:34:57 PM        58      0.00
04:34:57 PM        59      0.00
04:34:57 PM        60      0.00
04:34:57 PM        61      0.00
04:34:57 PM        62      0.00
04:34:57 PM        63      0.00
04:34:57 PM        64      0.00
04:34:57 PM        65      0.00
04:34:57 PM        66      0.00
04:34:57 PM        67      0.00
04:34:57 PM        68      0.00
04:34:57 PM        69      0.00
04:34:57 PM        70      0.00
04:34:57 PM        71      0.00
04:34:57 PM        72      0.00
04:34:57 PM        73      0.00
04:34:57 PM        74      0.00
04:34:57 PM        75      0.00
04:34:57 PM        76      0.00
04:34:57 PM        77      0.00
04:34:57 PM        78      0.00
04:34:57 PM        79      0.00
04:34:57 PM        80      0.00
04:34:57 PM        81      0.00
04:34:57 PM        82      0.00
04:34:57 PM        83      0.00
04:34:57 PM        84      0.00
04:34:57 PM        85      0.00
04:34:57 PM        86      0.00
04:34:57 PM        87      0.00
04:34:57 PM        88      0.00
04:34:57 PM        89      0.00
04:34:57 PM        90      0.00
04:34:57 PM        91      0.00
04:34:57 PM        92      0.00
04:34:57 PM        93      0.00
04:34:57 PM        94      0.00
04:34:57 PM        95      0.00
04:34:57 PM        96      0.00
04:34:57 PM        97      0.00
04:34:57 PM        98      0.00
04:34:57 PM        99      0.00
04:34:57 PM       100      0.00
04:34:57 PM       101      0.00
04:34:57 PM       102      0.00
04:34:57 PM       103      0.00
04:34:57 PM       104      0.00
04:34:57 PM       105      0.00
04:34:57 PM       106      0.00
04:34:57 PM       107      0.00
04:34:57 PM       108      0.00
04:34:57 PM       109      0.00
04:34:57 PM       110      0.00
04:34:57 PM       111      0.00
04:34:57 PM       112      0.00
04:34:57 PM       113      0.00
04:34:57 PM       114      0.00
04:34:57 PM       115      0.00
04:34:57 PM       116      0.00
04:34:57 PM       117      0.00
04:34:57 PM       118      0.00
04:34:57 PM       119      0.00
04:34:57 PM       120      0.00
04:34:57 PM       121      0.00
04:34:57 PM       122      0.00
04:34:57 PM       123      0.00
04:34:57 PM       124      0.00
04:34:57 PM       125      0.00
04:34:57 PM       126      0.00
04:34:57 PM       127      0.00
04:34:57 PM       128      0.00
04:34:57 PM       129      0.00
04:34:57 PM       130      0.00
04:34:57 PM       131      0.00
04:34:57 PM       132      0.00
04:34:57 PM       133      0.00
04:34:57 PM       134      0.00
04:34:57 PM       135      0.00
04:34:57 PM       136      0.00
04:34:57 PM       137      0.00
04:34:57 PM       138      0.00
04:34:57 PM       139      0.00
04:34:57 PM       140      0.00
04:34:57 PM       141      0.00
04:34:57 PM       142      0.00
04:34:57 PM       143      0.00
04:34:57 PM       144      0.00
04:34:57 PM       145      0.00
04:34:57 PM       146      0.00
04:34:57 PM       147      0.00
04:34:57 PM       148      0.00
04:34:57 PM       149      0.00
04:34:57 PM       150      0.00
04:34:57 PM       151      0.00
04:34:57 PM       152      0.00
04:34:57 PM       153      0.00
04:34:57 PM       154      0.00
04:34:57 PM       155      0.00
04:34:57 PM       156      0.00
04:34:57 PM       157      0.00
04:34:57 PM       158      0.00
04:34:57 PM       159      0.00
04:34:57 PM       160      0.00
04:34:57 PM       161      0.00
04:34:57 PM       162      0.00
04:34:57 PM       163      0.00
04:34:57 PM       164      0.00
04:34:57 PM       165      0.00
04:34:57 PM       166      0.00
04:34:57 PM       167      0.00
04:34:57 PM       168      0.00
04:34:57 PM       169      0.00
04:34:57 PM       170      0.00
04:34:57 PM       171      0.00
04:34:57 PM       172      0.00
04:34:57 PM       173      0.00
04:34:57 PM       174      0.00
04:34:57 PM       175      0.00
04:34:57 PM       176      0.00
04:34:57 PM       177      0.00
04:34:57 PM       178      0.00
04:34:57 PM       179      0.00
04:34:57 PM       180      0.00
04:34:57 PM       181      0.00
04:34:57 PM       182      0.00
04:34:57 PM       183      0.00
04:34:57 PM       184      0.00
04:34:57 PM       185      0.00
04:34:57 PM       186      0.00
04:34:57 PM       187      0.00
04:34:57 PM       188      0.00
04:34:57 PM       189      0.00
04:34:57 PM       190      0.00
04:34:57 PM       191      0.00
04:34:57 PM       192      0.00
04:34:57 PM       193      0.00
04:34:57 PM       194      0.00
04:34:57 PM       195      0.00
04:34:57 PM       196      0.00
04:34:57 PM       197      0.00
04:34:57 PM       198      0.00
04:34:57 PM       199      0.00
04:34:57 PM       200      0.00
04:34:57 PM       201      0.00
04:34:57 PM       202      0.00
04:34:57 PM       203      0.00
04:34:57 PM       204      0.00
04:34:57 PM       205      0.00
04:34:57 PM       206      0.00
04:34:57 PM       207      0.00
04:34:57 PM       208      0.00
04:34:57 PM       209      0.00
04:34:57 PM       210      0.00
04:34:57 PM       211      0.00
04:34:57 PM       212      0.00
04:34:57 PM       213      0.00
04:34:57 PM       214      0.00
04:34:57 PM       215      0.00
04:34:57 PM       216      0.00
04:34:57 PM       217      0.00
04:34:57 PM       218      0.00
04:34:57 PM       219      0.00
04:34:57 PM       220      0.00
04:34:57 PM       221      0.00
04:34:57 PM       222      0.00
04:34:57 PM       223      0.00
04:34:57 PM       224      0.00
04:34:57 PM       225      0.00
04:34:57 PM       226      0.00
04:34:57 PM       227      0.00
04:34:57 PM       228      0.00
04:34:57 PM       229      0.00
04:34:57 PM       230      0.00
04:34:57 PM       231      0.00
04:34:57 PM       232      0.00
04:34:57 PM       233      0.00
04:34:57 PM       234      0.00
04:34:57 PM       235      0.00
04:34:57 PM       236      0.00
04:34:57 PM       237      0.00
04:34:57 PM       238      0.00
04:34:57 PM       239      0.00
04:34:57 PM       240      0.00
04:34:57 PM       241      0.00
04:34:57 PM       242      0.00
04:34:57 PM       243      0.00
04:34:57 PM       244      0.00
04:34:57 PM       245      0.00
04:34:57 PM       246      0.00
04:34:57 PM       247      0.00
04:34:57 PM       248      0.00
04:34:57 PM       249      0.00
04:34:57 PM       250      0.00
04:34:57 PM       251      0.00
04:34:57 PM       252      0.00
04:34:57 PM       253      0.00
04:34:57 PM       254      0.00
04:34:57 PM       255      0.00

04:34:55 PM  pswpin/s pswpout/s
04:34:57 PM      0.00      0.00

04:34:55 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:34:57 PM      0.00      0.00     32.00      0.00    286.00      0.00      0.00      0.00      0.00

04:34:55 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00

04:34:55 PM   frmpg/s   bufpg/s   campg/s
04:34:57 PM      0.00      0.00      2.00

04:34:55 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:34:57 PM     81328   8114232     99.01       176   5018568   4689464      8.34   4225380   2971844

04:34:55 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:34:57 PM  48016452       948      0.00       224     23.63

04:34:55 PM dentunusd   file-nr  inode-nr    pty-nr
04:34:57 PM    158622      9888    134011       110

04:34:55 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:34:57 PM         0       475      0.00      0.01      0.05         0

04:34:55 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:34:57 PM    dev8-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:57 PM   dev8-16      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:57 PM    dev9-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:57 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:34:57 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:57 PM      eth0      6.50      6.50      0.86      8.94      0.00      0.00      0.00
04:34:57 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:57 PM      tun0      6.50      6.50      0.33      8.43      0.00      0.00      0.00

04:34:55 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:34:57 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:57 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:57 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:57 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:34:57 PM       882        32         9         0         0         0

04:34:55 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:34:57 PM     13.00      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:34:55 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM  active/s passive/s    iseg/s    oseg/s
04:34:57 PM      0.00      0.00      6.50      6.50

04:34:55 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00

04:34:55 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:34:57 PM      6.50      6.50      0.00      0.00

04:34:55 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:34:57 PM         2         2         0         0

04:34:55 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:34:57 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:55 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:34:57 PM      0.00      0.00      0.00      0.00

04:34:55 PM     CPU       MHz
04:34:57 PM     all   1596.00
04:34:57 PM       0   1596.00
04:34:57 PM       1   1596.00
04:34:57 PM       2   1596.00
04:34:57 PM       3   1596.00

04:34:55 PM     FAN       rpm      drpm                   DEVICE
04:34:57 PM       1   2596.00   1996.00           atk0110-acpi-0
04:34:57 PM       2      0.00   -800.00           atk0110-acpi-0
04:34:57 PM       3      0.00   -800.00           atk0110-acpi-0
04:34:57 PM       4      0.00   -800.00           atk0110-acpi-0

04:34:55 PM    TEMP      degC     %temp                   DEVICE
04:34:57 PM       1     47.00     78.33           atk0110-acpi-0
04:34:57 PM       2     43.00     95.56           atk0110-acpi-0

04:34:55 PM      IN       inV       %in                   DEVICE
04:34:57 PM       0      1.10     33.87           atk0110-acpi-0
04:34:57 PM       1      3.25     42.12           atk0110-acpi-0
04:34:57 PM       2      5.02     51.70           atk0110-acpi-0
04:34:57 PM       3     12.20     55.44           atk0110-acpi-0

04:34:55 PM kbhugfree kbhugused  %hugused
04:34:57 PM         0         0      0.00

04:34:55 PM     CPU    wghMHz
04:34:57 PM     all   1596.00
04:34:57 PM       0   1596.00
04:34:57 PM       1   1596.00
04:34:57 PM       2   1596.00
04:34:57 PM       3   1596.00

04:34:57 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:34:59 PM     all      3.25      0.00      0.88      0.00      0.00      0.00      0.00      0.00     95.88
04:34:59 PM       0      0.50      0.00      0.00      0.00      0.00      0.00      0.00      0.00     99.50
04:34:59 PM       1     10.50      0.00      2.00      0.00      0.00      0.00      0.00      0.00     87.50
04:34:59 PM       2      1.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     98.50
04:34:59 PM       3      1.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     98.00

04:34:57 PM    proc/s   cswch/s
04:34:59 PM      0.00   2091.00

04:34:57 PM      INTR    intr/s
04:34:59 PM       sum    701.50
04:34:59 PM         0      0.00
04:34:59 PM         1      0.00
04:34:59 PM         2      0.00
04:34:59 PM         3      0.00
04:34:59 PM         4      0.00
04:34:59 PM         5      0.00
04:34:59 PM         6      0.00
04:34:59 PM         7      0.00
04:34:59 PM         8      0.00
04:34:59 PM         9      0.00
04:34:59 PM        10      0.00
04:34:59 PM        11      0.00
04:34:59 PM        12      0.00
04:34:59 PM        13      0.00
04:34:59 PM        14      0.00
04:34:59 PM        15      0.00
04:34:59 PM        16      1.00
04:34:59 PM        17      2.50
04:34:59 PM        18      0.00
04:34:59 PM        19     14.00
04:34:59 PM        20      0.00
04:34:59 PM        21      0.00
04:34:59 PM        22      0.00
04:34:59 PM        23      0.50
04:34:59 PM        24      0.00
04:34:59 PM        25      0.00
04:34:59 PM        26      0.00
04:34:59 PM        27      0.00
04:34:59 PM        28      0.00
04:34:59 PM        29      0.00
04:34:59 PM        30      0.00
04:34:59 PM        31      0.00
04:34:59 PM        32      0.00
04:34:59 PM        33      0.00
04:34:59 PM        34      0.00
04:34:59 PM        35      0.00
04:34:59 PM        36      0.00
04:34:59 PM        37      0.00
04:34:59 PM        38      0.00
04:34:59 PM        39      0.00
04:34:59 PM        40      0.00
04:34:59 PM        41      0.00
04:34:59 PM        42      0.00
04:34:59 PM        43      0.00
04:34:59 PM        44     12.00
04:34:59 PM        45      1.00
04:34:59 PM        46      0.00
04:34:59 PM        47      0.00
04:34:59 PM        48      0.00
04:34:59 PM        49      0.00
04:34:59 PM        50      0.00
04:34:59 PM        51      0.00
04:34:59 PM        52      0.00
04:34:59 PM        53      0.00
04:34:59 PM        54      0.00
04:34:59 PM        55      0.00
04:34:59 PM        56      0.00
04:34:59 PM        57      0.00
04:34:59 PM        58      0.00
04:34:59 PM        59      0.00
04:34:59 PM        60      0.00
04:34:59 PM        61      0.00
04:34:59 PM        62      0.00
04:34:59 PM        63      0.00
04:34:59 PM        64      0.00
04:34:59 PM        65      0.00
04:34:59 PM        66      0.00
04:34:59 PM        67      0.00
04:34:59 PM        68      0.00
04:34:59 PM        69      0.00
04:34:59 PM        70      0.00
04:34:59 PM        71      0.00
04:34:59 PM        72      0.00
04:34:59 PM        73      0.00
04:34:59 PM        74      0.00
04:34:59 PM        75      0.00
04:34:59 PM        76      0.00
04:34:59 PM        77      0.00
04:34:59 PM        78      0.00
04:34:59 PM        79      0.00
04:34:59 PM        80      0.00
04:34:59 PM        81      0.00
04:34:59 PM        82      0.00
04:34:59 PM        83      0.00
04:34:59 PM        84      0.00
04:34:59 PM        85      0.00
04:34:59 PM        86      0.00
04:34:59 PM        87      0.00
04:34:59 PM        88      0.00
04:34:59 PM        89      0.00
04:34:59 PM        90      0.00
04:34:59 PM        91      0.00
04:34:59 PM        92      0.00
04:34:59 PM        93      0.00
04:34:59 PM        94      0.00
04:34:59 PM        95      0.00
04:34:59 PM        96      0.00
04:34:59 PM        97      0.00
04:34:59 PM        98      0.00
04:34:59 PM        99      0.00
04:34:59 PM       100      0.00
04:34:59 PM       101      0.00
04:34:59 PM       102      0.00
04:34:59 PM       103      0.00
04:34:59 PM       104      0.00
04:34:59 PM       105      0.00
04:34:59 PM       106      0.00
04:34:59 PM       107      0.00
04:34:59 PM       108      0.00
04:34:59 PM       109      0.00
04:34:59 PM       110      0.00
04:34:59 PM       111      0.00
04:34:59 PM       112      0.00
04:34:59 PM       113      0.00
04:34:59 PM       114      0.00
04:34:59 PM       115      0.00
04:34:59 PM       116      0.00
04:34:59 PM       117      0.00
04:34:59 PM       118      0.00
04:34:59 PM       119      0.00
04:34:59 PM       120      0.00
04:34:59 PM       121      0.00
04:34:59 PM       122      0.00
04:34:59 PM       123      0.00
04:34:59 PM       124      0.00
04:34:59 PM       125      0.00
04:34:59 PM       126      0.00
04:34:59 PM       127      0.00
04:34:59 PM       128      0.00
04:34:59 PM       129      0.00
04:34:59 PM       130      0.00
04:34:59 PM       131      0.00
04:34:59 PM       132      0.00
04:34:59 PM       133      0.00
04:34:59 PM       134      0.00
04:34:59 PM       135      0.00
04:34:59 PM       136      0.00
04:34:59 PM       137      0.00
04:34:59 PM       138      0.00
04:34:59 PM       139      0.00
04:34:59 PM       140      0.00
04:34:59 PM       141      0.00
04:34:59 PM       142      0.00
04:34:59 PM       143      0.00
04:34:59 PM       144      0.00
04:34:59 PM       145      0.00
04:34:59 PM       146      0.00
04:34:59 PM       147      0.00
04:34:59 PM       148      0.00
04:34:59 PM       149      0.00
04:34:59 PM       150      0.00
04:34:59 PM       151      0.00
04:34:59 PM       152      0.00
04:34:59 PM       153      0.00
04:34:59 PM       154      0.00
04:34:59 PM       155      0.00
04:34:59 PM       156      0.00
04:34:59 PM       157      0.00
04:34:59 PM       158      0.00
04:34:59 PM       159      0.00
04:34:59 PM       160      0.00
04:34:59 PM       161      0.00
04:34:59 PM       162      0.00
04:34:59 PM       163      0.00
04:34:59 PM       164      0.00
04:34:59 PM       165      0.00
04:34:59 PM       166      0.00
04:34:59 PM       167      0.00
04:34:59 PM       168      0.00
04:34:59 PM       169      0.00
04:34:59 PM       170      0.00
04:34:59 PM       171      0.00
04:34:59 PM       172      0.00
04:34:59 PM       173      0.00
04:34:59 PM       174      0.00
04:34:59 PM       175      0.00
04:34:59 PM       176      0.00
04:34:59 PM       177      0.00
04:34:59 PM       178      0.00
04:34:59 PM       179      0.00
04:34:59 PM       180      0.00
04:34:59 PM       181      0.00
04:34:59 PM       182      0.00
04:34:59 PM       183      0.00
04:34:59 PM       184      0.00
04:34:59 PM       185      0.00
04:34:59 PM       186      0.00
04:34:59 PM       187      0.00
04:34:59 PM       188      0.00
04:34:59 PM       189      0.00
04:34:59 PM       190      0.00
04:34:59 PM       191      0.00
04:34:59 PM       192      0.00
04:34:59 PM       193      0.00
04:34:59 PM       194      0.00
04:34:59 PM       195      0.00
04:34:59 PM       196      0.00
04:34:59 PM       197      0.00
04:34:59 PM       198      0.00
04:34:59 PM       199      0.00
04:34:59 PM       200      0.00
04:34:59 PM       201      0.00
04:34:59 PM       202      0.00
04:34:59 PM       203      0.00
04:34:59 PM       204      0.00
04:34:59 PM       205      0.00
04:34:59 PM       206      0.00
04:34:59 PM       207      0.00
04:34:59 PM       208      0.00
04:34:59 PM       209      0.00
04:34:59 PM       210      0.00
04:34:59 PM       211      0.00
04:34:59 PM       212      0.00
04:34:59 PM       213      0.00
04:34:59 PM       214      0.00
04:34:59 PM       215      0.00
04:34:59 PM       216      0.00
04:34:59 PM       217      0.00
04:34:59 PM       218      0.00
04:34:59 PM       219      0.00
04:34:59 PM       220      0.00
04:34:59 PM       221      0.00
04:34:59 PM       222      0.00
04:34:59 PM       223      0.00
04:34:59 PM       224      0.00
04:34:59 PM       225      0.00
04:34:59 PM       226      0.00
04:34:59 PM       227      0.00
04:34:59 PM       228      0.00
04:34:59 PM       229      0.00
04:34:59 PM       230      0.00
04:34:59 PM       231      0.00
04:34:59 PM       232      0.00
04:34:59 PM       233      0.00
04:34:59 PM       234      0.00
04:34:59 PM       235      0.00
04:34:59 PM       236      0.00
04:34:59 PM       237      0.00
04:34:59 PM       238      0.00
04:34:59 PM       239      0.00
04:34:59 PM       240      0.00
04:34:59 PM       241      0.00
04:34:59 PM       242      0.00
04:34:59 PM       243      0.00
04:34:59 PM       244      0.00
04:34:59 PM       245      0.00
04:34:59 PM       246      0.00
04:34:59 PM       247      0.00
04:34:59 PM       248      0.00
04:34:59 PM       249      0.00
04:34:59 PM       250      0.00
04:34:59 PM       251      0.00
04:34:59 PM       252      0.00
04:34:59 PM       253      0.00
04:34:59 PM       254      0.00
04:34:59 PM       255      0.00

04:34:57 PM  pswpin/s pswpout/s
04:34:59 PM      0.00      0.00

04:34:57 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:34:59 PM      0.00     34.00     32.00      0.00    283.50      0.00      0.00      0.00      0.00

04:34:57 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:34:59 PM     14.50      0.00     14.50      0.00    172.00

04:34:57 PM   frmpg/s   bufpg/s   campg/s
04:34:59 PM      0.00      0.00      2.00

04:34:57 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:34:59 PM     81328   8114232     99.01       176   5018584   4689464      8.34   4225380   2971852

04:34:57 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:34:59 PM  48016452       948      0.00       224     23.63

04:34:57 PM dentunusd   file-nr  inode-nr    pty-nr
04:34:59 PM    158622      9888    134011       110

04:34:57 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:34:59 PM         0       475      0.00      0.01      0.05         0

04:34:57 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:34:59 PM    dev8-0      5.00      0.00     60.00     12.00      0.03      5.00      5.00      2.50
04:34:59 PM   dev8-16      5.00      0.00     60.00     12.00      0.02      4.00      4.00      2.00
04:34:59 PM    dev9-0      4.50      0.00     52.00     11.56      0.00      0.00      0.00      0.00
04:34:59 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:34:59 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:59 PM      eth0      6.00      7.50      0.84      9.01      0.00      0.00      0.00
04:34:59 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:59 PM      tun0      5.50      7.00      0.30      8.43      0.00      0.00      0.00

04:34:57 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:34:59 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:59 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:59 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:34:59 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:34:59 PM       882        32         9         0         0         0

04:34:57 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:34:59 PM     11.50      0.00     11.50     14.50      0.00      0.00      0.00      0.00

04:34:57 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM  active/s passive/s    iseg/s    oseg/s
04:34:59 PM      0.00      0.00      6.00      7.50

04:34:57 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00

04:34:57 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:34:59 PM      5.50      7.00      0.00      0.00

04:34:57 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:34:59 PM         2         2         0         0

04:34:57 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:34:59 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:57 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:34:59 PM      0.00      0.00      0.00      0.00

04:34:57 PM     CPU       MHz
04:34:59 PM     all   1596.00
04:34:59 PM       0   1596.00
04:34:59 PM       1   1596.00
04:34:59 PM       2   1596.00
04:34:59 PM       3   1596.00

04:34:57 PM     FAN       rpm      drpm                   DEVICE
04:34:59 PM       1   2596.00   1996.00           atk0110-acpi-0
04:34:59 PM       2      0.00   -800.00           atk0110-acpi-0
04:34:59 PM       3      0.00   -800.00           atk0110-acpi-0
04:34:59 PM       4      0.00   -800.00           atk0110-acpi-0

04:34:57 PM    TEMP      degC     %temp                   DEVICE
04:34:59 PM       1     47.00     78.33           atk0110-acpi-0
04:34:59 PM       2     43.00     95.56           atk0110-acpi-0

04:34:57 PM      IN       inV       %in                   DEVICE
04:34:59 PM       0      1.10     33.87           atk0110-acpi-0
04:34:59 PM       1      3.25     42.12           atk0110-acpi-0
04:34:59 PM       2      5.02     51.70           atk0110-acpi-0
04:34:59 PM       3     12.20     55.44           atk0110-acpi-0

04:34:57 PM kbhugfree kbhugused  %hugused
04:34:59 PM         0         0      0.00

04:34:57 PM     CPU    wghMHz
04:34:59 PM     all   1596.00
04:34:59 PM       0   1596.00
04:34:59 PM       1   1596.00
04:34:59 PM       2   1596.00
04:34:59 PM       3   1596.00

04:34:59 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:01 PM     all      1.63      0.00      2.13      0.00      0.00      0.00      0.00      0.00     96.25
04:35:01 PM       0      0.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     99.00
04:35:01 PM       1      5.53      0.00      3.02      0.00      0.00      0.00      0.00      0.00     91.46
04:35:01 PM       2      0.50      0.00      2.50      0.00      0.00      0.00      0.00      0.00     97.00
04:35:01 PM       3      0.50      0.00      2.00      0.00      0.00      0.00      0.00      0.00     97.50

04:34:59 PM    proc/s   cswch/s
04:35:01 PM      3.50   2192.00

04:34:59 PM      INTR    intr/s
04:35:01 PM       sum    698.00
04:35:01 PM         0      0.00
04:35:01 PM         1      0.00
04:35:01 PM         2      0.00
04:35:01 PM         3      0.00
04:35:01 PM         4      0.00
04:35:01 PM         5      0.00
04:35:01 PM         6      0.00
04:35:01 PM         7      0.00
04:35:01 PM         8      0.00
04:35:01 PM         9      0.00
04:35:01 PM        10      0.00
04:35:01 PM        11      0.00
04:35:01 PM        12      0.00
04:35:01 PM        13      0.00
04:35:01 PM        14      0.00
04:35:01 PM        15      0.00
04:35:01 PM        16      1.00
04:35:01 PM        17      2.50
04:35:01 PM        18      0.00
04:35:01 PM        19      9.00
04:35:01 PM        20      0.00
04:35:01 PM        21      0.00
04:35:01 PM        22      0.00
04:35:01 PM        23      0.50
04:35:01 PM        24      0.00
04:35:01 PM        25      0.00
04:35:01 PM        26      0.00
04:35:01 PM        27      0.00
04:35:01 PM        28      0.00
04:35:01 PM        29      0.00
04:35:01 PM        30      0.00
04:35:01 PM        31      0.00
04:35:01 PM        32      0.00
04:35:01 PM        33      0.00
04:35:01 PM        34      0.00
04:35:01 PM        35      0.00
04:35:01 PM        36      0.00
04:35:01 PM        37      0.00
04:35:01 PM        38      0.00
04:35:01 PM        39      0.00
04:35:01 PM        40      0.00
04:35:01 PM        41      0.00
04:35:01 PM        42      0.00
04:35:01 PM        43      0.00
04:35:01 PM        44     11.00
04:35:01 PM        45      1.00
04:35:01 PM        46      0.00
04:35:01 PM        47      0.00
04:35:01 PM        48      0.00
04:35:01 PM        49      0.00
04:35:01 PM        50      0.00
04:35:01 PM        51      0.00
04:35:01 PM        52      0.00
04:35:01 PM        53      0.00
04:35:01 PM        54      0.00
04:35:01 PM        55      0.00
04:35:01 PM        56      0.00
04:35:01 PM        57      0.00
04:35:01 PM        58      0.00
04:35:01 PM        59      0.00
04:35:01 PM        60      0.00
04:35:01 PM        61      0.00
04:35:01 PM        62      0.00
04:35:01 PM        63      0.00
04:35:01 PM        64      0.00
04:35:01 PM        65      0.00
04:35:01 PM        66      0.00
04:35:01 PM        67      0.00
04:35:01 PM        68      0.00
04:35:01 PM        69      0.00
04:35:01 PM        70      0.00
04:35:01 PM        71      0.00
04:35:01 PM        72      0.00
04:35:01 PM        73      0.00
04:35:01 PM        74      0.00
04:35:01 PM        75      0.00
04:35:01 PM        76      0.00
04:35:01 PM        77      0.00
04:35:01 PM        78      0.00
04:35:01 PM        79      0.00
04:35:01 PM        80      0.00
04:35:01 PM        81      0.00
04:35:01 PM        82      0.00
04:35:01 PM        83      0.00
04:35:01 PM        84      0.00
04:35:01 PM        85      0.00
04:35:01 PM        86      0.00
04:35:01 PM        87      0.00
04:35:01 PM        88      0.00
04:35:01 PM        89      0.00
04:35:01 PM        90      0.00
04:35:01 PM        91      0.00
04:35:01 PM        92      0.00
04:35:01 PM        93      0.00
04:35:01 PM        94      0.00
04:35:01 PM        95      0.00
04:35:01 PM        96      0.00
04:35:01 PM        97      0.00
04:35:01 PM        98      0.00
04:35:01 PM        99      0.00
04:35:01 PM       100      0.00
04:35:01 PM       101      0.00
04:35:01 PM       102      0.00
04:35:01 PM       103      0.00
04:35:01 PM       104      0.00
04:35:01 PM       105      0.00
04:35:01 PM       106      0.00
04:35:01 PM       107      0.00
04:35:01 PM       108      0.00
04:35:01 PM       109      0.00
04:35:01 PM       110      0.00
04:35:01 PM       111      0.00
04:35:01 PM       112      0.00
04:35:01 PM       113      0.00
04:35:01 PM       114      0.00
04:35:01 PM       115      0.00
04:35:01 PM       116      0.00
04:35:01 PM       117      0.00
04:35:01 PM       118      0.00
04:35:01 PM       119      0.00
04:35:01 PM       120      0.00
04:35:01 PM       121      0.00
04:35:01 PM       122      0.00
04:35:01 PM       123      0.00
04:35:01 PM       124      0.00
04:35:01 PM       125      0.00
04:35:01 PM       126      0.00
04:35:01 PM       127      0.00
04:35:01 PM       128      0.00
04:35:01 PM       129      0.00
04:35:01 PM       130      0.00
04:35:01 PM       131      0.00
04:35:01 PM       132      0.00
04:35:01 PM       133      0.00
04:35:01 PM       134      0.00
04:35:01 PM       135      0.00
04:35:01 PM       136      0.00
04:35:01 PM       137      0.00
04:35:01 PM       138      0.00
04:35:01 PM       139      0.00
04:35:01 PM       140      0.00
04:35:01 PM       141      0.00
04:35:01 PM       142      0.00
04:35:01 PM       143      0.00
04:35:01 PM       144      0.00
04:35:01 PM       145      0.00
04:35:01 PM       146      0.00
04:35:01 PM       147      0.00
04:35:01 PM       148      0.00
04:35:01 PM       149      0.00
04:35:01 PM       150      0.00
04:35:01 PM       151      0.00
04:35:01 PM       152      0.00
04:35:01 PM       153      0.00
04:35:01 PM       154      0.00
04:35:01 PM       155      0.00
04:35:01 PM       156      0.00
04:35:01 PM       157      0.00
04:35:01 PM       158      0.00
04:35:01 PM       159      0.00
04:35:01 PM       160      0.00
04:35:01 PM       161      0.00
04:35:01 PM       162      0.00
04:35:01 PM       163      0.00
04:35:01 PM       164      0.00
04:35:01 PM       165      0.00
04:35:01 PM       166      0.00
04:35:01 PM       167      0.00
04:35:01 PM       168      0.00
04:35:01 PM       169      0.00
04:35:01 PM       170      0.00
04:35:01 PM       171      0.00
04:35:01 PM       172      0.00
04:35:01 PM       173      0.00
04:35:01 PM       174      0.00
04:35:01 PM       175      0.00
04:35:01 PM       176      0.00
04:35:01 PM       177      0.00
04:35:01 PM       178      0.00
04:35:01 PM       179      0.00
04:35:01 PM       180      0.00
04:35:01 PM       181      0.00
04:35:01 PM       182      0.00
04:35:01 PM       183      0.00
04:35:01 PM       184      0.00
04:35:01 PM       185      0.00
04:35:01 PM       186      0.00
04:35:01 PM       187      0.00
04:35:01 PM       188      0.00
04:35:01 PM       189      0.00
04:35:01 PM       190      0.00
04:35:01 PM       191      0.00
04:35:01 PM       192      0.00
04:35:01 PM       193      0.00
04:35:01 PM       194      0.00
04:35:01 PM       195      0.00
04:35:01 PM       196      0.00
04:35:01 PM       197      0.00
04:35:01 PM       198      0.00
04:35:01 PM       199      0.00
04:35:01 PM       200      0.00
04:35:01 PM       201      0.00
04:35:01 PM       202      0.00
04:35:01 PM       203      0.00
04:35:01 PM       204      0.00
04:35:01 PM       205      0.00
04:35:01 PM       206      0.00
04:35:01 PM       207      0.00
04:35:01 PM       208      0.00
04:35:01 PM       209      0.00
04:35:01 PM       210      0.00
04:35:01 PM       211      0.00
04:35:01 PM       212      0.00
04:35:01 PM       213      0.00
04:35:01 PM       214      0.00
04:35:01 PM       215      0.00
04:35:01 PM       216      0.00
04:35:01 PM       217      0.00
04:35:01 PM       218      0.00
04:35:01 PM       219      0.00
04:35:01 PM       220      0.00
04:35:01 PM       221      0.00
04:35:01 PM       222      0.00
04:35:01 PM       223      0.00
04:35:01 PM       224      0.00
04:35:01 PM       225      0.00
04:35:01 PM       226      0.00
04:35:01 PM       227      0.00
04:35:01 PM       228      0.00
04:35:01 PM       229      0.00
04:35:01 PM       230      0.00
04:35:01 PM       231      0.00
04:35:01 PM       232      0.00
04:35:01 PM       233      0.00
04:35:01 PM       234      0.00
04:35:01 PM       235      0.00
04:35:01 PM       236      0.00
04:35:01 PM       237      0.00
04:35:01 PM       238      0.00
04:35:01 PM       239      0.00
04:35:01 PM       240      0.00
04:35:01 PM       241      0.00
04:35:01 PM       242      0.00
04:35:01 PM       243      0.00
04:35:01 PM       244      0.00
04:35:01 PM       245      0.00
04:35:01 PM       246      0.00
04:35:01 PM       247      0.00
04:35:01 PM       248      0.00
04:35:01 PM       249      0.00
04:35:01 PM       250      0.00
04:35:01 PM       251      0.00
04:35:01 PM       252      0.00
04:35:01 PM       253      0.00
04:35:01 PM       254      0.00
04:35:01 PM       255      0.00

04:34:59 PM  pswpin/s pswpout/s
04:35:01 PM      0.00      0.00

04:34:59 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:01 PM      0.00     24.00   1625.50      0.00    830.50      0.00      0.00      0.00      0.00

04:34:59 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:01 PM      3.50      0.00      3.50      0.00    112.00

04:34:59 PM   frmpg/s   bufpg/s   campg/s
04:35:01 PM     14.50      0.00      2.50

04:34:59 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:01 PM     81444   8114116     99.01       176   5018604   4689464      8.34   4225352   2971880

04:34:59 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:01 PM  48016452       948      0.00       224     23.63

04:34:59 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:01 PM    158622      9888    134011       110

04:34:59 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:01 PM         0       475      0.00      0.01      0.05         0

04:34:59 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:01 PM    dev8-0      1.50      0.00     40.00     26.67      0.06     36.67     36.67      5.50
04:35:01 PM   dev8-16      1.50      0.00     40.00     26.67      0.06     40.00     40.00      6.00
04:35:01 PM    dev9-0      0.50      0.00     32.00     64.00      0.00      0.00      0.00      0.00
04:35:01 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:01 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:01 PM      eth0      6.00      6.50      0.79      8.91      0.00      0.00      0.00
04:35:01 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:01 PM      tun0      6.00      6.50      0.30      8.41      0.00      0.00      0.00

04:34:59 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:01 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:01 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:01 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:01 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:01 PM       882        32         9         0         0         0

04:34:59 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:01 PM     12.00      0.00     12.00     13.00      0.00      0.00      0.00      0.00

04:34:59 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM  active/s passive/s    iseg/s    oseg/s
04:35:01 PM      0.00      0.00      6.00      6.50

04:34:59 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00

04:34:59 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:01 PM      6.00      6.50      0.00      0.00

04:34:59 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:01 PM         2         2         0         0

04:34:59 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:01 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:34:59 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:01 PM      0.00      0.00      0.00      0.00

04:34:59 PM     CPU       MHz
04:35:01 PM     all   1596.00
04:35:01 PM       0   1596.00
04:35:01 PM       1   1596.00
04:35:01 PM       2   1596.00
04:35:01 PM       3   1596.00

04:34:59 PM     FAN       rpm      drpm                   DEVICE
04:35:01 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:01 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:01 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:01 PM       4      0.00   -800.00           atk0110-acpi-0

04:34:59 PM    TEMP      degC     %temp                   DEVICE
04:35:01 PM       1     47.00     78.33           atk0110-acpi-0
04:35:01 PM       2     43.00     95.56           atk0110-acpi-0

04:34:59 PM      IN       inV       %in                   DEVICE
04:35:01 PM       0      1.10     33.87           atk0110-acpi-0
04:35:01 PM       1      3.25     42.12           atk0110-acpi-0
04:35:01 PM       2      5.02     51.70           atk0110-acpi-0
04:35:01 PM       3     12.20     55.44           atk0110-acpi-0

04:34:59 PM kbhugfree kbhugused  %hugused
04:35:01 PM         0         0      0.00

04:34:59 PM     CPU    wghMHz
04:35:01 PM     all   1596.00
04:35:01 PM       0   1596.00
04:35:01 PM       1   1596.00
04:35:01 PM       2   1596.00
04:35:01 PM       3   1596.00

04:35:01 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:03 PM     all      2.25      0.00      1.37      0.00      0.00      0.00      0.00      0.00     96.38
04:35:03 PM       0      1.50      0.00      0.50      0.00      0.00      0.00      0.00      0.00     98.00
04:35:03 PM       1      5.97      0.00      3.48      0.00      0.00      0.00      0.00      0.00     90.55
04:35:03 PM       2      1.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     98.00
04:35:03 PM       3      0.50      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.00

04:35:01 PM    proc/s   cswch/s
04:35:03 PM      0.00   2131.00

04:35:01 PM      INTR    intr/s
04:35:03 PM       sum    710.50
04:35:03 PM         0      0.00
04:35:03 PM         1      0.00
04:35:03 PM         2      0.00
04:35:03 PM         3      0.00
04:35:03 PM         4      0.00
04:35:03 PM         5      0.00
04:35:03 PM         6      0.00
04:35:03 PM         7      0.00
04:35:03 PM         8      0.00
04:35:03 PM         9      0.00
04:35:03 PM        10      0.00
04:35:03 PM        11      0.00
04:35:03 PM        12      0.00
04:35:03 PM        13      0.00
04:35:03 PM        14      0.00
04:35:03 PM        15      0.00
04:35:03 PM        16      1.00
04:35:03 PM        17      2.50
04:35:03 PM        18      0.00
04:35:03 PM        19     28.00
04:35:03 PM        20      0.00
04:35:03 PM        21      0.00
04:35:03 PM        22      0.00
04:35:03 PM        23      0.50
04:35:03 PM        24      0.00
04:35:03 PM        25      0.00
04:35:03 PM        26      0.00
04:35:03 PM        27      0.00
04:35:03 PM        28      0.00
04:35:03 PM        29      0.00
04:35:03 PM        30      0.00
04:35:03 PM        31      0.00
04:35:03 PM        32      0.00
04:35:03 PM        33      0.00
04:35:03 PM        34      0.00
04:35:03 PM        35      0.00
04:35:03 PM        36      0.00
04:35:03 PM        37      0.00
04:35:03 PM        38      0.00
04:35:03 PM        39      0.00
04:35:03 PM        40      0.00
04:35:03 PM        41      0.00
04:35:03 PM        42      0.00
04:35:03 PM        43      0.00
04:35:03 PM        44     12.00
04:35:03 PM        45      1.00
04:35:03 PM        46      0.00
04:35:03 PM        47      0.00
04:35:03 PM        48      0.00
04:35:03 PM        49      0.00
04:35:03 PM        50      0.00
04:35:03 PM        51      0.00
04:35:03 PM        52      0.00
04:35:03 PM        53      0.00
04:35:03 PM        54      0.00
04:35:03 PM        55      0.00
04:35:03 PM        56      0.00
04:35:03 PM        57      0.00
04:35:03 PM        58      0.00
04:35:03 PM        59      0.00
04:35:03 PM        60      0.00
04:35:03 PM        61      0.00
04:35:03 PM        62      0.00
04:35:03 PM        63      0.00
04:35:03 PM        64      0.00
04:35:03 PM        65      0.00
04:35:03 PM        66      0.00
04:35:03 PM        67      0.00
04:35:03 PM        68      0.00
04:35:03 PM        69      0.00
04:35:03 PM        70      0.00
04:35:03 PM        71      0.00
04:35:03 PM        72      0.00
04:35:03 PM        73      0.00
04:35:03 PM        74      0.00
04:35:03 PM        75      0.00
04:35:03 PM        76      0.00
04:35:03 PM        77      0.00
04:35:03 PM        78      0.00
04:35:03 PM        79      0.00
04:35:03 PM        80      0.00
04:35:03 PM        81      0.00
04:35:03 PM        82      0.00
04:35:03 PM        83      0.00
04:35:03 PM        84      0.00
04:35:03 PM        85      0.00
04:35:03 PM        86      0.00
04:35:03 PM        87      0.00
04:35:03 PM        88      0.00
04:35:03 PM        89      0.00
04:35:03 PM        90      0.00
04:35:03 PM        91      0.00
04:35:03 PM        92      0.00
04:35:03 PM        93      0.00
04:35:03 PM        94      0.00
04:35:03 PM        95      0.00
04:35:03 PM        96      0.00
04:35:03 PM        97      0.00
04:35:03 PM        98      0.00
04:35:03 PM        99      0.00
04:35:03 PM       100      0.00
04:35:03 PM       101      0.00
04:35:03 PM       102      0.00
04:35:03 PM       103      0.00
04:35:03 PM       104      0.00
04:35:03 PM       105      0.00
04:35:03 PM       106      0.00
04:35:03 PM       107      0.00
04:35:03 PM       108      0.00
04:35:03 PM       109      0.00
04:35:03 PM       110      0.00
04:35:03 PM       111      0.00
04:35:03 PM       112      0.00
04:35:03 PM       113      0.00
04:35:03 PM       114      0.00
04:35:03 PM       115      0.00
04:35:03 PM       116      0.00
04:35:03 PM       117      0.00
04:35:03 PM       118      0.00
04:35:03 PM       119      0.00
04:35:03 PM       120      0.00
04:35:03 PM       121      0.00
04:35:03 PM       122      0.00
04:35:03 PM       123      0.00
04:35:03 PM       124      0.00
04:35:03 PM       125      0.00
04:35:03 PM       126      0.00
04:35:03 PM       127      0.00
04:35:03 PM       128      0.00
04:35:03 PM       129      0.00
04:35:03 PM       130      0.00
04:35:03 PM       131      0.00
04:35:03 PM       132      0.00
04:35:03 PM       133      0.00
04:35:03 PM       134      0.00
04:35:03 PM       135      0.00
04:35:03 PM       136      0.00
04:35:03 PM       137      0.00
04:35:03 PM       138      0.00
04:35:03 PM       139      0.00
04:35:03 PM       140      0.00
04:35:03 PM       141      0.00
04:35:03 PM       142      0.00
04:35:03 PM       143      0.00
04:35:03 PM       144      0.00
04:35:03 PM       145      0.00
04:35:03 PM       146      0.00
04:35:03 PM       147      0.00
04:35:03 PM       148      0.00
04:35:03 PM       149      0.00
04:35:03 PM       150      0.00
04:35:03 PM       151      0.00
04:35:03 PM       152      0.00
04:35:03 PM       153      0.00
04:35:03 PM       154      0.00
04:35:03 PM       155      0.00
04:35:03 PM       156      0.00
04:35:03 PM       157      0.00
04:35:03 PM       158      0.00
04:35:03 PM       159      0.00
04:35:03 PM       160      0.00
04:35:03 PM       161      0.00
04:35:03 PM       162      0.00
04:35:03 PM       163      0.00
04:35:03 PM       164      0.00
04:35:03 PM       165      0.00
04:35:03 PM       166      0.00
04:35:03 PM       167      0.00
04:35:03 PM       168      0.00
04:35:03 PM       169      0.00
04:35:03 PM       170      0.00
04:35:03 PM       171      0.00
04:35:03 PM       172      0.00
04:35:03 PM       173      0.00
04:35:03 PM       174      0.00
04:35:03 PM       175      0.00
04:35:03 PM       176      0.00
04:35:03 PM       177      0.00
04:35:03 PM       178      0.00
04:35:03 PM       179      0.00
04:35:03 PM       180      0.00
04:35:03 PM       181      0.00
04:35:03 PM       182      0.00
04:35:03 PM       183      0.00
04:35:03 PM       184      0.00
04:35:03 PM       185      0.00
04:35:03 PM       186      0.00
04:35:03 PM       187      0.00
04:35:03 PM       188      0.00
04:35:03 PM       189      0.00
04:35:03 PM       190      0.00
04:35:03 PM       191      0.00
04:35:03 PM       192      0.00
04:35:03 PM       193      0.00
04:35:03 PM       194      0.00
04:35:03 PM       195      0.00
04:35:03 PM       196      0.00
04:35:03 PM       197      0.00
04:35:03 PM       198      0.00
04:35:03 PM       199      0.00
04:35:03 PM       200      0.00
04:35:03 PM       201      0.00
04:35:03 PM       202      0.00
04:35:03 PM       203      0.00
04:35:03 PM       204      0.00
04:35:03 PM       205      0.00
04:35:03 PM       206      0.00
04:35:03 PM       207      0.00
04:35:03 PM       208      0.00
04:35:03 PM       209      0.00
04:35:03 PM       210      0.00
04:35:03 PM       211      0.00
04:35:03 PM       212      0.00
04:35:03 PM       213      0.00
04:35:03 PM       214      0.00
04:35:03 PM       215      0.00
04:35:03 PM       216      0.00
04:35:03 PM       217      0.00
04:35:03 PM       218      0.00
04:35:03 PM       219      0.00
04:35:03 PM       220      0.00
04:35:03 PM       221      0.00
04:35:03 PM       222      0.00
04:35:03 PM       223      0.00
04:35:03 PM       224      0.00
04:35:03 PM       225      0.00
04:35:03 PM       226      0.00
04:35:03 PM       227      0.00
04:35:03 PM       228      0.00
04:35:03 PM       229      0.00
04:35:03 PM       230      0.00
04:35:03 PM       231      0.00
04:35:03 PM       232      0.00
04:35:03 PM       233      0.00
04:35:03 PM       234      0.00
04:35:03 PM       235      0.00
04:35:03 PM       236      0.00
04:35:03 PM       237      0.00
04:35:03 PM       238      0.00
04:35:03 PM       239      0.00
04:35:03 PM       240      0.00
04:35:03 PM       241      0.00
04:35:03 PM       242      0.00
04:35:03 PM       243      0.00
04:35:03 PM       244      0.00
04:35:03 PM       245      0.00
04:35:03 PM       246      0.00
04:35:03 PM       247      0.00
04:35:03 PM       248      0.00
04:35:03 PM       249      0.00
04:35:03 PM       250      0.00
04:35:03 PM       251      0.00
04:35:03 PM       252      0.00
04:35:03 PM       253      0.00
04:35:03 PM       254      0.00
04:35:03 PM       255      0.00

04:35:01 PM  pswpin/s pswpout/s
04:35:03 PM      0.00      0.00

04:35:01 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:03 PM      0.00     47.50     31.00      0.00    290.50      0.00      0.00      0.00      0.00

04:35:01 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:03 PM     25.50      0.00     25.50      0.00    219.50

04:35:01 PM   frmpg/s   bufpg/s   campg/s
04:35:03 PM      1.00      0.00      2.00

04:35:01 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:03 PM     81452   8114108     99.01       176   5018620   4689464      8.34   4225392   2971876

04:35:01 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:03 PM  48016452       948      0.00       224     23.63

04:35:01 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:03 PM    158622      9888    134011       110

04:35:01 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:03 PM         0       475      0.00      0.01      0.05         0

04:35:01 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:03 PM    dev8-0      9.00      0.00     78.50      8.72      0.14     15.00      8.33      7.50
04:35:03 PM   dev8-16      9.00      0.00     78.50      8.72      0.12     13.33      6.67      6.00
04:35:03 PM    dev9-0      7.50      0.00     62.50      8.33      0.00      0.00      0.00      0.00
04:35:03 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:03 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:03 PM      eth0      6.50      6.50      0.86      8.91      0.00      0.00      0.00
04:35:03 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:03 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:01 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:03 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:03 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:03 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:03 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:03 PM       882        32         9         0         0         0

04:35:01 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:03 PM     13.00      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:01 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM  active/s passive/s    iseg/s    oseg/s
04:35:03 PM      0.00      0.00      6.50      6.50

04:35:01 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00

04:35:01 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:03 PM      6.50      6.50      0.00      0.00

04:35:01 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:03 PM         2         2         0         0

04:35:01 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:03 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:01 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:03 PM      0.00      0.00      0.00      0.00

04:35:01 PM     CPU       MHz
04:35:03 PM     all   1596.00
04:35:03 PM       0   1596.00
04:35:03 PM       1   1596.00
04:35:03 PM       2   1596.00
04:35:03 PM       3   1596.00

04:35:01 PM     FAN       rpm      drpm                   DEVICE
04:35:03 PM       1   2596.00   1996.00           atk0110-acpi-0
04:35:03 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:03 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:03 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:01 PM    TEMP      degC     %temp                   DEVICE
04:35:03 PM       1     47.00     78.33           atk0110-acpi-0
04:35:03 PM       2     43.00     95.56           atk0110-acpi-0

04:35:01 PM      IN       inV       %in                   DEVICE
04:35:03 PM       0      1.10     33.87           atk0110-acpi-0
04:35:03 PM       1      3.25     42.12           atk0110-acpi-0
04:35:03 PM       2      5.02     51.70           atk0110-acpi-0
04:35:03 PM       3     12.20     55.44           atk0110-acpi-0

04:35:01 PM kbhugfree kbhugused  %hugused
04:35:03 PM         0         0      0.00

04:35:01 PM     CPU    wghMHz
04:35:03 PM     all   1596.00
04:35:03 PM       0   1596.00
04:35:03 PM       1   1596.00
04:35:03 PM       2   1596.00
04:35:03 PM       3   1596.00

04:35:03 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:05 PM     all      1.88      0.00      1.13      0.00      0.00      0.00      0.00      0.00     97.00
04:35:05 PM       0      2.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     96.50
04:35:05 PM       1      3.52      0.00      2.01      0.00      0.00      0.00      0.00      0.00     94.47
04:35:05 PM       2      0.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     98.50
04:35:05 PM       3      1.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     98.50

04:35:03 PM    proc/s   cswch/s
04:35:05 PM      0.00   2120.50

04:35:03 PM      INTR    intr/s
04:35:05 PM       sum    690.00
04:35:05 PM         0      0.00
04:35:05 PM         1      0.00
04:35:05 PM         2      0.00
04:35:05 PM         3      0.00
04:35:05 PM         4      0.00
04:35:05 PM         5      0.00
04:35:05 PM         6      0.00
04:35:05 PM         7      0.00
04:35:05 PM         8      0.00
04:35:05 PM         9      0.00
04:35:05 PM        10      0.00
04:35:05 PM        11      0.00
04:35:05 PM        12      0.00
04:35:05 PM        13      0.00
04:35:05 PM        14      0.00
04:35:05 PM        15      0.00
04:35:05 PM        16      1.00
04:35:05 PM        17      2.50
04:35:05 PM        18      0.00
04:35:05 PM        19     17.00
04:35:05 PM        20      0.00
04:35:05 PM        21      0.00
04:35:05 PM        22      0.00
04:35:05 PM        23      0.50
04:35:05 PM        24      0.00
04:35:05 PM        25      0.00
04:35:05 PM        26      0.00
04:35:05 PM        27      0.00
04:35:05 PM        28      0.00
04:35:05 PM        29      0.00
04:35:05 PM        30      0.00
04:35:05 PM        31      0.00
04:35:05 PM        32      0.00
04:35:05 PM        33      0.00
04:35:05 PM        34      0.00
04:35:05 PM        35      0.00
04:35:05 PM        36      0.00
04:35:05 PM        37      0.00
04:35:05 PM        38      0.00
04:35:05 PM        39      0.00
04:35:05 PM        40      0.00
04:35:05 PM        41      0.00
04:35:05 PM        42      0.00
04:35:05 PM        43      0.00
04:35:05 PM        44     12.50
04:35:05 PM        45      1.00
04:35:05 PM        46      0.00
04:35:05 PM        47      0.00
04:35:05 PM        48      0.00
04:35:05 PM        49      0.00
04:35:05 PM        50      0.00
04:35:05 PM        51      0.00
04:35:05 PM        52      0.00
04:35:05 PM        53      0.00
04:35:05 PM        54      0.00
04:35:05 PM        55      0.00
04:35:05 PM        56      0.00
04:35:05 PM        57      0.00
04:35:05 PM        58      0.00
04:35:05 PM        59      0.00
04:35:05 PM        60      0.00
04:35:05 PM        61      0.00
04:35:05 PM        62      0.00
04:35:05 PM        63      0.00
04:35:05 PM        64      0.00
04:35:05 PM        65      0.00
04:35:05 PM        66      0.00
04:35:05 PM        67      0.00
04:35:05 PM        68      0.00
04:35:05 PM        69      0.00
04:35:05 PM        70      0.00
04:35:05 PM        71      0.00
04:35:05 PM        72      0.00
04:35:05 PM        73      0.00
04:35:05 PM        74      0.00
04:35:05 PM        75      0.00
04:35:05 PM        76      0.00
04:35:05 PM        77      0.00
04:35:05 PM        78      0.00
04:35:05 PM        79      0.00
04:35:05 PM        80      0.00
04:35:05 PM        81      0.00
04:35:05 PM        82      0.00
04:35:05 PM        83      0.00
04:35:05 PM        84      0.00
04:35:05 PM        85      0.00
04:35:05 PM        86      0.00
04:35:05 PM        87      0.00
04:35:05 PM        88      0.00
04:35:05 PM        89      0.00
04:35:05 PM        90      0.00
04:35:05 PM        91      0.00
04:35:05 PM        92      0.00
04:35:05 PM        93      0.00
04:35:05 PM        94      0.00
04:35:05 PM        95      0.00
04:35:05 PM        96      0.00
04:35:05 PM        97      0.00
04:35:05 PM        98      0.00
04:35:05 PM        99      0.00
04:35:05 PM       100      0.00
04:35:05 PM       101      0.00
04:35:05 PM       102      0.00
04:35:05 PM       103      0.00
04:35:05 PM       104      0.00
04:35:05 PM       105      0.00
04:35:05 PM       106      0.00
04:35:05 PM       107      0.00
04:35:05 PM       108      0.00
04:35:05 PM       109      0.00
04:35:05 PM       110      0.00
04:35:05 PM       111      0.00
04:35:05 PM       112      0.00
04:35:05 PM       113      0.00
04:35:05 PM       114      0.00
04:35:05 PM       115      0.00
04:35:05 PM       116      0.00
04:35:05 PM       117      0.00
04:35:05 PM       118      0.00
04:35:05 PM       119      0.00
04:35:05 PM       120      0.00
04:35:05 PM       121      0.00
04:35:05 PM       122      0.00
04:35:05 PM       123      0.00
04:35:05 PM       124      0.00
04:35:05 PM       125      0.00
04:35:05 PM       126      0.00
04:35:05 PM       127      0.00
04:35:05 PM       128      0.00
04:35:05 PM       129      0.00
04:35:05 PM       130      0.00
04:35:05 PM       131      0.00
04:35:05 PM       132      0.00
04:35:05 PM       133      0.00
04:35:05 PM       134      0.00
04:35:05 PM       135      0.00
04:35:05 PM       136      0.00
04:35:05 PM       137      0.00
04:35:05 PM       138      0.00
04:35:05 PM       139      0.00
04:35:05 PM       140      0.00
04:35:05 PM       141      0.00
04:35:05 PM       142      0.00
04:35:05 PM       143      0.00
04:35:05 PM       144      0.00
04:35:05 PM       145      0.00
04:35:05 PM       146      0.00
04:35:05 PM       147      0.00
04:35:05 PM       148      0.00
04:35:05 PM       149      0.00
04:35:05 PM       150      0.00
04:35:05 PM       151      0.00
04:35:05 PM       152      0.00
04:35:05 PM       153      0.00
04:35:05 PM       154      0.00
04:35:05 PM       155      0.00
04:35:05 PM       156      0.00
04:35:05 PM       157      0.00
04:35:05 PM       158      0.00
04:35:05 PM       159      0.00
04:35:05 PM       160      0.00
04:35:05 PM       161      0.00
04:35:05 PM       162      0.00
04:35:05 PM       163      0.00
04:35:05 PM       164      0.00
04:35:05 PM       165      0.00
04:35:05 PM       166      0.00
04:35:05 PM       167      0.00
04:35:05 PM       168      0.00
04:35:05 PM       169      0.00
04:35:05 PM       170      0.00
04:35:05 PM       171      0.00
04:35:05 PM       172      0.00
04:35:05 PM       173      0.00
04:35:05 PM       174      0.00
04:35:05 PM       175      0.00
04:35:05 PM       176      0.00
04:35:05 PM       177      0.00
04:35:05 PM       178      0.00
04:35:05 PM       179      0.00
04:35:05 PM       180      0.00
04:35:05 PM       181      0.00
04:35:05 PM       182      0.00
04:35:05 PM       183      0.00
04:35:05 PM       184      0.00
04:35:05 PM       185      0.00
04:35:05 PM       186      0.00
04:35:05 PM       187      0.00
04:35:05 PM       188      0.00
04:35:05 PM       189      0.00
04:35:05 PM       190      0.00
04:35:05 PM       191      0.00
04:35:05 PM       192      0.00
04:35:05 PM       193      0.00
04:35:05 PM       194      0.00
04:35:05 PM       195      0.00
04:35:05 PM       196      0.00
04:35:05 PM       197      0.00
04:35:05 PM       198      0.00
04:35:05 PM       199      0.00
04:35:05 PM       200      0.00
04:35:05 PM       201      0.00
04:35:05 PM       202      0.00
04:35:05 PM       203      0.00
04:35:05 PM       204      0.00
04:35:05 PM       205      0.00
04:35:05 PM       206      0.00
04:35:05 PM       207      0.00
04:35:05 PM       208      0.00
04:35:05 PM       209      0.00
04:35:05 PM       210      0.00
04:35:05 PM       211      0.00
04:35:05 PM       212      0.00
04:35:05 PM       213      0.00
04:35:05 PM       214      0.00
04:35:05 PM       215      0.00
04:35:05 PM       216      0.00
04:35:05 PM       217      0.00
04:35:05 PM       218      0.00
04:35:05 PM       219      0.00
04:35:05 PM       220      0.00
04:35:05 PM       221      0.00
04:35:05 PM       222      0.00
04:35:05 PM       223      0.00
04:35:05 PM       224      0.00
04:35:05 PM       225      0.00
04:35:05 PM       226      0.00
04:35:05 PM       227      0.00
04:35:05 PM       228      0.00
04:35:05 PM       229      0.00
04:35:05 PM       230      0.00
04:35:05 PM       231      0.00
04:35:05 PM       232      0.00
04:35:05 PM       233      0.00
04:35:05 PM       234      0.00
04:35:05 PM       235      0.00
04:35:05 PM       236      0.00
04:35:05 PM       237      0.00
04:35:05 PM       238      0.00
04:35:05 PM       239      0.00
04:35:05 PM       240      0.00
04:35:05 PM       241      0.00
04:35:05 PM       242      0.00
04:35:05 PM       243      0.00
04:35:05 PM       244      0.00
04:35:05 PM       245      0.00
04:35:05 PM       246      0.00
04:35:05 PM       247      0.00
04:35:05 PM       248      0.00
04:35:05 PM       249      0.00
04:35:05 PM       250      0.00
04:35:05 PM       251      0.00
04:35:05 PM       252      0.00
04:35:05 PM       253      0.00
04:35:05 PM       254      0.00
04:35:05 PM       255      0.00

04:35:03 PM  pswpin/s pswpout/s
04:35:05 PM      0.00      0.00

04:35:03 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:05 PM      0.00     18.50     31.00      0.00    288.00      0.00      0.00      0.00      0.00

04:35:03 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:05 PM      8.50      0.00      8.50      0.00     48.50

04:35:03 PM   frmpg/s   bufpg/s   campg/s
04:35:05 PM      0.00      0.00      2.00

04:35:03 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:05 PM     81452   8114108     99.01       176   5018636   4689464      8.34   4225396   2971888

04:35:03 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:05 PM  48016452       948      0.00       224     23.63

04:35:03 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:05 PM    158622      9888    134011       110

04:35:03 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:05 PM         0       475      0.00      0.01      0.05         0

04:35:03 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:05 PM    dev8-0      3.50      0.00     21.50      6.14      0.04     11.43     11.43      4.00
04:35:05 PM   dev8-16      3.50      0.00     21.50      6.14      0.05     14.29     14.29      5.00
04:35:05 PM    dev9-0      1.50      0.00      5.50      3.67      0.00      0.00      0.00      0.00
04:35:05 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:05 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:05 PM      eth0      6.50      7.50      0.88      9.00      0.00      0.00      0.00
04:35:05 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:05 PM      tun0      6.50      7.00      0.35      8.43      0.00      0.00      0.00

04:35:03 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:05 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:05 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:05 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:05 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:05 PM       882        32         9         0         0         0

04:35:03 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:05 PM     13.00      0.00     13.00     14.50      0.00      0.00      0.00      0.00

04:35:03 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM  active/s passive/s    iseg/s    oseg/s
04:35:05 PM      0.00      0.00      6.50      7.00

04:35:03 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00

04:35:03 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:05 PM      6.50      7.50      0.00      0.00

04:35:03 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:05 PM         2         2         0         0

04:35:03 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:05 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:03 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:05 PM      0.00      0.00      0.00      0.00

04:35:03 PM     CPU       MHz
04:35:05 PM     all   1596.00
04:35:05 PM       0   1596.00
04:35:05 PM       1   1596.00
04:35:05 PM       2   1596.00
04:35:05 PM       3   1596.00

04:35:03 PM     FAN       rpm      drpm                   DEVICE
04:35:05 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:05 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:05 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:05 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:03 PM    TEMP      degC     %temp                   DEVICE
04:35:05 PM       1     47.00     78.33           atk0110-acpi-0
04:35:05 PM       2     43.00     95.56           atk0110-acpi-0

04:35:03 PM      IN       inV       %in                   DEVICE
04:35:05 PM       0      1.10     33.87           atk0110-acpi-0
04:35:05 PM       1      3.25     42.12           atk0110-acpi-0
04:35:05 PM       2      5.02     51.70           atk0110-acpi-0
04:35:05 PM       3     12.20     55.44           atk0110-acpi-0

04:35:03 PM kbhugfree kbhugused  %hugused
04:35:05 PM         0         0      0.00

04:35:03 PM     CPU    wghMHz
04:35:05 PM     all   1596.00
04:35:05 PM       0   1596.00
04:35:05 PM       1   1596.00
04:35:05 PM       2   1596.00
04:35:05 PM       3   1596.00

04:35:05 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:07 PM     all      1.50      0.00      1.25      0.00      0.00      0.00      0.00      0.00     97.25
04:35:07 PM       0      4.52      0.00      1.01      0.00      0.00      0.00      0.00      0.00     94.47
04:35:07 PM       1      1.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     98.01
04:35:07 PM       2      0.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.50
04:35:07 PM       3      0.50      0.00      2.50      0.00      0.00      0.00      0.00      0.00     97.00

04:35:05 PM    proc/s   cswch/s
04:35:07 PM      0.00   2124.00

04:35:05 PM      INTR    intr/s
04:35:07 PM       sum    680.50
04:35:07 PM         0      0.00
04:35:07 PM         1      0.00
04:35:07 PM         2      0.00
04:35:07 PM         3      0.00
04:35:07 PM         4      0.00
04:35:07 PM         5      0.00
04:35:07 PM         6      0.00
04:35:07 PM         7      0.00
04:35:07 PM         8      0.00
04:35:07 PM         9      0.00
04:35:07 PM        10      0.00
04:35:07 PM        11      0.00
04:35:07 PM        12      0.00
04:35:07 PM        13      0.00
04:35:07 PM        14      0.00
04:35:07 PM        15      0.00
04:35:07 PM        16      1.00
04:35:07 PM        17      2.50
04:35:07 PM        18      0.00
04:35:07 PM        19      9.00
04:35:07 PM        20      0.00
04:35:07 PM        21      0.00
04:35:07 PM        22      0.00
04:35:07 PM        23      0.50
04:35:07 PM        24      0.00
04:35:07 PM        25      0.00
04:35:07 PM        26      0.00
04:35:07 PM        27      0.00
04:35:07 PM        28      0.00
04:35:07 PM        29      0.00
04:35:07 PM        30      0.00
04:35:07 PM        31      0.00
04:35:07 PM        32      0.00
04:35:07 PM        33      0.00
04:35:07 PM        34      0.00
04:35:07 PM        35      0.00
04:35:07 PM        36      0.00
04:35:07 PM        37      0.00
04:35:07 PM        38      0.00
04:35:07 PM        39      0.00
04:35:07 PM        40      0.00
04:35:07 PM        41      0.00
04:35:07 PM        42      0.00
04:35:07 PM        43      0.00
04:35:07 PM        44     11.00
04:35:07 PM        45      1.00
04:35:07 PM        46      0.00
04:35:07 PM        47      0.00
04:35:07 PM        48      0.00
04:35:07 PM        49      0.00
04:35:07 PM        50      0.00
04:35:07 PM        51      0.00
04:35:07 PM        52      0.00
04:35:07 PM        53      0.00
04:35:07 PM        54      0.00
04:35:07 PM        55      0.00
04:35:07 PM        56      0.00
04:35:07 PM        57      0.00
04:35:07 PM        58      0.00
04:35:07 PM        59      0.00
04:35:07 PM        60      0.00
04:35:07 PM        61      0.00
04:35:07 PM        62      0.00
04:35:07 PM        63      0.00
04:35:07 PM        64      0.00
04:35:07 PM        65      0.00
04:35:07 PM        66      0.00
04:35:07 PM        67      0.00
04:35:07 PM        68      0.00
04:35:07 PM        69      0.00
04:35:07 PM        70      0.00
04:35:07 PM        71      0.00
04:35:07 PM        72      0.00
04:35:07 PM        73      0.00
04:35:07 PM        74      0.00
04:35:07 PM        75      0.00
04:35:07 PM        76      0.00
04:35:07 PM        77      0.00
04:35:07 PM        78      0.00
04:35:07 PM        79      0.00
04:35:07 PM        80      0.00
04:35:07 PM        81      0.00
04:35:07 PM        82      0.00
04:35:07 PM        83      0.00
04:35:07 PM        84      0.00
04:35:07 PM        85      0.00
04:35:07 PM        86      0.00
04:35:07 PM        87      0.00
04:35:07 PM        88      0.00
04:35:07 PM        89      0.00
04:35:07 PM        90      0.00
04:35:07 PM        91      0.00
04:35:07 PM        92      0.00
04:35:07 PM        93      0.00
04:35:07 PM        94      0.00
04:35:07 PM        95      0.00
04:35:07 PM        96      0.00
04:35:07 PM        97      0.00
04:35:07 PM        98      0.00
04:35:07 PM        99      0.00
04:35:07 PM       100      0.00
04:35:07 PM       101      0.00
04:35:07 PM       102      0.00
04:35:07 PM       103      0.00
04:35:07 PM       104      0.00
04:35:07 PM       105      0.00
04:35:07 PM       106      0.00
04:35:07 PM       107      0.00
04:35:07 PM       108      0.00
04:35:07 PM       109      0.00
04:35:07 PM       110      0.00
04:35:07 PM       111      0.00
04:35:07 PM       112      0.00
04:35:07 PM       113      0.00
04:35:07 PM       114      0.00
04:35:07 PM       115      0.00
04:35:07 PM       116      0.00
04:35:07 PM       117      0.00
04:35:07 PM       118      0.00
04:35:07 PM       119      0.00
04:35:07 PM       120      0.00
04:35:07 PM       121      0.00
04:35:07 PM       122      0.00
04:35:07 PM       123      0.00
04:35:07 PM       124      0.00
04:35:07 PM       125      0.00
04:35:07 PM       126      0.00
04:35:07 PM       127      0.00
04:35:07 PM       128      0.00
04:35:07 PM       129      0.00
04:35:07 PM       130      0.00
04:35:07 PM       131      0.00
04:35:07 PM       132      0.00
04:35:07 PM       133      0.00
04:35:07 PM       134      0.00
04:35:07 PM       135      0.00
04:35:07 PM       136      0.00
04:35:07 PM       137      0.00
04:35:07 PM       138      0.00
04:35:07 PM       139      0.00
04:35:07 PM       140      0.00
04:35:07 PM       141      0.00
04:35:07 PM       142      0.00
04:35:07 PM       143      0.00
04:35:07 PM       144      0.00
04:35:07 PM       145      0.00
04:35:07 PM       146      0.00
04:35:07 PM       147      0.00
04:35:07 PM       148      0.00
04:35:07 PM       149      0.00
04:35:07 PM       150      0.00
04:35:07 PM       151      0.00
04:35:07 PM       152      0.00
04:35:07 PM       153      0.00
04:35:07 PM       154      0.00
04:35:07 PM       155      0.00
04:35:07 PM       156      0.00
04:35:07 PM       157      0.00
04:35:07 PM       158      0.00
04:35:07 PM       159      0.00
04:35:07 PM       160      0.00
04:35:07 PM       161      0.00
04:35:07 PM       162      0.00
04:35:07 PM       163      0.00
04:35:07 PM       164      0.00
04:35:07 PM       165      0.00
04:35:07 PM       166      0.00
04:35:07 PM       167      0.00
04:35:07 PM       168      0.00
04:35:07 PM       169      0.00
04:35:07 PM       170      0.00
04:35:07 PM       171      0.00
04:35:07 PM       172      0.00
04:35:07 PM       173      0.00
04:35:07 PM       174      0.00
04:35:07 PM       175      0.00
04:35:07 PM       176      0.00
04:35:07 PM       177      0.00
04:35:07 PM       178      0.00
04:35:07 PM       179      0.00
04:35:07 PM       180      0.00
04:35:07 PM       181      0.00
04:35:07 PM       182      0.00
04:35:07 PM       183      0.00
04:35:07 PM       184      0.00
04:35:07 PM       185      0.00
04:35:07 PM       186      0.00
04:35:07 PM       187      0.00
04:35:07 PM       188      0.00
04:35:07 PM       189      0.00
04:35:07 PM       190      0.00
04:35:07 PM       191      0.00
04:35:07 PM       192      0.00
04:35:07 PM       193      0.00
04:35:07 PM       194      0.00
04:35:07 PM       195      0.00
04:35:07 PM       196      0.00
04:35:07 PM       197      0.00
04:35:07 PM       198      0.00
04:35:07 PM       199      0.00
04:35:07 PM       200      0.00
04:35:07 PM       201      0.00
04:35:07 PM       202      0.00
04:35:07 PM       203      0.00
04:35:07 PM       204      0.00
04:35:07 PM       205      0.00
04:35:07 PM       206      0.00
04:35:07 PM       207      0.00
04:35:07 PM       208      0.00
04:35:07 PM       209      0.00
04:35:07 PM       210      0.00
04:35:07 PM       211      0.00
04:35:07 PM       212      0.00
04:35:07 PM       213      0.00
04:35:07 PM       214      0.00
04:35:07 PM       215      0.00
04:35:07 PM       216      0.00
04:35:07 PM       217      0.00
04:35:07 PM       218      0.00
04:35:07 PM       219      0.00
04:35:07 PM       220      0.00
04:35:07 PM       221      0.00
04:35:07 PM       222      0.00
04:35:07 PM       223      0.00
04:35:07 PM       224      0.00
04:35:07 PM       225      0.00
04:35:07 PM       226      0.00
04:35:07 PM       227      0.00
04:35:07 PM       228      0.00
04:35:07 PM       229      0.00
04:35:07 PM       230      0.00
04:35:07 PM       231      0.00
04:35:07 PM       232      0.00
04:35:07 PM       233      0.00
04:35:07 PM       234      0.00
04:35:07 PM       235      0.00
04:35:07 PM       236      0.00
04:35:07 PM       237      0.00
04:35:07 PM       238      0.00
04:35:07 PM       239      0.00
04:35:07 PM       240      0.00
04:35:07 PM       241      0.00
04:35:07 PM       242      0.00
04:35:07 PM       243      0.00
04:35:07 PM       244      0.00
04:35:07 PM       245      0.00
04:35:07 PM       246      0.00
04:35:07 PM       247      0.00
04:35:07 PM       248      0.00
04:35:07 PM       249      0.00
04:35:07 PM       250      0.00
04:35:07 PM       251      0.00
04:35:07 PM       252      0.00
04:35:07 PM       253      0.00
04:35:07 PM       254      0.00
04:35:07 PM       255      0.00

04:35:05 PM  pswpin/s pswpout/s
04:35:07 PM      0.00      0.00

04:35:05 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:07 PM      0.00     12.50     33.50      0.00    293.50      0.00      0.00      0.00      0.00

04:35:05 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:07 PM      6.50      0.00      6.50      0.00     41.50

04:35:05 PM   frmpg/s   bufpg/s   campg/s
04:35:07 PM      0.00      0.00      2.00

04:35:05 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:07 PM     81452   8114108     99.01       176   5018652   4689464      8.34   4225400   2971900

04:35:05 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:07 PM  48016452       948      0.00       224     23.63

04:35:05 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:07 PM    158622      9888    134011       110

04:35:05 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:07 PM         0       475      0.00      0.01      0.05         0

04:35:05 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:07 PM    dev8-0      2.50      0.00     16.50      6.60      0.02      8.00      8.00      2.00
04:35:07 PM   dev8-16      2.50      0.00     16.50      6.60      0.03     10.00     10.00      2.50
04:35:07 PM    dev9-0      1.50      0.00      8.50      5.67      0.00      0.00      0.00      0.00
04:35:07 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:07 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:07 PM      eth0      7.00      6.50      0.96      8.91      0.00      0.00      0.00
04:35:07 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:07 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:05 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:07 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:07 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:07 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:07 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:07 PM       882        32         9         0         0         0

04:35:05 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:07 PM     13.50      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:05 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM  active/s passive/s    iseg/s    oseg/s
04:35:07 PM      0.00      0.00      6.50      6.50

04:35:05 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00

04:35:05 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:07 PM      6.50      6.50      0.00      0.00

04:35:05 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:07 PM         2         2         0         0

04:35:05 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:07 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:05 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:07 PM      0.00      0.00      0.00      0.00

04:35:05 PM     CPU       MHz
04:35:07 PM     all   1596.00
04:35:07 PM       0   1596.00
04:35:07 PM       1   1596.00
04:35:07 PM       2   1596.00
04:35:07 PM       3   1596.00

04:35:05 PM     FAN       rpm      drpm                   DEVICE
04:35:07 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:07 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:07 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:07 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:05 PM    TEMP      degC     %temp                   DEVICE
04:35:07 PM       1     47.00     78.33           atk0110-acpi-0
04:35:07 PM       2     43.00     95.56           atk0110-acpi-0

04:35:05 PM      IN       inV       %in                   DEVICE
04:35:07 PM       0      1.11     34.93           atk0110-acpi-0
04:35:07 PM       1      3.25     42.12           atk0110-acpi-0
04:35:07 PM       2      5.02     51.70           atk0110-acpi-0
04:35:07 PM       3     12.20     55.44           atk0110-acpi-0

04:35:05 PM kbhugfree kbhugused  %hugused
04:35:07 PM         0         0      0.00

04:35:05 PM     CPU    wghMHz
04:35:07 PM     all   1611.88
04:35:07 PM       0   1596.00
04:35:07 PM       1   1596.00
04:35:07 PM       2   1651.86
04:35:07 PM       3   1596.00

04:35:07 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:09 PM     all      3.00      0.00      1.37      0.00      0.00      0.00      0.00      0.00     95.63
04:35:09 PM       0      4.48      0.00      1.00      0.00      0.00      0.00      0.00      0.00     94.53
04:35:09 PM       1      2.50      0.00      3.50      0.00      0.00      0.00      0.00      0.00     94.00
04:35:09 PM       2      4.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     94.50
04:35:09 PM       3      0.50      0.00      0.00      0.00      0.00      0.00      0.00      0.00     99.50

04:35:07 PM    proc/s   cswch/s
04:35:09 PM      0.00   2635.00

04:35:07 PM      INTR    intr/s
04:35:09 PM       sum    714.00
04:35:09 PM         0      0.00
04:35:09 PM         1      0.00
04:35:09 PM         2      0.00
04:35:09 PM         3      0.00
04:35:09 PM         4      0.00
04:35:09 PM         5      0.00
04:35:09 PM         6      0.00
04:35:09 PM         7      0.00
04:35:09 PM         8      0.00
04:35:09 PM         9      0.00
04:35:09 PM        10      0.00
04:35:09 PM        11      0.00
04:35:09 PM        12      0.00
04:35:09 PM        13      0.00
04:35:09 PM        14      0.00
04:35:09 PM        15      0.00
04:35:09 PM        16      1.00
04:35:09 PM        17      2.50
04:35:09 PM        18      0.00
04:35:09 PM        19      7.00
04:35:09 PM        20      0.00
04:35:09 PM        21      0.00
04:35:09 PM        22      0.00
04:35:09 PM        23      0.50
04:35:09 PM        24      0.00
04:35:09 PM        25      0.00
04:35:09 PM        26      0.00
04:35:09 PM        27      0.00
04:35:09 PM        28      0.00
04:35:09 PM        29      0.00
04:35:09 PM        30      0.00
04:35:09 PM        31      0.00
04:35:09 PM        32      0.00
04:35:09 PM        33      0.00
04:35:09 PM        34      0.00
04:35:09 PM        35      0.00
04:35:09 PM        36      0.00
04:35:09 PM        37      0.00
04:35:09 PM        38      0.00
04:35:09 PM        39      0.00
04:35:09 PM        40      0.00
04:35:09 PM        41      0.00
04:35:09 PM        42      0.00
04:35:09 PM        43      0.00
04:35:09 PM        44     11.00
04:35:09 PM        45      1.00
04:35:09 PM        46      0.00
04:35:09 PM        47      0.00
04:35:09 PM        48      0.00
04:35:09 PM        49      0.00
04:35:09 PM        50      0.00
04:35:09 PM        51      0.00
04:35:09 PM        52      0.00
04:35:09 PM        53      0.00
04:35:09 PM        54      0.00
04:35:09 PM        55      0.00
04:35:09 PM        56      0.00
04:35:09 PM        57      0.00
04:35:09 PM        58      0.00
04:35:09 PM        59      0.00
04:35:09 PM        60      0.00
04:35:09 PM        61      0.00
04:35:09 PM        62      0.00
04:35:09 PM        63      0.00
04:35:09 PM        64      0.00
04:35:09 PM        65      0.00
04:35:09 PM        66      0.00
04:35:09 PM        67      0.00
04:35:09 PM        68      0.00
04:35:09 PM        69      0.00
04:35:09 PM        70      0.00
04:35:09 PM        71      0.00
04:35:09 PM        72      0.00
04:35:09 PM        73      0.00
04:35:09 PM        74      0.00
04:35:09 PM        75      0.00
04:35:09 PM        76      0.00
04:35:09 PM        77      0.00
04:35:09 PM        78      0.00
04:35:09 PM        79      0.00
04:35:09 PM        80      0.00
04:35:09 PM        81      0.00
04:35:09 PM        82      0.00
04:35:09 PM        83      0.00
04:35:09 PM        84      0.00
04:35:09 PM        85      0.00
04:35:09 PM        86      0.00
04:35:09 PM        87      0.00
04:35:09 PM        88      0.00
04:35:09 PM        89      0.00
04:35:09 PM        90      0.00
04:35:09 PM        91      0.00
04:35:09 PM        92      0.00
04:35:09 PM        93      0.00
04:35:09 PM        94      0.00
04:35:09 PM        95      0.00
04:35:09 PM        96      0.00
04:35:09 PM        97      0.00
04:35:09 PM        98      0.00
04:35:09 PM        99      0.00
04:35:09 PM       100      0.00
04:35:09 PM       101      0.00
04:35:09 PM       102      0.00
04:35:09 PM       103      0.00
04:35:09 PM       104      0.00
04:35:09 PM       105      0.00
04:35:09 PM       106      0.00
04:35:09 PM       107      0.00
04:35:09 PM       108      0.00
04:35:09 PM       109      0.00
04:35:09 PM       110      0.00
04:35:09 PM       111      0.00
04:35:09 PM       112      0.00
04:35:09 PM       113      0.00
04:35:09 PM       114      0.00
04:35:09 PM       115      0.00
04:35:09 PM       116      0.00
04:35:09 PM       117      0.00
04:35:09 PM       118      0.00
04:35:09 PM       119      0.00
04:35:09 PM       120      0.00
04:35:09 PM       121      0.00
04:35:09 PM       122      0.00
04:35:09 PM       123      0.00
04:35:09 PM       124      0.00
04:35:09 PM       125      0.00
04:35:09 PM       126      0.00
04:35:09 PM       127      0.00
04:35:09 PM       128      0.00
04:35:09 PM       129      0.00
04:35:09 PM       130      0.00
04:35:09 PM       131      0.00
04:35:09 PM       132      0.00
04:35:09 PM       133      0.00
04:35:09 PM       134      0.00
04:35:09 PM       135      0.00
04:35:09 PM       136      0.00
04:35:09 PM       137      0.00
04:35:09 PM       138      0.00
04:35:09 PM       139      0.00
04:35:09 PM       140      0.00
04:35:09 PM       141      0.00
04:35:09 PM       142      0.00
04:35:09 PM       143      0.00
04:35:09 PM       144      0.00
04:35:09 PM       145      0.00
04:35:09 PM       146      0.00
04:35:09 PM       147      0.00
04:35:09 PM       148      0.00
04:35:09 PM       149      0.00
04:35:09 PM       150      0.00
04:35:09 PM       151      0.00
04:35:09 PM       152      0.00
04:35:09 PM       153      0.00
04:35:09 PM       154      0.00
04:35:09 PM       155      0.00
04:35:09 PM       156      0.00
04:35:09 PM       157      0.00
04:35:09 PM       158      0.00
04:35:09 PM       159      0.00
04:35:09 PM       160      0.00
04:35:09 PM       161      0.00
04:35:09 PM       162      0.00
04:35:09 PM       163      0.00
04:35:09 PM       164      0.00
04:35:09 PM       165      0.00
04:35:09 PM       166      0.00
04:35:09 PM       167      0.00
04:35:09 PM       168      0.00
04:35:09 PM       169      0.00
04:35:09 PM       170      0.00
04:35:09 PM       171      0.00
04:35:09 PM       172      0.00
04:35:09 PM       173      0.00
04:35:09 PM       174      0.00
04:35:09 PM       175      0.00
04:35:09 PM       176      0.00
04:35:09 PM       177      0.00
04:35:09 PM       178      0.00
04:35:09 PM       179      0.00
04:35:09 PM       180      0.00
04:35:09 PM       181      0.00
04:35:09 PM       182      0.00
04:35:09 PM       183      0.00
04:35:09 PM       184      0.00
04:35:09 PM       185      0.00
04:35:09 PM       186      0.00
04:35:09 PM       187      0.00
04:35:09 PM       188      0.00
04:35:09 PM       189      0.00
04:35:09 PM       190      0.00
04:35:09 PM       191      0.00
04:35:09 PM       192      0.00
04:35:09 PM       193      0.00
04:35:09 PM       194      0.00
04:35:09 PM       195      0.00
04:35:09 PM       196      0.00
04:35:09 PM       197      0.00
04:35:09 PM       198      0.00
04:35:09 PM       199      0.00
04:35:09 PM       200      0.00
04:35:09 PM       201      0.00
04:35:09 PM       202      0.00
04:35:09 PM       203      0.00
04:35:09 PM       204      0.00
04:35:09 PM       205      0.00
04:35:09 PM       206      0.00
04:35:09 PM       207      0.00
04:35:09 PM       208      0.00
04:35:09 PM       209      0.00
04:35:09 PM       210      0.00
04:35:09 PM       211      0.00
04:35:09 PM       212      0.00
04:35:09 PM       213      0.00
04:35:09 PM       214      0.00
04:35:09 PM       215      0.00
04:35:09 PM       216      0.00
04:35:09 PM       217      0.00
04:35:09 PM       218      0.00
04:35:09 PM       219      0.00
04:35:09 PM       220      0.00
04:35:09 PM       221      0.00
04:35:09 PM       222      0.00
04:35:09 PM       223      0.00
04:35:09 PM       224      0.00
04:35:09 PM       225      0.00
04:35:09 PM       226      0.00
04:35:09 PM       227      0.00
04:35:09 PM       228      0.00
04:35:09 PM       229      0.00
04:35:09 PM       230      0.00
04:35:09 PM       231      0.00
04:35:09 PM       232      0.00
04:35:09 PM       233      0.00
04:35:09 PM       234      0.00
04:35:09 PM       235      0.00
04:35:09 PM       236      0.00
04:35:09 PM       237      0.00
04:35:09 PM       238      0.00
04:35:09 PM       239      0.00
04:35:09 PM       240      0.00
04:35:09 PM       241      0.00
04:35:09 PM       242      0.00
04:35:09 PM       243      0.00
04:35:09 PM       244      0.00
04:35:09 PM       245      0.00
04:35:09 PM       246      0.00
04:35:09 PM       247      0.00
04:35:09 PM       248      0.00
04:35:09 PM       249      0.00
04:35:09 PM       250      0.00
04:35:09 PM       251      0.00
04:35:09 PM       252      0.00
04:35:09 PM       253      0.00
04:35:09 PM       254      0.00
04:35:09 PM       255      0.00

04:35:07 PM  pswpin/s pswpout/s
04:35:09 PM      0.00      0.00

04:35:07 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:09 PM      0.00     10.00    122.50      0.00    570.50      0.00      0.00      0.00      0.00

04:35:07 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:09 PM      3.50      0.00      3.50      0.00     28.00

04:35:07 PM   frmpg/s   bufpg/s   campg/s
04:35:09 PM    -46.50      0.00      2.00

04:35:07 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:09 PM     81080   8114480     99.01       176   5018668   4685372      8.34   4226080   2971912

04:35:07 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:09 PM  48016452       948      0.00       224     23.63

04:35:07 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:09 PM    158622      9888    134011       110

04:35:07 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:09 PM         0       475      0.00      0.01      0.05         0

04:35:07 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:09 PM    dev8-0      1.50      0.00     12.00      8.00      0.01     10.00     10.00      1.50
04:35:09 PM   dev8-16      1.50      0.00     12.00      8.00      0.01      6.67      6.67      1.00
04:35:09 PM    dev9-0      0.50      0.00      4.00      8.00      0.00      0.00      0.00      0.00
04:35:09 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:09 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:09 PM      eth0      6.50      6.50      0.86      8.94      0.00      0.00      0.00
04:35:09 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:09 PM      tun0      6.50      6.50      0.33      8.43      0.00      0.00      0.00

04:35:07 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:09 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:09 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:09 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:09 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:09 PM       882        32         9         0         0         0

04:35:07 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:09 PM     13.00      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:07 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM  active/s passive/s    iseg/s    oseg/s
04:35:09 PM      0.00      0.00      6.50      6.50

04:35:07 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00

04:35:07 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:09 PM      6.50      6.50      0.00      0.00

04:35:07 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:09 PM         2         2         0         0

04:35:07 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:09 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:07 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:09 PM      0.00      0.00      0.00      0.00

04:35:07 PM     CPU       MHz
04:35:09 PM     all   1596.00
04:35:09 PM       0   1596.00
04:35:09 PM       1   1596.00
04:35:09 PM       2   1596.00
04:35:09 PM       3   1596.00

04:35:07 PM     FAN       rpm      drpm                   DEVICE
04:35:09 PM       1   2616.00   2016.00           atk0110-acpi-0
04:35:09 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:09 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:09 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:07 PM    TEMP      degC     %temp                   DEVICE
04:35:09 PM       1     47.00     78.33           atk0110-acpi-0
04:35:09 PM       2     43.00     95.56           atk0110-acpi-0

04:35:07 PM      IN       inV       %in                   DEVICE
04:35:09 PM       0      1.10     33.87           atk0110-acpi-0
04:35:09 PM       1      3.25     42.12           atk0110-acpi-0
04:35:09 PM       2      5.02     51.70           atk0110-acpi-0
04:35:09 PM       3     12.20     55.44           atk0110-acpi-0

04:35:07 PM kbhugfree kbhugused  %hugused
04:35:09 PM         0         0      0.00

04:35:07 PM     CPU    wghMHz
04:35:09 PM     all   1596.00
04:35:09 PM       0   1596.00
04:35:09 PM       1   1596.00
04:35:09 PM       2   1596.00
04:35:09 PM       3   1596.00

04:35:09 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:11 PM     all      3.12      0.00      0.62      0.00      0.00      0.00      0.00      0.00     96.25
04:35:11 PM       0      3.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     96.50
04:35:11 PM       1      8.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     90.50
04:35:11 PM       2      0.50      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.00
04:35:11 PM       3      0.50      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.00

04:35:09 PM    proc/s   cswch/s
04:35:11 PM      0.00   2125.50

04:35:09 PM      INTR    intr/s
04:35:11 PM       sum    707.00
04:35:11 PM         0      0.00
04:35:11 PM         1      0.00
04:35:11 PM         2      0.00
04:35:11 PM         3      0.00
04:35:11 PM         4      0.00
04:35:11 PM         5      0.00
04:35:11 PM         6      0.00
04:35:11 PM         7      0.00
04:35:11 PM         8      0.00
04:35:11 PM         9      0.00
04:35:11 PM        10      0.00
04:35:11 PM        11      0.00
04:35:11 PM        12      0.00
04:35:11 PM        13      0.00
04:35:11 PM        14      0.00
04:35:11 PM        15      0.00
04:35:11 PM        16      1.00
04:35:11 PM        17      2.50
04:35:11 PM        18      0.00
04:35:11 PM        19      0.00
04:35:11 PM        20      0.00
04:35:11 PM        21      0.00
04:35:11 PM        22      0.00
04:35:11 PM        23      0.50
04:35:11 PM        24      0.00
04:35:11 PM        25      0.00
04:35:11 PM        26      0.00
04:35:11 PM        27      0.00
04:35:11 PM        28      0.00
04:35:11 PM        29      0.00
04:35:11 PM        30      0.00
04:35:11 PM        31      0.00
04:35:11 PM        32      0.00
04:35:11 PM        33      0.00
04:35:11 PM        34      0.00
04:35:11 PM        35      0.00
04:35:11 PM        36      0.00
04:35:11 PM        37      0.00
04:35:11 PM        38      0.00
04:35:11 PM        39      0.00
04:35:11 PM        40      0.00
04:35:11 PM        41      0.00
04:35:11 PM        42      0.00
04:35:11 PM        43      0.00
04:35:11 PM        44     23.00
04:35:11 PM        45      1.00
04:35:11 PM        46      0.00
04:35:11 PM        47      0.00
04:35:11 PM        48      0.00
04:35:11 PM        49      0.00
04:35:11 PM        50      0.00
04:35:11 PM        51      0.00
04:35:11 PM        52      0.00
04:35:11 PM        53      0.00
04:35:11 PM        54      0.00
04:35:11 PM        55      0.00
04:35:11 PM        56      0.00
04:35:11 PM        57      0.00
04:35:11 PM        58      0.00
04:35:11 PM        59      0.00
04:35:11 PM        60      0.00
04:35:11 PM        61      0.00
04:35:11 PM        62      0.00
04:35:11 PM        63      0.00
04:35:11 PM        64      0.00
04:35:11 PM        65      0.00
04:35:11 PM        66      0.00
04:35:11 PM        67      0.00
04:35:11 PM        68      0.00
04:35:11 PM        69      0.00
04:35:11 PM        70      0.00
04:35:11 PM        71      0.00
04:35:11 PM        72      0.00
04:35:11 PM        73      0.00
04:35:11 PM        74      0.00
04:35:11 PM        75      0.00
04:35:11 PM        76      0.00
04:35:11 PM        77      0.00
04:35:11 PM        78      0.00
04:35:11 PM        79      0.00
04:35:11 PM        80      0.00
04:35:11 PM        81      0.00
04:35:11 PM        82      0.00
04:35:11 PM        83      0.00
04:35:11 PM        84      0.00
04:35:11 PM        85      0.00
04:35:11 PM        86      0.00
04:35:11 PM        87      0.00
04:35:11 PM        88      0.00
04:35:11 PM        89      0.00
04:35:11 PM        90      0.00
04:35:11 PM        91      0.00
04:35:11 PM        92      0.00
04:35:11 PM        93      0.00
04:35:11 PM        94      0.00
04:35:11 PM        95      0.00
04:35:11 PM        96      0.00
04:35:11 PM        97      0.00
04:35:11 PM        98      0.00
04:35:11 PM        99      0.00
04:35:11 PM       100      0.00
04:35:11 PM       101      0.00
04:35:11 PM       102      0.00
04:35:11 PM       103      0.00
04:35:11 PM       104      0.00
04:35:11 PM       105      0.00
04:35:11 PM       106      0.00
04:35:11 PM       107      0.00
04:35:11 PM       108      0.00
04:35:11 PM       109      0.00
04:35:11 PM       110      0.00
04:35:11 PM       111      0.00
04:35:11 PM       112      0.00
04:35:11 PM       113      0.00
04:35:11 PM       114      0.00
04:35:11 PM       115      0.00
04:35:11 PM       116      0.00
04:35:11 PM       117      0.00
04:35:11 PM       118      0.00
04:35:11 PM       119      0.00
04:35:11 PM       120      0.00
04:35:11 PM       121      0.00
04:35:11 PM       122      0.00
04:35:11 PM       123      0.00
04:35:11 PM       124      0.00
04:35:11 PM       125      0.00
04:35:11 PM       126      0.00
04:35:11 PM       127      0.00
04:35:11 PM       128      0.00
04:35:11 PM       129      0.00
04:35:11 PM       130      0.00
04:35:11 PM       131      0.00
04:35:11 PM       132      0.00
04:35:11 PM       133      0.00
04:35:11 PM       134      0.00
04:35:11 PM       135      0.00
04:35:11 PM       136      0.00
04:35:11 PM       137      0.00
04:35:11 PM       138      0.00
04:35:11 PM       139      0.00
04:35:11 PM       140      0.00
04:35:11 PM       141      0.00
04:35:11 PM       142      0.00
04:35:11 PM       143      0.00
04:35:11 PM       144      0.00
04:35:11 PM       145      0.00
04:35:11 PM       146      0.00
04:35:11 PM       147      0.00
04:35:11 PM       148      0.00
04:35:11 PM       149      0.00
04:35:11 PM       150      0.00
04:35:11 PM       151      0.00
04:35:11 PM       152      0.00
04:35:11 PM       153      0.00
04:35:11 PM       154      0.00
04:35:11 PM       155      0.00
04:35:11 PM       156      0.00
04:35:11 PM       157      0.00
04:35:11 PM       158      0.00
04:35:11 PM       159      0.00
04:35:11 PM       160      0.00
04:35:11 PM       161      0.00
04:35:11 PM       162      0.00
04:35:11 PM       163      0.00
04:35:11 PM       164      0.00
04:35:11 PM       165      0.00
04:35:11 PM       166      0.00
04:35:11 PM       167      0.00
04:35:11 PM       168      0.00
04:35:11 PM       169      0.00
04:35:11 PM       170      0.00
04:35:11 PM       171      0.00
04:35:11 PM       172      0.00
04:35:11 PM       173      0.00
04:35:11 PM       174      0.00
04:35:11 PM       175      0.00
04:35:11 PM       176      0.00
04:35:11 PM       177      0.00
04:35:11 PM       178      0.00
04:35:11 PM       179      0.00
04:35:11 PM       180      0.00
04:35:11 PM       181      0.00
04:35:11 PM       182      0.00
04:35:11 PM       183      0.00
04:35:11 PM       184      0.00
04:35:11 PM       185      0.00
04:35:11 PM       186      0.00
04:35:11 PM       187      0.00
04:35:11 PM       188      0.00
04:35:11 PM       189      0.00
04:35:11 PM       190      0.00
04:35:11 PM       191      0.00
04:35:11 PM       192      0.00
04:35:11 PM       193      0.00
04:35:11 PM       194      0.00
04:35:11 PM       195      0.00
04:35:11 PM       196      0.00
04:35:11 PM       197      0.00
04:35:11 PM       198      0.00
04:35:11 PM       199      0.00
04:35:11 PM       200      0.00
04:35:11 PM       201      0.00
04:35:11 PM       202      0.00
04:35:11 PM       203      0.00
04:35:11 PM       204      0.00
04:35:11 PM       205      0.00
04:35:11 PM       206      0.00
04:35:11 PM       207      0.00
04:35:11 PM       208      0.00
04:35:11 PM       209      0.00
04:35:11 PM       210      0.00
04:35:11 PM       211      0.00
04:35:11 PM       212      0.00
04:35:11 PM       213      0.00
04:35:11 PM       214      0.00
04:35:11 PM       215      0.00
04:35:11 PM       216      0.00
04:35:11 PM       217      0.00
04:35:11 PM       218      0.00
04:35:11 PM       219      0.00
04:35:11 PM       220      0.00
04:35:11 PM       221      0.00
04:35:11 PM       222      0.00
04:35:11 PM       223      0.00
04:35:11 PM       224      0.00
04:35:11 PM       225      0.00
04:35:11 PM       226      0.00
04:35:11 PM       227      0.00
04:35:11 PM       228      0.00
04:35:11 PM       229      0.00
04:35:11 PM       230      0.00
04:35:11 PM       231      0.00
04:35:11 PM       232      0.00
04:35:11 PM       233      0.00
04:35:11 PM       234      0.00
04:35:11 PM       235      0.00
04:35:11 PM       236      0.00
04:35:11 PM       237      0.00
04:35:11 PM       238      0.00
04:35:11 PM       239      0.00
04:35:11 PM       240      0.00
04:35:11 PM       241      0.00
04:35:11 PM       242      0.00
04:35:11 PM       243      0.00
04:35:11 PM       244      0.00
04:35:11 PM       245      0.00
04:35:11 PM       246      0.00
04:35:11 PM       247      0.00
04:35:11 PM       248      0.00
04:35:11 PM       249      0.00
04:35:11 PM       250      0.00
04:35:11 PM       251      0.00
04:35:11 PM       252      0.00
04:35:11 PM       253      0.00
04:35:11 PM       254      0.00
04:35:11 PM       255      0.00

04:35:09 PM  pswpin/s pswpout/s
04:35:11 PM      0.00      0.00

04:35:09 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:11 PM      0.00      0.00     33.50      0.00    284.00      0.00      0.00      0.00      0.00

04:35:09 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00

04:35:09 PM   frmpg/s   bufpg/s   campg/s
04:35:11 PM      0.00      0.00      2.00

04:35:09 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:11 PM     81080   8114480     99.01       176   5018684   4685372      8.34   4226100   2971912

04:35:09 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:11 PM  48016452       948      0.00       224     23.63

04:35:09 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:11 PM    158622      9888    134011       110

04:35:09 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:11 PM         0       475      0.00      0.01      0.05         0

04:35:09 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:11 PM    dev8-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:11 PM   dev8-16      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:11 PM    dev9-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:11 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:11 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:11 PM      eth0     12.50     12.50      5.33      9.87      0.00      0.00      0.00
04:35:11 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:11 PM      tun0     12.00     12.00      4.35      8.91      0.00      0.00      0.00

04:35:09 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:11 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:11 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:11 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:11 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:11 PM       882        32         9         0         0         0

04:35:09 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:11 PM     24.00      0.00     24.00     24.00      0.00      0.00      0.00      0.00

04:35:09 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM  active/s passive/s    iseg/s    oseg/s
04:35:11 PM      0.00      0.00     12.00     12.00

04:35:09 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00

04:35:09 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:11 PM     12.00     12.00      0.00      0.00

04:35:09 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:11 PM         2         2         0         0

04:35:09 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:11 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:09 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:11 PM      0.00      0.00      0.00      0.00

04:35:09 PM     CPU       MHz
04:35:11 PM     all   1596.00
04:35:11 PM       0   1596.00
04:35:11 PM       1   1596.00
04:35:11 PM       2   1596.00
04:35:11 PM       3   1596.00

04:35:09 PM     FAN       rpm      drpm                   DEVICE
04:35:11 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:11 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:11 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:11 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:09 PM    TEMP      degC     %temp                   DEVICE
04:35:11 PM       1     47.00     78.33           atk0110-acpi-0
04:35:11 PM       2     43.00     95.56           atk0110-acpi-0

04:35:09 PM      IN       inV       %in                   DEVICE
04:35:11 PM       0      1.10     33.87           atk0110-acpi-0
04:35:11 PM       1      3.25     42.12           atk0110-acpi-0
04:35:11 PM       2      5.02     51.70           atk0110-acpi-0
04:35:11 PM       3     12.20     55.44           atk0110-acpi-0

04:35:09 PM kbhugfree kbhugused  %hugused
04:35:11 PM         0         0      0.00

04:35:09 PM     CPU    wghMHz
04:35:11 PM     all   1620.06
04:35:11 PM       0   1596.00
04:35:11 PM       1   1699.74
04:35:11 PM       2   1596.00
04:35:11 PM       3   1596.00

04:35:11 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:13 PM     all      5.38      0.00      0.62      3.38      0.00      0.00      0.00      0.00     90.62
04:35:13 PM       0      5.50      0.00      0.00     13.50      0.00      0.00      0.00      0.00     81.00
04:35:13 PM       1      9.50      0.00      0.50      0.00      0.00      0.00      0.00      0.00     90.00
04:35:13 PM       2      1.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     97.50
04:35:13 PM       3      5.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     94.00

04:35:11 PM    proc/s   cswch/s
04:35:13 PM      0.50   2904.50

04:35:11 PM      INTR    intr/s
04:35:13 PM       sum    880.00
04:35:13 PM         0      0.00
04:35:13 PM         1      0.00
04:35:13 PM         2      0.00
04:35:13 PM         3      0.00
04:35:13 PM         4      0.00
04:35:13 PM         5      0.00
04:35:13 PM         6      0.00
04:35:13 PM         7      0.00
04:35:13 PM         8      0.00
04:35:13 PM         9      0.00
04:35:13 PM        10      0.00
04:35:13 PM        11      0.00
04:35:13 PM        12      0.00
04:35:13 PM        13      0.00
04:35:13 PM        14      0.00
04:35:13 PM        15      0.00
04:35:13 PM        16      1.00
04:35:13 PM        17      2.50
04:35:13 PM        18      0.00
04:35:13 PM        19     66.50
04:35:13 PM        20      0.00
04:35:13 PM        21      0.00
04:35:13 PM        22      0.00
04:35:13 PM        23      0.50
04:35:13 PM        24      0.00
04:35:13 PM        25      0.00
04:35:13 PM        26      0.00
04:35:13 PM        27      0.00
04:35:13 PM        28      0.00
04:35:13 PM        29      0.00
04:35:13 PM        30      0.00
04:35:13 PM        31      0.00
04:35:13 PM        32      0.00
04:35:13 PM        33      0.00
04:35:13 PM        34      0.00
04:35:13 PM        35      0.00
04:35:13 PM        36      0.00
04:35:13 PM        37      0.00
04:35:13 PM        38      0.00
04:35:13 PM        39      0.00
04:35:13 PM        40      0.00
04:35:13 PM        41      0.00
04:35:13 PM        42      0.00
04:35:13 PM        43      0.00
04:35:13 PM        44     54.00
04:35:13 PM        45      1.00
04:35:13 PM        46      0.00
04:35:13 PM        47      0.00
04:35:13 PM        48      0.00
04:35:13 PM        49      0.00
04:35:13 PM        50      0.00
04:35:13 PM        51      0.00
04:35:13 PM        52      0.00
04:35:13 PM        53      0.00
04:35:13 PM        54      0.00
04:35:13 PM        55      0.00
04:35:13 PM        56      0.00
04:35:13 PM        57      0.00
04:35:13 PM        58      0.00
04:35:13 PM        59      0.00
04:35:13 PM        60      0.00
04:35:13 PM        61      0.00
04:35:13 PM        62      0.00
04:35:13 PM        63      0.00
04:35:13 PM        64      0.00
04:35:13 PM        65      0.00
04:35:13 PM        66      0.00
04:35:13 PM        67      0.00
04:35:13 PM        68      0.00
04:35:13 PM        69      0.00
04:35:13 PM        70      0.00
04:35:13 PM        71      0.00
04:35:13 PM        72      0.00
04:35:13 PM        73      0.00
04:35:13 PM        74      0.00
04:35:13 PM        75      0.00
04:35:13 PM        76      0.00
04:35:13 PM        77      0.00
04:35:13 PM        78      0.00
04:35:13 PM        79      0.00
04:35:13 PM        80      0.00
04:35:13 PM        81      0.00
04:35:13 PM        82      0.00
04:35:13 PM        83      0.00
04:35:13 PM        84      0.00
04:35:13 PM        85      0.00
04:35:13 PM        86      0.00
04:35:13 PM        87      0.00
04:35:13 PM        88      0.00
04:35:13 PM        89      0.00
04:35:13 PM        90      0.00
04:35:13 PM        91      0.00
04:35:13 PM        92      0.00
04:35:13 PM        93      0.00
04:35:13 PM        94      0.00
04:35:13 PM        95      0.00
04:35:13 PM        96      0.00
04:35:13 PM        97      0.00
04:35:13 PM        98      0.00
04:35:13 PM        99      0.00
04:35:13 PM       100      0.00
04:35:13 PM       101      0.00
04:35:13 PM       102      0.00
04:35:13 PM       103      0.00
04:35:13 PM       104      0.00
04:35:13 PM       105      0.00
04:35:13 PM       106      0.00
04:35:13 PM       107      0.00
04:35:13 PM       108      0.00
04:35:13 PM       109      0.00
04:35:13 PM       110      0.00
04:35:13 PM       111      0.00
04:35:13 PM       112      0.00
04:35:13 PM       113      0.00
04:35:13 PM       114      0.00
04:35:13 PM       115      0.00
04:35:13 PM       116      0.00
04:35:13 PM       117      0.00
04:35:13 PM       118      0.00
04:35:13 PM       119      0.00
04:35:13 PM       120      0.00
04:35:13 PM       121      0.00
04:35:13 PM       122      0.00
04:35:13 PM       123      0.00
04:35:13 PM       124      0.00
04:35:13 PM       125      0.00
04:35:13 PM       126      0.00
04:35:13 PM       127      0.00
04:35:13 PM       128      0.00
04:35:13 PM       129      0.00
04:35:13 PM       130      0.00
04:35:13 PM       131      0.00
04:35:13 PM       132      0.00
04:35:13 PM       133      0.00
04:35:13 PM       134      0.00
04:35:13 PM       135      0.00
04:35:13 PM       136      0.00
04:35:13 PM       137      0.00
04:35:13 PM       138      0.00
04:35:13 PM       139      0.00
04:35:13 PM       140      0.00
04:35:13 PM       141      0.00
04:35:13 PM       142      0.00
04:35:13 PM       143      0.00
04:35:13 PM       144      0.00
04:35:13 PM       145      0.00
04:35:13 PM       146      0.00
04:35:13 PM       147      0.00
04:35:13 PM       148      0.00
04:35:13 PM       149      0.00
04:35:13 PM       150      0.00
04:35:13 PM       151      0.00
04:35:13 PM       152      0.00
04:35:13 PM       153      0.00
04:35:13 PM       154      0.00
04:35:13 PM       155      0.00
04:35:13 PM       156      0.00
04:35:13 PM       157      0.00
04:35:13 PM       158      0.00
04:35:13 PM       159      0.00
04:35:13 PM       160      0.00
04:35:13 PM       161      0.00
04:35:13 PM       162      0.00
04:35:13 PM       163      0.00
04:35:13 PM       164      0.00
04:35:13 PM       165      0.00
04:35:13 PM       166      0.00
04:35:13 PM       167      0.00
04:35:13 PM       168      0.00
04:35:13 PM       169      0.00
04:35:13 PM       170      0.00
04:35:13 PM       171      0.00
04:35:13 PM       172      0.00
04:35:13 PM       173      0.00
04:35:13 PM       174      0.00
04:35:13 PM       175      0.00
04:35:13 PM       176      0.00
04:35:13 PM       177      0.00
04:35:13 PM       178      0.00
04:35:13 PM       179      0.00
04:35:13 PM       180      0.00
04:35:13 PM       181      0.00
04:35:13 PM       182      0.00
04:35:13 PM       183      0.00
04:35:13 PM       184      0.00
04:35:13 PM       185      0.00
04:35:13 PM       186      0.00
04:35:13 PM       187      0.00
04:35:13 PM       188      0.00
04:35:13 PM       189      0.00
04:35:13 PM       190      0.00
04:35:13 PM       191      0.00
04:35:13 PM       192      0.00
04:35:13 PM       193      0.00
04:35:13 PM       194      0.00
04:35:13 PM       195      0.00
04:35:13 PM       196      0.00
04:35:13 PM       197      0.00
04:35:13 PM       198      0.00
04:35:13 PM       199      0.00
04:35:13 PM       200      0.00
04:35:13 PM       201      0.00
04:35:13 PM       202      0.00
04:35:13 PM       203      0.00
04:35:13 PM       204      0.00
04:35:13 PM       205      0.00
04:35:13 PM       206      0.00
04:35:13 PM       207      0.00
04:35:13 PM       208      0.00
04:35:13 PM       209      0.00
04:35:13 PM       210      0.00
04:35:13 PM       211      0.00
04:35:13 PM       212      0.00
04:35:13 PM       213      0.00
04:35:13 PM       214      0.00
04:35:13 PM       215      0.00
04:35:13 PM       216      0.00
04:35:13 PM       217      0.00
04:35:13 PM       218      0.00
04:35:13 PM       219      0.00
04:35:13 PM       220      0.00
04:35:13 PM       221      0.00
04:35:13 PM       222      0.00
04:35:13 PM       223      0.00
04:35:13 PM       224      0.00
04:35:13 PM       225      0.00
04:35:13 PM       226      0.00
04:35:13 PM       227      0.00
04:35:13 PM       228      0.00
04:35:13 PM       229      0.00
04:35:13 PM       230      0.00
04:35:13 PM       231      0.00
04:35:13 PM       232      0.00
04:35:13 PM       233      0.00
04:35:13 PM       234      0.00
04:35:13 PM       235      0.00
04:35:13 PM       236      0.00
04:35:13 PM       237      0.00
04:35:13 PM       238      0.00
04:35:13 PM       239      0.00
04:35:13 PM       240      0.00
04:35:13 PM       241      0.00
04:35:13 PM       242      0.00
04:35:13 PM       243      0.00
04:35:13 PM       244      0.00
04:35:13 PM       245      0.00
04:35:13 PM       246      0.00
04:35:13 PM       247      0.00
04:35:13 PM       248      0.00
04:35:13 PM       249      0.00
04:35:13 PM       250      0.00
04:35:13 PM       251      0.00
04:35:13 PM       252      0.00
04:35:13 PM       253      0.00
04:35:13 PM       254      0.00
04:35:13 PM       255      0.00

04:35:11 PM  pswpin/s pswpout/s
04:35:13 PM      0.00      0.00

04:35:11 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:13 PM     52.00    159.00   1033.00      0.00   1284.00      0.00      0.00      0.00      0.00

04:35:11 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:13 PM     91.00     15.00     76.00    208.00    922.00

04:35:11 PM   frmpg/s   bufpg/s   campg/s
04:35:13 PM   -140.50      0.00     24.50

04:35:11 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:13 PM     79956   8115604     99.02       176   5018880   4689468      8.34   4226692   2972032

04:35:11 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:13 PM  48016452       948      0.00       224     23.63

04:35:11 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:13 PM    158622      9888    134011       110

04:35:11 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:13 PM         0       476      0.00      0.01      0.05         0

04:35:11 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:13 PM    dev8-0     30.00     36.00    310.00     11.53      0.25      8.33      8.33     25.00
04:35:13 PM   dev8-16     28.50     68.00    310.00     13.26      0.25      8.77      8.77     25.00
04:35:13 PM    dev9-0     32.50    104.00    302.00     12.49      0.00      0.00      0.00      0.00
04:35:13 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:13 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:13 PM      eth0     33.50     24.00     38.88     11.31      0.00      0.00      0.00
04:35:13 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:13 PM      tun0     33.50     24.00     36.27      9.40      0.00      0.00      0.00

04:35:11 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:13 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:13 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:13 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:13 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:13 PM       882        32         9         0         0         0

04:35:11 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:13 PM     67.00      0.00     67.00     48.00      0.00      0.00      0.00      0.00

04:35:11 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM  active/s passive/s    iseg/s    oseg/s
04:35:13 PM      0.00      0.00     33.50     24.00

04:35:11 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00

04:35:11 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:13 PM     33.50     24.00      0.00      0.00

04:35:11 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:13 PM         2         2         0         0

04:35:11 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:13 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:11 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:13 PM      0.00      0.00      0.00      0.00

04:35:11 PM     CPU       MHz
04:35:13 PM     all   1596.00
04:35:13 PM       0   1596.00
04:35:13 PM       1   1596.00
04:35:13 PM       2   1596.00
04:35:13 PM       3   1596.00

04:35:11 PM     FAN       rpm      drpm                   DEVICE
04:35:13 PM       1   2596.00   1996.00           atk0110-acpi-0
04:35:13 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:13 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:13 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:11 PM    TEMP      degC     %temp                   DEVICE
04:35:13 PM       1     47.00     78.33           atk0110-acpi-0
04:35:13 PM       2     43.00     95.56           atk0110-acpi-0

04:35:11 PM      IN       inV       %in                   DEVICE
04:35:13 PM       0      1.10     33.87           atk0110-acpi-0
04:35:13 PM       1      3.25     42.12           atk0110-acpi-0
04:35:13 PM       2      5.02     51.70           atk0110-acpi-0
04:35:13 PM       3     12.20     55.44           atk0110-acpi-0

04:35:11 PM kbhugfree kbhugused  %hugused
04:35:13 PM         0         0      0.00

04:35:11 PM     CPU    wghMHz
04:35:13 PM     all   1699.74
04:35:13 PM       0   1703.73
04:35:13 PM       1   1895.25
04:35:13 PM       2   1596.00
04:35:13 PM       3   1603.98

04:35:13 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:15 PM     all      2.63      0.00      0.75      0.00      0.00      0.00      0.00      0.00     96.62
04:35:15 PM       0      3.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00     97.00
04:35:15 PM       1      7.54      0.00      2.01      0.00      0.00      0.00      0.00      0.00     90.45
04:35:15 PM       2      0.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.50
04:35:15 PM       3      0.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.50

04:35:13 PM    proc/s   cswch/s
04:35:15 PM      0.00   2055.50

04:35:13 PM      INTR    intr/s
04:35:15 PM       sum    688.00
04:35:15 PM         0      0.00
04:35:15 PM         1      0.00
04:35:15 PM         2      0.00
04:35:15 PM         3      0.00
04:35:15 PM         4      0.00
04:35:15 PM         5      0.00
04:35:15 PM         6      0.00
04:35:15 PM         7      0.00
04:35:15 PM         8      0.00
04:35:15 PM         9      0.00
04:35:15 PM        10      0.00
04:35:15 PM        11      0.00
04:35:15 PM        12      0.00
04:35:15 PM        13      0.00
04:35:15 PM        14      0.00
04:35:15 PM        15      0.00
04:35:15 PM        16      1.00
04:35:15 PM        17      2.50
04:35:15 PM        18      0.00
04:35:15 PM        19      0.00
04:35:15 PM        20      0.00
04:35:15 PM        21      0.00
04:35:15 PM        22      0.00
04:35:15 PM        23      0.50
04:35:15 PM        24      0.00
04:35:15 PM        25      0.00
04:35:15 PM        26      0.00
04:35:15 PM        27      0.00
04:35:15 PM        28      0.00
04:35:15 PM        29      0.00
04:35:15 PM        30      0.00
04:35:15 PM        31      0.00
04:35:15 PM        32      0.00
04:35:15 PM        33      0.00
04:35:15 PM        34      0.00
04:35:15 PM        35      0.00
04:35:15 PM        36      0.00
04:35:15 PM        37      0.00
04:35:15 PM        38      0.00
04:35:15 PM        39      0.00
04:35:15 PM        40      0.00
04:35:15 PM        41      0.00
04:35:15 PM        42      0.00
04:35:15 PM        43      0.00
04:35:15 PM        44     12.00
04:35:15 PM        45      1.00
04:35:15 PM        46      0.00
04:35:15 PM        47      0.00
04:35:15 PM        48      0.00
04:35:15 PM        49      0.00
04:35:15 PM        50      0.00
04:35:15 PM        51      0.00
04:35:15 PM        52      0.00
04:35:15 PM        53      0.00
04:35:15 PM        54      0.00
04:35:15 PM        55      0.00
04:35:15 PM        56      0.00
04:35:15 PM        57      0.00
04:35:15 PM        58      0.00
04:35:15 PM        59      0.00
04:35:15 PM        60      0.00
04:35:15 PM        61      0.00
04:35:15 PM        62      0.00
04:35:15 PM        63      0.00
04:35:15 PM        64      0.00
04:35:15 PM        65      0.00
04:35:15 PM        66      0.00
04:35:15 PM        67      0.00
04:35:15 PM        68      0.00
04:35:15 PM        69      0.00
04:35:15 PM        70      0.00
04:35:15 PM        71      0.00
04:35:15 PM        72      0.00
04:35:15 PM        73      0.00
04:35:15 PM        74      0.00
04:35:15 PM        75      0.00
04:35:15 PM        76      0.00
04:35:15 PM        77      0.00
04:35:15 PM        78      0.00
04:35:15 PM        79      0.00
04:35:15 PM        80      0.00
04:35:15 PM        81      0.00
04:35:15 PM        82      0.00
04:35:15 PM        83      0.00
04:35:15 PM        84      0.00
04:35:15 PM        85      0.00
04:35:15 PM        86      0.00
04:35:15 PM        87      0.00
04:35:15 PM        88      0.00
04:35:15 PM        89      0.00
04:35:15 PM        90      0.00
04:35:15 PM        91      0.00
04:35:15 PM        92      0.00
04:35:15 PM        93      0.00
04:35:15 PM        94      0.00
04:35:15 PM        95      0.00
04:35:15 PM        96      0.00
04:35:15 PM        97      0.00
04:35:15 PM        98      0.00
04:35:15 PM        99      0.00
04:35:15 PM       100      0.00
04:35:15 PM       101      0.00
04:35:15 PM       102      0.00
04:35:15 PM       103      0.00
04:35:15 PM       104      0.00
04:35:15 PM       105      0.00
04:35:15 PM       106      0.00
04:35:15 PM       107      0.00
04:35:15 PM       108      0.00
04:35:15 PM       109      0.00
04:35:15 PM       110      0.00
04:35:15 PM       111      0.00
04:35:15 PM       112      0.00
04:35:15 PM       113      0.00
04:35:15 PM       114      0.00
04:35:15 PM       115      0.00
04:35:15 PM       116      0.00
04:35:15 PM       117      0.00
04:35:15 PM       118      0.00
04:35:15 PM       119      0.00
04:35:15 PM       120      0.00
04:35:15 PM       121      0.00
04:35:15 PM       122      0.00
04:35:15 PM       123      0.00
04:35:15 PM       124      0.00
04:35:15 PM       125      0.00
04:35:15 PM       126      0.00
04:35:15 PM       127      0.00
04:35:15 PM       128      0.00
04:35:15 PM       129      0.00
04:35:15 PM       130      0.00
04:35:15 PM       131      0.00
04:35:15 PM       132      0.00
04:35:15 PM       133      0.00
04:35:15 PM       134      0.00
04:35:15 PM       135      0.00
04:35:15 PM       136      0.00
04:35:15 PM       137      0.00
04:35:15 PM       138      0.00
04:35:15 PM       139      0.00
04:35:15 PM       140      0.00
04:35:15 PM       141      0.00
04:35:15 PM       142      0.00
04:35:15 PM       143      0.00
04:35:15 PM       144      0.00
04:35:15 PM       145      0.00
04:35:15 PM       146      0.00
04:35:15 PM       147      0.00
04:35:15 PM       148      0.00
04:35:15 PM       149      0.00
04:35:15 PM       150      0.00
04:35:15 PM       151      0.00
04:35:15 PM       152      0.00
04:35:15 PM       153      0.00
04:35:15 PM       154      0.00
04:35:15 PM       155      0.00
04:35:15 PM       156      0.00
04:35:15 PM       157      0.00
04:35:15 PM       158      0.00
04:35:15 PM       159      0.00
04:35:15 PM       160      0.00
04:35:15 PM       161      0.00
04:35:15 PM       162      0.00
04:35:15 PM       163      0.00
04:35:15 PM       164      0.00
04:35:15 PM       165      0.00
04:35:15 PM       166      0.00
04:35:15 PM       167      0.00
04:35:15 PM       168      0.00
04:35:15 PM       169      0.00
04:35:15 PM       170      0.00
04:35:15 PM       171      0.00
04:35:15 PM       172      0.00
04:35:15 PM       173      0.00
04:35:15 PM       174      0.00
04:35:15 PM       175      0.00
04:35:15 PM       176      0.00
04:35:15 PM       177      0.00
04:35:15 PM       178      0.00
04:35:15 PM       179      0.00
04:35:15 PM       180      0.00
04:35:15 PM       181      0.00
04:35:15 PM       182      0.00
04:35:15 PM       183      0.00
04:35:15 PM       184      0.00
04:35:15 PM       185      0.00
04:35:15 PM       186      0.00
04:35:15 PM       187      0.00
04:35:15 PM       188      0.00
04:35:15 PM       189      0.00
04:35:15 PM       190      0.00
04:35:15 PM       191      0.00
04:35:15 PM       192      0.00
04:35:15 PM       193      0.00
04:35:15 PM       194      0.00
04:35:15 PM       195      0.00
04:35:15 PM       196      0.00
04:35:15 PM       197      0.00
04:35:15 PM       198      0.00
04:35:15 PM       199      0.00
04:35:15 PM       200      0.00
04:35:15 PM       201      0.00
04:35:15 PM       202      0.00
04:35:15 PM       203      0.00
04:35:15 PM       204      0.00
04:35:15 PM       205      0.00
04:35:15 PM       206      0.00
04:35:15 PM       207      0.00
04:35:15 PM       208      0.00
04:35:15 PM       209      0.00
04:35:15 PM       210      0.00
04:35:15 PM       211      0.00
04:35:15 PM       212      0.00
04:35:15 PM       213      0.00
04:35:15 PM       214      0.00
04:35:15 PM       215      0.00
04:35:15 PM       216      0.00
04:35:15 PM       217      0.00
04:35:15 PM       218      0.00
04:35:15 PM       219      0.00
04:35:15 PM       220      0.00
04:35:15 PM       221      0.00
04:35:15 PM       222      0.00
04:35:15 PM       223      0.00
04:35:15 PM       224      0.00
04:35:15 PM       225      0.00
04:35:15 PM       226      0.00
04:35:15 PM       227      0.00
04:35:15 PM       228      0.00
04:35:15 PM       229      0.00
04:35:15 PM       230      0.00
04:35:15 PM       231      0.00
04:35:15 PM       232      0.00
04:35:15 PM       233      0.00
04:35:15 PM       234      0.00
04:35:15 PM       235      0.00
04:35:15 PM       236      0.00
04:35:15 PM       237      0.00
04:35:15 PM       238      0.00
04:35:15 PM       239      0.00
04:35:15 PM       240      0.00
04:35:15 PM       241      0.00
04:35:15 PM       242      0.00
04:35:15 PM       243      0.00
04:35:15 PM       244      0.00
04:35:15 PM       245      0.00
04:35:15 PM       246      0.00
04:35:15 PM       247      0.00
04:35:15 PM       248      0.00
04:35:15 PM       249      0.00
04:35:15 PM       250      0.00
04:35:15 PM       251      0.00
04:35:15 PM       252      0.00
04:35:15 PM       253      0.00
04:35:15 PM       254      0.00
04:35:15 PM       255      0.00

04:35:13 PM  pswpin/s pswpout/s
04:35:15 PM      0.00      0.00

04:35:13 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:15 PM      0.00      0.00     37.50      0.00    278.50      0.00      0.00      0.00      0.00

04:35:13 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00

04:35:13 PM   frmpg/s   bufpg/s   campg/s
04:35:15 PM      0.00      0.00      1.50

04:35:13 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:15 PM     79956   8115604     99.02       176   5018892   4689468      8.34   4226696   2972040

04:35:13 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:15 PM  48016452       948      0.00       224     23.63

04:35:13 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:15 PM    158622      9888    134011       110

04:35:13 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:15 PM         1       476      0.00      0.01      0.05         0

04:35:13 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:15 PM    dev8-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:15 PM   dev8-16      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:15 PM    dev9-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:15 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:15 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:15 PM      eth0      6.50      7.00      0.86      8.93      0.00      0.00      0.00
04:35:15 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:15 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:13 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:15 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:15 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:15 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:15 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:15 PM       882        32         9         0         0         0

04:35:13 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:15 PM     13.00      0.00     13.00     13.50      0.00      0.00      0.00      0.00

04:35:13 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM  active/s passive/s    iseg/s    oseg/s
04:35:15 PM      0.00      0.00      6.50      6.50

04:35:13 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00

04:35:13 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:15 PM      6.50      7.00      0.00      0.00

04:35:13 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:15 PM         2         2         0         0

04:35:13 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:15 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:13 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:15 PM      0.00      0.00      0.00      0.00

04:35:13 PM     CPU       MHz
04:35:15 PM     all   1596.00
04:35:15 PM       0   1596.00
04:35:15 PM       1   1596.00
04:35:15 PM       2   1596.00
04:35:15 PM       3   1596.00

04:35:13 PM     FAN       rpm      drpm                   DEVICE
04:35:15 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:15 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:15 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:15 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:13 PM    TEMP      degC     %temp                   DEVICE
04:35:15 PM       1     47.00     78.33           atk0110-acpi-0
04:35:15 PM       2     43.00     95.56           atk0110-acpi-0

04:35:13 PM      IN       inV       %in                   DEVICE
04:35:15 PM       0      1.10     33.87           atk0110-acpi-0
04:35:15 PM       1      3.25     42.12           atk0110-acpi-0
04:35:15 PM       2      5.02     51.70           atk0110-acpi-0
04:35:15 PM       3     12.20     55.44           atk0110-acpi-0

04:35:13 PM kbhugfree kbhugused  %hugused
04:35:15 PM         0         0      0.00

04:35:13 PM     CPU    wghMHz
04:35:15 PM     all   1596.00
04:35:15 PM       0   1596.00
04:35:15 PM       1   1596.00
04:35:15 PM       2   1596.00
04:35:15 PM       3   1596.00

04:35:15 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:17 PM     all      2.38      0.00      0.75      0.00      0.00      0.00      0.00      0.00     96.87
04:35:17 PM       0      7.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     92.00
04:35:17 PM       1      1.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     98.50
04:35:17 PM       2      0.50      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.00
04:35:17 PM       3      1.01      0.00      1.01      0.00      0.00      0.00      0.00      0.00     97.99

04:35:15 PM    proc/s   cswch/s
04:35:17 PM      0.00   2148.00

04:35:15 PM      INTR    intr/s
04:35:17 PM       sum    707.00
04:35:17 PM         0      0.00
04:35:17 PM         1      0.00
04:35:17 PM         2      0.00
04:35:17 PM         3      0.00
04:35:17 PM         4      0.00
04:35:17 PM         5      0.00
04:35:17 PM         6      0.00
04:35:17 PM         7      0.00
04:35:17 PM         8      0.00
04:35:17 PM         9      0.00
04:35:17 PM        10      0.00
04:35:17 PM        11      0.00
04:35:17 PM        12      0.00
04:35:17 PM        13      0.00
04:35:17 PM        14      0.00
04:35:17 PM        15      0.00
04:35:17 PM        16      1.00
04:35:17 PM        17      2.50
04:35:17 PM        18      0.00
04:35:17 PM        19      7.00
04:35:17 PM        20      0.00
04:35:17 PM        21      0.00
04:35:17 PM        22      0.00
04:35:17 PM        23      0.50
04:35:17 PM        24      0.00
04:35:17 PM        25      0.00
04:35:17 PM        26      0.00
04:35:17 PM        27      0.00
04:35:17 PM        28      0.00
04:35:17 PM        29      0.00
04:35:17 PM        30      0.00
04:35:17 PM        31      0.00
04:35:17 PM        32      0.00
04:35:17 PM        33      0.00
04:35:17 PM        34      0.00
04:35:17 PM        35      0.00
04:35:17 PM        36      0.00
04:35:17 PM        37      0.00
04:35:17 PM        38      0.00
04:35:17 PM        39      0.00
04:35:17 PM        40      0.00
04:35:17 PM        41      0.00
04:35:17 PM        42      0.00
04:35:17 PM        43      0.00
04:35:17 PM        44     12.50
04:35:17 PM        45      1.00
04:35:17 PM        46      0.00
04:35:17 PM        47      0.00
04:35:17 PM        48      0.00
04:35:17 PM        49      0.00
04:35:17 PM        50      0.00
04:35:17 PM        51      0.00
04:35:17 PM        52      0.00
04:35:17 PM        53      0.00
04:35:17 PM        54      0.00
04:35:17 PM        55      0.00
04:35:17 PM        56      0.00
04:35:17 PM        57      0.00
04:35:17 PM        58      0.00
04:35:17 PM        59      0.00
04:35:17 PM        60      0.00
04:35:17 PM        61      0.00
04:35:17 PM        62      0.00
04:35:17 PM        63      0.00
04:35:17 PM        64      0.00
04:35:17 PM        65      0.00
04:35:17 PM        66      0.00
04:35:17 PM        67      0.00
04:35:17 PM        68      0.00
04:35:17 PM        69      0.00
04:35:17 PM        70      0.00
04:35:17 PM        71      0.00
04:35:17 PM        72      0.00
04:35:17 PM        73      0.00
04:35:17 PM        74      0.00
04:35:17 PM        75      0.00
04:35:17 PM        76      0.00
04:35:17 PM        77      0.00
04:35:17 PM        78      0.00
04:35:17 PM        79      0.00
04:35:17 PM        80      0.00
04:35:17 PM        81      0.00
04:35:17 PM        82      0.00
04:35:17 PM        83      0.00
04:35:17 PM        84      0.00
04:35:17 PM        85      0.00
04:35:17 PM        86      0.00
04:35:17 PM        87      0.00
04:35:17 PM        88      0.00
04:35:17 PM        89      0.00
04:35:17 PM        90      0.00
04:35:17 PM        91      0.00
04:35:17 PM        92      0.00
04:35:17 PM        93      0.00
04:35:17 PM        94      0.00
04:35:17 PM        95      0.00
04:35:17 PM        96      0.00
04:35:17 PM        97      0.00
04:35:17 PM        98      0.00
04:35:17 PM        99      0.00
04:35:17 PM       100      0.00
04:35:17 PM       101      0.00
04:35:17 PM       102      0.00
04:35:17 PM       103      0.00
04:35:17 PM       104      0.00
04:35:17 PM       105      0.00
04:35:17 PM       106      0.00
04:35:17 PM       107      0.00
04:35:17 PM       108      0.00
04:35:17 PM       109      0.00
04:35:17 PM       110      0.00
04:35:17 PM       111      0.00
04:35:17 PM       112      0.00
04:35:17 PM       113      0.00
04:35:17 PM       114      0.00
04:35:17 PM       115      0.00
04:35:17 PM       116      0.00
04:35:17 PM       117      0.00
04:35:17 PM       118      0.00
04:35:17 PM       119      0.00
04:35:17 PM       120      0.00
04:35:17 PM       121      0.00
04:35:17 PM       122      0.00
04:35:17 PM       123      0.00
04:35:17 PM       124      0.00
04:35:17 PM       125      0.00
04:35:17 PM       126      0.00
04:35:17 PM       127      0.00
04:35:17 PM       128      0.00
04:35:17 PM       129      0.00
04:35:17 PM       130      0.00
04:35:17 PM       131      0.00
04:35:17 PM       132      0.00
04:35:17 PM       133      0.00
04:35:17 PM       134      0.00
04:35:17 PM       135      0.00
04:35:17 PM       136      0.00
04:35:17 PM       137      0.00
04:35:17 PM       138      0.00
04:35:17 PM       139      0.00
04:35:17 PM       140      0.00
04:35:17 PM       141      0.00
04:35:17 PM       142      0.00
04:35:17 PM       143      0.00
04:35:17 PM       144      0.00
04:35:17 PM       145      0.00
04:35:17 PM       146      0.00
04:35:17 PM       147      0.00
04:35:17 PM       148      0.00
04:35:17 PM       149      0.00
04:35:17 PM       150      0.00
04:35:17 PM       151      0.00
04:35:17 PM       152      0.00
04:35:17 PM       153      0.00
04:35:17 PM       154      0.00
04:35:17 PM       155      0.00
04:35:17 PM       156      0.00
04:35:17 PM       157      0.00
04:35:17 PM       158      0.00
04:35:17 PM       159      0.00
04:35:17 PM       160      0.00
04:35:17 PM       161      0.00
04:35:17 PM       162      0.00
04:35:17 PM       163      0.00
04:35:17 PM       164      0.00
04:35:17 PM       165      0.00
04:35:17 PM       166      0.00
04:35:17 PM       167      0.00
04:35:17 PM       168      0.00
04:35:17 PM       169      0.00
04:35:17 PM       170      0.00
04:35:17 PM       171      0.00
04:35:17 PM       172      0.00
04:35:17 PM       173      0.00
04:35:17 PM       174      0.00
04:35:17 PM       175      0.00
04:35:17 PM       176      0.00
04:35:17 PM       177      0.00
04:35:17 PM       178      0.00
04:35:17 PM       179      0.00
04:35:17 PM       180      0.00
04:35:17 PM       181      0.00
04:35:17 PM       182      0.00
04:35:17 PM       183      0.00
04:35:17 PM       184      0.00
04:35:17 PM       185      0.00
04:35:17 PM       186      0.00
04:35:17 PM       187      0.00
04:35:17 PM       188      0.00
04:35:17 PM       189      0.00
04:35:17 PM       190      0.00
04:35:17 PM       191      0.00
04:35:17 PM       192      0.00
04:35:17 PM       193      0.00
04:35:17 PM       194      0.00
04:35:17 PM       195      0.00
04:35:17 PM       196      0.00
04:35:17 PM       197      0.00
04:35:17 PM       198      0.00
04:35:17 PM       199      0.00
04:35:17 PM       200      0.00
04:35:17 PM       201      0.00
04:35:17 PM       202      0.00
04:35:17 PM       203      0.00
04:35:17 PM       204      0.00
04:35:17 PM       205      0.00
04:35:17 PM       206      0.00
04:35:17 PM       207      0.00
04:35:17 PM       208      0.00
04:35:17 PM       209      0.00
04:35:17 PM       210      0.00
04:35:17 PM       211      0.00
04:35:17 PM       212      0.00
04:35:17 PM       213      0.00
04:35:17 PM       214      0.00
04:35:17 PM       215      0.00
04:35:17 PM       216      0.00
04:35:17 PM       217      0.00
04:35:17 PM       218      0.00
04:35:17 PM       219      0.00
04:35:17 PM       220      0.00
04:35:17 PM       221      0.00
04:35:17 PM       222      0.00
04:35:17 PM       223      0.00
04:35:17 PM       224      0.00
04:35:17 PM       225      0.00
04:35:17 PM       226      0.00
04:35:17 PM       227      0.00
04:35:17 PM       228      0.00
04:35:17 PM       229      0.00
04:35:17 PM       230      0.00
04:35:17 PM       231      0.00
04:35:17 PM       232      0.00
04:35:17 PM       233      0.00
04:35:17 PM       234      0.00
04:35:17 PM       235      0.00
04:35:17 PM       236      0.00
04:35:17 PM       237      0.00
04:35:17 PM       238      0.00
04:35:17 PM       239      0.00
04:35:17 PM       240      0.00
04:35:17 PM       241      0.00
04:35:17 PM       242      0.00
04:35:17 PM       243      0.00
04:35:17 PM       244      0.00
04:35:17 PM       245      0.00
04:35:17 PM       246      0.00
04:35:17 PM       247      0.00
04:35:17 PM       248      0.00
04:35:17 PM       249      0.00
04:35:17 PM       250      0.00
04:35:17 PM       251      0.00
04:35:17 PM       252      0.00
04:35:17 PM       253      0.00
04:35:17 PM       254      0.00
04:35:17 PM       255      0.00

04:35:15 PM  pswpin/s pswpout/s
04:35:17 PM      0.00      0.00

04:35:15 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:17 PM      0.00     10.00     31.00      0.00    302.50      0.00      0.00      0.00      0.00

04:35:15 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:17 PM      3.50      0.00      3.50      0.00     28.00

04:35:15 PM   frmpg/s   bufpg/s   campg/s
04:35:17 PM      0.00      0.00      2.00

04:35:15 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:17 PM     79956   8115604     99.02       176   5018908   4689468      8.34   4226700   2972052

04:35:15 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:17 PM  48016452       948      0.00       224     23.63

04:35:15 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:17 PM    158622      9888    134011       110

04:35:15 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:17 PM         0       476      0.00      0.01      0.05         0

04:35:15 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:17 PM    dev8-0      1.50      0.00     12.00      8.00      0.03     16.67     16.67      2.50
04:35:17 PM   dev8-16      1.50      0.00     12.00      8.00      0.02     13.33     13.33      2.00
04:35:17 PM    dev9-0      0.50      0.00      4.00      8.00      0.00      0.00      0.00      0.00
04:35:17 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:17 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:17 PM      eth0      8.00      7.00      1.02      8.93      0.00      0.00      0.00
04:35:17 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:17 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:15 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:17 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:17 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:17 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:17 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:17 PM       882        32         9         0         0         0

04:35:15 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:17 PM     13.50      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:15 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM  active/s passive/s    iseg/s    oseg/s
04:35:17 PM      0.00      0.00      6.50      6.50

04:35:15 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00

04:35:15 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:17 PM      6.50      6.50      0.00      0.00

04:35:15 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:17 PM         2         2         0         0

04:35:15 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:17 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:15 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:17 PM      0.00      0.00      0.00      0.00

04:35:15 PM     CPU       MHz
04:35:17 PM     all   1596.00
04:35:17 PM       0   1596.00
04:35:17 PM       1   1596.00
04:35:17 PM       2   1596.00
04:35:17 PM       3   1596.00

04:35:15 PM     FAN       rpm      drpm                   DEVICE
04:35:17 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:17 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:17 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:17 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:15 PM    TEMP      degC     %temp                   DEVICE
04:35:17 PM       1     47.00     78.33           atk0110-acpi-0
04:35:17 PM       2     43.00     95.56           atk0110-acpi-0

04:35:15 PM      IN       inV       %in                   DEVICE
04:35:17 PM       0      1.10     33.87           atk0110-acpi-0
04:35:17 PM       1      3.25     42.12           atk0110-acpi-0
04:35:17 PM       2      5.02     51.70           atk0110-acpi-0
04:35:17 PM       3     12.20     55.44           atk0110-acpi-0

04:35:15 PM kbhugfree kbhugused  %hugused
04:35:17 PM         0         0      0.00

04:35:15 PM     CPU    wghMHz
04:35:17 PM     all   1596.00
04:35:17 PM       0   1596.00
04:35:17 PM       1   1596.00
04:35:17 PM       2   1596.00
04:35:17 PM       3   1596.00

04:35:17 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:19 PM     all      3.62      0.00      0.87      0.00      0.00      0.00      0.12      0.00     95.38
04:35:19 PM       0      7.50      0.00      1.00      0.00      0.00      0.00      0.50      0.00     91.00
04:35:19 PM       1      2.99      0.00      1.00      0.00      0.00      0.00      0.00      0.00     96.02
04:35:19 PM       2      0.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.50
04:35:19 PM       3      4.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     95.00

04:35:17 PM    proc/s   cswch/s
04:35:19 PM      0.00   2094.50

04:35:17 PM      INTR    intr/s
04:35:19 PM       sum    703.00
04:35:19 PM         0      0.00
04:35:19 PM         1      0.00
04:35:19 PM         2      0.00
04:35:19 PM         3      0.00
04:35:19 PM         4      0.00
04:35:19 PM         5      0.00
04:35:19 PM         6      0.00
04:35:19 PM         7      0.00
04:35:19 PM         8      0.00
04:35:19 PM         9      0.00
04:35:19 PM        10      0.00
04:35:19 PM        11      0.00
04:35:19 PM        12      0.00
04:35:19 PM        13      0.00
04:35:19 PM        14      0.00
04:35:19 PM        15      0.00
04:35:19 PM        16      1.00
04:35:19 PM        17      2.50
04:35:19 PM        18      0.00
04:35:19 PM        19      8.00
04:35:19 PM        20      0.00
04:35:19 PM        21      0.00
04:35:19 PM        22      0.00
04:35:19 PM        23      0.50
04:35:19 PM        24      0.00
04:35:19 PM        25      0.00
04:35:19 PM        26      0.00
04:35:19 PM        27      0.00
04:35:19 PM        28      0.00
04:35:19 PM        29      0.00
04:35:19 PM        30      0.00
04:35:19 PM        31      0.00
04:35:19 PM        32      0.00
04:35:19 PM        33      0.00
04:35:19 PM        34      0.00
04:35:19 PM        35      0.00
04:35:19 PM        36      0.00
04:35:19 PM        37      0.00
04:35:19 PM        38      0.00
04:35:19 PM        39      0.00
04:35:19 PM        40      0.00
04:35:19 PM        41      0.00
04:35:19 PM        42      0.00
04:35:19 PM        43      0.00
04:35:19 PM        44     11.50
04:35:19 PM        45      1.00
04:35:19 PM        46      0.00
04:35:19 PM        47      0.00
04:35:19 PM        48      0.00
04:35:19 PM        49      0.00
04:35:19 PM        50      0.00
04:35:19 PM        51      0.00
04:35:19 PM        52      0.00
04:35:19 PM        53      0.00
04:35:19 PM        54      0.00
04:35:19 PM        55      0.00
04:35:19 PM        56      0.00
04:35:19 PM        57      0.00
04:35:19 PM        58      0.00
04:35:19 PM        59      0.00
04:35:19 PM        60      0.00
04:35:19 PM        61      0.00
04:35:19 PM        62      0.00
04:35:19 PM        63      0.00
04:35:19 PM        64      0.00
04:35:19 PM        65      0.00
04:35:19 PM        66      0.00
04:35:19 PM        67      0.00
04:35:19 PM        68      0.00
04:35:19 PM        69      0.00
04:35:19 PM        70      0.00
04:35:19 PM        71      0.00
04:35:19 PM        72      0.00
04:35:19 PM        73      0.00
04:35:19 PM        74      0.00
04:35:19 PM        75      0.00
04:35:19 PM        76      0.00
04:35:19 PM        77      0.00
04:35:19 PM        78      0.00
04:35:19 PM        79      0.00
04:35:19 PM        80      0.00
04:35:19 PM        81      0.00
04:35:19 PM        82      0.00
04:35:19 PM        83      0.00
04:35:19 PM        84      0.00
04:35:19 PM        85      0.00
04:35:19 PM        86      0.00
04:35:19 PM        87      0.00
04:35:19 PM        88      0.00
04:35:19 PM        89      0.00
04:35:19 PM        90      0.00
04:35:19 PM        91      0.00
04:35:19 PM        92      0.00
04:35:19 PM        93      0.00
04:35:19 PM        94      0.00
04:35:19 PM        95      0.00
04:35:19 PM        96      0.00
04:35:19 PM        97      0.00
04:35:19 PM        98      0.00
04:35:19 PM        99      0.00
04:35:19 PM       100      0.00
04:35:19 PM       101      0.00
04:35:19 PM       102      0.00
04:35:19 PM       103      0.00
04:35:19 PM       104      0.00
04:35:19 PM       105      0.00
04:35:19 PM       106      0.00
04:35:19 PM       107      0.00
04:35:19 PM       108      0.00
04:35:19 PM       109      0.00
04:35:19 PM       110      0.00
04:35:19 PM       111      0.00
04:35:19 PM       112      0.00
04:35:19 PM       113      0.00
04:35:19 PM       114      0.00
04:35:19 PM       115      0.00
04:35:19 PM       116      0.00
04:35:19 PM       117      0.00
04:35:19 PM       118      0.00
04:35:19 PM       119      0.00
04:35:19 PM       120      0.00
04:35:19 PM       121      0.00
04:35:19 PM       122      0.00
04:35:19 PM       123      0.00
04:35:19 PM       124      0.00
04:35:19 PM       125      0.00
04:35:19 PM       126      0.00
04:35:19 PM       127      0.00
04:35:19 PM       128      0.00
04:35:19 PM       129      0.00
04:35:19 PM       130      0.00
04:35:19 PM       131      0.00
04:35:19 PM       132      0.00
04:35:19 PM       133      0.00
04:35:19 PM       134      0.00
04:35:19 PM       135      0.00
04:35:19 PM       136      0.00
04:35:19 PM       137      0.00
04:35:19 PM       138      0.00
04:35:19 PM       139      0.00
04:35:19 PM       140      0.00
04:35:19 PM       141      0.00
04:35:19 PM       142      0.00
04:35:19 PM       143      0.00
04:35:19 PM       144      0.00
04:35:19 PM       145      0.00
04:35:19 PM       146      0.00
04:35:19 PM       147      0.00
04:35:19 PM       148      0.00
04:35:19 PM       149      0.00
04:35:19 PM       150      0.00
04:35:19 PM       151      0.00
04:35:19 PM       152      0.00
04:35:19 PM       153      0.00
04:35:19 PM       154      0.00
04:35:19 PM       155      0.00
04:35:19 PM       156      0.00
04:35:19 PM       157      0.00
04:35:19 PM       158      0.00
04:35:19 PM       159      0.00
04:35:19 PM       160      0.00
04:35:19 PM       161      0.00
04:35:19 PM       162      0.00
04:35:19 PM       163      0.00
04:35:19 PM       164      0.00
04:35:19 PM       165      0.00
04:35:19 PM       166      0.00
04:35:19 PM       167      0.00
04:35:19 PM       168      0.00
04:35:19 PM       169      0.00
04:35:19 PM       170      0.00
04:35:19 PM       171      0.00
04:35:19 PM       172      0.00
04:35:19 PM       173      0.00
04:35:19 PM       174      0.00
04:35:19 PM       175      0.00
04:35:19 PM       176      0.00
04:35:19 PM       177      0.00
04:35:19 PM       178      0.00
04:35:19 PM       179      0.00
04:35:19 PM       180      0.00
04:35:19 PM       181      0.00
04:35:19 PM       182      0.00
04:35:19 PM       183      0.00
04:35:19 PM       184      0.00
04:35:19 PM       185      0.00
04:35:19 PM       186      0.00
04:35:19 PM       187      0.00
04:35:19 PM       188      0.00
04:35:19 PM       189      0.00
04:35:19 PM       190      0.00
04:35:19 PM       191      0.00
04:35:19 PM       192      0.00
04:35:19 PM       193      0.00
04:35:19 PM       194      0.00
04:35:19 PM       195      0.00
04:35:19 PM       196      0.00
04:35:19 PM       197      0.00
04:35:19 PM       198      0.00
04:35:19 PM       199      0.00
04:35:19 PM       200      0.00
04:35:19 PM       201      0.00
04:35:19 PM       202      0.00
04:35:19 PM       203      0.00
04:35:19 PM       204      0.00
04:35:19 PM       205      0.00
04:35:19 PM       206      0.00
04:35:19 PM       207      0.00
04:35:19 PM       208      0.00
04:35:19 PM       209      0.00
04:35:19 PM       210      0.00
04:35:19 PM       211      0.00
04:35:19 PM       212      0.00
04:35:19 PM       213      0.00
04:35:19 PM       214      0.00
04:35:19 PM       215      0.00
04:35:19 PM       216      0.00
04:35:19 PM       217      0.00
04:35:19 PM       218      0.00
04:35:19 PM       219      0.00
04:35:19 PM       220      0.00
04:35:19 PM       221      0.00
04:35:19 PM       222      0.00
04:35:19 PM       223      0.00
04:35:19 PM       224      0.00
04:35:19 PM       225      0.00
04:35:19 PM       226      0.00
04:35:19 PM       227      0.00
04:35:19 PM       228      0.00
04:35:19 PM       229      0.00
04:35:19 PM       230      0.00
04:35:19 PM       231      0.00
04:35:19 PM       232      0.00
04:35:19 PM       233      0.00
04:35:19 PM       234      0.00
04:35:19 PM       235      0.00
04:35:19 PM       236      0.00
04:35:19 PM       237      0.00
04:35:19 PM       238      0.00
04:35:19 PM       239      0.00
04:35:19 PM       240      0.00
04:35:19 PM       241      0.00
04:35:19 PM       242      0.00
04:35:19 PM       243      0.00
04:35:19 PM       244      0.00
04:35:19 PM       245      0.00
04:35:19 PM       246      0.00
04:35:19 PM       247      0.00
04:35:19 PM       248      0.00
04:35:19 PM       249      0.00
04:35:19 PM       250      0.00
04:35:19 PM       251      0.00
04:35:19 PM       252      0.00
04:35:19 PM       253      0.00
04:35:19 PM       254      0.00
04:35:19 PM       255      0.00

04:35:17 PM  pswpin/s pswpout/s
04:35:19 PM      0.00      0.00

04:35:17 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:19 PM      0.00     22.00    752.00      0.00    923.50      0.00      0.00      0.00      0.00

04:35:17 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:19 PM      5.00      0.00      5.00      0.00    100.00

04:35:17 PM   frmpg/s   bufpg/s   campg/s
04:35:19 PM     15.50      0.00      2.00

04:35:17 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:19 PM     80080   8115480     99.02       176   5018924   4689464      8.34   4226292   2972008

04:35:17 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:19 PM  48016452       948      0.00       224     23.63

04:35:17 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:19 PM    158622      9888    134011       110

04:35:17 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:19 PM         0       476      0.00      0.01      0.05         0

04:35:17 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:19 PM    dev8-0      2.00      0.00     36.00     18.00      0.02     10.00     10.00      2.00
04:35:19 PM   dev8-16      2.00      0.00     36.00     18.00      0.01      5.00      5.00      1.00
04:35:19 PM    dev9-0      1.00      0.00     28.00     28.00      0.00      0.00      0.00      0.00
04:35:19 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:19 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:19 PM      eth0      6.00      7.00      0.81      8.98      0.00      0.00      0.00
04:35:19 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:19 PM      tun0      6.00      7.00      0.33      8.43      0.00      0.00      0.00

04:35:17 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:19 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:19 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:19 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:19 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:19 PM       882        32         9         0         0         0

04:35:17 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:19 PM     12.00      0.00     12.00     14.00      0.00      0.00      0.00      0.00

04:35:17 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM  active/s passive/s    iseg/s    oseg/s
04:35:19 PM      0.00      0.00      6.00      7.00

04:35:17 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00

04:35:17 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:19 PM      6.00      7.00      0.00      0.00

04:35:17 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:19 PM         2         2         0         0

04:35:17 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:19 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:17 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:19 PM      0.00      0.00      0.00      0.00

04:35:17 PM     CPU       MHz
04:35:19 PM     all   1596.00
04:35:19 PM       0   1596.00
04:35:19 PM       1   1596.00
04:35:19 PM       2   1596.00
04:35:19 PM       3   1596.00

04:35:17 PM     FAN       rpm      drpm                   DEVICE
04:35:19 PM       1   2596.00   1996.00           atk0110-acpi-0
04:35:19 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:19 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:19 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:17 PM    TEMP      degC     %temp                   DEVICE
04:35:19 PM       1     47.00     78.33           atk0110-acpi-0
04:35:19 PM       2     43.00     95.56           atk0110-acpi-0

04:35:17 PM      IN       inV       %in                   DEVICE
04:35:19 PM       0      1.10     33.87           atk0110-acpi-0
04:35:19 PM       1      3.25     42.12           atk0110-acpi-0
04:35:19 PM       2      5.02     51.70           atk0110-acpi-0
04:35:19 PM       3     12.20     55.44           atk0110-acpi-0

04:35:17 PM kbhugfree kbhugused  %hugused
04:35:19 PM         0         0      0.00

04:35:17 PM     CPU    wghMHz
04:35:19 PM     all   1687.31
04:35:19 PM       0   1596.00
04:35:19 PM       1   1596.00
04:35:19 PM       2   1596.00
04:35:19 PM       3   1955.10

04:35:19 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:21 PM     all      2.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     97.00
04:35:21 PM       0      4.50      0.00      3.00      0.00      0.00      0.00      0.00      0.00     92.50
04:35:21 PM       1      2.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     96.50
04:35:21 PM       2      0.50      0.00      0.00      0.00      0.00      0.00      0.00      0.00     99.50
04:35:21 PM       3      0.50      0.00      0.00      0.00      0.00      0.00      0.00      0.00     99.50

04:35:19 PM    proc/s   cswch/s
04:35:21 PM      0.00   2112.00

04:35:19 PM      INTR    intr/s
04:35:21 PM       sum    689.00
04:35:21 PM         0      0.00
04:35:21 PM         1      0.00
04:35:21 PM         2      0.00
04:35:21 PM         3      0.00
04:35:21 PM         4      0.00
04:35:21 PM         5      0.00
04:35:21 PM         6      0.00
04:35:21 PM         7      0.00
04:35:21 PM         8      0.00
04:35:21 PM         9      0.00
04:35:21 PM        10      0.00
04:35:21 PM        11      0.00
04:35:21 PM        12      0.00
04:35:21 PM        13      0.00
04:35:21 PM        14      0.00
04:35:21 PM        15      0.00
04:35:21 PM        16      1.00
04:35:21 PM        17      2.50
04:35:21 PM        18      0.00
04:35:21 PM        19      8.00
04:35:21 PM        20      0.00
04:35:21 PM        21      0.00
04:35:21 PM        22      0.00
04:35:21 PM        23      0.50
04:35:21 PM        24      0.00
04:35:21 PM        25      0.00
04:35:21 PM        26      0.00
04:35:21 PM        27      0.00
04:35:21 PM        28      0.00
04:35:21 PM        29      0.00
04:35:21 PM        30      0.00
04:35:21 PM        31      0.00
04:35:21 PM        32      0.00
04:35:21 PM        33      0.00
04:35:21 PM        34      0.00
04:35:21 PM        35      0.00
04:35:21 PM        36      0.00
04:35:21 PM        37      0.00
04:35:21 PM        38      0.00
04:35:21 PM        39      0.00
04:35:21 PM        40      0.00
04:35:21 PM        41      0.00
04:35:21 PM        42      0.00
04:35:21 PM        43      0.00
04:35:21 PM        44     11.50
04:35:21 PM        45      1.00
04:35:21 PM        46      0.00
04:35:21 PM        47      0.00
04:35:21 PM        48      0.00
04:35:21 PM        49      0.00
04:35:21 PM        50      0.00
04:35:21 PM        51      0.00
04:35:21 PM        52      0.00
04:35:21 PM        53      0.00
04:35:21 PM        54      0.00
04:35:21 PM        55      0.00
04:35:21 PM        56      0.00
04:35:21 PM        57      0.00
04:35:21 PM        58      0.00
04:35:21 PM        59      0.00
04:35:21 PM        60      0.00
04:35:21 PM        61      0.00
04:35:21 PM        62      0.00
04:35:21 PM        63      0.00
04:35:21 PM        64      0.00
04:35:21 PM        65      0.00
04:35:21 PM        66      0.00
04:35:21 PM        67      0.00
04:35:21 PM        68      0.00
04:35:21 PM        69      0.00
04:35:21 PM        70      0.00
04:35:21 PM        71      0.00
04:35:21 PM        72      0.00
04:35:21 PM        73      0.00
04:35:21 PM        74      0.00
04:35:21 PM        75      0.00
04:35:21 PM        76      0.00
04:35:21 PM        77      0.00
04:35:21 PM        78      0.00
04:35:21 PM        79      0.00
04:35:21 PM        80      0.00
04:35:21 PM        81      0.00
04:35:21 PM        82      0.00
04:35:21 PM        83      0.00
04:35:21 PM        84      0.00
04:35:21 PM        85      0.00
04:35:21 PM        86      0.00
04:35:21 PM        87      0.00
04:35:21 PM        88      0.00
04:35:21 PM        89      0.00
04:35:21 PM        90      0.00
04:35:21 PM        91      0.00
04:35:21 PM        92      0.00
04:35:21 PM        93      0.00
04:35:21 PM        94      0.00
04:35:21 PM        95      0.00
04:35:21 PM        96      0.00
04:35:21 PM        97      0.00
04:35:21 PM        98      0.00
04:35:21 PM        99      0.00
04:35:21 PM       100      0.00
04:35:21 PM       101      0.00
04:35:21 PM       102      0.00
04:35:21 PM       103      0.00
04:35:21 PM       104      0.00
04:35:21 PM       105      0.00
04:35:21 PM       106      0.00
04:35:21 PM       107      0.00
04:35:21 PM       108      0.00
04:35:21 PM       109      0.00
04:35:21 PM       110      0.00
04:35:21 PM       111      0.00
04:35:21 PM       112      0.00
04:35:21 PM       113      0.00
04:35:21 PM       114      0.00
04:35:21 PM       115      0.00
04:35:21 PM       116      0.00
04:35:21 PM       117      0.00
04:35:21 PM       118      0.00
04:35:21 PM       119      0.00
04:35:21 PM       120      0.00
04:35:21 PM       121      0.00
04:35:21 PM       122      0.00
04:35:21 PM       123      0.00
04:35:21 PM       124      0.00
04:35:21 PM       125      0.00
04:35:21 PM       126      0.00
04:35:21 PM       127      0.00
04:35:21 PM       128      0.00
04:35:21 PM       129      0.00
04:35:21 PM       130      0.00
04:35:21 PM       131      0.00
04:35:21 PM       132      0.00
04:35:21 PM       133      0.00
04:35:21 PM       134      0.00
04:35:21 PM       135      0.00
04:35:21 PM       136      0.00
04:35:21 PM       137      0.00
04:35:21 PM       138      0.00
04:35:21 PM       139      0.00
04:35:21 PM       140      0.00
04:35:21 PM       141      0.00
04:35:21 PM       142      0.00
04:35:21 PM       143      0.00
04:35:21 PM       144      0.00
04:35:21 PM       145      0.00
04:35:21 PM       146      0.00
04:35:21 PM       147      0.00
04:35:21 PM       148      0.00
04:35:21 PM       149      0.00
04:35:21 PM       150      0.00
04:35:21 PM       151      0.00
04:35:21 PM       152      0.00
04:35:21 PM       153      0.00
04:35:21 PM       154      0.00
04:35:21 PM       155      0.00
04:35:21 PM       156      0.00
04:35:21 PM       157      0.00
04:35:21 PM       158      0.00
04:35:21 PM       159      0.00
04:35:21 PM       160      0.00
04:35:21 PM       161      0.00
04:35:21 PM       162      0.00
04:35:21 PM       163      0.00
04:35:21 PM       164      0.00
04:35:21 PM       165      0.00
04:35:21 PM       166      0.00
04:35:21 PM       167      0.00
04:35:21 PM       168      0.00
04:35:21 PM       169      0.00
04:35:21 PM       170      0.00
04:35:21 PM       171      0.00
04:35:21 PM       172      0.00
04:35:21 PM       173      0.00
04:35:21 PM       174      0.00
04:35:21 PM       175      0.00
04:35:21 PM       176      0.00
04:35:21 PM       177      0.00
04:35:21 PM       178      0.00
04:35:21 PM       179      0.00
04:35:21 PM       180      0.00
04:35:21 PM       181      0.00
04:35:21 PM       182      0.00
04:35:21 PM       183      0.00
04:35:21 PM       184      0.00
04:35:21 PM       185      0.00
04:35:21 PM       186      0.00
04:35:21 PM       187      0.00
04:35:21 PM       188      0.00
04:35:21 PM       189      0.00
04:35:21 PM       190      0.00
04:35:21 PM       191      0.00
04:35:21 PM       192      0.00
04:35:21 PM       193      0.00
04:35:21 PM       194      0.00
04:35:21 PM       195      0.00
04:35:21 PM       196      0.00
04:35:21 PM       197      0.00
04:35:21 PM       198      0.00
04:35:21 PM       199      0.00
04:35:21 PM       200      0.00
04:35:21 PM       201      0.00
04:35:21 PM       202      0.00
04:35:21 PM       203      0.00
04:35:21 PM       204      0.00
04:35:21 PM       205      0.00
04:35:21 PM       206      0.00
04:35:21 PM       207      0.00
04:35:21 PM       208      0.00
04:35:21 PM       209      0.00
04:35:21 PM       210      0.00
04:35:21 PM       211      0.00
04:35:21 PM       212      0.00
04:35:21 PM       213      0.00
04:35:21 PM       214      0.00
04:35:21 PM       215      0.00
04:35:21 PM       216      0.00
04:35:21 PM       217      0.00
04:35:21 PM       218      0.00
04:35:21 PM       219      0.00
04:35:21 PM       220      0.00
04:35:21 PM       221      0.00
04:35:21 PM       222      0.00
04:35:21 PM       223      0.00
04:35:21 PM       224      0.00
04:35:21 PM       225      0.00
04:35:21 PM       226      0.00
04:35:21 PM       227      0.00
04:35:21 PM       228      0.00
04:35:21 PM       229      0.00
04:35:21 PM       230      0.00
04:35:21 PM       231      0.00
04:35:21 PM       232      0.00
04:35:21 PM       233      0.00
04:35:21 PM       234      0.00
04:35:21 PM       235      0.00
04:35:21 PM       236      0.00
04:35:21 PM       237      0.00
04:35:21 PM       238      0.00
04:35:21 PM       239      0.00
04:35:21 PM       240      0.00
04:35:21 PM       241      0.00
04:35:21 PM       242      0.00
04:35:21 PM       243      0.00
04:35:21 PM       244      0.00
04:35:21 PM       245      0.00
04:35:21 PM       246      0.00
04:35:21 PM       247      0.00
04:35:21 PM       248      0.00
04:35:21 PM       249      0.00
04:35:21 PM       250      0.00
04:35:21 PM       251      0.00
04:35:21 PM       252      0.00
04:35:21 PM       253      0.00
04:35:21 PM       254      0.00
04:35:21 PM       255      0.00

04:35:19 PM  pswpin/s pswpout/s
04:35:21 PM      0.00      0.00

04:35:19 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:21 PM      0.00     12.00     31.00      0.00    280.00      0.00      0.00      0.00      0.00

04:35:19 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:21 PM      5.00      0.00      5.00      0.00     41.50

04:35:19 PM   frmpg/s   bufpg/s   campg/s
04:35:21 PM      0.00      0.00      2.00

04:35:19 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:21 PM     80080   8115480     99.02       176   5018940   4689464      8.34   4226296   2972012

04:35:19 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:21 PM  48016452       948      0.00       224     23.63

04:35:19 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:21 PM    158622      9888    134011       110

04:35:19 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:21 PM         0       476      0.00      0.01      0.05         0

04:35:19 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:21 PM    dev8-0      2.00      0.00     16.50      8.25      0.01      7.50      7.50      1.50
04:35:21 PM   dev8-16      2.00      0.00     16.50      8.25      0.01      5.00      5.00      1.00
04:35:21 PM    dev9-0      1.00      0.00      8.50      8.50      0.00      0.00      0.00      0.00
04:35:21 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:21 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:21 PM      eth0      6.50      6.50      0.86      8.91      0.00      0.00      0.00
04:35:21 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:21 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:19 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:21 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:21 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:21 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:21 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:21 PM       882        32         9         0         0         0

04:35:19 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:21 PM     13.00      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:19 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM  active/s passive/s    iseg/s    oseg/s
04:35:21 PM      0.00      0.00      6.50      6.50

04:35:19 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00

04:35:19 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:21 PM      6.50      6.50      0.00      0.00

04:35:19 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:21 PM         2         2         0         0

04:35:19 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:21 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:19 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:21 PM      0.00      0.00      0.00      0.00

04:35:19 PM     CPU       MHz
04:35:21 PM     all   1596.00
04:35:21 PM       0   1596.00
04:35:21 PM       1   1596.00
04:35:21 PM       2   1596.00
04:35:21 PM       3   1596.00

04:35:19 PM     FAN       rpm      drpm                   DEVICE
04:35:21 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:21 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:21 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:21 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:19 PM    TEMP      degC     %temp                   DEVICE
04:35:21 PM       1     47.00     78.33           atk0110-acpi-0
04:35:21 PM       2     43.00     95.56           atk0110-acpi-0

04:35:19 PM      IN       inV       %in                   DEVICE
04:35:21 PM       0      1.10     33.87           atk0110-acpi-0
04:35:21 PM       1      3.25     42.12           atk0110-acpi-0
04:35:21 PM       2      5.02     51.70           atk0110-acpi-0
04:35:21 PM       3     12.20     55.44           atk0110-acpi-0

04:35:19 PM kbhugfree kbhugused  %hugused
04:35:21 PM         0         0      0.00

04:35:19 PM     CPU    wghMHz
04:35:21 PM     all   1596.00
04:35:21 PM       0   1596.00
04:35:21 PM       1   1596.00
04:35:21 PM       2   1596.00
04:35:21 PM       3   1596.00

04:35:21 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:23 PM     all      2.76      0.00      1.13      0.00      0.00      0.00      0.00      0.00     96.12
04:35:23 PM       0      3.02      0.00      1.51      0.00      0.00      0.00      0.00      0.00     95.48
04:35:23 PM       1      7.54      0.00      1.01      0.00      0.00      0.00      0.00      0.00     91.46
04:35:23 PM       2      0.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     98.50
04:35:23 PM       3      0.00      0.00      1.01      0.00      0.00      0.00      0.00      0.00     98.99

04:35:21 PM    proc/s   cswch/s
04:35:23 PM      0.00   2255.00

04:35:21 PM      INTR    intr/s
04:35:23 PM       sum    836.50
04:35:23 PM         0      0.00
04:35:23 PM         1      0.00
04:35:23 PM         2      0.00
04:35:23 PM         3      0.00
04:35:23 PM         4      0.00
04:35:23 PM         5      0.00
04:35:23 PM         6      0.00
04:35:23 PM         7      0.00
04:35:23 PM         8      0.00
04:35:23 PM         9      0.00
04:35:23 PM        10      0.00
04:35:23 PM        11      0.00
04:35:23 PM        12      0.00
04:35:23 PM        13      0.00
04:35:23 PM        14      0.00
04:35:23 PM        15      0.00
04:35:23 PM        16      1.00
04:35:23 PM        17      2.50
04:35:23 PM        18      0.00
04:35:23 PM        19    149.00
04:35:23 PM        20      0.00
04:35:23 PM        21      0.00
04:35:23 PM        22      0.00
04:35:23 PM        23      0.50
04:35:23 PM        24      0.00
04:35:23 PM        25      0.00
04:35:23 PM        26      0.00
04:35:23 PM        27      0.00
04:35:23 PM        28      0.00
04:35:23 PM        29      0.00
04:35:23 PM        30      0.00
04:35:23 PM        31      0.00
04:35:23 PM        32      0.00
04:35:23 PM        33      0.00
04:35:23 PM        34      0.00
04:35:23 PM        35      0.00
04:35:23 PM        36      0.00
04:35:23 PM        37      0.00
04:35:23 PM        38      0.00
04:35:23 PM        39      0.00
04:35:23 PM        40      0.00
04:35:23 PM        41      0.00
04:35:23 PM        42      0.00
04:35:23 PM        43      0.00
04:35:23 PM        44     11.00
04:35:23 PM        45      1.00
04:35:23 PM        46      0.00
04:35:23 PM        47      0.00
04:35:23 PM        48      0.00
04:35:23 PM        49      0.00
04:35:23 PM        50      0.00
04:35:23 PM        51      0.00
04:35:23 PM        52      0.00
04:35:23 PM        53      0.00
04:35:23 PM        54      0.00
04:35:23 PM        55      0.00
04:35:23 PM        56      0.00
04:35:23 PM        57      0.00
04:35:23 PM        58      0.00
04:35:23 PM        59      0.00
04:35:23 PM        60      0.00
04:35:23 PM        61      0.00
04:35:23 PM        62      0.00
04:35:23 PM        63      0.00
04:35:23 PM        64      0.00
04:35:23 PM        65      0.00
04:35:23 PM        66      0.00
04:35:23 PM        67      0.00
04:35:23 PM        68      0.00
04:35:23 PM        69      0.00
04:35:23 PM        70      0.00
04:35:23 PM        71      0.00
04:35:23 PM        72      0.00
04:35:23 PM        73      0.00
04:35:23 PM        74      0.00
04:35:23 PM        75      0.00
04:35:23 PM        76      0.00
04:35:23 PM        77      0.00
04:35:23 PM        78      0.00
04:35:23 PM        79      0.00
04:35:23 PM        80      0.00
04:35:23 PM        81      0.00
04:35:23 PM        82      0.00
04:35:23 PM        83      0.00
04:35:23 PM        84      0.00
04:35:23 PM        85      0.00
04:35:23 PM        86      0.00
04:35:23 PM        87      0.00
04:35:23 PM        88      0.00
04:35:23 PM        89      0.00
04:35:23 PM        90      0.00
04:35:23 PM        91      0.00
04:35:23 PM        92      0.00
04:35:23 PM        93      0.00
04:35:23 PM        94      0.00
04:35:23 PM        95      0.00
04:35:23 PM        96      0.00
04:35:23 PM        97      0.00
04:35:23 PM        98      0.00
04:35:23 PM        99      0.00
04:35:23 PM       100      0.00
04:35:23 PM       101      0.00
04:35:23 PM       102      0.00
04:35:23 PM       103      0.00
04:35:23 PM       104      0.00
04:35:23 PM       105      0.00
04:35:23 PM       106      0.00
04:35:23 PM       107      0.00
04:35:23 PM       108      0.00
04:35:23 PM       109      0.00
04:35:23 PM       110      0.00
04:35:23 PM       111      0.00
04:35:23 PM       112      0.00
04:35:23 PM       113      0.00
04:35:23 PM       114      0.00
04:35:23 PM       115      0.00
04:35:23 PM       116      0.00
04:35:23 PM       117      0.00
04:35:23 PM       118      0.00
04:35:23 PM       119      0.00
04:35:23 PM       120      0.00
04:35:23 PM       121      0.00
04:35:23 PM       122      0.00
04:35:23 PM       123      0.00
04:35:23 PM       124      0.00
04:35:23 PM       125      0.00
04:35:23 PM       126      0.00
04:35:23 PM       127      0.00
04:35:23 PM       128      0.00
04:35:23 PM       129      0.00
04:35:23 PM       130      0.00
04:35:23 PM       131      0.00
04:35:23 PM       132      0.00
04:35:23 PM       133      0.00
04:35:23 PM       134      0.00
04:35:23 PM       135      0.00
04:35:23 PM       136      0.00
04:35:23 PM       137      0.00
04:35:23 PM       138      0.00
04:35:23 PM       139      0.00
04:35:23 PM       140      0.00
04:35:23 PM       141      0.00
04:35:23 PM       142      0.00
04:35:23 PM       143      0.00
04:35:23 PM       144      0.00
04:35:23 PM       145      0.00
04:35:23 PM       146      0.00
04:35:23 PM       147      0.00
04:35:23 PM       148      0.00
04:35:23 PM       149      0.00
04:35:23 PM       150      0.00
04:35:23 PM       151      0.00
04:35:23 PM       152      0.00
04:35:23 PM       153      0.00
04:35:23 PM       154      0.00
04:35:23 PM       155      0.00
04:35:23 PM       156      0.00
04:35:23 PM       157      0.00
04:35:23 PM       158      0.00
04:35:23 PM       159      0.00
04:35:23 PM       160      0.00
04:35:23 PM       161      0.00
04:35:23 PM       162      0.00
04:35:23 PM       163      0.00
04:35:23 PM       164      0.00
04:35:23 PM       165      0.00
04:35:23 PM       166      0.00
04:35:23 PM       167      0.00
04:35:23 PM       168      0.00
04:35:23 PM       169      0.00
04:35:23 PM       170      0.00
04:35:23 PM       171      0.00
04:35:23 PM       172      0.00
04:35:23 PM       173      0.00
04:35:23 PM       174      0.00
04:35:23 PM       175      0.00
04:35:23 PM       176      0.00
04:35:23 PM       177      0.00
04:35:23 PM       178      0.00
04:35:23 PM       179      0.00
04:35:23 PM       180      0.00
04:35:23 PM       181      0.00
04:35:23 PM       182      0.00
04:35:23 PM       183      0.00
04:35:23 PM       184      0.00
04:35:23 PM       185      0.00
04:35:23 PM       186      0.00
04:35:23 PM       187      0.00
04:35:23 PM       188      0.00
04:35:23 PM       189      0.00
04:35:23 PM       190      0.00
04:35:23 PM       191      0.00
04:35:23 PM       192      0.00
04:35:23 PM       193      0.00
04:35:23 PM       194      0.00
04:35:23 PM       195      0.00
04:35:23 PM       196      0.00
04:35:23 PM       197      0.00
04:35:23 PM       198      0.00
04:35:23 PM       199      0.00
04:35:23 PM       200      0.00
04:35:23 PM       201      0.00
04:35:23 PM       202      0.00
04:35:23 PM       203      0.00
04:35:23 PM       204      0.00
04:35:23 PM       205      0.00
04:35:23 PM       206      0.00
04:35:23 PM       207      0.00
04:35:23 PM       208      0.00
04:35:23 PM       209      0.00
04:35:23 PM       210      0.00
04:35:23 PM       211      0.00
04:35:23 PM       212      0.00
04:35:23 PM       213      0.00
04:35:23 PM       214      0.00
04:35:23 PM       215      0.00
04:35:23 PM       216      0.00
04:35:23 PM       217      0.00
04:35:23 PM       218      0.00
04:35:23 PM       219      0.00
04:35:23 PM       220      0.00
04:35:23 PM       221      0.00
04:35:23 PM       222      0.00
04:35:23 PM       223      0.00
04:35:23 PM       224      0.00
04:35:23 PM       225      0.00
04:35:23 PM       226      0.00
04:35:23 PM       227      0.00
04:35:23 PM       228      0.00
04:35:23 PM       229      0.00
04:35:23 PM       230      0.00
04:35:23 PM       231      0.00
04:35:23 PM       232      0.00
04:35:23 PM       233      0.00
04:35:23 PM       234      0.00
04:35:23 PM       235      0.00
04:35:23 PM       236      0.00
04:35:23 PM       237      0.00
04:35:23 PM       238      0.00
04:35:23 PM       239      0.00
04:35:23 PM       240      0.00
04:35:23 PM       241      0.00
04:35:23 PM       242      0.00
04:35:23 PM       243      0.00
04:35:23 PM       244      0.00
04:35:23 PM       245      0.00
04:35:23 PM       246      0.00
04:35:23 PM       247      0.00
04:35:23 PM       248      0.00
04:35:23 PM       249      0.00
04:35:23 PM       250      0.00
04:35:23 PM       251      0.00
04:35:23 PM       252      0.00
04:35:23 PM       253      0.00
04:35:23 PM       254      0.00
04:35:23 PM       255      0.00

04:35:21 PM  pswpin/s pswpout/s
04:35:23 PM      0.00      0.00

04:35:21 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:23 PM      0.00    600.00     31.00      0.00    309.50      0.00      0.00      0.00      0.00

04:35:21 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:23 PM    217.00      0.00    217.00      0.00   3568.00

04:35:21 PM   frmpg/s   bufpg/s   campg/s
04:35:23 PM    -16.00      0.00      2.00

04:35:21 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:23 PM     79952   8115608     99.02       176   5018956   4689464      8.34   4226300   2972020

04:35:21 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:23 PM  48016452       948      0.00       224     23.63

04:35:21 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:23 PM    158622      9888    134011       110

04:35:21 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:23 PM         0       476      0.00      0.01      0.05         0

04:35:21 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:23 PM    dev8-0     72.50      0.00   1192.00     16.44      1.00     13.79      1.45     10.50
04:35:23 PM   dev8-16     72.50      0.00   1192.00     16.44      1.01     13.86      1.59     11.50
04:35:23 PM    dev9-0     72.00      0.00   1184.00     16.44      0.00      0.00      0.00      0.00
04:35:23 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:23 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:23 PM      eth0      6.50      6.50      0.86      8.91      0.00      0.00      0.00
04:35:23 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:23 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:21 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:23 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:23 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:23 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:23 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:23 PM       882        32         9         0         0         0

04:35:21 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:23 PM     13.00      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:21 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM  active/s passive/s    iseg/s    oseg/s
04:35:23 PM      0.00      0.00      6.50      6.50

04:35:21 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00

04:35:21 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:23 PM      6.50      6.50      0.00      0.00

04:35:21 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:23 PM         2         2         0         0

04:35:21 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:23 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:21 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:23 PM      0.00      0.00      0.00      0.00

04:35:21 PM     CPU       MHz
04:35:23 PM     all   1596.00
04:35:23 PM       0   1596.00
04:35:23 PM       1   1596.00
04:35:23 PM       2   1596.00
04:35:23 PM       3   1596.00

04:35:21 PM     FAN       rpm      drpm                   DEVICE
04:35:23 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:23 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:23 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:23 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:21 PM    TEMP      degC     %temp                   DEVICE
04:35:23 PM       1     47.00     78.33           atk0110-acpi-0
04:35:23 PM       2     43.00     95.56           atk0110-acpi-0

04:35:21 PM      IN       inV       %in                   DEVICE
04:35:23 PM       0      1.10     33.87           atk0110-acpi-0
04:35:23 PM       1      3.25     42.12           atk0110-acpi-0
04:35:23 PM       2      5.02     51.70           atk0110-acpi-0
04:35:23 PM       3     12.20     55.44           atk0110-acpi-0

04:35:21 PM kbhugfree kbhugused  %hugused
04:35:23 PM         0         0      0.00

04:35:21 PM     CPU    wghMHz
04:35:23 PM     all   1596.00
04:35:23 PM       0   1596.00
04:35:23 PM       1   1596.00
04:35:23 PM       2   1596.00
04:35:23 PM       3   1596.00

04:35:23 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:25 PM     all      2.00      0.00      1.37      0.00      0.00      0.00      0.00      0.00     96.63
04:35:25 PM       0      0.50      0.00      0.00      0.00      0.00      0.00      0.00      0.00     99.50
04:35:25 PM       1      6.97      0.00      3.98      0.00      0.00      0.00      0.00      0.00     89.05
04:35:25 PM       2      0.50      0.00      1.00      0.00      0.00      0.00      0.00      0.00     98.50
04:35:25 PM       3      0.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.50

04:35:23 PM    proc/s   cswch/s
04:35:25 PM      0.00   2099.50

04:35:23 PM      INTR    intr/s
04:35:25 PM       sum    690.50
04:35:25 PM         0      0.00
04:35:25 PM         1      0.00
04:35:25 PM         2      0.00
04:35:25 PM         3      0.00
04:35:25 PM         4      0.00
04:35:25 PM         5      0.00
04:35:25 PM         6      0.00
04:35:25 PM         7      0.00
04:35:25 PM         8      0.00
04:35:25 PM         9      0.00
04:35:25 PM        10      0.00
04:35:25 PM        11      0.00
04:35:25 PM        12      0.00
04:35:25 PM        13      0.00
04:35:25 PM        14      0.00
04:35:25 PM        15      0.00
04:35:25 PM        16      1.00
04:35:25 PM        17      2.50
04:35:25 PM        18      0.00
04:35:25 PM        19      0.00
04:35:25 PM        20      0.00
04:35:25 PM        21      0.00
04:35:25 PM        22      0.00
04:35:25 PM        23      0.50
04:35:25 PM        24      0.00
04:35:25 PM        25      0.00
04:35:25 PM        26      0.00
04:35:25 PM        27      0.00
04:35:25 PM        28      0.00
04:35:25 PM        29      0.00
04:35:25 PM        30      0.00
04:35:25 PM        31      0.00
04:35:25 PM        32      0.00
04:35:25 PM        33      0.00
04:35:25 PM        34      0.00
04:35:25 PM        35      0.00
04:35:25 PM        36      0.00
04:35:25 PM        37      0.00
04:35:25 PM        38      0.00
04:35:25 PM        39      0.00
04:35:25 PM        40      0.00
04:35:25 PM        41      0.00
04:35:25 PM        42      0.00
04:35:25 PM        43      0.00
04:35:25 PM        44     12.50
04:35:25 PM        45      1.00
04:35:25 PM        46      0.00
04:35:25 PM        47      0.00
04:35:25 PM        48      0.00
04:35:25 PM        49      0.00
04:35:25 PM        50      0.00
04:35:25 PM        51      0.00
04:35:25 PM        52      0.00
04:35:25 PM        53      0.00
04:35:25 PM        54      0.00
04:35:25 PM        55      0.00
04:35:25 PM        56      0.00
04:35:25 PM        57      0.00
04:35:25 PM        58      0.00
04:35:25 PM        59      0.00
04:35:25 PM        60      0.00
04:35:25 PM        61      0.00
04:35:25 PM        62      0.00
04:35:25 PM        63      0.00
04:35:25 PM        64      0.00
04:35:25 PM        65      0.00
04:35:25 PM        66      0.00
04:35:25 PM        67      0.00
04:35:25 PM        68      0.00
04:35:25 PM        69      0.00
04:35:25 PM        70      0.00
04:35:25 PM        71      0.00
04:35:25 PM        72      0.00
04:35:25 PM        73      0.00
04:35:25 PM        74      0.00
04:35:25 PM        75      0.00
04:35:25 PM        76      0.00
04:35:25 PM        77      0.00
04:35:25 PM        78      0.00
04:35:25 PM        79      0.00
04:35:25 PM        80      0.00
04:35:25 PM        81      0.00
04:35:25 PM        82      0.00
04:35:25 PM        83      0.00
04:35:25 PM        84      0.00
04:35:25 PM        85      0.00
04:35:25 PM        86      0.00
04:35:25 PM        87      0.00
04:35:25 PM        88      0.00
04:35:25 PM        89      0.00
04:35:25 PM        90      0.00
04:35:25 PM        91      0.00
04:35:25 PM        92      0.00
04:35:25 PM        93      0.00
04:35:25 PM        94      0.00
04:35:25 PM        95      0.00
04:35:25 PM        96      0.00
04:35:25 PM        97      0.00
04:35:25 PM        98      0.00
04:35:25 PM        99      0.00
04:35:25 PM       100      0.00
04:35:25 PM       101      0.00
04:35:25 PM       102      0.00
04:35:25 PM       103      0.00
04:35:25 PM       104      0.00
04:35:25 PM       105      0.00
04:35:25 PM       106      0.00
04:35:25 PM       107      0.00
04:35:25 PM       108      0.00
04:35:25 PM       109      0.00
04:35:25 PM       110      0.00
04:35:25 PM       111      0.00
04:35:25 PM       112      0.00
04:35:25 PM       113      0.00
04:35:25 PM       114      0.00
04:35:25 PM       115      0.00
04:35:25 PM       116      0.00
04:35:25 PM       117      0.00
04:35:25 PM       118      0.00
04:35:25 PM       119      0.00
04:35:25 PM       120      0.00
04:35:25 PM       121      0.00
04:35:25 PM       122      0.00
04:35:25 PM       123      0.00
04:35:25 PM       124      0.00
04:35:25 PM       125      0.00
04:35:25 PM       126      0.00
04:35:25 PM       127      0.00
04:35:25 PM       128      0.00
04:35:25 PM       129      0.00
04:35:25 PM       130      0.00
04:35:25 PM       131      0.00
04:35:25 PM       132      0.00
04:35:25 PM       133      0.00
04:35:25 PM       134      0.00
04:35:25 PM       135      0.00
04:35:25 PM       136      0.00
04:35:25 PM       137      0.00
04:35:25 PM       138      0.00
04:35:25 PM       139      0.00
04:35:25 PM       140      0.00
04:35:25 PM       141      0.00
04:35:25 PM       142      0.00
04:35:25 PM       143      0.00
04:35:25 PM       144      0.00
04:35:25 PM       145      0.00
04:35:25 PM       146      0.00
04:35:25 PM       147      0.00
04:35:25 PM       148      0.00
04:35:25 PM       149      0.00
04:35:25 PM       150      0.00
04:35:25 PM       151      0.00
04:35:25 PM       152      0.00
04:35:25 PM       153      0.00
04:35:25 PM       154      0.00
04:35:25 PM       155      0.00
04:35:25 PM       156      0.00
04:35:25 PM       157      0.00
04:35:25 PM       158      0.00
04:35:25 PM       159      0.00
04:35:25 PM       160      0.00
04:35:25 PM       161      0.00
04:35:25 PM       162      0.00
04:35:25 PM       163      0.00
04:35:25 PM       164      0.00
04:35:25 PM       165      0.00
04:35:25 PM       166      0.00
04:35:25 PM       167      0.00
04:35:25 PM       168      0.00
04:35:25 PM       169      0.00
04:35:25 PM       170      0.00
04:35:25 PM       171      0.00
04:35:25 PM       172      0.00
04:35:25 PM       173      0.00
04:35:25 PM       174      0.00
04:35:25 PM       175      0.00
04:35:25 PM       176      0.00
04:35:25 PM       177      0.00
04:35:25 PM       178      0.00
04:35:25 PM       179      0.00
04:35:25 PM       180      0.00
04:35:25 PM       181      0.00
04:35:25 PM       182      0.00
04:35:25 PM       183      0.00
04:35:25 PM       184      0.00
04:35:25 PM       185      0.00
04:35:25 PM       186      0.00
04:35:25 PM       187      0.00
04:35:25 PM       188      0.00
04:35:25 PM       189      0.00
04:35:25 PM       190      0.00
04:35:25 PM       191      0.00
04:35:25 PM       192      0.00
04:35:25 PM       193      0.00
04:35:25 PM       194      0.00
04:35:25 PM       195      0.00
04:35:25 PM       196      0.00
04:35:25 PM       197      0.00
04:35:25 PM       198      0.00
04:35:25 PM       199      0.00
04:35:25 PM       200      0.00
04:35:25 PM       201      0.00
04:35:25 PM       202      0.00
04:35:25 PM       203      0.00
04:35:25 PM       204      0.00
04:35:25 PM       205      0.00
04:35:25 PM       206      0.00
04:35:25 PM       207      0.00
04:35:25 PM       208      0.00
04:35:25 PM       209      0.00
04:35:25 PM       210      0.00
04:35:25 PM       211      0.00
04:35:25 PM       212      0.00
04:35:25 PM       213      0.00
04:35:25 PM       214      0.00
04:35:25 PM       215      0.00
04:35:25 PM       216      0.00
04:35:25 PM       217      0.00
04:35:25 PM       218      0.00
04:35:25 PM       219      0.00
04:35:25 PM       220      0.00
04:35:25 PM       221      0.00
04:35:25 PM       222      0.00
04:35:25 PM       223      0.00
04:35:25 PM       224      0.00
04:35:25 PM       225      0.00
04:35:25 PM       226      0.00
04:35:25 PM       227      0.00
04:35:25 PM       228      0.00
04:35:25 PM       229      0.00
04:35:25 PM       230      0.00
04:35:25 PM       231      0.00
04:35:25 PM       232      0.00
04:35:25 PM       233      0.00
04:35:25 PM       234      0.00
04:35:25 PM       235      0.00
04:35:25 PM       236      0.00
04:35:25 PM       237      0.00
04:35:25 PM       238      0.00
04:35:25 PM       239      0.00
04:35:25 PM       240      0.00
04:35:25 PM       241      0.00
04:35:25 PM       242      0.00
04:35:25 PM       243      0.00
04:35:25 PM       244      0.00
04:35:25 PM       245      0.00
04:35:25 PM       246      0.00
04:35:25 PM       247      0.00
04:35:25 PM       248      0.00
04:35:25 PM       249      0.00
04:35:25 PM       250      0.00
04:35:25 PM       251      0.00
04:35:25 PM       252      0.00
04:35:25 PM       253      0.00
04:35:25 PM       254      0.00
04:35:25 PM       255      0.00

04:35:23 PM  pswpin/s pswpout/s
04:35:25 PM      0.00      0.00

04:35:23 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:25 PM      0.00      0.00     31.00      0.00    286.00      0.00      0.00      0.00      0.00

04:35:23 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00

04:35:23 PM   frmpg/s   bufpg/s   campg/s
04:35:25 PM     14.00      0.00      2.00

04:35:23 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:25 PM     80064   8115496     99.02       176   5018972   4689464      8.34   4226300   2972036

04:35:23 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:25 PM  48016452       948      0.00       224     23.63

04:35:23 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:25 PM    158622      9888    134011       110

04:35:23 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:25 PM         0       476      0.00      0.01      0.05         0

04:35:23 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:25 PM    dev8-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:25 PM   dev8-16      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:25 PM    dev9-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:25 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:25 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:25 PM      eth0      7.00      7.50      0.95      9.00      0.00      0.00      0.00
04:35:25 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:25 PM      tun0      7.00      7.00      0.38      8.43      0.00      0.00      0.00

04:35:23 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:25 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:25 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:25 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:25 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:25 PM       882        32         9         0         0         0

04:35:23 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:25 PM     14.00      0.00     14.00     14.50      0.00      0.00      0.00      0.00

04:35:23 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM  active/s passive/s    iseg/s    oseg/s
04:35:25 PM      0.00      0.00      7.00      7.00

04:35:23 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00

04:35:23 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:25 PM      7.00      7.50      0.00      0.00

04:35:23 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:25 PM         2         2         0         0

04:35:23 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:25 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:23 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:25 PM      0.00      0.00      0.00      0.00

04:35:23 PM     CPU       MHz
04:35:25 PM     all   1596.00
04:35:25 PM       0   1596.00
04:35:25 PM       1   1596.00
04:35:25 PM       2   1596.00
04:35:25 PM       3   1596.00

04:35:23 PM     FAN       rpm      drpm                   DEVICE
04:35:25 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:25 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:25 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:25 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:23 PM    TEMP      degC     %temp                   DEVICE
04:35:25 PM       1     47.00     78.33           atk0110-acpi-0
04:35:25 PM       2     43.00     95.56           atk0110-acpi-0

04:35:23 PM      IN       inV       %in                   DEVICE
04:35:25 PM       0      1.10     33.87           atk0110-acpi-0
04:35:25 PM       1      3.25     42.12           atk0110-acpi-0
04:35:25 PM       2      5.02     51.70           atk0110-acpi-0
04:35:25 PM       3     12.20     55.44           atk0110-acpi-0

04:35:23 PM kbhugfree kbhugused  %hugused
04:35:25 PM         0         0      0.00

04:35:23 PM     CPU    wghMHz
04:35:25 PM     all   1596.00
04:35:25 PM       0   1596.00
04:35:25 PM       1   1596.00
04:35:25 PM       2   1596.00
04:35:25 PM       3   1596.00

04:35:25 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:27 PM     all      3.00      0.00      1.50      0.00      0.00      0.00      0.00      0.00     95.51
04:35:27 PM       0      4.48      0.00      1.00      0.00      0.00      0.00      0.00      0.00     94.53
04:35:27 PM       1      4.50      0.00      4.00      0.00      0.00      0.00      0.00      0.00     91.50
04:35:27 PM       2      2.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     97.50
04:35:27 PM       3      1.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     98.50

04:35:25 PM    proc/s   cswch/s
04:35:27 PM      1.00   2217.00

04:35:25 PM      INTR    intr/s
04:35:27 PM       sum    699.50
04:35:27 PM         0      0.00
04:35:27 PM         1      0.00
04:35:27 PM         2      0.00
04:35:27 PM         3      0.00
04:35:27 PM         4      0.00
04:35:27 PM         5      0.00
04:35:27 PM         6      0.00
04:35:27 PM         7      0.00
04:35:27 PM         8      0.00
04:35:27 PM         9      0.00
04:35:27 PM        10      0.00
04:35:27 PM        11      0.00
04:35:27 PM        12      0.00
04:35:27 PM        13      0.00
04:35:27 PM        14      0.00
04:35:27 PM        15      0.00
04:35:27 PM        16      1.00
04:35:27 PM        17      2.50
04:35:27 PM        18      0.00
04:35:27 PM        19      5.00
04:35:27 PM        20      0.00
04:35:27 PM        21      0.00
04:35:27 PM        22      0.00
04:35:27 PM        23      0.50
04:35:27 PM        24      0.00
04:35:27 PM        25      0.00
04:35:27 PM        26      0.00
04:35:27 PM        27      0.00
04:35:27 PM        28      0.00
04:35:27 PM        29      0.00
04:35:27 PM        30      0.00
04:35:27 PM        31      0.00
04:35:27 PM        32      0.00
04:35:27 PM        33      0.00
04:35:27 PM        34      0.00
04:35:27 PM        35      0.00
04:35:27 PM        36      0.00
04:35:27 PM        37      0.00
04:35:27 PM        38      0.00
04:35:27 PM        39      0.00
04:35:27 PM        40      0.00
04:35:27 PM        41      0.00
04:35:27 PM        42      0.00
04:35:27 PM        43      0.00
04:35:27 PM        44     11.00
04:35:27 PM        45      1.00
04:35:27 PM        46      0.00
04:35:27 PM        47      0.00
04:35:27 PM        48      0.00
04:35:27 PM        49      0.00
04:35:27 PM        50      0.00
04:35:27 PM        51      0.00
04:35:27 PM        52      0.00
04:35:27 PM        53      0.00
04:35:27 PM        54      0.00
04:35:27 PM        55      0.00
04:35:27 PM        56      0.00
04:35:27 PM        57      0.00
04:35:27 PM        58      0.00
04:35:27 PM        59      0.00
04:35:27 PM        60      0.00
04:35:27 PM        61      0.00
04:35:27 PM        62      0.00
04:35:27 PM        63      0.00
04:35:27 PM        64      0.00
04:35:27 PM        65      0.00
04:35:27 PM        66      0.00
04:35:27 PM        67      0.00
04:35:27 PM        68      0.00
04:35:27 PM        69      0.00
04:35:27 PM        70      0.00
04:35:27 PM        71      0.00
04:35:27 PM        72      0.00
04:35:27 PM        73      0.00
04:35:27 PM        74      0.00
04:35:27 PM        75      0.00
04:35:27 PM        76      0.00
04:35:27 PM        77      0.00
04:35:27 PM        78      0.00
04:35:27 PM        79      0.00
04:35:27 PM        80      0.00
04:35:27 PM        81      0.00
04:35:27 PM        82      0.00
04:35:27 PM        83      0.00
04:35:27 PM        84      0.00
04:35:27 PM        85      0.00
04:35:27 PM        86      0.00
04:35:27 PM        87      0.00
04:35:27 PM        88      0.00
04:35:27 PM        89      0.00
04:35:27 PM        90      0.00
04:35:27 PM        91      0.00
04:35:27 PM        92      0.00
04:35:27 PM        93      0.00
04:35:27 PM        94      0.00
04:35:27 PM        95      0.00
04:35:27 PM        96      0.00
04:35:27 PM        97      0.00
04:35:27 PM        98      0.00
04:35:27 PM        99      0.00
04:35:27 PM       100      0.00
04:35:27 PM       101      0.00
04:35:27 PM       102      0.00
04:35:27 PM       103      0.00
04:35:27 PM       104      0.00
04:35:27 PM       105      0.00
04:35:27 PM       106      0.00
04:35:27 PM       107      0.00
04:35:27 PM       108      0.00
04:35:27 PM       109      0.00
04:35:27 PM       110      0.00
04:35:27 PM       111      0.00
04:35:27 PM       112      0.00
04:35:27 PM       113      0.00
04:35:27 PM       114      0.00
04:35:27 PM       115      0.00
04:35:27 PM       116      0.00
04:35:27 PM       117      0.00
04:35:27 PM       118      0.00
04:35:27 PM       119      0.00
04:35:27 PM       120      0.00
04:35:27 PM       121      0.00
04:35:27 PM       122      0.00
04:35:27 PM       123      0.00
04:35:27 PM       124      0.00
04:35:27 PM       125      0.00
04:35:27 PM       126      0.00
04:35:27 PM       127      0.00
04:35:27 PM       128      0.00
04:35:27 PM       129      0.00
04:35:27 PM       130      0.00
04:35:27 PM       131      0.00
04:35:27 PM       132      0.00
04:35:27 PM       133      0.00
04:35:27 PM       134      0.00
04:35:27 PM       135      0.00
04:35:27 PM       136      0.00
04:35:27 PM       137      0.00
04:35:27 PM       138      0.00
04:35:27 PM       139      0.00
04:35:27 PM       140      0.00
04:35:27 PM       141      0.00
04:35:27 PM       142      0.00
04:35:27 PM       143      0.00
04:35:27 PM       144      0.00
04:35:27 PM       145      0.00
04:35:27 PM       146      0.00
04:35:27 PM       147      0.00
04:35:27 PM       148      0.00
04:35:27 PM       149      0.00
04:35:27 PM       150      0.00
04:35:27 PM       151      0.00
04:35:27 PM       152      0.00
04:35:27 PM       153      0.00
04:35:27 PM       154      0.00
04:35:27 PM       155      0.00
04:35:27 PM       156      0.00
04:35:27 PM       157      0.00
04:35:27 PM       158      0.00
04:35:27 PM       159      0.00
04:35:27 PM       160      0.00
04:35:27 PM       161      0.00
04:35:27 PM       162      0.00
04:35:27 PM       163      0.00
04:35:27 PM       164      0.00
04:35:27 PM       165      0.00
04:35:27 PM       166      0.00
04:35:27 PM       167      0.00
04:35:27 PM       168      0.00
04:35:27 PM       169      0.00
04:35:27 PM       170      0.00
04:35:27 PM       171      0.00
04:35:27 PM       172      0.00
04:35:27 PM       173      0.00
04:35:27 PM       174      0.00
04:35:27 PM       175      0.00
04:35:27 PM       176      0.00
04:35:27 PM       177      0.00
04:35:27 PM       178      0.00
04:35:27 PM       179      0.00
04:35:27 PM       180      0.00
04:35:27 PM       181      0.00
04:35:27 PM       182      0.00
04:35:27 PM       183      0.00
04:35:27 PM       184      0.00
04:35:27 PM       185      0.00
04:35:27 PM       186      0.00
04:35:27 PM       187      0.00
04:35:27 PM       188      0.00
04:35:27 PM       189      0.00
04:35:27 PM       190      0.00
04:35:27 PM       191      0.00
04:35:27 PM       192      0.00
04:35:27 PM       193      0.00
04:35:27 PM       194      0.00
04:35:27 PM       195      0.00
04:35:27 PM       196      0.00
04:35:27 PM       197      0.00
04:35:27 PM       198      0.00
04:35:27 PM       199      0.00
04:35:27 PM       200      0.00
04:35:27 PM       201      0.00
04:35:27 PM       202      0.00
04:35:27 PM       203      0.00
04:35:27 PM       204      0.00
04:35:27 PM       205      0.00
04:35:27 PM       206      0.00
04:35:27 PM       207      0.00
04:35:27 PM       208      0.00
04:35:27 PM       209      0.00
04:35:27 PM       210      0.00
04:35:27 PM       211      0.00
04:35:27 PM       212      0.00
04:35:27 PM       213      0.00
04:35:27 PM       214      0.00
04:35:27 PM       215      0.00
04:35:27 PM       216      0.00
04:35:27 PM       217      0.00
04:35:27 PM       218      0.00
04:35:27 PM       219      0.00
04:35:27 PM       220      0.00
04:35:27 PM       221      0.00
04:35:27 PM       222      0.00
04:35:27 PM       223      0.00
04:35:27 PM       224      0.00
04:35:27 PM       225      0.00
04:35:27 PM       226      0.00
04:35:27 PM       227      0.00
04:35:27 PM       228      0.00
04:35:27 PM       229      0.00
04:35:27 PM       230      0.00
04:35:27 PM       231      0.00
04:35:27 PM       232      0.00
04:35:27 PM       233      0.00
04:35:27 PM       234      0.00
04:35:27 PM       235      0.00
04:35:27 PM       236      0.00
04:35:27 PM       237      0.00
04:35:27 PM       238      0.00
04:35:27 PM       239      0.00
04:35:27 PM       240      0.00
04:35:27 PM       241      0.00
04:35:27 PM       242      0.00
04:35:27 PM       243      0.00
04:35:27 PM       244      0.00
04:35:27 PM       245      0.00
04:35:27 PM       246      0.00
04:35:27 PM       247      0.00
04:35:27 PM       248      0.00
04:35:27 PM       249      0.00
04:35:27 PM       250      0.00
04:35:27 PM       251      0.00
04:35:27 PM       252      0.00
04:35:27 PM       253      0.00
04:35:27 PM       254      0.00
04:35:27 PM       255      0.00

04:35:25 PM  pswpin/s pswpout/s
04:35:27 PM      0.00      0.00

04:35:25 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:27 PM      0.00      0.00   1553.00      0.00   1485.00      0.00      0.00      0.00      0.00

04:35:25 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00

04:35:25 PM   frmpg/s   bufpg/s   campg/s
04:35:27 PM    -31.00      0.00      2.00

04:35:25 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:27 PM     79816   8115744     99.03       176   5018988   4689476      8.34   4226316   2972044

04:35:25 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:27 PM  48016452       948      0.00       224     23.63

04:35:25 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:27 PM    158622      9888    134011       110

04:35:25 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:27 PM         0       476      0.00      0.01      0.05         0

04:35:25 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:27 PM    dev8-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:27 PM   dev8-16      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:27 PM    dev9-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:27 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:27 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:27 PM      eth0      6.50      6.50      0.86      8.91      0.00      0.00      0.00
04:35:27 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:27 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:25 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:27 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:27 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:27 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:27 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:27 PM       882        32         9         0         0         0

04:35:25 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:27 PM     13.00      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:25 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM  active/s passive/s    iseg/s    oseg/s
04:35:27 PM      0.00      0.00      6.50      6.50

04:35:25 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00

04:35:25 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:27 PM      6.50      6.50      0.00      0.00

04:35:25 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:27 PM         2         2         0         0

04:35:25 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:27 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:25 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:27 PM      0.00      0.00      0.00      0.00

04:35:25 PM     CPU       MHz
04:35:27 PM     all   1596.00
04:35:27 PM       0   1596.00
04:35:27 PM       1   1596.00
04:35:27 PM       2   1596.00
04:35:27 PM       3   1596.00

04:35:25 PM     FAN       rpm      drpm                   DEVICE
04:35:27 PM       1   2596.00   1996.00           atk0110-acpi-0
04:35:27 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:27 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:27 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:25 PM    TEMP      degC     %temp                   DEVICE
04:35:27 PM       1     47.00     78.33           atk0110-acpi-0
04:35:27 PM       2     43.00     95.56           atk0110-acpi-0

04:35:25 PM      IN       inV       %in                   DEVICE
04:35:27 PM       0      1.10     33.87           atk0110-acpi-0
04:35:27 PM       1      3.25     42.12           atk0110-acpi-0
04:35:27 PM       2      5.02     51.70           atk0110-acpi-0
04:35:27 PM       3     12.20     55.44           atk0110-acpi-0

04:35:25 PM kbhugfree kbhugused  %hugused
04:35:27 PM         0         0      0.00

04:35:25 PM     CPU    wghMHz
04:35:27 PM     all   1600.01
04:35:27 PM       0   1599.99
04:35:27 PM       1   1596.00
04:35:27 PM       2   1611.96
04:35:27 PM       3   1596.00

04:35:27 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:29 PM     all      3.50      0.00      0.75      0.00      0.00      0.00      0.00      0.00     95.76
04:35:29 PM       0      9.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     90.00
04:35:29 PM       1      4.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     95.00
04:35:29 PM       2      1.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00     99.00
04:35:29 PM       3      0.00      0.00      1.00      0.00      0.00      0.00      0.00      0.00     99.00

04:35:27 PM    proc/s   cswch/s
04:35:29 PM      0.00   2181.50

04:35:27 PM      INTR    intr/s
04:35:29 PM       sum    713.00
04:35:29 PM         0      0.00
04:35:29 PM         1      0.00
04:35:29 PM         2      0.00
04:35:29 PM         3      0.00
04:35:29 PM         4      0.00
04:35:29 PM         5      0.00
04:35:29 PM         6      0.00
04:35:29 PM         7      0.00
04:35:29 PM         8      0.00
04:35:29 PM         9      0.00
04:35:29 PM        10      0.00
04:35:29 PM        11      0.00
04:35:29 PM        12      0.00
04:35:29 PM        13      0.00
04:35:29 PM        14      0.00
04:35:29 PM        15      0.00
04:35:29 PM        16      1.00
04:35:29 PM        17      2.50
04:35:29 PM        18      0.00
04:35:29 PM        19     13.50
04:35:29 PM        20      0.00
04:35:29 PM        21      0.00
04:35:29 PM        22      0.00
04:35:29 PM        23      0.50
04:35:29 PM        24      0.00
04:35:29 PM        25      0.00
04:35:29 PM        26      0.00
04:35:29 PM        27      0.00
04:35:29 PM        28      0.00
04:35:29 PM        29      0.00
04:35:29 PM        30      0.00
04:35:29 PM        31      0.00
04:35:29 PM        32      0.00
04:35:29 PM        33      0.00
04:35:29 PM        34      0.00
04:35:29 PM        35      0.00
04:35:29 PM        36      0.00
04:35:29 PM        37      0.00
04:35:29 PM        38      0.00
04:35:29 PM        39      0.00
04:35:29 PM        40      0.00
04:35:29 PM        41      0.00
04:35:29 PM        42      0.00
04:35:29 PM        43      0.00
04:35:29 PM        44     11.00
04:35:29 PM        45      1.00
04:35:29 PM        46      0.00
04:35:29 PM        47      0.00
04:35:29 PM        48      0.00
04:35:29 PM        49      0.00
04:35:29 PM        50      0.00
04:35:29 PM        51      0.00
04:35:29 PM        52      0.00
04:35:29 PM        53      0.00
04:35:29 PM        54      0.00
04:35:29 PM        55      0.00
04:35:29 PM        56      0.00
04:35:29 PM        57      0.00
04:35:29 PM        58      0.00
04:35:29 PM        59      0.00
04:35:29 PM        60      0.00
04:35:29 PM        61      0.00
04:35:29 PM        62      0.00
04:35:29 PM        63      0.00
04:35:29 PM        64      0.00
04:35:29 PM        65      0.00
04:35:29 PM        66      0.00
04:35:29 PM        67      0.00
04:35:29 PM        68      0.00
04:35:29 PM        69      0.00
04:35:29 PM        70      0.00
04:35:29 PM        71      0.00
04:35:29 PM        72      0.00
04:35:29 PM        73      0.00
04:35:29 PM        74      0.00
04:35:29 PM        75      0.00
04:35:29 PM        76      0.00
04:35:29 PM        77      0.00
04:35:29 PM        78      0.00
04:35:29 PM        79      0.00
04:35:29 PM        80      0.00
04:35:29 PM        81      0.00
04:35:29 PM        82      0.00
04:35:29 PM        83      0.00
04:35:29 PM        84      0.00
04:35:29 PM        85      0.00
04:35:29 PM        86      0.00
04:35:29 PM        87      0.00
04:35:29 PM        88      0.00
04:35:29 PM        89      0.00
04:35:29 PM        90      0.00
04:35:29 PM        91      0.00
04:35:29 PM        92      0.00
04:35:29 PM        93      0.00
04:35:29 PM        94      0.00
04:35:29 PM        95      0.00
04:35:29 PM        96      0.00
04:35:29 PM        97      0.00
04:35:29 PM        98      0.00
04:35:29 PM        99      0.00
04:35:29 PM       100      0.00
04:35:29 PM       101      0.00
04:35:29 PM       102      0.00
04:35:29 PM       103      0.00
04:35:29 PM       104      0.00
04:35:29 PM       105      0.00
04:35:29 PM       106      0.00
04:35:29 PM       107      0.00
04:35:29 PM       108      0.00
04:35:29 PM       109      0.00
04:35:29 PM       110      0.00
04:35:29 PM       111      0.00
04:35:29 PM       112      0.00
04:35:29 PM       113      0.00
04:35:29 PM       114      0.00
04:35:29 PM       115      0.00
04:35:29 PM       116      0.00
04:35:29 PM       117      0.00
04:35:29 PM       118      0.00
04:35:29 PM       119      0.00
04:35:29 PM       120      0.00
04:35:29 PM       121      0.00
04:35:29 PM       122      0.00
04:35:29 PM       123      0.00
04:35:29 PM       124      0.00
04:35:29 PM       125      0.00
04:35:29 PM       126      0.00
04:35:29 PM       127      0.00
04:35:29 PM       128      0.00
04:35:29 PM       129      0.00
04:35:29 PM       130      0.00
04:35:29 PM       131      0.00
04:35:29 PM       132      0.00
04:35:29 PM       133      0.00
04:35:29 PM       134      0.00
04:35:29 PM       135      0.00
04:35:29 PM       136      0.00
04:35:29 PM       137      0.00
04:35:29 PM       138      0.00
04:35:29 PM       139      0.00
04:35:29 PM       140      0.00
04:35:29 PM       141      0.00
04:35:29 PM       142      0.00
04:35:29 PM       143      0.00
04:35:29 PM       144      0.00
04:35:29 PM       145      0.00
04:35:29 PM       146      0.00
04:35:29 PM       147      0.00
04:35:29 PM       148      0.00
04:35:29 PM       149      0.00
04:35:29 PM       150      0.00
04:35:29 PM       151      0.00
04:35:29 PM       152      0.00
04:35:29 PM       153      0.00
04:35:29 PM       154      0.00
04:35:29 PM       155      0.00
04:35:29 PM       156      0.00
04:35:29 PM       157      0.00
04:35:29 PM       158      0.00
04:35:29 PM       159      0.00
04:35:29 PM       160      0.00
04:35:29 PM       161      0.00
04:35:29 PM       162      0.00
04:35:29 PM       163      0.00
04:35:29 PM       164      0.00
04:35:29 PM       165      0.00
04:35:29 PM       166      0.00
04:35:29 PM       167      0.00
04:35:29 PM       168      0.00
04:35:29 PM       169      0.00
04:35:29 PM       170      0.00
04:35:29 PM       171      0.00
04:35:29 PM       172      0.00
04:35:29 PM       173      0.00
04:35:29 PM       174      0.00
04:35:29 PM       175      0.00
04:35:29 PM       176      0.00
04:35:29 PM       177      0.00
04:35:29 PM       178      0.00
04:35:29 PM       179      0.00
04:35:29 PM       180      0.00
04:35:29 PM       181      0.00
04:35:29 PM       182      0.00
04:35:29 PM       183      0.00
04:35:29 PM       184      0.00
04:35:29 PM       185      0.00
04:35:29 PM       186      0.00
04:35:29 PM       187      0.00
04:35:29 PM       188      0.00
04:35:29 PM       189      0.00
04:35:29 PM       190      0.00
04:35:29 PM       191      0.00
04:35:29 PM       192      0.00
04:35:29 PM       193      0.00
04:35:29 PM       194      0.00
04:35:29 PM       195      0.00
04:35:29 PM       196      0.00
04:35:29 PM       197      0.00
04:35:29 PM       198      0.00
04:35:29 PM       199      0.00
04:35:29 PM       200      0.00
04:35:29 PM       201      0.00
04:35:29 PM       202      0.00
04:35:29 PM       203      0.00
04:35:29 PM       204      0.00
04:35:29 PM       205      0.00
04:35:29 PM       206      0.00
04:35:29 PM       207      0.00
04:35:29 PM       208      0.00
04:35:29 PM       209      0.00
04:35:29 PM       210      0.00
04:35:29 PM       211      0.00
04:35:29 PM       212      0.00
04:35:29 PM       213      0.00
04:35:29 PM       214      0.00
04:35:29 PM       215      0.00
04:35:29 PM       216      0.00
04:35:29 PM       217      0.00
04:35:29 PM       218      0.00
04:35:29 PM       219      0.00
04:35:29 PM       220      0.00
04:35:29 PM       221      0.00
04:35:29 PM       222      0.00
04:35:29 PM       223      0.00
04:35:29 PM       224      0.00
04:35:29 PM       225      0.00
04:35:29 PM       226      0.00
04:35:29 PM       227      0.00
04:35:29 PM       228      0.00
04:35:29 PM       229      0.00
04:35:29 PM       230      0.00
04:35:29 PM       231      0.00
04:35:29 PM       232      0.00
04:35:29 PM       233      0.00
04:35:29 PM       234      0.00
04:35:29 PM       235      0.00
04:35:29 PM       236      0.00
04:35:29 PM       237      0.00
04:35:29 PM       238      0.00
04:35:29 PM       239      0.00
04:35:29 PM       240      0.00
04:35:29 PM       241      0.00
04:35:29 PM       242      0.00
04:35:29 PM       243      0.00
04:35:29 PM       244      0.00
04:35:29 PM       245      0.00
04:35:29 PM       246      0.00
04:35:29 PM       247      0.00
04:35:29 PM       248      0.00
04:35:29 PM       249      0.00
04:35:29 PM       250      0.00
04:35:29 PM       251      0.00
04:35:29 PM       252      0.00
04:35:29 PM       253      0.00
04:35:29 PM       254      0.00
04:35:29 PM       255      0.00

04:35:27 PM  pswpin/s pswpout/s
04:35:29 PM      0.00      0.00

04:35:27 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:29 PM      0.00     44.00    122.50      0.00    546.50      0.00      0.00      0.00      0.00

04:35:27 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:29 PM     14.50      0.00     14.50      0.00    232.00

04:35:27 PM   frmpg/s   bufpg/s   campg/s
04:35:29 PM    232.50      0.00      2.00

04:35:27 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:29 PM     81676   8113884     99.00       176   5019004   4685380      8.34   4224920   2972072

04:35:27 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:29 PM  48016452       948      0.00       224     23.63

04:35:27 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:29 PM    158622      9888    134011       110

04:35:27 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:29 PM         0       476      0.00      0.01      0.05         0

04:35:27 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:29 PM    dev8-0      5.00      0.00     80.00     16.00      0.04      8.00      7.00      3.50
04:35:29 PM   dev8-16      5.00      0.00     80.00     16.00      0.04      8.00      7.00      3.50
04:35:29 PM    dev9-0      4.50      0.00     72.00     16.00      0.00      0.00      0.00      0.00
04:35:29 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:29 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:29 PM      eth0      6.50      6.50      0.86      8.94      0.00      0.00      0.00
04:35:29 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:29 PM      tun0      6.50      6.50      0.33      8.43      0.00      0.00      0.00

04:35:27 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:29 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:29 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:29 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:29 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:29 PM       882        32         9         0         0         0

04:35:27 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:29 PM     13.00      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:27 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM  active/s passive/s    iseg/s    oseg/s
04:35:29 PM      0.00      0.00      6.50      6.50

04:35:27 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00

04:35:27 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:29 PM      6.50      6.50      0.00      0.00

04:35:27 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:29 PM         2         2         0         0

04:35:27 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:29 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:27 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:29 PM      0.00      0.00      0.00      0.00

04:35:27 PM     CPU       MHz
04:35:29 PM     all   1596.00
04:35:29 PM       0   1596.00
04:35:29 PM       1   1596.00
04:35:29 PM       2   1596.00
04:35:29 PM       3   1596.00

04:35:27 PM     FAN       rpm      drpm                   DEVICE
04:35:29 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:29 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:29 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:29 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:27 PM    TEMP      degC     %temp                   DEVICE
04:35:29 PM       1     47.00     78.33           atk0110-acpi-0
04:35:29 PM       2     43.00     95.56           atk0110-acpi-0

04:35:27 PM      IN       inV       %in                   DEVICE
04:35:29 PM       0      1.10     33.87           atk0110-acpi-0
04:35:29 PM       1      3.25     42.12           atk0110-acpi-0
04:35:29 PM       2      5.02     51.70           atk0110-acpi-0
04:35:29 PM       3     12.20     55.44           atk0110-acpi-0

04:35:27 PM kbhugfree kbhugused  %hugused
04:35:29 PM         0         0      0.00

04:35:27 PM     CPU    wghMHz
04:35:29 PM     all   1619.94
04:35:29 PM       0   1695.75
04:35:29 PM       1   1596.00
04:35:29 PM       2   1596.00
04:35:29 PM       3   1596.00

04:35:29 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:31 PM     all      2.51      0.00      1.38      0.00      0.00      0.00      0.00      0.00     96.11
04:35:31 PM       0      7.54      0.00      4.02      0.00      0.00      0.00      0.00      0.00     88.44
04:35:31 PM       1      1.51      0.00      0.50      0.00      0.00      0.00      0.00      0.00     97.99
04:35:31 PM       2      1.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     98.50
04:35:31 PM       3      0.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.50

04:35:29 PM    proc/s   cswch/s
04:35:31 PM      0.00   2094.50

04:35:29 PM      INTR    intr/s
04:35:31 PM       sum    692.50
04:35:31 PM         0      0.00
04:35:31 PM         1      0.00
04:35:31 PM         2      0.00
04:35:31 PM         3      0.00
04:35:31 PM         4      0.00
04:35:31 PM         5      0.00
04:35:31 PM         6      0.00
04:35:31 PM         7      0.00
04:35:31 PM         8      0.00
04:35:31 PM         9      0.00
04:35:31 PM        10      0.00
04:35:31 PM        11      0.00
04:35:31 PM        12      0.00
04:35:31 PM        13      0.00
04:35:31 PM        14      0.00
04:35:31 PM        15      0.00
04:35:31 PM        16      1.00
04:35:31 PM        17      2.50
04:35:31 PM        18      0.00
04:35:31 PM        19      0.00
04:35:31 PM        20      0.00
04:35:31 PM        21      0.00
04:35:31 PM        22      0.00
04:35:31 PM        23      0.50
04:35:31 PM        24      0.00
04:35:31 PM        25      0.00
04:35:31 PM        26      0.00
04:35:31 PM        27      0.00
04:35:31 PM        28      0.00
04:35:31 PM        29      0.00
04:35:31 PM        30      0.00
04:35:31 PM        31      0.00
04:35:31 PM        32      0.00
04:35:31 PM        33      0.00
04:35:31 PM        34      0.00
04:35:31 PM        35      0.00
04:35:31 PM        36      0.00
04:35:31 PM        37      0.00
04:35:31 PM        38      0.00
04:35:31 PM        39      0.00
04:35:31 PM        40      0.00
04:35:31 PM        41      0.00
04:35:31 PM        42      0.00
04:35:31 PM        43      0.00
04:35:31 PM        44     12.50
04:35:31 PM        45      1.00
04:35:31 PM        46      0.00
04:35:31 PM        47      0.00
04:35:31 PM        48      0.00
04:35:31 PM        49      0.00
04:35:31 PM        50      0.00
04:35:31 PM        51      0.00
04:35:31 PM        52      0.00
04:35:31 PM        53      0.00
04:35:31 PM        54      0.00
04:35:31 PM        55      0.00
04:35:31 PM        56      0.00
04:35:31 PM        57      0.00
04:35:31 PM        58      0.00
04:35:31 PM        59      0.00
04:35:31 PM        60      0.00
04:35:31 PM        61      0.00
04:35:31 PM        62      0.00
04:35:31 PM        63      0.00
04:35:31 PM        64      0.00
04:35:31 PM        65      0.00
04:35:31 PM        66      0.00
04:35:31 PM        67      0.00
04:35:31 PM        68      0.00
04:35:31 PM        69      0.00
04:35:31 PM        70      0.00
04:35:31 PM        71      0.00
04:35:31 PM        72      0.00
04:35:31 PM        73      0.00
04:35:31 PM        74      0.00
04:35:31 PM        75      0.00
04:35:31 PM        76      0.00
04:35:31 PM        77      0.00
04:35:31 PM        78      0.00
04:35:31 PM        79      0.00
04:35:31 PM        80      0.00
04:35:31 PM        81      0.00
04:35:31 PM        82      0.00
04:35:31 PM        83      0.00
04:35:31 PM        84      0.00
04:35:31 PM        85      0.00
04:35:31 PM        86      0.00
04:35:31 PM        87      0.00
04:35:31 PM        88      0.00
04:35:31 PM        89      0.00
04:35:31 PM        90      0.00
04:35:31 PM        91      0.00
04:35:31 PM        92      0.00
04:35:31 PM        93      0.00
04:35:31 PM        94      0.00
04:35:31 PM        95      0.00
04:35:31 PM        96      0.00
04:35:31 PM        97      0.00
04:35:31 PM        98      0.00
04:35:31 PM        99      0.00
04:35:31 PM       100      0.00
04:35:31 PM       101      0.00
04:35:31 PM       102      0.00
04:35:31 PM       103      0.00
04:35:31 PM       104      0.00
04:35:31 PM       105      0.00
04:35:31 PM       106      0.00
04:35:31 PM       107      0.00
04:35:31 PM       108      0.00
04:35:31 PM       109      0.00
04:35:31 PM       110      0.00
04:35:31 PM       111      0.00
04:35:31 PM       112      0.00
04:35:31 PM       113      0.00
04:35:31 PM       114      0.00
04:35:31 PM       115      0.00
04:35:31 PM       116      0.00
04:35:31 PM       117      0.00
04:35:31 PM       118      0.00
04:35:31 PM       119      0.00
04:35:31 PM       120      0.00
04:35:31 PM       121      0.00
04:35:31 PM       122      0.00
04:35:31 PM       123      0.00
04:35:31 PM       124      0.00
04:35:31 PM       125      0.00
04:35:31 PM       126      0.00
04:35:31 PM       127      0.00
04:35:31 PM       128      0.00
04:35:31 PM       129      0.00
04:35:31 PM       130      0.00
04:35:31 PM       131      0.00
04:35:31 PM       132      0.00
04:35:31 PM       133      0.00
04:35:31 PM       134      0.00
04:35:31 PM       135      0.00
04:35:31 PM       136      0.00
04:35:31 PM       137      0.00
04:35:31 PM       138      0.00
04:35:31 PM       139      0.00
04:35:31 PM       140      0.00
04:35:31 PM       141      0.00
04:35:31 PM       142      0.00
04:35:31 PM       143      0.00
04:35:31 PM       144      0.00
04:35:31 PM       145      0.00
04:35:31 PM       146      0.00
04:35:31 PM       147      0.00
04:35:31 PM       148      0.00
04:35:31 PM       149      0.00
04:35:31 PM       150      0.00
04:35:31 PM       151      0.00
04:35:31 PM       152      0.00
04:35:31 PM       153      0.00
04:35:31 PM       154      0.00
04:35:31 PM       155      0.00
04:35:31 PM       156      0.00
04:35:31 PM       157      0.00
04:35:31 PM       158      0.00
04:35:31 PM       159      0.00
04:35:31 PM       160      0.00
04:35:31 PM       161      0.00
04:35:31 PM       162      0.00
04:35:31 PM       163      0.00
04:35:31 PM       164      0.00
04:35:31 PM       165      0.00
04:35:31 PM       166      0.00
04:35:31 PM       167      0.00
04:35:31 PM       168      0.00
04:35:31 PM       169      0.00
04:35:31 PM       170      0.00
04:35:31 PM       171      0.00
04:35:31 PM       172      0.00
04:35:31 PM       173      0.00
04:35:31 PM       174      0.00
04:35:31 PM       175      0.00
04:35:31 PM       176      0.00
04:35:31 PM       177      0.00
04:35:31 PM       178      0.00
04:35:31 PM       179      0.00
04:35:31 PM       180      0.00
04:35:31 PM       181      0.00
04:35:31 PM       182      0.00
04:35:31 PM       183      0.00
04:35:31 PM       184      0.00
04:35:31 PM       185      0.00
04:35:31 PM       186      0.00
04:35:31 PM       187      0.00
04:35:31 PM       188      0.00
04:35:31 PM       189      0.00
04:35:31 PM       190      0.00
04:35:31 PM       191      0.00
04:35:31 PM       192      0.00
04:35:31 PM       193      0.00
04:35:31 PM       194      0.00
04:35:31 PM       195      0.00
04:35:31 PM       196      0.00
04:35:31 PM       197      0.00
04:35:31 PM       198      0.00
04:35:31 PM       199      0.00
04:35:31 PM       200      0.00
04:35:31 PM       201      0.00
04:35:31 PM       202      0.00
04:35:31 PM       203      0.00
04:35:31 PM       204      0.00
04:35:31 PM       205      0.00
04:35:31 PM       206      0.00
04:35:31 PM       207      0.00
04:35:31 PM       208      0.00
04:35:31 PM       209      0.00
04:35:31 PM       210      0.00
04:35:31 PM       211      0.00
04:35:31 PM       212      0.00
04:35:31 PM       213      0.00
04:35:31 PM       214      0.00
04:35:31 PM       215      0.00
04:35:31 PM       216      0.00
04:35:31 PM       217      0.00
04:35:31 PM       218      0.00
04:35:31 PM       219      0.00
04:35:31 PM       220      0.00
04:35:31 PM       221      0.00
04:35:31 PM       222      0.00
04:35:31 PM       223      0.00
04:35:31 PM       224      0.00
04:35:31 PM       225      0.00
04:35:31 PM       226      0.00
04:35:31 PM       227      0.00
04:35:31 PM       228      0.00
04:35:31 PM       229      0.00
04:35:31 PM       230      0.00
04:35:31 PM       231      0.00
04:35:31 PM       232      0.00
04:35:31 PM       233      0.00
04:35:31 PM       234      0.00
04:35:31 PM       235      0.00
04:35:31 PM       236      0.00
04:35:31 PM       237      0.00
04:35:31 PM       238      0.00
04:35:31 PM       239      0.00
04:35:31 PM       240      0.00
04:35:31 PM       241      0.00
04:35:31 PM       242      0.00
04:35:31 PM       243      0.00
04:35:31 PM       244      0.00
04:35:31 PM       245      0.00
04:35:31 PM       246      0.00
04:35:31 PM       247      0.00
04:35:31 PM       248      0.00
04:35:31 PM       249      0.00
04:35:31 PM       250      0.00
04:35:31 PM       251      0.00
04:35:31 PM       252      0.00
04:35:31 PM       253      0.00
04:35:31 PM       254      0.00
04:35:31 PM       255      0.00

04:35:29 PM  pswpin/s pswpout/s
04:35:31 PM      0.00      0.00

04:35:29 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:31 PM      0.00      0.00     40.00      0.00    283.00      0.00      0.00      0.00      0.00

04:35:29 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00

04:35:29 PM   frmpg/s   bufpg/s   campg/s
04:35:31 PM      0.00      0.00      2.00

04:35:29 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:31 PM     81676   8113884     99.00       176   5019020   4685380      8.34   4224972   2972076

04:35:29 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:31 PM  48016452       948      0.00       224     23.63

04:35:29 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:31 PM    158622      9888    134011       110

04:35:29 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:31 PM         0       476      0.00      0.01      0.05         0

04:35:29 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:31 PM    dev8-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:31 PM   dev8-16      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:31 PM    dev9-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:31 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:31 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:31 PM      eth0      6.50      7.00      0.88      8.98      0.00      0.00      0.00
04:35:31 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:31 PM      tun0      6.50      7.00      0.35      8.43      0.00      0.00      0.00

04:35:29 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:31 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:31 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:31 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:31 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:31 PM       882        32         9         0         0         0

04:35:29 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:31 PM     13.00      0.00     13.00     14.00      0.00      0.00      0.00      0.00

04:35:29 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM  active/s passive/s    iseg/s    oseg/s
04:35:31 PM      0.00      0.00      6.50      7.00

04:35:29 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00

04:35:29 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:31 PM      6.50      7.00      0.00      0.00

04:35:29 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:31 PM         2         2         0         0

04:35:29 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:31 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:29 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:31 PM      0.00      0.00      0.00      0.00

04:35:29 PM     CPU       MHz
04:35:31 PM     all   1596.00
04:35:31 PM       0   1596.00
04:35:31 PM       1   1596.00
04:35:31 PM       2   1596.00
04:35:31 PM       3   1596.00

04:35:29 PM     FAN       rpm      drpm                   DEVICE
04:35:31 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:31 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:31 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:31 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:29 PM    TEMP      degC     %temp                   DEVICE
04:35:31 PM       1     47.00     78.33           atk0110-acpi-0
04:35:31 PM       2     43.00     95.56           atk0110-acpi-0

04:35:29 PM      IN       inV       %in                   DEVICE
04:35:31 PM       0      1.10     33.87           atk0110-acpi-0
04:35:31 PM       1      3.25     42.12           atk0110-acpi-0
04:35:31 PM       2      5.02     51.70           atk0110-acpi-0
04:35:31 PM       3     12.20     55.44           atk0110-acpi-0

04:35:29 PM kbhugfree kbhugused  %hugused
04:35:31 PM         0         0      0.00

04:35:29 PM     CPU    wghMHz
04:35:31 PM     all   1596.00
04:35:31 PM       0   1596.00
04:35:31 PM       1   1596.00
04:35:31 PM       2   1596.00
04:35:31 PM       3   1596.00

04:35:31 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:33 PM     all      2.12      0.00      0.87      0.00      0.00      0.00      0.00      0.00     97.01
04:35:33 PM       0      2.49      0.00      1.00      0.00      0.00      0.00      0.00      0.00     96.52
04:35:33 PM       1      5.47      0.00      1.99      0.00      0.00      0.00      0.00      0.00     92.54
04:35:33 PM       2      0.50      0.00      0.00      0.00      0.00      0.00      0.00      0.00     99.50
04:35:33 PM       3      0.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     99.50

04:35:31 PM    proc/s   cswch/s
04:35:33 PM      0.00   2119.00

04:35:31 PM      INTR    intr/s
04:35:33 PM       sum    693.50
04:35:33 PM         0      0.00
04:35:33 PM         1      0.00
04:35:33 PM         2      0.00
04:35:33 PM         3      0.00
04:35:33 PM         4      0.00
04:35:33 PM         5      0.00
04:35:33 PM         6      0.00
04:35:33 PM         7      0.00
04:35:33 PM         8      0.00
04:35:33 PM         9      0.00
04:35:33 PM        10      0.00
04:35:33 PM        11      0.00
04:35:33 PM        12      0.00
04:35:33 PM        13      0.00
04:35:33 PM        14      0.00
04:35:33 PM        15      0.00
04:35:33 PM        16      1.00
04:35:33 PM        17      2.50
04:35:33 PM        18      0.00
04:35:33 PM        19      9.00
04:35:33 PM        20      0.00
04:35:33 PM        21      0.00
04:35:33 PM        22      0.00
04:35:33 PM        23      0.50
04:35:33 PM        24      0.00
04:35:33 PM        25      0.00
04:35:33 PM        26      0.00
04:35:33 PM        27      0.00
04:35:33 PM        28      0.00
04:35:33 PM        29      0.00
04:35:33 PM        30      0.00
04:35:33 PM        31      0.00
04:35:33 PM        32      0.00
04:35:33 PM        33      0.00
04:35:33 PM        34      0.00
04:35:33 PM        35      0.00
04:35:33 PM        36      0.00
04:35:33 PM        37      0.00
04:35:33 PM        38      0.00
04:35:33 PM        39      0.00
04:35:33 PM        40      0.00
04:35:33 PM        41      0.00
04:35:33 PM        42      0.00
04:35:33 PM        43      0.00
04:35:33 PM        44     12.50
04:35:33 PM        45      1.00
04:35:33 PM        46      0.00
04:35:33 PM        47      0.00
04:35:33 PM        48      0.00
04:35:33 PM        49      0.00
04:35:33 PM        50      0.00
04:35:33 PM        51      0.00
04:35:33 PM        52      0.00
04:35:33 PM        53      0.00
04:35:33 PM        54      0.00
04:35:33 PM        55      0.00
04:35:33 PM        56      0.00
04:35:33 PM        57      0.00
04:35:33 PM        58      0.00
04:35:33 PM        59      0.00
04:35:33 PM        60      0.00
04:35:33 PM        61      0.00
04:35:33 PM        62      0.00
04:35:33 PM        63      0.00
04:35:33 PM        64      0.00
04:35:33 PM        65      0.00
04:35:33 PM        66      0.00
04:35:33 PM        67      0.00
04:35:33 PM        68      0.00
04:35:33 PM        69      0.00
04:35:33 PM        70      0.00
04:35:33 PM        71      0.00
04:35:33 PM        72      0.00
04:35:33 PM        73      0.00
04:35:33 PM        74      0.00
04:35:33 PM        75      0.00
04:35:33 PM        76      0.00
04:35:33 PM        77      0.00
04:35:33 PM        78      0.00
04:35:33 PM        79      0.00
04:35:33 PM        80      0.00
04:35:33 PM        81      0.00
04:35:33 PM        82      0.00
04:35:33 PM        83      0.00
04:35:33 PM        84      0.00
04:35:33 PM        85      0.00
04:35:33 PM        86      0.00
04:35:33 PM        87      0.00
04:35:33 PM        88      0.00
04:35:33 PM        89      0.00
04:35:33 PM        90      0.00
04:35:33 PM        91      0.00
04:35:33 PM        92      0.00
04:35:33 PM        93      0.00
04:35:33 PM        94      0.00
04:35:33 PM        95      0.00
04:35:33 PM        96      0.00
04:35:33 PM        97      0.00
04:35:33 PM        98      0.00
04:35:33 PM        99      0.00
04:35:33 PM       100      0.00
04:35:33 PM       101      0.00
04:35:33 PM       102      0.00
04:35:33 PM       103      0.00
04:35:33 PM       104      0.00
04:35:33 PM       105      0.00
04:35:33 PM       106      0.00
04:35:33 PM       107      0.00
04:35:33 PM       108      0.00
04:35:33 PM       109      0.00
04:35:33 PM       110      0.00
04:35:33 PM       111      0.00
04:35:33 PM       112      0.00
04:35:33 PM       113      0.00
04:35:33 PM       114      0.00
04:35:33 PM       115      0.00
04:35:33 PM       116      0.00
04:35:33 PM       117      0.00
04:35:33 PM       118      0.00
04:35:33 PM       119      0.00
04:35:33 PM       120      0.00
04:35:33 PM       121      0.00
04:35:33 PM       122      0.00
04:35:33 PM       123      0.00
04:35:33 PM       124      0.00
04:35:33 PM       125      0.00
04:35:33 PM       126      0.00
04:35:33 PM       127      0.00
04:35:33 PM       128      0.00
04:35:33 PM       129      0.00
04:35:33 PM       130      0.00
04:35:33 PM       131      0.00
04:35:33 PM       132      0.00
04:35:33 PM       133      0.00
04:35:33 PM       134      0.00
04:35:33 PM       135      0.00
04:35:33 PM       136      0.00
04:35:33 PM       137      0.00
04:35:33 PM       138      0.00
04:35:33 PM       139      0.00
04:35:33 PM       140      0.00
04:35:33 PM       141      0.00
04:35:33 PM       142      0.00
04:35:33 PM       143      0.00
04:35:33 PM       144      0.00
04:35:33 PM       145      0.00
04:35:33 PM       146      0.00
04:35:33 PM       147      0.00
04:35:33 PM       148      0.00
04:35:33 PM       149      0.00
04:35:33 PM       150      0.00
04:35:33 PM       151      0.00
04:35:33 PM       152      0.00
04:35:33 PM       153      0.00
04:35:33 PM       154      0.00
04:35:33 PM       155      0.00
04:35:33 PM       156      0.00
04:35:33 PM       157      0.00
04:35:33 PM       158      0.00
04:35:33 PM       159      0.00
04:35:33 PM       160      0.00
04:35:33 PM       161      0.00
04:35:33 PM       162      0.00
04:35:33 PM       163      0.00
04:35:33 PM       164      0.00
04:35:33 PM       165      0.00
04:35:33 PM       166      0.00
04:35:33 PM       167      0.00
04:35:33 PM       168      0.00
04:35:33 PM       169      0.00
04:35:33 PM       170      0.00
04:35:33 PM       171      0.00
04:35:33 PM       172      0.00
04:35:33 PM       173      0.00
04:35:33 PM       174      0.00
04:35:33 PM       175      0.00
04:35:33 PM       176      0.00
04:35:33 PM       177      0.00
04:35:33 PM       178      0.00
04:35:33 PM       179      0.00
04:35:33 PM       180      0.00
04:35:33 PM       181      0.00
04:35:33 PM       182      0.00
04:35:33 PM       183      0.00
04:35:33 PM       184      0.00
04:35:33 PM       185      0.00
04:35:33 PM       186      0.00
04:35:33 PM       187      0.00
04:35:33 PM       188      0.00
04:35:33 PM       189      0.00
04:35:33 PM       190      0.00
04:35:33 PM       191      0.00
04:35:33 PM       192      0.00
04:35:33 PM       193      0.00
04:35:33 PM       194      0.00
04:35:33 PM       195      0.00
04:35:33 PM       196      0.00
04:35:33 PM       197      0.00
04:35:33 PM       198      0.00
04:35:33 PM       199      0.00
04:35:33 PM       200      0.00
04:35:33 PM       201      0.00
04:35:33 PM       202      0.00
04:35:33 PM       203      0.00
04:35:33 PM       204      0.00
04:35:33 PM       205      0.00
04:35:33 PM       206      0.00
04:35:33 PM       207      0.00
04:35:33 PM       208      0.00
04:35:33 PM       209      0.00
04:35:33 PM       210      0.00
04:35:33 PM       211      0.00
04:35:33 PM       212      0.00
04:35:33 PM       213      0.00
04:35:33 PM       214      0.00
04:35:33 PM       215      0.00
04:35:33 PM       216      0.00
04:35:33 PM       217      0.00
04:35:33 PM       218      0.00
04:35:33 PM       219      0.00
04:35:33 PM       220      0.00
04:35:33 PM       221      0.00
04:35:33 PM       222      0.00
04:35:33 PM       223      0.00
04:35:33 PM       224      0.00
04:35:33 PM       225      0.00
04:35:33 PM       226      0.00
04:35:33 PM       227      0.00
04:35:33 PM       228      0.00
04:35:33 PM       229      0.00
04:35:33 PM       230      0.00
04:35:33 PM       231      0.00
04:35:33 PM       232      0.00
04:35:33 PM       233      0.00
04:35:33 PM       234      0.00
04:35:33 PM       235      0.00
04:35:33 PM       236      0.00
04:35:33 PM       237      0.00
04:35:33 PM       238      0.00
04:35:33 PM       239      0.00
04:35:33 PM       240      0.00
04:35:33 PM       241      0.00
04:35:33 PM       242      0.00
04:35:33 PM       243      0.00
04:35:33 PM       244      0.00
04:35:33 PM       245      0.00
04:35:33 PM       246      0.00
04:35:33 PM       247      0.00
04:35:33 PM       248      0.00
04:35:33 PM       249      0.00
04:35:33 PM       250      0.00
04:35:33 PM       251      0.00
04:35:33 PM       252      0.00
04:35:33 PM       253      0.00
04:35:33 PM       254      0.00
04:35:33 PM       255      0.00

04:35:31 PM  pswpin/s pswpout/s
04:35:33 PM      0.00      0.00

04:35:31 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:33 PM      0.00     18.00     31.00      0.00    283.00      0.00      0.00      0.00      0.00

04:35:31 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:33 PM      6.50      0.00      6.50      0.00     76.00

04:35:31 PM   frmpg/s   bufpg/s   campg/s
04:35:33 PM      0.00      0.00      1.50

04:35:31 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:33 PM     81676   8113884     99.00       176   5019032   4685380      8.34   4225008   2972080

04:35:31 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:33 PM  48016452       948      0.00       224     23.63

04:35:31 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:33 PM    158622      9888    134011       110

04:35:31 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:33 PM         0       476      0.00      0.01      0.05         0

04:35:31 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:33 PM    dev8-0      2.50      0.00     28.00     11.20      0.03     10.00     10.00      2.50
04:35:33 PM   dev8-16      2.50      0.00     28.00     11.20      0.03     10.00     10.00      2.50
04:35:33 PM    dev9-0      1.50      0.00     20.00     13.33      0.00      0.00      0.00      0.00
04:35:33 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:33 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:33 PM      eth0      7.00      7.00      0.89      8.93      0.00      0.00      0.00
04:35:33 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:33 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:31 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:33 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:33 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:33 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:33 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:33 PM       882        32         9         0         0         0

04:35:31 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:33 PM     13.00      0.00     13.00     13.00      0.00      0.00      0.00      0.00

04:35:31 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM  active/s passive/s    iseg/s    oseg/s
04:35:33 PM      0.00      0.00      6.50      6.50

04:35:31 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00

04:35:31 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:33 PM      6.50      6.50      0.00      0.00

04:35:31 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:33 PM         2         2         0         0

04:35:31 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:33 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:31 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:33 PM      0.00      0.00      0.00      0.00

04:35:31 PM     CPU       MHz
04:35:33 PM     all   1596.00
04:35:33 PM       0   1596.00
04:35:33 PM       1   1596.00
04:35:33 PM       2   1596.00
04:35:33 PM       3   1596.00

04:35:31 PM     FAN       rpm      drpm                   DEVICE
04:35:33 PM       1   2596.00   1996.00           atk0110-acpi-0
04:35:33 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:33 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:33 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:31 PM    TEMP      degC     %temp                   DEVICE
04:35:33 PM       1     47.00     78.33           atk0110-acpi-0
04:35:33 PM       2     43.00     95.56           atk0110-acpi-0

04:35:31 PM      IN       inV       %in                   DEVICE
04:35:33 PM       0      1.14     38.13           atk0110-acpi-0
04:35:33 PM       1      3.25     42.12           atk0110-acpi-0
04:35:33 PM       2      5.02     51.70           atk0110-acpi-0
04:35:33 PM       3     12.20     55.44           atk0110-acpi-0

04:35:31 PM kbhugfree kbhugused  %hugused
04:35:33 PM         0         0      0.00

04:35:31 PM     CPU    wghMHz
04:35:33 PM     all   1619.82
04:35:33 PM       0   1596.00
04:35:33 PM       1   1683.78
04:35:33 PM       2   1596.00
04:35:33 PM       3   1596.00

04:35:33 PM     CPU      %usr     %nice      %sys   %iowait    %steal      %irq     %soft    %guest     %idle
04:35:35 PM     all      3.37      0.00      1.12      0.00      0.00      0.00      0.00      0.00     95.51
04:35:35 PM       0      3.50      0.00      0.50      0.00      0.00      0.00      0.00      0.00     96.00
04:35:35 PM       1      8.50      0.00      1.50      0.00      0.00      0.00      0.00      0.00     90.00
04:35:35 PM       2      1.00      0.00      0.50      0.00      0.00      0.00      0.00      0.00     98.50
04:35:35 PM       3      0.50      0.00      1.99      0.00      0.00      0.00      0.00      0.00     97.51

04:35:33 PM    proc/s   cswch/s
04:35:35 PM      0.00   2170.50

04:35:33 PM      INTR    intr/s
04:35:35 PM       sum    727.00
04:35:35 PM         0      0.00
04:35:35 PM         1      0.00
04:35:35 PM         2      0.00
04:35:35 PM         3      0.00
04:35:35 PM         4      0.00
04:35:35 PM         5      0.00
04:35:35 PM         6      0.00
04:35:35 PM         7      0.00
04:35:35 PM         8      0.00
04:35:35 PM         9      0.00
04:35:35 PM        10      0.00
04:35:35 PM        11      0.00
04:35:35 PM        12      0.00
04:35:35 PM        13      0.00
04:35:35 PM        14      0.00
04:35:35 PM        15      0.00
04:35:35 PM        16      1.00
04:35:35 PM        17      2.50
04:35:35 PM        18      0.00
04:35:35 PM        19     27.00
04:35:35 PM        20      0.00
04:35:35 PM        21      0.00
04:35:35 PM        22      0.00
04:35:35 PM        23      0.50
04:35:35 PM        24      0.00
04:35:35 PM        25      0.00
04:35:35 PM        26      0.00
04:35:35 PM        27      0.00
04:35:35 PM        28      0.00
04:35:35 PM        29      0.00
04:35:35 PM        30      0.00
04:35:35 PM        31      0.00
04:35:35 PM        32      0.00
04:35:35 PM        33      0.00
04:35:35 PM        34      0.00
04:35:35 PM        35      0.00
04:35:35 PM        36      0.00
04:35:35 PM        37      0.00
04:35:35 PM        38      0.00
04:35:35 PM        39      0.00
04:35:35 PM        40      0.00
04:35:35 PM        41      0.00
04:35:35 PM        42      0.00
04:35:35 PM        43      0.00
04:35:35 PM        44     11.50
04:35:35 PM        45      1.00
04:35:35 PM        46      0.00
04:35:35 PM        47      0.00
04:35:35 PM        48      0.00
04:35:35 PM        49      0.00
04:35:35 PM        50      0.00
04:35:35 PM        51      0.00
04:35:35 PM        52      0.00
04:35:35 PM        53      0.00
04:35:35 PM        54      0.00
04:35:35 PM        55      0.00
04:35:35 PM        56      0.00
04:35:35 PM        57      0.00
04:35:35 PM        58      0.00
04:35:35 PM        59      0.00
04:35:35 PM        60      0.00
04:35:35 PM        61      0.00
04:35:35 PM        62      0.00
04:35:35 PM        63      0.00
04:35:35 PM        64      0.00
04:35:35 PM        65      0.00
04:35:35 PM        66      0.00
04:35:35 PM        67      0.00
04:35:35 PM        68      0.00
04:35:35 PM        69      0.00
04:35:35 PM        70      0.00
04:35:35 PM        71      0.00
04:35:35 PM        72      0.00
04:35:35 PM        73      0.00
04:35:35 PM        74      0.00
04:35:35 PM        75      0.00
04:35:35 PM        76      0.00
04:35:35 PM        77      0.00
04:35:35 PM        78      0.00
04:35:35 PM        79      0.00
04:35:35 PM        80      0.00
04:35:35 PM        81      0.00
04:35:35 PM        82      0.00
04:35:35 PM        83      0.00
04:35:35 PM        84      0.00
04:35:35 PM        85      0.00
04:35:35 PM        86      0.00
04:35:35 PM        87      0.00
04:35:35 PM        88      0.00
04:35:35 PM        89      0.00
04:35:35 PM        90      0.00
04:35:35 PM        91      0.00
04:35:35 PM        92      0.00
04:35:35 PM        93      0.00
04:35:35 PM        94      0.00
04:35:35 PM        95      0.00
04:35:35 PM        96      0.00
04:35:35 PM        97      0.00
04:35:35 PM        98      0.00
04:35:35 PM        99      0.00
04:35:35 PM       100      0.00
04:35:35 PM       101      0.00
04:35:35 PM       102      0.00
04:35:35 PM       103      0.00
04:35:35 PM       104      0.00
04:35:35 PM       105      0.00
04:35:35 PM       106      0.00
04:35:35 PM       107      0.00
04:35:35 PM       108      0.00
04:35:35 PM       109      0.00
04:35:35 PM       110      0.00
04:35:35 PM       111      0.00
04:35:35 PM       112      0.00
04:35:35 PM       113      0.00
04:35:35 PM       114      0.00
04:35:35 PM       115      0.00
04:35:35 PM       116      0.00
04:35:35 PM       117      0.00
04:35:35 PM       118      0.00
04:35:35 PM       119      0.00
04:35:35 PM       120      0.00
04:35:35 PM       121      0.00
04:35:35 PM       122      0.00
04:35:35 PM       123      0.00
04:35:35 PM       124      0.00
04:35:35 PM       125      0.00
04:35:35 PM       126      0.00
04:35:35 PM       127      0.00
04:35:35 PM       128      0.00
04:35:35 PM       129      0.00
04:35:35 PM       130      0.00
04:35:35 PM       131      0.00
04:35:35 PM       132      0.00
04:35:35 PM       133      0.00
04:35:35 PM       134      0.00
04:35:35 PM       135      0.00
04:35:35 PM       136      0.00
04:35:35 PM       137      0.00
04:35:35 PM       138      0.00
04:35:35 PM       139      0.00
04:35:35 PM       140      0.00
04:35:35 PM       141      0.00
04:35:35 PM       142      0.00
04:35:35 PM       143      0.00
04:35:35 PM       144      0.00
04:35:35 PM       145      0.00
04:35:35 PM       146      0.00
04:35:35 PM       147      0.00
04:35:35 PM       148      0.00
04:35:35 PM       149      0.00
04:35:35 PM       150      0.00
04:35:35 PM       151      0.00
04:35:35 PM       152      0.00
04:35:35 PM       153      0.00
04:35:35 PM       154      0.00
04:35:35 PM       155      0.00
04:35:35 PM       156      0.00
04:35:35 PM       157      0.00
04:35:35 PM       158      0.00
04:35:35 PM       159      0.00
04:35:35 PM       160      0.00
04:35:35 PM       161      0.00
04:35:35 PM       162      0.00
04:35:35 PM       163      0.00
04:35:35 PM       164      0.00
04:35:35 PM       165      0.00
04:35:35 PM       166      0.00
04:35:35 PM       167      0.00
04:35:35 PM       168      0.00
04:35:35 PM       169      0.00
04:35:35 PM       170      0.00
04:35:35 PM       171      0.00
04:35:35 PM       172      0.00
04:35:35 PM       173      0.00
04:35:35 PM       174      0.00
04:35:35 PM       175      0.00
04:35:35 PM       176      0.00
04:35:35 PM       177      0.00
04:35:35 PM       178      0.00
04:35:35 PM       179      0.00
04:35:35 PM       180      0.00
04:35:35 PM       181      0.00
04:35:35 PM       182      0.00
04:35:35 PM       183      0.00
04:35:35 PM       184      0.00
04:35:35 PM       185      0.00
04:35:35 PM       186      0.00
04:35:35 PM       187      0.00
04:35:35 PM       188      0.00
04:35:35 PM       189      0.00
04:35:35 PM       190      0.00
04:35:35 PM       191      0.00
04:35:35 PM       192      0.00
04:35:35 PM       193      0.00
04:35:35 PM       194      0.00
04:35:35 PM       195      0.00
04:35:35 PM       196      0.00
04:35:35 PM       197      0.00
04:35:35 PM       198      0.00
04:35:35 PM       199      0.00
04:35:35 PM       200      0.00
04:35:35 PM       201      0.00
04:35:35 PM       202      0.00
04:35:35 PM       203      0.00
04:35:35 PM       204      0.00
04:35:35 PM       205      0.00
04:35:35 PM       206      0.00
04:35:35 PM       207      0.00
04:35:35 PM       208      0.00
04:35:35 PM       209      0.00
04:35:35 PM       210      0.00
04:35:35 PM       211      0.00
04:35:35 PM       212      0.00
04:35:35 PM       213      0.00
04:35:35 PM       214      0.00
04:35:35 PM       215      0.00
04:35:35 PM       216      0.00
04:35:35 PM       217      0.00
04:35:35 PM       218      0.00
04:35:35 PM       219      0.00
04:35:35 PM       220      0.00
04:35:35 PM       221      0.00
04:35:35 PM       222      0.00
04:35:35 PM       223      0.00
04:35:35 PM       224      0.00
04:35:35 PM       225      0.00
04:35:35 PM       226      0.00
04:35:35 PM       227      0.00
04:35:35 PM       228      0.00
04:35:35 PM       229      0.00
04:35:35 PM       230      0.00
04:35:35 PM       231      0.00
04:35:35 PM       232      0.00
04:35:35 PM       233      0.00
04:35:35 PM       234      0.00
04:35:35 PM       235      0.00
04:35:35 PM       236      0.00
04:35:35 PM       237      0.00
04:35:35 PM       238      0.00
04:35:35 PM       239      0.00
04:35:35 PM       240      0.00
04:35:35 PM       241      0.00
04:35:35 PM       242      0.00
04:35:35 PM       243      0.00
04:35:35 PM       244      0.00
04:35:35 PM       245      0.00
04:35:35 PM       246      0.00
04:35:35 PM       247      0.00
04:35:35 PM       248      0.00
04:35:35 PM       249      0.00
04:35:35 PM       250      0.00
04:35:35 PM       251      0.00
04:35:35 PM       252      0.00
04:35:35 PM       253      0.00
04:35:35 PM       254      0.00
04:35:35 PM       255      0.00

04:35:33 PM  pswpin/s pswpout/s
04:35:35 PM      0.00      0.00

04:35:33 PM  pgpgin/s pgpgout/s   fault/s  majflt/s  pgfree/s pgscank/s pgscand/s pgsteal/s    %vmeff
04:35:35 PM      0.00     45.00   1019.00      0.00   1230.00      0.00      0.00      0.00      0.00

04:35:33 PM       tps      rtps      wtps   bread/s   bwrtn/s
04:35:35 PM     23.50      0.00     23.50      0.00    204.50

04:35:33 PM   frmpg/s   bufpg/s   campg/s
04:35:35 PM    -77.50      0.00      2.00

04:35:33 PM kbmemfree kbmemused  %memused kbbuffers  kbcached  kbcommit   %commit  kbactive   kbinact
04:35:35 PM     81056   8114504     99.01       176   5019048   4689476      8.34   4225368   2972092

04:35:33 PM kbswpfree kbswpused  %swpused  kbswpcad   %swpcad
04:35:35 PM  48016452       948      0.00       224     23.63

04:35:33 PM dentunusd   file-nr  inode-nr    pty-nr
04:35:35 PM    158622      9888    134011       110

04:35:33 PM   runq-sz  plist-sz   ldavg-1   ldavg-5  ldavg-15   blocked
04:35:35 PM         0       476      0.00      0.01      0.05         0

04:35:33 PM       DEV       tps  rd_sec/s  wr_sec/s  avgrq-sz  avgqu-sz     await     svctm     %util
04:35:35 PM    dev8-0      8.50      0.00     73.50      8.65      0.07      8.82      8.82      7.50
04:35:35 PM   dev8-16      8.50      0.00     73.50      8.65      0.10     11.76     11.76     10.00
04:35:35 PM    dev9-0      6.50      0.00     57.50      8.85      0.00      0.00      0.00      0.00
04:35:35 PM   dev11-0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM     IFACE   rxpck/s   txpck/s    rxkB/s    txkB/s   rxcmp/s   txcmp/s  rxmcst/s
04:35:35 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:35 PM      eth0      6.50      7.00      0.86      8.93      0.00      0.00      0.00
04:35:35 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:35 PM      tun0      6.50      6.50      0.33      8.41      0.00      0.00      0.00

04:35:33 PM     IFACE   rxerr/s   txerr/s    coll/s  rxdrop/s  txdrop/s  txcarr/s  rxfram/s  rxfifo/s  txfifo/s
04:35:35 PM        lo      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:35 PM      eth0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:35 PM      eth1      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00
04:35:35 PM      tun0      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM    call/s retrans/s    read/s   write/s  access/s  getatt/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM   scall/s badcall/s  packet/s     udp/s     tcp/s     hit/s    miss/s   sread/s  swrite/s saccess/s sgetatt/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM    totsck    tcpsck    udpsck    rawsck   ip-frag    tcp-tw
04:35:35 PM       882        32         9         0         0         0

04:35:33 PM    irec/s  fwddgm/s    idel/s     orq/s   asmrq/s   asmok/s  fragok/s fragcrt/s
04:35:35 PM     13.00      0.00     13.00     13.50      0.00      0.00      0.00      0.00

04:35:33 PM ihdrerr/s iadrerr/s iukwnpr/s   idisc/s   odisc/s   onort/s    asmf/s   fragf/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM    imsg/s    omsg/s    iech/s   iechr/s    oech/s   oechr/s     itm/s    itmr/s     otm/s    otmr/s  iadrmk/s iadrmkr/s  oadrmk/s oadrmkr/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM    ierr/s    oerr/s idstunr/s odstunr/s   itmex/s   otmex/s iparmpb/s oparmpb/s   isrcq/s   osrcq/s  iredir/s  oredir/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM  active/s passive/s    iseg/s    oseg/s
04:35:35 PM      0.00      0.00      6.50      6.50

04:35:33 PM  atmptf/s  estres/s retrans/s isegerr/s   orsts/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00

04:35:33 PM    idgm/s    odgm/s  noport/s idgmerr/s
04:35:35 PM      6.50      7.00      0.00      0.00

04:35:33 PM   tcp6sck   udp6sck   raw6sck  ip6-frag
04:35:35 PM         2         2         0         0

04:35:33 PM   irec6/s fwddgm6/s   idel6/s    orq6/s  asmrq6/s  asmok6/s imcpck6/s omcpck6/s fragok6/s fragcr6/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM ihdrer6/s iadrer6/s iukwnp6/s  i2big6/s  idisc6/s  odisc6/s  inort6/s  onort6/s   asmf6/s  fragf6/s itrpck6/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM   imsg6/s   omsg6/s   iech6/s  iechr6/s  oechr6/s  igmbq6/s  igmbr6/s  ogmbr6/s igmbrd6/s ogmbrd6/s irtsol6/s ortsol6/s  irtad6/s inbsol6/s onbsol6/s  inbad6/s  onbad6/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM   ierr6/s idtunr6/s odtunr6/s  itmex6/s  otmex6/s iprmpb6/s oprmpb6/s iredir6/s oredir6/s ipck2b6/s opck2b6/s
04:35:35 PM      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00

04:35:33 PM   idgm6/s   odgm6/s noport6/s idgmer6/s
04:35:35 PM      0.00      0.00      0.00      0.00

04:35:33 PM     CPU       MHz
04:35:35 PM     all   1596.00
04:35:35 PM       0   1596.00
04:35:35 PM       1   1596.00
04:35:35 PM       2   1596.00
04:35:35 PM       3   1596.00

04:35:33 PM     FAN       rpm      drpm                   DEVICE
04:35:35 PM       1   2576.00   1976.00           atk0110-acpi-0
04:35:35 PM       2      0.00   -800.00           atk0110-acpi-0
04:35:35 PM       3      0.00   -800.00           atk0110-acpi-0
04:35:35 PM       4      0.00   -800.00           atk0110-acpi-0

04:35:33 PM    TEMP      degC     %temp                   DEVICE
04:35:35 PM       1     47.00     78.33           atk0110-acpi-0
04:35:35 PM       2     43.00     95.56           atk0110-acpi-0

04:35:33 PM      IN       inV       %in                   DEVICE
04:35:35 PM       0      1.10     33.87           atk0110-acpi-0
04:35:35 PM       1      3.25     42.12           atk0110-acpi-0
04:35:35 PM       2      5.02     51.70           atk0110-acpi-0
04:35:35 PM       3     12.20     55.44           atk0110-acpi-0

04:35:33 PM kbhugfree kbhugused  %hugused
04:35:35 PM         0         0      0.00

04:35:33 PM     CPU    wghMHz
04:35:35 PM     all   1596.00
04:35:35 PM       0   1596.00
04:35:35 PM       1   1596.00
04:35:35 PM       2   1596.00
04:35:35 PM       3   1596.00
