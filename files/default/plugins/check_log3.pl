#!/usr/bin/perl -w
# nagios: -epn
#
# Log file regular expression based parser plugin for Nagios.
#
# Written by Aaron Bostick (abostick@mydoconline.com)
# Rewritten by Peter Mc Aulay and Tom Wuyts
# The -a feature was contributed by Ian Gibbs
# Released under the terms of the GNU General Public Licence v2.0
#
# Last updated 2013-10-16 by Peter Mc Aulay <peter@zeron.be>
#
# Thanks and acknowledgements to Ethan Galstad for Nagios and the check_log
# plugin this is modeled after.
#
# Tested on Linux, Windows, AIX and Solaris.
#
# Usage: check_log3.pl --help
#
#
# *** Description ***
#
# This plugin will scan arbitrary text files looking for regular expression
# matches.  A temporary file is used to store the seek byte position of the
# last scan.  Specifying this file is optional.  To read the entire file
# each run, use /dev/null as the seek file.  If you specify a directory, the
# seek file will be written to that directory instead of in /tmp.
#
# The search pattern can be any Perl regular expression.  It will be passed
# verbatim to the m/// operator (see "man perlop").  The search patterns can
# be read from a file, one per line; the lines will be concatenated into a
# single regexp of the form 'line1|line2|line3|...'.
#
# A negation/whitelist pattern can be specified, causing the plugin to ignore
# all lines matching it.  Alternatively, the ignore patterns can be read from
# a file (one regexp per line).  This is for badly behaved applications that
# produce lots of error messages when running "normally" (certain Java apps
# come to mind).  You can use either -n or -f, but not both.  If both are
# specified, -f will take precedence.
#
# Pattern matching can be either case sensitive or case insensitive.  The -i
# option controls case sensitivity for both search and ignore patterns.
#
# To monitor files with a dynamic component in the filename, such as rotated
# or timestamped logsnames, use -l to specify the fixed part of the file's
# path and filename, and the -m option to specify the variable part, using
# a glob expression (see "man 7 glob").  If this pattern matches more than
# one file, you can use the -t option to further narrow down the selection
# to the most recently modified file, the first match (sorted alphabetically)
# or the last match (this is the default).  For timestamped files, you can
# use macro's similar to the date(1) format string syntax, and you can use
# the --timestamp option to tell the script to look for files with timestamps
# in the past.
#
# When using -m, do not specify a seek file, it will be ignored unless it is
# /dev/null or a directory.  Also note that glob patterns are not the same as
# regular expressions (please let me know if you want support for that).
#
# If the log file name provided via -l points to a directory, -m '*' (and -t)
# is assumed to be in effect.
#
# It is also possible to raise a warning of critical alert if the log file was
# not written to since the last check, using -d or -D.  This can be used as a
# kind of "heartbeat" monitor.  You can use these options either by themselves
# or in combination with pattern matching.
#
# Note that a bad regexp might case an infinite loop, so set a reasonable
# plugin time-out in Nagios.  This plugin will also set an internal time-out
# alarm based on the $TIMEOUT setting found in utils.pm.
#
# Optionally the plugin can execute a block of Perl code on each matched line,
# to further affect the output (using -e or -E).  The code should be enclosed
# in curly brackets (and probably quoted).  This allows for complex parsing
# rules of log files based on their actual content.  You can use either -e or
# -E, but not both.  If you do, -E will take precedence.
#
# The code passed to the plugin via -e be executed as a Perl 'eval' block and
# the matched line passed will be to it as $_.  Modify $parse_out to make the
# plugin save a custom string for this match (the default is the input line
# itself).  When using the context option, modify @line_buffer instead of
# $parse_out.  You can also modify $perfdata to return custom performance data
# to Nagios.  See the plugin development guidelines for the proper format of
# performance data metrics, as no validation is done by this plugin.
#
# Expected return codes:
# - If the code returns non-zero, it is counted towards the alert threshold.
# - If the code returns 0, the line is not counted against the threshold.
#   (It's still counted as a match, but for informational purposes only.)
#
# Note: -e and -E are experimental features and potentially dangerous!  The
# eval code has full access to the plugin's internal variables, so bugs in
# your code may lead to unpredictable plugin behaviour.
#
# The plugin will respect the global plugin time-out setting in utils.pm;
# use the --no-timeout option to disable this.
#
#
# *** Exit codes ***
#
# This plugin returns OK when a file is successfully scanned and no lines
# matching the search pattern(s) are found.
#
# By default, the plugin returns WARNING if one match was found.
#
# It returns WARNING or CRITICAL if any matches were found that are not also
# whitelisted; the -w and -c options determine how many lines must match before
# an alert is raised.  If an eval block is defined (via -e or -E) a line is
# only counted if it both matches the search pattern *and* the custom code
# returns a non-zero result for that line.
#
# If the thresholds are expressed as percentages, they are taken to mean the
# percentage of lines in the input that match (match / total * 100).  When
# using the -e or -E options, the percentage of matched lines that also match
# the parsing condition is taken, rather than the total number of lines in the
# input.
#
# Note that it is not possible to generate WARNING alerts for one pattern and
# CRITICAL alerts for another in the same run.  If you want that, you need to
# define two service checks (using different seek files!) or use a diffent
# plugin.
#
# The plugin returns WARNING if the -d option is used, and the log file hasn't
# grown since the last run.  Likewise, if -D is used, it will return CRITICAL
# instead.  Take care that the time between service checks is less than the
# minimum amount of time your application writes to the log file when you use
# these options.
#
# If the --ok option is used, the plugin will always return OK unless an error
# occurs and will ignore any thresholds.  This can be useful if you use this
# plugin only for its log parsing functionality, not for alerting (e.g. to
# just plot a graph of values extracted from the log file).
#
# The plugin always returns CRITICAL if an error occurs, such as if a file
# is not found (except when using --missing-ok) or in case of a permissions
# problem or I/O error.
#
#
# *** Output ***
#
# The line of the last pattern matched is returned in the output along with
# the pattern count.  If custom Perl code is run on matched lines using -e,
# it may modify the output via $parse_out (for best results, do not produce
# output directly using 'print' or related functions).
#
# Use the -a option to output all matching lines instead of just the last
# matching one.  Note that Nagios will only read the first 4 KB of data that
# a plugin returns, and that the NRPE daemon even has a 1KB output limit.
#
# Use the -C option to return some lines of context before and/or after the
# match, like "grep -C".  Prefix the number with - to return extra lines only
# before the matched line, with + to return extra lines only after the matched
# line, or with nothing to return extra lines both before and after the match.
#
# Note: lines returned as context are not parsed with -e or -E, nor is any
# context preserved if you override the output by modifying $parse_out.  If
# you want to modify the output while using -C, modify @line_buffer instead.
#
# If you use -a and -C together, the plugin will output "---" between blocks
# of matched lines and their context.
#
# Use --debug to see what the plugin is doing behind the scenes.
#
#
# *** Performance data ***
#
# The number of matching lines is returned as performance data (label "lines").
# If -e is used, the number of lines for which the eval code returned 1 is
# also returned (label "parsed").  The eval code can change the perfdata output
# by modifying the value of the $perfdata variable, e.g. for when you want to
# graph the actual figures appearing in the log file.
#
#
# Nagios service check configuration notes:
#
# 1. The maximum check attempts value for the service should always be 1, to
#    prevent Nagios from retrying the service check (the next time the check
#    is run it will not produce the same results).  Otherwise you will not
#    receive a notification for every match.
#
# 2. The notification options for the service should always be set to not
#    notify you of recoveries for the check.  Since pattern matches in log
#    file will only be reported once, "recoveries" don't really apply.
#
# 3. If you have more than one service check reading the same log file, you
#    must explicitly supply a seek file name using the -s option.  If you use
#    the -s option explicitly you must always use a different seek file for
#    each service check.  Otherwise one service check may start reading where
#    another left off, which is likely not what you want (especially since
#    the order in which they are run is unpredictable).
#
#
# *** Examples ***
#
# Return WARNING if errors occur in the system log, but ignore the ones from
# the NRPE agent itself:
#   check_log3.pl -l /var/log/messages -p '[Ee]rror' -n nrpe
#
# Return WARNING if 10 or more logon failures have been logged since the last
# check, or CRITICAL if there are 50 or more:
#   check_log3.pl -l /var/log/auth.log -p 'Invalid user' -w 10 -c 50
#
# Return WARNING if 10 or more errors were logged or return CRITICAL if the
# application stops logging altogether:
#   check_log3.pl -l /var/log/heartbeat.log -p ERROR -w 10 -D
#
# Return WARNING if there are error messages in a log which may be rotated, so
# we're actually looking for /var/log/messages* and want the most recent one:
#   check_log3.pl -l /var/log/messages -m '*' -p Error -t most_recent
#
# Return WARNING if there are error messages in a log whose name contains a
# timestamp, so we're really reading access.YYMMDD.log:
#   check_log3.pl -l /data/logs/httpd/access -m '.%Y%m%d.log' -p Error
#
# Return WARNING and print a custom message if there are 50 or more lines
# in a CSV formatted log file where column 7 contains a value over 4000:
#
# check_log3.pl -l processing.log -p ',' -w 50 -e \
# '{
#       my @fields = split(/,/);
#       if ($fields[6] > 4000) {
#	       $parse_out = "Processing time for $fields[0] exceeded: $fields[6]\n";
#	       return 1
#       }
# }'
#
# Note: in nrpe.cfg this will all have to be put on one line.  It will be more
# readable if you put the parser code in a separate file and use -E.
#
# Shameless plug: to make configuration and maintenance of this plugin easier,
# check out the plugin "check_customlog".
#
####

# Plugin version
my $plugin_revision = '3.7c';

# Load modules
require 5.004;
use strict;
use lib "/usr/lib/nagios/plugins";    # Debian
use lib "/usr/lib64/nagios/plugins";  # 64 bit
use lib "/usr/local/nagios/libexec";  # Other
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use Getopt::Long qw(:config no_ignore_case);
use File::Spec;

# Predeclare subroutines
sub print_usage ();
sub print_version ();
sub print_help ();
sub ioerror;
sub add_to_buffer;
sub read_next;

# Initialise variables and defaults
my $tmpdir = File::Spec->tmpdir();
my $devnull = File::Spec->devnull();
my $log_file = '';
my $log_pattern;
my $timestamp = time;
my $log_select = 'last_match';
my @logfiles;
my $seek_file = '';
my $warning = '1';
my $critical = '0';
my $diff_warn = '';
my $diff_crit = '';
my $re_pattern = '';
my $case_insensitive = '';
my $neg_re_pattern = '';
my $pattern_file = '';
my $negpatternfile = '';
my $pattern_count = 0;
my $pattern_line = '';
my $parse_pattern = '';
my $parse_file = '';
my $parse_line = '';
my $parse_count = 0;
my $parse_out = '';
my $output_all = 0;
my $total = 0;
my $stop_first_match;
my $always_ok;
my $missing_ok;
my $missing_msg = "No log file found";
my @line_buffer;
my $read_ahead = 0;
my $read_back = 0;
my $no_timeout;
my $output;
my $context;
my $perfdata;
my $version;
my $help;
my $debug;

