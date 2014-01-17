This repo consists of the tools for collecting the Green Dataset: 
A Dataset for Mining the Impact of Software Change on Energy Consumption

greenlogger
===========
GreenLogger is able to collect power consumption readings from power 
meter WattsUp? Pro and also system utilizations from SAR utinity.
It has been developed by Abram Hindle. If you want to utilize this tool in
your papers, please cite this work:
@inproceedings{green-msr,
  author    = {Abram Hindle},
  title     = {{Green Mining: A Methodology of Relating Software Change
  to Power Consumption}},
  booktitle = {MSR},
  year      = {2012},
  pages     = {78-87},
  ee        = {http://dx.doi.org/10.1109/MSR.2012.6224303},
}

How to collect data:
perl green-logger.pl -o output-file-name

What is in folder wattsup:
The source code has been modified per this post ie. baud rate
changed from 9600 to 115200

    https://www.wattsupmeters.com/forum/index.php?topic=8.0

To compile the binary type

gcc -o wattsup wattsup.c

Sample usage is as follows

    ./wattsup -c 1 ttyUSB0 watts

This will connect to WattsUp once and output the watt usage

Binary has been provided. It was compiled under Centos 5 however it should
be usable under most modern Linux 2.6+ systems. I tested it under Ubuntu 
8.04 and works just fine. Use at your own risk otherwise compile from 
source.

How to parse data:
In the folder parse-data, demo-usage-shell.sh is for parsing data.
