### FLDigi_Log

A simple script to keep Cloudlog in synch with FLDigi's logbook. The last log-entries will be transferred to Cloudlog.
The script should becalled by crontab every 5 minutes. First it is checked, if FLDigi is runnng, then if last modification of the logbook is younger than 5 minutes.
After that, all entries of the last 5 minutes are sent to Cloudlog. 

Installation:
 copy the script and this config file in a directory
 add the script in your crontab, so it is called every 5 minutes
 */5 * * * * -c/home/pi/Cloudlog/RigControl/get_fldigi_log.pl &
 a log file is created, if necessary on the first call
 if you use root's crontab, make sure, that the script runs under your current user, otherwise the accressrights for the log file will be wrong 
 */5 * * * * su pi -c/home/pi/Cloudlog/RigControl/get_fldigi_log.pl &
 add the logfile to /etc/logrotate.d/rsyslog

