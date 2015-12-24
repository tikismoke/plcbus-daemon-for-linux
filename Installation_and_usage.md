# Requirements #
  1. Installed Linux distribution (other platforms may also be supported, or not, your mileage may vary).
  1. The plcbus deamon server.
  1. IOSelectBuffered.pm - Perl Module originally written by Ron Frazer.
  1. Device::SerialPort - emulation of Win32::SerialPort for Linux/POSIX (libdevice-serialport-perl package with Debian/**buntu distros).
  1. PLCBUS-1141 or PLCBUS-1141+ PLCBUS Computer Interface (USB or RS-232).**

# Installation #
  1. Download the latest tarball from [here](http://plcbus-daemon-for-linux.googlecode.com/files/plcbus-1.01.tar.bz2) and extract the files.
  1. Save plcbus.pl into an executable directory (I use /usr/local/bin) and make it executable.
  1. Save IOSelectBurrered.pm into a directory called SerialLibs (note the use of uppercase letters) in one of the standard perl module locations (I use /usr/lib/perl5/site\_perl/5.12.3/SerialLibs).
  1. Run the server help page to see the default settings and available options:
> `plcbus.pl --help`
  1. Run the server in the background with the appropriate settings if required:
> `plcbus.pl --device=/dev/ttyUSB0 &`

# Usage #
  * Interact with the controller from any network connect pc using netcat in the following manner:

> `nc localhost 5151`

> Change localhost and 5151 to the appropriate hostname (or IP address) and port accordingly.
> Note that for some Linux installation, 'nc' has to replaced with 'netcat'.  To exit the session, simply type

> `exit`

> Commands can be issued to the 1141 in the following format:

> `a1,preset_dim,64,5`

> where:
  * _a1_ can be replaced with the appropriate plcbus device
  * preset\_dim can be replaced with the appropriate command or query (see the output of `plcbus.pl --info` for a complete list)
  * _64_ can be replaced with a decimal value from 0 to 100 for the command (ignored if not relevant)
  * _5_ can be replaced with a decimal value from 0 to 100 for the command (ignored if not relevant)

> The example code above turns device a1 (a dimmable light module) on to 64% brightness over a period of 5 seconds. The response given is:

> `A1,PRESET_DIM,64,5`

> ...which tells you that the dim level is 64% and the fade time was 5 seconds.

> Commands can be sent from scripts easily by piping the output of echo to netcat.  For the above example:

> `echo -e 'a1,preset_dim,64,5\nEXIT\n' | nc localhost 5151`

> ...would achieve the same result.  If you are using a slow remote connection use netcats -i  option to increase the interval:

> `echo -e 'a1,preset_dim,64,5\nEXIT\n' | nc -i 1 othernetworkhost 5151`

> plcbus.pl is also aware of commands sent by other transmitters (i.e. PLCBUS-2269 Scene Controller) and will display any and all messages
> that are not a result of activity from the local 1141.  Any messgages will be stored and displayed the next time a command is sent.  You
> can also check for any stored messages by sending a blank command (i.e. a newline).

## Examples ##

To turn all lights off:

