#!/usr/bin/perl
use warnings;
use strict;

use Time::localtime;
use Time::gmtime;
use Time::HiRes qw(gettimeofday);
use Time::Piece;
use Date::Parse;
use File::stat;

my $parsestop = 0;
my $verbose = 0;
my $logging_ok = 1;
my $checkfile_ok = 1;
my $data = "";
my $nn = 0;
my $ii = 0;
my $entry;
my $item;
my $tag;
my $tags;
my $content;
my @array;
my @qso_array;
my %QSOtab;
my $adif_header;
my $total_rqsos = 0;
my $total_wqsos = 0;
my $band = "";
my $mode = "";
my $call = "";
my $date = "";
my $time = "";
my $timel = "";
my $datelong = "";
my $timelong = "";
my $notes = "";
my $datenow = "";
my $timenow = "";
my $timenow_epoc = 0;
my $timestart = "";
my $timestart_epoc = 0;
my $timestart_epoc_save = 0;
my $timeqso = "";
my $timeqso_epoc = 0;
my $cloudlogApiKey = "";
my $station_profile_id = "5";
my $cloudlogApiUrl = "";
my $fldigi_logbook = "";
my $par;
my $check_minutes = 6;
my $check_minutes_par = 0;
my $logfile = "";
my $checkdatei = "";
my $debug = 0;
my $fldigi_check ="";

# get total arg passed to this script

	# get script name
	my $scriptname = $0;
	my $path = ($scriptname =~ /(.*)fldigi_log.pl/s)? $1 : "undef";
	$logfile = $path . "fldigi_log.log";
	$checkdatei = $path ."log_detail.txt";
	my $tm = localtime(time);
	
	# Use loop to print all args stored in an array called @ARGV
	my $total = $#ARGV + 1;
	my $counter = 1;
	print "Total args passed to $scriptname : $total \n" if $verbose;
	foreach my $a(@ARGV) {
		print "Arg # $counter : $a\n" if ($verbose == 7);
		$counter++;
		if (substr($a,0,2) eq "v=") {
			$verbose = substr($a,2,1);
			print "Debug On, Level: $verbose\n" if $verbose;
		}
		if (substr($a,0,14) eq "check_minutes=") {
			$check_minutes_par = substr($a,14,length($a)-1);
			print "Checkminutes: $check_minutes_par\n" if $verbose;
		}
	}