# If invoked with a path, strip the path from our name
my ($prog_vol, $prog_dir, $prog_name) = File::Spec->splitpath($0);

# Grab options from command line
GetOptions (
	"l|logfile=s"		=> \$log_file,
	"m|log-pattern=s"	=> \$log_pattern,
	"t|log-select=s"	=> \$log_select,
	"s|seekfile=s"		=> \$seek_file,
	"p|pattern=s"		=> \$re_pattern,
	"P|patternfile=s"       => \$pattern_file,
	"n|negpattern=s"	=> \$neg_re_pattern,
	"f|negpatternfile=s"	=> \$negpatternfile,
	"w|warning=s"		=> \$warning,
	"c|critical=s"		=> \$critical,
	"i|case-insensitive"	=> \$case_insensitive,
	"d|nodiff-warn"		=> \$diff_warn,
	"D|nodiff-crit"		=> \$diff_crit,
	"e|parse=s"		=> \$parse_pattern,
	"E|parsefile=s"		=> \$parse_file,
	"a|output-all"		=> \$output_all,
	"C|context=s"		=> \$context,
	"1|stop-first-match"	=> \$stop_first_match,
	"ok"			=> \$always_ok,
	"missing-ok"		=> \$missing_ok,
	"missing-msg=s"		=> \$missing_msg,
	"no-timeout"		=> \$no_timeout,
	"timestamp=s"		=> \$timestamp,
	"v|version"		=> \$version,
	"h|help"		=> \$help,
	"debug"			=> \$debug,
);

#
# Parse input
#

($version) && print_version ();
($help) && print_help ();

# These options are mandatory
($log_file) || usage("Log file not specified.\n");
($re_pattern) || usage("Regular expression not specified.\n") unless ($pattern_file || $diff_warn || $diff_crit);

# Just in case of problems, let's not hang Nagios
unless ($no_timeout) {
	$SIG{'ALRM'} = sub {
		print "Plug-in error: time out after $TIMEOUT seconds\n";
		exit $ERRORS{'UNKNOWN'};
	};
	alarm($TIMEOUT);
}

