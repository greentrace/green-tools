#!/usr/bin/perl
use GreenLogger;
use strict;
# we expect to get file names from stdin
# and we expect to get columns from argv
my @filenames = <STDIN>;
chomp(@filenames);
my @columns = @ARGV;
@columns = map { normalizeName( $_ ) } @columns;
die "No Columns" unless @columns;
my %columns = map { $_ => 1 } @columns;

if ($columns[0] eq "-ls") {
    lsHeaders( @filenames );
} else {
    processFiles( \@filenames, \@columns );
}

sub getHeaders {
    my ($OUT) = @_;
    my %h = ();    
    foreach my $elm (@$OUT) {
        my @headers = addHeaders([],undef,$elm);
        foreach my $header (@headers) {
            unless (exists $h{$header->[0]}) {
                $h{$header->[0]} = $header->[1];
            }
        }
    }
    return \%h;
}

sub lsHeaders {
    my @filenames = @_;
    foreach my $filename (@filenames) {
        warn $filename;
        my $OUT = GreenLogger::interpretFile( $filename );
        my $h = getHeaders($OUT);
        print join("$/", keys %$h),$/;
        #die "Done";
    }
}

sub processFiles {
    my ($filenames,$columns) = @_;
    my @filenames =@$filenames;
    my @columns = @$columns;
    my $h = undef;
    my $first = 1;
    foreach my $filename (@filenames) {
        warn $filename;
        my $parse = GreenLogger::parseFileName($filename);
        my $OUT = GreenLogger::interpretFile( $filename );
        $h = getHeaders($OUT) unless defined $h;
        if ($first) {
            foreach my $column (@columns) {
                die "$column not found! ".join($/,keys %$h) if (!($column =~ /^FILE\./) && !exists $h->{$column});
            }
            print join(",",@columns),$/;
            $first = 0;
        }
        my @keys = @columns;
        my $n = 1;
        foreach my $elm (@$OUT) {
            $parse->{n} = $n++;
            print join(",", map { 
                access($elm, $h->{$_}, $parse, $_) 
            } @keys),$/;
        }
    }
}

sub access {
    my ($elm, $arr, $fileparse, $name) = @_;
    if ($name =~ /^FILE\.(.*)$/) {
        my $n = $1;
        return $fileparse->{$n};
    }
    my $e = $elm;
    eval {
    foreach my $key (@$arr) {  
        $e = $e->{$key};
    }
    };
    return undef if $@;
    return $e;
}

sub addHeaders{
    my ($prefix,$key,$val) = @_;
    my @karr = @$prefix;
    push @karr, $key if defined($key);
    if (ref($val)) {
        return map { 
            my $key2 = $_; 
            my $val2 = $val->{$key2};
            addHeaders([@karr],$key2,$val2);
        } keys %$val;
    } else {
        my $name = join(".",@karr);
        $name = normalizeName($name);
        return [$name, [@karr]];
    }
}
sub normalizeName {
    my ($name) = @_;
    if ($name =~ /[\s\/%]/) {
        $name = "\"$name\"";
    }
    return $name;
}