## Bei Änderungen des Pfades bitte auch /etc/logrotate.d/rsyslog anpassen
	my $confdatei = $path . "fldigi_log.conf";
	open(INPUT, $confdatei) or die "Fehler bei Eingabedatei: $confdatei\n";
		undef $/;#	
		$data = <INPUT>;
	close INPUT;
	print "Datei $confdatei erfolgreich geöffnet\n" if $verbose;
	@array = split (/\n/, $data);
	$nn=0;
	foreach $entry (@array) {
		if ((substr($entry,0,1) ne "#") && (substr($entry,0,1) ne "")) {
			printf "%d [%s]\n",$nn,$entry if $verbose;
			$par = ($entry =~ /([\w]+).*\=.*\"(.*)\"/s)? $2 : "undef";
			$station_profile_id = $par if ($1 eq "station_profile_id");
			$cloudlogApiKey = $par if ($1 eq "cloudlogApiKey");
			$cloudlogApiUrl = $par if ($1 eq "cloudlogApiUrl");
			$fldigi_logbook = $par if ($1 eq "fldigi_logbook");
			$fldigi_check = $par if ($1 eq "fldigi_check");
			$check_minutes = $par if ($1 eq "check_minutes");
			$debug = $par if ($1 eq "debug");
		}
		++$nn;
	}
	$check_minutes = $check_minutes_par if ($check_minutes_par);
	$verbose = $debug if (!$verbose);
	printf "Parameter: Key: %s ID: %s URL: %s LB: %s CheckM: %s Debug: %s\n",$cloudlogApiKey,$station_profile_id,$cloudlogApiUrl,$fldigi_logbook,$check_minutes,$verbose if $verbose;	
	write_log(sprintf("Main Start: %02d:%02d:%02d am %02d.%02d.%04d\n",$tm->hour, $tm->min, $tm->sec, $tm->mday, $tm->mon,$tm->year)) if $verbose;
	write_log(sprintf("CLI Parameter: Verbose=%s check_Minutes=%s\n",$verbose, $check_minutes_par)) if $verbose;
	write_log(sprintf("Run-Parameter: Key: %s ID: %s URL: %s LB: %s CheckM: %s FLR_Check %s Debug: %s\n",$cloudlogApiKey,$station_profile_id,$cloudlogApiUrl,$fldigi_logbook,$check_minutes,$fldigi_check,$verbose)) if $verbose;

	if ($fldigi_check ne "") {
		if (!check_fldigi()) {
			print "Exit, keine Änderungen, FLDigi läuft nicht\n" if $verbose;
			write_log(sprintf("Exit, keine Änderungen, , FLDigi läuft nicht\n\n")) if $verbose;;
			exit(0);
		} 
		else {
			print "FLDigi running, ok to proceed\n" if $verbose;
		}
	}	

#http://dadanini.at/books/Perl_in_21Tagen/Kap05.html
#https://perldoc.perl.org/perlreftut
#	one_call("DL3EL","-20221126-Log.adi");

	my $epoc = time();
	$epoc = $epoc - $check_minutes * 60;    # 5Min before of current date.
	printf "Uhrzeit LogDatei: %s Prüf-Zeit: %s, Delta: %s\n",stat($fldigi_logbook)->mtime,$epoc,stat($fldigi_logbook)->mtime-$epoc if $verbose;

	if (stat($fldigi_logbook)->mtime-$epoc < 0) {
		print "Exit, keine Änderungen, Logdatei ($fldigi_logbook) älter als $check_minutes Minuten\n" if $verbose;
		write_log(sprintf("Exit, keine Änderungen, Logdatei älter als $check_minutes Minuten\n\n")) if $verbose;
		exit(0);
	}
	$datenow = sprintf("%02d%02d%02d",gmtime->year(),gmtime->mon(),gmtime->mday());
	$timenow = gmtime();
	$timestart= $timenow - ($check_minutes * 60);
	$timestart_epoc = str2time($timestart);

	print "Start Uhrzeit: $timenow, checkwindow starts at: $timestart $timestart_epoc für Datum $datenow\n" if $verbose;
	write_log(sprintf("Start Uhrzeit: $timenow, checkwindow starts at: $timestart für Datum $datenow\n"));

	open(INPUT, $fldigi_logbook) or die "Fehler bei Logdatei: $fldigi_logbook\n";
	undef $/;#	
	$data = <INPUT>;
	close INPUT;
	print "Datei $fldigi_logbook erfolgreich geöffnet\n" if $verbose;
	write_log(sprintf("Datei $fldigi_logbook erfolgreich geöffnet\n"));

	if ($verbose) {
		if (! open(CHECK, ">$checkdatei"))  {
			print "Fehler bei Protokolldatei: $checkdatei\n";
			$checkfile_ok = 0;
		}
		else {
			print "Datei $checkdatei erfolgreich geöffnet\n" if $verbose;
			write_log(sprintf("Datei $checkdatei erfolgreich geöffnet\n"));
		}
	}		
	
	@array = split (/<EOH>|<EOR|<eor>/, $data);
	foreach $entry (@array) {
		if ((substr($entry,0,5) eq "Cloud") || (substr($entry,0,5) eq "File:")) {
			$adif_header = $entry . "<eoh>\r\n";
		}	
		else {
#Schlüssel: Call Date Time Mode
			print CHECK "$entry\n" if ($verbose && $checkfile_ok);
			@qso_array = split (/\</, $entry);
			$ii = 0;
			%QSOtab = ();
			foreach $item (@qso_array) {
				$tag = ($item =~ /([\w]+):(\d+)>(.*)/s)? $1 : "undef";
				if (($tag ne "undef") && ($tag ne "")) {
					if ((substr($tag,0,3) eq "MY_")) {
						$tag = "z" . $tag;
					}	
					push @{$QSOtab{$tag}}, length($3);
					push @{$QSOtab{$tag}}, $3;
					push @{$QSOtab{$tag}}, 1;
					printf CHECK "Nr: %s, Tag: %s, Länge: %s, Inhalt: %s\n",$ii,$tag,length($3),$3 if ($verbose && $checkfile_ok);
					++$ii;
					if ($tag eq "QSO_DATE") {
# qso must be since the last run time (see $check_minutes) so at least today
# skip parsing, if older
						if ($QSOtab{'QSO_DATE'}[1] < $datenow) {
							printf CHECK "Nr: %s, Tag: %s, hier abgebrochen, zu alt\n",$ii,$tag if ($verbose && $checkfile_ok);
							$parsestop = 1;
							last;
						}	
					}
				}
			}	
			last if (!$ii);

			if (!$parsestop) {
				++$total_rqsos;
				$band = $QSOtab{'BAND'}[1];
				$mode = $QSOtab{'MODE'}[1];
				$call = $QSOtab{'CALL'}[1];
				$date = $QSOtab{'QSO_DATE'}[1];
				$time = substr($QSOtab{'TIME_ON'}[1],0,4);

				$datelong = $date;
				$datelong =~ s/(\d\d\d\d)(\d\d)(\d\d)/$1-$2-$3/;
				$timelong = $QSOtab{'TIME_ON'}[1];
				$timelong =~ s/(\d\d)(\d\d)(\d\d)/$1:$2:$3/;
				$timel = $datelong . "T" . $timelong;
				$timeqso_epoc = str2time($timel);
			}
			else {
				$parsestop = 0;
				$timeqso_epoc = 0;
			}		
			
			if ($timeqso_epoc >= $timestart_epoc) {
# qso must be since the last run time (see $check_minutes) so at least today
# skip processing, if older
# print "$timel $timeqso_epoc $timeqso Vergleich $timestart $timestart_epoc)\n";

				if (exists($QSOtab{'NOTES'})) {
					if (($QSOtab{'NOTES'}[0] == 39) && substr($QSOtab{'NOTES'}[1],0,10) eq "QRZ error:") {
						printf("%s-%s-%s-%s-%s, Notes: %s [%d] gelöscht\n",$call,$date,$time,$mode,$band,$QSOtab{'NOTES'}[1],length($QSOtab{'NOTES'}[1])) if $verbose;
						$QSOtab{'NOTES'}[0] = 0;
						$QSOtab{'NOTES'}[1] = "";
						$QSOtab{'NOTES'}[2] = 0;
						--$ii;
					}	
					else {
						printf("%s-%s-%s-%s-%s, Notes: %s [%d]\n",$call,$date,$time,$mode,$band,$QSOtab{'NOTES'}[1],length($QSOtab{'NOTES'}[1])) if $verbose;
						$notes = $QSOtab{'NOTES'}[1];
						$notes =~ tr/\r/ /s;
						$notes =~ tr/\n/ /s;
						$notes =~ tr/[ ]./ /s;
						if ($QSOtab{'NOTES'}[0] > length($notes)+1) {
							printf("%s-%s-%s-%s-%s, Notes: %s [%d, was %d]\n",$call,$date,$time,$mode,$band,$notes,length($notes),$QSOtab{'NOTES'}[0]) if $verbose;
							write_log(sprintf("%s-%s-%s-%s-%s, Notes: %s [%d, was %d]\n",$call,$date,$time,$mode,$band,$notes,length($notes),$QSOtab{'NOTES'}[0])) if $verbose;
							$QSOtab{'NOTES'}[1] = $notes;
							$QSOtab{'NOTES'}[0] = length($notes);
						}	
					}
				}

# clear contest counter if not in contest, not used in Cloudlog
				if ((not exists($QSOtab{'SRX'})) && (not exists($QSOtab{'SRX_STRING'}))) {
					if (exists($QSOtab{'STX'})) {
						$QSOtab{'STX'}[0] = 0;
						$QSOtab{'STX'}[1] = "";
						$QSOtab{'STX'}[2] = 0;
						--$ii;
					}
				}
			
### API/QSO
#API/QSO/
#{
#    "key":"YOUR_API_KEY",
#    "station_profile_id":"Station Profile ID Number",
#    "type":"adif",
#    "string":"<call:5>N9EAT<band:4>70cm<mode:3>SSB<freq:10>432.166976<qso_date:8>20190616<time_on:6>170600<time_off:6>170600<rst_rcvd:2>59<rst_sent:2>55<qsl_rcvd:1>N<qsl_sent:1>N<country:24>United States Of America<gridsquare:4>EN42<sat_mode:3>U/V<sat_name:4>AO-7<prop_mode:3>SAT<name:5>Marty<eor>"
#}
#

#    curl --silent --insecure \
#        --header "Content-Type: application/json" \
#         --request POST \
#         --data "{ 
#           \"key\":\"$cloudlogApiKey\",
#           \"radio\":\"$cloudlogRadioId\",
#           \"frequency\":\"$rigFreq\",
#           \"mode\":\"$rigMode\",
#           \"timestamp\":\"$(date +"%Y/%m/%d %H:%M")\"
#         }" $cloudlogApiUrl >/dev/null 2>&1
#	$apicall = `curl -s https://pskreporter.info/cgi-bin/psk-freq.pl?grid=JO&mode=FT8`; 
# curl --silent --insecure --header "Content-Type: application/json" --request POST --data

my $apistring_fix = sprintf("{\\\"key\\\":\\\"%s\\\",\\\"station_profile_id\\\":\\\"%s\\\",\\\"type\\\":\\\"adif\\\",\\\"string\\\":\\\"",$cloudlogApiKey,$station_profile_id);
my $apistring_var = "";
my $apicall = "";

				$nn=0;
				for my $tag (sort keys %QSOtab) {
					if ($QSOtab{$tag}[2]) {
						if ((substr($tag,0,4) eq "zMY_")) {
							$tags = substr($tag,1,length($tag)-1);
						}
						else {
							$tags = $tag;
						}		
						++$nn;
						$apistring_var = $apistring_var . sprintf("<$tags:$QSOtab{$tag}[0]>$QSOtab{$tag}[1]");
					}	
				}
				if ($ii != $nn) {
					print "$QSOtab{'CALL'}[1] CHECK ITEMS! ($ii/$nn) \n" if $verbose;
				}	

				$apistring_fix = $apistring_fix . $apistring_var . "<EOR>\\\"}";
				$apicall = sprintf("curl --silent --insecure --header \"Content-Type: application/json\" --request POST --data \"%s\" %s >/dev/null 2>&1\n",$apistring_fix,$cloudlogApiUrl);
				write_log($apicall);
				if ($verbose == 2) {
					printf CHECK "[%s]",$apicall if ($verbose && $checkfile_ok);
				}
				else {	
					print CHECK $apicall if ($verbose && $checkfile_ok);
					`$apicall`;
					if (!$verbose) {
						++$verbose;
						write_log(sprintf("QSO sent to Cloudlog: %02d:%02d:%02d am %02d.%02d.%04d\n",$tm->hour, $tm->min, $tm->sec, $tm->mday, $tm->mon,$tm->year)) if $verbose;
						write_log($apicall);
						--$verbose;
					}	
#					$apicall = `$apicall`;
					print "Sleep 5s to give upload of $QSOtab{'CALL'}[1] some time\n" if $verbose;
					sleep(5);
				}	

				$apistring_var = "";
				++$total_wqsos;
			}
		}	
	}		
	close CHECK if ($verbose && $checkfile_ok);
	if ($verbose == 2) {
		print "$total_rqsos relevante QSOs gelesen, $total_wqsos davon identifiziert\n";
		write_log(sprintf("$total_rqsos relevante QSOs gelesen, $total_wqsos davon identifiziert\n"));
	}
	else {	
		print "$total_rqsos relevante QSOs gelesen, $total_wqsos davon gesendet\n" if $verbose == 1;
		write_log(sprintf("$total_rqsos relevante QSOs gelesen, $total_wqsos davon gesendet\n"));
	}	

	$tm = localtime(time);
	write_log(sprintf("Main End: %02d:%02d:%02d am %02d.%02d.%04d\n\n",$tm->hour, $tm->min, $tm->sec, $tm->mday, $tm->mon,$tm->year));


sub write_log {
my $record = $_[0]; 
	
	if ($verbose && $logging_ok) {
		if (! open(LOG, ">>$logfile"))  {
			print "Fehler bei Logdatei: >>$logfile ($logging_ok)\n";
			$logging_ok = 0;
		}
		else {	
			printf LOG "%s",$record;
			close LOG;
		}	
	}	
}
sub check_fldigi {
# curl -m 5 -d "<?xml version='1.0'?><methodCall><methodName>main.get_frequency</methodName></methodCall>" http://192.168.241.54:7362 
# alter flrig call: # fldigi_check="rigctl -r 192.168.241.54:12345 -m4 f"

my $fldigi_xmlrpc = "";
my $status = "";

	$fldigi_xmlrpc = sprintf("curl -m 5 --silent -d \"<?xml version=\'1.0\'?><methodCall><methodName>main.get_frequency</methodName></methodCall>\" %s 2>&1",$fldigi_check);
	printf "[%s]\n",$fldigi_xmlrpc if $verbose;
	$fldigi_xmlrpc = `$fldigi_xmlrpc`;
	$status = $fldigi_xmlrpc;
	if ($status eq "") {
		print "[fldigi not running, exiting]\n"if $verbose;
		return (0);
	}
	else {
		printf "[%s]\n",$status if $verbose;
		return (1);
	}	
}