# Determine line buffer characteristics
if ($context && $context =~ /\+(\d+)/) {
	$read_ahead = $1;
} elsif ($context && $context =~ /\-(\d+)/) {
	$read_back = $1 + 1;
} elsif ($context && $context =~ /(\d+)/) {
	$read_ahead = $1;
	$read_back = $1 + 1;
}

print "debug: using line buffer: $read_back back, $read_ahead ahead\n" if $debug;

# If we have a pattern file, read it and construct a pattern of the form 'line1|line2|line3|...'
my @patterns;
if ($pattern_file) {
	print "debug: using pattern file $pattern_file\n" if $debug;
	open (PATFILE, $pattern_file) || ioerror("Unable to open $pattern_file: $!");
	chomp(@patterns = <PATFILE>);
	close(PATFILE);
	$re_pattern = join('|', @patterns);
	($re_pattern) || usage("Regular expression not specified.\n")
}

# If we have an ignore pattern file, read it
my @negpatterns;
if ($negpatternfile) {
	print "debug: using negpattern file $negpatternfile\n" if $debug;
	open (PATFILE, $negpatternfile) || ioerror("Unable to open $negpatternfile: $!");
	chomp(@negpatterns = <PATFILE>);
	close(PATFILE);
} else {
	@negpatterns = ($neg_re_pattern);
}

# If we have a custom code file, read it
if ($parse_file) {
	print "debug: using parse file $parse_file\n" if $debug;
	open (EVALFILE, $parse_file) || ioerror("Unable to open $parse_file: $!");
	while (<EVALFILE>) {
		$parse_pattern .= $_;
	}
	close(EVALFILE);
}

# If -s points to a directory we take that as the new $tmpdir
if (-d $seek_file) {
	$tmpdir = $seek_file;
	print "debug: using seek dir $tmpdir\n" if $debug;
	# Will auto-generate this later
	undef $seek_file;
}
print "Warning: $tmpdir not writable, seek position will not be saved\n" if not -w $tmpdir;

# Seek files are always auto-generated for dynamic log files
if ($log_pattern) {
	print "debug: overriding seek file for dynamic filenames\n" if $debug;
	undef $seek_file unless $seek_file eq $devnull;
}

#
# Matching log filenames against glob patterns (rotated, timestamped, etc)
#

# Note that if nothing matches $log_pattern this will select just $log_file
if ($log_pattern) {
	# Timestamped filenames support
	if ($log_pattern =~ /%/) {
		print "debug: enabling timestamp substitutions\n" if $debug;

		# Timestamp can be expressed as 'X months|weeks|days|hours|minutes|seconds ... [ago]'
		# or as seconds after the epoch
		if ($timestamp =~ /\D/) {
			# Safe fall-back
			if ($timestamp !~ /(sec|min|hour|day|week|mon|now|yesterday)/i) {
				print "debug: timestamp '$timestamp' not valid, using 'now'\n" if $debug;
				$timestamp = time;
			} else {
				my $newtimestamp;
				if ($timestamp =~ /now/i) { $newtimestamp = time; }
				if ($timestamp =~ /yesterday/i) { $newtimestamp = time - 86400; }
				if (my ($t) = ($timestamp =~ /(\d+) mon/i)) { $newtimestamp = time - ($t * 2592000); }
				if (my ($t) = ($timestamp =~ /(\d+) week/i)) { $newtimestamp = time - ($t * 604800); }
				if (my ($t) = ($timestamp =~ /(\d+) day/i)) { $newtimestamp = time - ($t * 86400); }
				if (my ($t) = ($timestamp =~ /(\d+) hour/i)) { $newtimestamp = time - ($t * 3600); }
				if (my ($t) = ($timestamp =~ /(\d+) min/i)) { $newtimestamp = time - ($t * 60); }
				if (my ($t) = ($timestamp =~ /(\d+) sec/i)) { $newtimestamp = time - $t; }
				print "debug: new reference timestamp: " . localtime($newtimestamp) . "\n" if $debug;
				$timestamp = $newtimestamp;
			}
		}

		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($timestamp);
		# Adjust some values for user-friendliness
		$year += 1900;
		$mon += 1;
		my $yr = sprintf("%02d", $year % 100);
		# Add padding zeros
		$yday = sprintf("%03d", $yday);
		foreach my $t (($sec, $min, $hour, $mday, $mon)) {
			$t = sprintf("%02d", $t);
		}

		# Emulate some common date(1) format options
		$log_pattern =~ s/%Y/$year/g;
		$log_pattern =~ s/%y/$yr/g;
		$log_pattern =~ s/%m/$mon/g;
		$log_pattern =~ s/%d/$mday/g;
		$log_pattern =~ s/%H/$hour/g;
		$log_pattern =~ s/%M/$min/g;
		# Less common
		$log_pattern =~ s/%S/$sec/g;
		$log_pattern =~ s/%w/$wday/g;
		$log_pattern =~ s/%j/$yday/g;
	}

	print "debug: looking for files matching $log_file$log_pattern\n" if $debug;
	@logfiles = <$log_file$log_pattern>;
# Only if not using -m
} elsif (-d $log_file) {
	print "debug: log_file is a directory, assuming $log_file/*\n" if $debug;
	@logfiles = <$log_file/*>;
}

# If selecting multiple files
if (@logfiles) {
	# Filter out anything that is not a file
	foreach my $f (@logfiles) {
		shift @logfiles unless -f $f;
	}

	# Refine further with -t if there is more than one match
	if (scalar(@logfiles) gt 1) {
		if ($debug) {
			print "debug: found " . scalar(@logfiles) . " files matching selection:\n";
			foreach (@logfiles) {
				print "debug:     $_\n";
			}
		}

		# Trivial cases: first and last match (the default)
		my @sorted = sort(@logfiles);
		$log_select = "last_match" if not $log_select;
		if ($log_select =~ /last_match/i) {
			print "debug: picking last match\n" if $debug;
			$log_file = pop(@sorted);
		} elsif ($log_select =~ /first_match/i) {
			print "debug: picking first match\n" if $debug;
			$log_file = $sorted[0];
		# By mtime: stat each file and keep the most recent one
		} elsif ($log_select =~ /most_recent/i) {
			print "debug: picking most recent match\n" if $debug;
			my $latest_mtime = 0;
			foreach my $f (@sorted) {
				my $timestamp = (stat("$f"))[9];
				print "debug: considering $f ($timestamp)\n" if $debug;
				if ($timestamp >= $latest_mtime) {
					$latest_mtime = $timestamp;
					$log_file = $f;
				}
			}
			print "debug: $log_file is most recent\n" if $debug;
		# Safe fall-back
		} else {
			print "debug: $log_select not supported, using default\n" if $debug;
			$log_file = pop(@sorted);
		}
	} elsif (scalar(@logfiles) == 1) {
		print "debug: only one matching file\n" if $debug;
		$log_file = $logfiles[0];
	} else {
		# Set contained objects, but none of them are files
		print "debug: no matching files found, trying just $log_file\n" if $debug;
	}
} else {
	# Glob returned nothing
	print "debug: no multiple match or set is empty, trying just $log_file\n" if $debug;
}

# Open the log file - only here can errors be fatal
print "debug: using log file $log_file\n" if $debug;
if (! -f $log_file) {
	if ($missing_ok) {
		print "$missing_msg\n";
		exit $ERRORS{'OK'};
	} else {
		my $errstr = "Cannot read $log_file";
		$errstr = "Cannot read $log_file$log_pattern or $log_file" if $log_pattern;
		ioerror($errstr);
	}
}
open (LOG_FILE, $log_file) || ioerror("Unable to open $log_file: $!");

# Auto-generate seek file if necessary
if (not $seek_file) {
	my ($log_vol, $log_dir, $basename) = File::Spec->splitpath($log_file);
	$seek_file = File::Spec->catfile($tmpdir, $basename . ".seek");
}
print "debug: using seek file $seek_file\n" if $debug;

# Try to open log seek file.  If open fails, we seek from beginning of file by default.
if (open(SEEK_FILE, $seek_file)) {
	chomp(my @seek_pos = <SEEK_FILE>);
	close(SEEK_FILE);

	# If file is empty, no need to seek...
	if ($seek_pos[0] && $seek_pos[0] != 0) {

		# Compare seek position to actual file size.  If file size is smaller,
		# then we just start from beginning i.e. the log was rotated.
		my @stat = stat(LOG_FILE);
		my $size = $stat[7];
		print "debug: seek from $seek_pos[0] (eof = $size)\n" if $debug;

		# If the file hasn't grown since last time and -d or -D was specified, stop here.
		if ($seek_pos[0] == $size && $diff_crit) {
			print "CRITICAL: Log file not written to since last check\n";
			exit $ERRORS{'CRITICAL'};
		} elsif ($seek_pos[0] == $size && $diff_warn) {
			print "WARNING: Log file not written to since last check\n";
			exit $ERRORS{'WARNING'};
		}

		# Seek to where we stopped reading before
		if ($seek_pos[0] <= $size) {
			seek(LOG_FILE, $seek_pos[0], 0);
		}
	}
} else {
	print "debug: cannot open seek file, first time reading this file\n" if $debug;
}

# Loop through every line of log file and check for pattern matches.
# Count the number of pattern matches and remember the full line of
# the most recent match.
print "debug: reading file...\n" if $debug;
while (<LOG_FILE>) {
	my $line = $_;
	my $negmatch = 0;

	# Count total number of lines
	$total++;

	# Add current line to buffer, if required
	add_to_buffer($line, $read_back) if $read_back;

	# Try if the line matches the pattern
	if (/$re_pattern/i) {
		# If not case insensitive, skip if not an exact match
		unless ($case_insensitive) {
			next unless /$re_pattern/;
		}

		# And if it also matches the ignore list
		foreach (@negpatterns) {
			next if ($_ eq '');
			if ($line =~ /$_/i) {
				# As case sensitive as the first match
				unless ($case_insensitive) {
					next unless $line =~ /$_/;
				}
				$negmatch = 1;
				last;
			}
		}

		# OK, line matched!
		if ($negmatch == 0) {
			# Increment final count
			$pattern_count += 1;

			# Save the line matched and optionally some lines of context before and/or after
			if ($output_all) {
				$pattern_line .= join('', @line_buffer) if $read_back;
				$pattern_line .= "($pattern_count) $line" if not $read_back;
				$pattern_line .= read_next(*LOG_FILE, $read_ahead) if $read_ahead;
				$pattern_line .= "---\n" if $context;
			} else {
				$pattern_line = join('', @line_buffer) if $read_back;
				$pattern_line = $line if not $read_back;
				$pattern_line .= read_next(*LOG_FILE, $read_ahead) if $read_ahead;
			}

			# Optionally execute custom code
			if ($parse_pattern) {
				my $res = eval $parse_pattern;
				warn $@ if $@;
				# Save the result if non-zero
				if ($res > 0) {
					$parse_count += 1;
					# If the eval block set $parse_out, save that instead
					# Note: in this case we don't save any context
					if ($parse_out && $parse_out ne "") {
						if ($output_all) {
							$parse_line .= "($parse_count) $parse_out";
						} else {
							$parse_line = $parse_out;
						}
					# Otherwise save the current line as before
					} else {
						if ($output_all) {
							$parse_line .= join('', @line_buffer) if $read_back;
							$parse_line .= "($parse_count) $line" if not $read_back;
							$parse_line .= read_next(*LOG_FILE, $read_ahead) if $read_ahead;
							$parse_line .= "---\n" if $context;
						} else {
							$parse_line = join('', @line_buffer) if $read_back;
							$parse_line = $line if not $read_back;
							$parse_line .= read_next(*LOG_FILE, $read_ahead) if $read_ahead;
						}
					}
				}
			}
		}
		# Stop here?
		last if $stop_first_match;
	}
}

print "debug: found matches $pattern_count total $total parsed $parse_count, limits: warn $warning crit $critical\n" if $debug;

# Overwrite log seek file and print the byte position we have seeked to.
open(SEEK_FILE, "> $seek_file") || ioerror("Unable to open $seek_file for writing: $!");
print SEEK_FILE tell(LOG_FILE);

# Close files
close(SEEK_FILE);
close(LOG_FILE);

#
# Compute exit code, terminate if no thresholds were exceeded
#
my $endresult = $ERRORS{'UNKNOWN'};

# Thresholds may be expressed as percentages
my ($warnpct, $critpct);
if ($warning =~ /%/) {
	if ($parse_pattern) {
		# Ratio of parsed lines to matched lines
		$warnpct = ($parse_count / $pattern_count) * 100 if $pattern_count;
	} else {
		# Ratio of matched lines to total lines
		$warnpct = ($pattern_count / $total) * 100 if $total;
	}
	$warning =~ s/%//g;
}

if ($critical =~ /%/) {
	if ($parse_pattern) {
		# Ratio of parsed lines to matched lines
		$critpct = ($parse_count / $pattern_count) * 100 if $pattern_count;
	} else {
		# Ratio of matched lines to total lines
		$critpct = ($pattern_count / $total) * 100 if $total;
	}
	$critical =~ s/%//g;
}

print "debug: warnpct = $warnpct, critpct = $critpct\n" if ($debug && ($warnpct || $critpct));

#
# Count parse matches if applicable, or else just count the matches.
#

# Warning?
if ($warnpct) {
	if ($warnpct >= $warning) {
		$endresult = $ERRORS{'WARNING'};
		print "debug: warnpct >= warning\n" if $debug;
	}
} elsif ($parse_pattern) {
	if ($parse_count >= $warning) {
		$endresult = $ERRORS{'WARNING'};
		print "debug: parse_count >= warning\n" if $debug;
	}
} elsif ($pattern_count >= $warning) {
		$endresult = $ERRORS{'WARNING'};
		print "debug: pattern_count >= warning\n" if $debug;
} else {
	$endresult = $ERRORS{'OK'};
}

# Critical?
if ($critical > 0) {
	if ($critpct) {
		if ($critpct >= $critical) {
			$endresult = $ERRORS{'CRITICAL'};
			print "debug: critpct >= critical\n" if $debug;
		}
	} elsif ($parse_pattern) {
		if ($parse_count >= $critical) {
			print "debug: parse_count >= critical\n" if $debug;
			$endresult = $ERRORS{'CRITICAL'};
		}
	} elsif ($pattern_count >= $critical) {
		print "debug: pattern_count >= critical\n" if $debug;
		$endresult = $ERRORS{'CRITICAL'};
	}
}


# If matches were found, print the last line matched, or all lines if -a was
# specified.  Note that there is a limit to how much data can be returned to
# Nagios: 4 KB if run locally, 1 KB if run via NRPE.
# If -e was used, print the last line parsed with a non-zero result
# (possibly something else if the code modified $parse_out).
if ($parse_pattern) {
	$output = "Parsed output ($parse_count matched): $parse_line";
	$perfdata = "lines=$pattern_count parsed=$parse_count" unless $perfdata;
} else {
	$output = $pattern_line;
	$perfdata = "lines=$pattern_count";
}

# Filter any pipes from the output, as that is the Nagios output/perfdata separator
$output =~ s/\|/\!/g;

# Prepare output, or terminate if nothing to do
if ($endresult == $ERRORS{'CRITICAL'}) {
	print "CRITICAL: " unless $always_ok;
} elsif ($endresult == $ERRORS{'WARNING'}) {
	print "WARNING: " unless $always_ok;
} else {
	print "OK - No matches found.|$perfdata\n";
	exit $ERRORS{'OK'};
}

# Print output and exit
$warning .= "%" if $warnpct;
$critical .= "%" if $critpct;
chomp($output);
print "Found $pattern_count lines (limit=$warning/$critical): ";
print "\n" if $context;
print "$output|$perfdata";
exit $ERRORS{'OK'} if $always_ok;
exit $endresult;


#
# Main programme ends
#
###

#
# Subroutines
#

# Die with error message and Nagios error code, for system errors
sub ioerror() {
	print @_;
	print "\n";
	exit $ERRORS{'CRITICAL'};
}

# Die with usage info, for improper invocation
sub usage {
	my $format=shift;
	printf($format,@_);
	print "\n";
	print_usage();
	exit $ERRORS{'UNKNOWN'};
}

# Print version number
sub print_version () {
	print "$prog_name version $plugin_revision\n";
	exit $ERRORS{'OK'};
}

# Add a line to the read-back buffer, a FIFO queue with max length $c
sub add_to_buffer {
	my ($l, $c) = @_;
	push(@line_buffer, $l);
	shift(@line_buffer) if @line_buffer > $c;
}

# Get next $n lines from current file position of file $fh
# The current seek position is preserved
sub read_next {
	my ($fh, $n) = @_;
	my $lines;
	my $i = 1;

	# Save current position
	my $oldpos = tell($fh);

	# Read next $i lines (if possible)
	while (<$fh>) {
		last if not $_;
		last if $i > $n;
		$lines .= $_;
		$i++;
	}

	# Restore seek position and return
	seek ($fh, $oldpos, 0);
	return $lines;
}

# Short usage info
sub print_usage () {
	print "This is $prog_name version $plugin_revision\n\n";
	print "Usage: $prog_name [ -h | --help ]\n";
	print "Usage: $prog_name [ -v | --version ]\n";
	print "Usage: $prog_name -p pattern | -P patternfile -l log_file|dir [ -s seek_file|base_dir ]
	( [ -m glob-pattern ] [ -t most_recent|first_match|last_match ] [--timestamp=time-spec ] )
	[ -n negpattern | -f negpatternfile ]
	[ --missing-ok [ --missing-msg=message ] ]
	[ -e '{ eval block }' | -E script_file ]
	[ --ok ] | ( [ -w warn_count ] [ -c crit_count ] )
	[ -i ]  [-d | -D ] [ -1 ] [ -a ] [ -C [-|+]n ]
\n";
}

# Long usage info
sub print_help () {
################################################################################
	print_usage();
	print "
This plugin scans arbitrary log files for regular expression matches.

Log file control:

-l, --logfile=<logfile|dir>
    The log file to be scanned, or the fixed path component if -m is in use.
    If this is a directory, -t and -m '*' is assumed.
-s, --seekfile=<seekfile|base_dir>
    The temporary file to store the seek position of the last scan.  If not
    specified, it will be automatically generated in $tmpdir, based on the
    log file's base name.  If this is a directory, the seek file will be auto-
    generated there instead of in $tmpdir.
-m, --logfile-pattern=<expression>
    A glob(7) expression, used together with the -l option for selecting log
    files whose name is variable, such as timestamped or rotated logs.
    If you use this option, the -s option will be ignored unless it points to
    either a directory or to the null device ($devnull).
    For selecting timestamped logs, you can use the following date(1)-like
    expressions, which by default refer to the current date and time:
	\%Y = year
	\%y = last 2 digits of year
	\%m = month (01-12)
	\%d = day of month (01-31)
    	\%H = hour (00-23)
	\%M = minute (00-59)
	\%S = second (00-60)
	\%w = week day (0-6), 0 is Sunday
	\%j = day of year (000-365)
    Use the --timestamp option to refer to timestamps in the past.
-t, --logfile-select=most_recent|first_match|last_match
    How to further select amongst multiple files when using -m:
     - most_recent: select the most recently modified file
     - first_match: select the first match (sorting alphabetically)
     - last_match: select the last match (this is the default)
--timestamp='(X months|weeks|days|hours|minutes|seconds)... [ago]'
    Use this option to make the timestamp macro's in the -m expression refer
    to a time in the past, e.g. '1 day, 6 hours ago'.  The shortcuts 'now' and
    'yesterday' are also recognised.  The default is 'now'.
    If this expression is purely numerical it will be interpreted as seconds
    since 1970-01-01 00:00:00 UTC.

Search pattern control:

-p, --pattern=<pattern>
    The regular expression to scan for in the log file.
-P, --patternfile=<filename>
    File containing regular expressions, one per line, which will be combined
    into an expression of the form 'line1|line2|line3|...'.
-n, --negpattern=<negpattern>
    The regular expression to skip in the log file.
-f, --negpatternfile=<negpatternfile>
    Specifies a file with regular expressions which all will be skipped.
-i, --case-insensitive
    Do a case insensitive scan.

Alerting control:

-w, --warning=<number>
    Return WARNING if at least this many matches found.  The default is 1.
-c, --critical=<number>
    Return CRITICAL if at least this many matches found.  The default is 0,
    i.e. don't return critical alerts unless specified explicitly.
-d, --nodiff-warn
    Return WARNING if the log file was not written to since the last scan.
-D, --nodiff-crit
    Return CRITICAL if the log was not written to since the last scan.
--missing-ok [ --missing-msg=\"message\" ]
    Return OK instead of CRITICAL if the log file does not exist, with an
    optional custom message (by default \"No log file found\").
--ok
    Always return an OK status to Nagios.

Output control:

-1, --stop-first-match
    Stop at the first line matched, instead of the last one (implies an
    alerting threshold of 1).
-a, --output-all
    Output all matching lines instead of just the last one.  Note that the
    plugin output may be truncated if it exceeds 4KB (1KB when using NRPE).
-C, --context=[-|+]<number>
    Output <number> lines of context before or after matched line; use -N for
    N lines before the match, +N for N lines after the match (if possible) or
    an unqualified number to get N lines before and after the match.
-e, --parse=<code>
-E, --parse-file=<filename>
    Perl 'eval' block to parse each matched line with (EXPERIMENTAL).  The code
    should be in curly brackets and quoted.  If the return code of the block is
    non-zero, the line is counted against the threshold; otherwise it isn't.
--no-timeout
    Disable the plugin time-out timer (set to $TIMEOUT seconds in utils.pm).

Support information:

Send email to pmcaulay\@evilgeek.net if you have questions regarding use of this
software, or to submit patches or suggest improvements.  Please include version
information with all correspondence (the output of the --version option).

This Nagios plugin comes with ABSOLUTELY NO WARRANTY. You may redistribute
copies of the plugins under the terms of the GNU General Public License.
For more information about these matters, see the file named COPYING.

";
	exit $ERRORS{'OK'};
}

