#!/usr/bin/perl -w

###############################################################################
#
# Created by Wayne Thomas, contributions by Maurice de Bijl
#
# Listens on the designated TCP port for correctly formatted commands and passes them to the 
# PLCBUS adaptor then returns the response.
#
#	 Initial version by Wayne Thomas, based upon hub_plcbus.pl (written
#	 by Jfn of  domoticaforum) with some code borrowed from Ron Frazier
# 	(http://www.ronfrazier.net).
#
# Latest version and discussion, see http://code.google.com/p/plcbus-daemon-for-linux/
# History, see http://code.google.com/p/plcbus-daemon-for-linux/source/list
#
# Feel free to do anything you want with this, as long as you
# include the above attribution.
#
#
# For more information, execute 'plcbus.pl --info'
#
###############################################################################

use Device::SerialPort;
use IO::Socket;
use Time::HiRes qw(sleep);
use IO::Socket::INET;
use SerialLibs::IOSelectBuffered;
use List::Util qw(sum);
use Getopt::Long;

my $verbose = '';		# verbose flag, default is false
my $serdev = '/dev/ttyS0';	# default serial device, typically COM1
my $listenport = 5151;		# default tcp port
my $plcbus_usercode = '0xFF';	# default usercode, value can be (00-FF) 
my $phase = 1;			# number of phases, valid values are 1 or 3
my $serport;                    # handle for the serial port

# Hash containing relation between ASCII command and PLCBUS command hex code
#
my %plcbus_command_to_hex = (
	'ALL_UNITS_OFF'		=> 0x00,
	'ALL_LIGHTS_ON'		=> 0x01,
	'ON'			=> 0x02,
	'OFF'			=> 0x03,
	'DIM'			=> 0x04,
	'BRIGHT'		=> 0x05,
	'ALL_LIGHTS_OFF'	=> 0x06,
	'ALL_USER_LIGHTS_ON'	=> 0x07,
	'ALL_USER_UNITS_OFF'	=> 0x08,
	'ALL_USER_LIGHTS_OFF'	=> 0x09,
	'BLINK'			=> 0x0a,
	'FADE_STOP'		=> 0x0b,
	'PRESET_DIM'		=> 0x0c,
#	'STATUS_ON'		=> 0x0d,
#	'STATUS_OFF'		=> 0x0e,
	'STATUS_REQUEST'	=> 0x0f,
	'RX_MASTER_ADDR_SETUP'	=> 0x10,
	'TX_MASTER_ADDR_SETUP'	=> 0x11,
	'SCENE_ADDR_SETUP'	=> 0x12,
	'SCENE_ADDR_ERASE'	=> 0x13,
	'ALL_SCENES_ADDR_ERASE'	=> 0x14,
	'GET_SIGNAL_STRENGTH'	=> 0x18,
	'GET_NOISE_STRENGTH'	=> 0x19,
#	'REPORT_SIGNAL_STRENGTH'=> 0x1a,
#	'REPORT_NOISE_STRENGTH' => 0x1b,
	'GET_ALL_ID_PULSE'	=> 0x1c,
	'GET_ON_ID_PULSE'	=> 0x1d,
#	'REPORT_ALL_ID_PULSE'	=> 0x1e,
#	'REPORT_ON_ID_PULSE'	=> 0x1f, 
);



# Convert hex code to status messages 
#
my %plcbus_hex_to_status = (
	0x00    => "ALL_UNITS_OFF",
	0x01	=> "ALL_LIGHTS_ON",
	0x02	=> "ON",
	0x03	=> "OFF",
	0x04	=> "DIM",
	0x05	=> "BRIGHT",
        0x06    => "ALL_LIGHTS_OFF",
	0x07    => "ALL_USER_LIGHTS_ON",
	0x08    => "ALL_USER_UNITS_OFF",
	0x09    => "ALL_USER_LIGHTS_OFF",
        0x0a    => "BLINK",
	0x0b    => "FADE_STOP",
        0x0c    => "PRESET_DIM",
	0x0d	=> "STATUS_ON",
	0x0e	=> "STATUS_OFF",
	0x0f    => "STATUS_REQUEST",
	0x10    => "RX_MASTER_ADDR_SETUP",
	0x11    => "TX_MASTER_ADDR_SETUP",
	0x12    => "SCENE_ADDR_SETUP",
	0x13    => "SCENE_ADDR_ERASE",
	0x14    => "ALL_SCENES_ADDR_ERASE",
	0x18    => "GET_SIGNAL_STRENGTH",
	0x19    => "GET_NOISE_STRENGTH",
	0x1a    => "REPORT_SIGNAL_STRENGTH",
	0x1b    => "REPORT_NOISE_STRENGTH",
	0x1c    => "GET_ALL_ID_PULSE",
	0x1d    => "GET_ON_ID_PULSE",
	0x1e	=> "REPORT_ALL_ID_PULSE",
	0x1f    => "REPORT_ON_ID_PULSE",
);

# Display help page
sub help
{
	print	"\n	==================================================\n";
	print	"	plcbus.pl - PLCBUS control server written in perl.\n";
	print	"	==================================================\n\n";
	print	"Usage: 		plcbus.pl [Options] [&]\n\n";
	print	"Options:	--help		Display this page\n";
	print	"		--info		Display info regarding plcbus.pl\n";
	print	"		--verbose	Turn on verbose output\n";
	print	"		--port		TCP Port to listen for commands on (default: 5151)\n";
	print	"		--device	PLCBUS 1141 / 1141+ device location (default: /dev/ttyS0)\n";
	print	"		--user		Unique hexidecimal User Code, chosen to prevent interference\n";
	print	"				from neighbours (default: FF)\n";
	print	"		--phase		Number of electrical phases in your house.  Valid values are:\n";
	print	"				1 - Fully supported\n";
	print	"				3 - Requires use of a PLCBUS 3-phase Coupler.  Currently\n";
	print	"				    this is untested, but should work if version 2.3 of the\n";
	print	"				    RS232 to PLCBUS Control Transport Protocol document is\n";
	print	"				    correct.  At worst the commands should work but you will\n";
	print	"				    receive false Command FAIL messages.\n\n";
	print	"&:		Used to daemonise plcbus.pl\n\n";
	print	"Example:	plcbus.pl --device=/dev/ttyUSB0 --port=1221 &\n\n";
	print	"For more information execute 'plcbus.pl --info'\n\n";
	return;
}

# Display Info page
#
sub info
{
	print   "\n     ==================================================\n";
	print   "       plcbus.pl - PLCBUS control server written in perl.\n";
	print   "       ==================================================\n\n";
	print   "Created by Wayne Thomas, contributions by Maurice de Bijl\n\n";
	print	"Listens on the designated TCP port for correctly formatted commands and passes them to the\n";
	print	"PLCBUS adaptor then returns the response.\n\n";
	print	"	Initial version by Wayne Thomas, based upon hub_plcbus.pl (written\n";
	print	"	by Jfn of  domoticaforum) with some code borrowed from Ron Frazier\n";
	print	"	(http://www.ronfrazier.net).\n\n";
	print	"Latest version and discussion, see http://code.google.com/p/plcbus-daemon-for-linux/\n";
	print	"History, see http://code.google.com/p/plcbus-daemon-for-linux/source/list\n\n";
	print	"Feel free to do anything you want with this, as long as you\n";
	print	"include the above attribution.\n\n";
	print	"Accepts commands in the following format:\n";
	print	"	homeunit,command,[value1],[value2]\n\n";
	print	"Valid HomeUnit codes are from A1 - A16 through to P1 - P16\n";
	print	"	Note:   For each Home (A - P), Units 10 thru 16 have been reserved for Scene\n";
	print	"		Addresses.  This is due to scenes not providing a response the same as\n";
	print	"		individual modules.  If you do use a individual module with an address\n";
	print	"		reserved for a scene it will still work.  Using a scene with a non-scene\n";
	print	"		address will produce error messages but will work anyway.\n";
	print	"	Note2:  HomeUnit P16 appears to be a 'All Units' or 'All Lights' address.\n\n";
	print	"Example Command: A14,PRESET_DIM,100,5 (change dim value to 100% over 5 seconds)\n";
	print	"Example Response: PRESET_DIM,100,5 (confirms command executed by PLCBUS module)\n\n";
	print	"Suggested command line interaction for above example:\n";
	print	"	echo -e 'a14,preset_dim,100,5\\nEXIT\\n' | nc localhost 5151\n";
	print	"If sending commands across a slow network you may need to increase the\n";
	print	"interval to 1 or 2 seconds in order to receive a response:\n";
	print	"	echo -e 'a14,preset_dim,100,5\\nEXIT\\n' | nc -i 1 serverip 5151\n\n";
	print	"Valid commands:\n\n";
	print	"-	homeunit,ALL_UNITS_OFF\n";
	print	"-	homeunit,ALL_LIGHTS_ON\n";
	print	"-	homeunit,ON\n";
	print	"-	homeunit,OFF\n";
	print	"-	homeunit,DIM,fadetime\n";
	print	"-	homeunit,BRIGHT,fadetime\n";
	print	"-	homeunit,ALL_LIGHTS_OFF\n";
	print	"-	homeunit,ALL_USER_LIGHTS_ON\n";
	print	"-	homeunit,ALL_USER_UNITS_OFF\n";
	print	"-	homeunit,ALL_USER_LIGHTS_OFF\n";
	print	"-	homeunit,FADE_STOP\n";
	print	"-	homeunit,PRESET_DIM,fadelevel,fadetime\n";
	print	"-	homeunit,STATUS_REQUEST\n";
	print	"-	homeunit,RX_MASTER_ADDR_SETUP,newusercode,newhomeunit\n";
	print	"-	homeunit,TX_MASTER_ADDR_SETUP,newusercode,newhomeunit\n";
	print	"-	homeunit,SCENE_ADDR_SETUP,state	==> state ON = 2, state OFF = 3\n";
	print	"-	homeunit,SCENE_ADDR_ERASE\n";
	print	"-	homeunit,ALL_SCENES_ADDR_ERASE\n";
	print	"-	homeunit,GET_SIGNAL_STRENGTH\n";
	print	"-	homeunit,GET_NOISE_STRENGTH\n";
	print	"-	homeunit,GET_ALL_ID_PULSE\n";
	print	"-	homeunit,GET_ON_ID_PULSE\n\n";

	return;
}


# Send command to PLCBUS
#
sub plcbus_tx_command
{
	my ($handle, $params) = @_;
	$params = uc($params);
	$plcbus_data1 = 0x0;
	$plcbus_data2 = 0x0;
	my $result;

	my @params_data = split(/\,/, $params); # Split the command in its various parts (Example: A1,ON; D4,DIM,10,1)
	if (!defined($params_data[1])) {
		syswrite ($handle, "ERROR, Illegal Command Format\n") if $verbose;
		return 0;
	}
	my @homeunit = split(//, $params_data[0]);
	my $home = unpack ('C*', $homeunit[0]) - 65;
	my $unit = substr ($params_data[0], 1, 2);
	if (($home =~ /\D/) || ($home < 0) || ($home > 16) || ($unit =~ /\D/) || ($unit <1) || ($unit > 16)) {
		syswrite ($handle, "ERROR, Illegal HomeUnit Code\n") if $verbose;
		return 0;
	}
	my $plcbus_homeunit = $home*16 + $unit - 1;

	# provide some flexibility in command syntax
	$params_data[1] =~ s/-/_/g;
	$params_data[1] =~ s/ /_/g;

	# if command is not valid return to main
	if (!defined ($plcbus_command_to_hex{$params_data[1]})) {
		syswrite ($handle, "ERROR, Unknown PLCBUS Command\n") if $verbose;
		return 0;
	}

	# prepare command and data for transmission
	$plcbus_command = ($plcbus_command_to_hex {$params_data[1]});
	if (($plcbus_command >= 0x1C) || ($plcbus_command <= 0x1) || (($plcbus_command >= 0x06) && ($plcbus_command <=0x09))) {
		$plcbus_homeunit &= 0xF0; }
	$plcbus_command += 0x20 unless (($plcbus_command == 0x1C) || ($plcbus_command == 0x1D));
	$plcbus_command += 0x40 if ($phase == 3);
	$plcbus_data1 = $params_data[2] if defined($params_data[2]);
	if (($plcbus_data1 =~/\D/) || ($plcbus_data1 < 0) || ($plcbus_data1 > 100)) {
		syswrite ($handle, "ERROR, Illegal Data1 Value\n") if $verbose;
		return 0;
	}
	$plcbus_data2 = $params_data[3] if defined($params_data[3]);
	if (($plcbus_data2 =~/\D/) || ($plcbus_data2 < 0) || ($plcbus_data2 > 100)) {
		syswrite ($handle, "ERROR, Illegal Data2 Value\n") if $verbose;
		return 0;
	}

	$plcbus_frame = pack ('C*', 0x02, 0x05, $plcbus_usercode, $plcbus_homeunit, $plcbus_command, $plcbus_data1, $plcbus_data2, 0x03);

	# Empty any loafing data from the serial buffer
	while (1)
	{
		my ($bytes, $plcbus_frame) = $serport->read(9);
		last if $bytes == 0;
		my @params_data = unpack ('C*', $plcbus_frame);

                if (plcbus_rx_valid_frame ($handle, @params_data))
                {
                	if (plcbus_rx_status($handle,undef,undef, @params_data))        # Did we receive a valid frame and does it contain a$
               		{
				plcbus_output_message ($handle, @params_data);
			}
		}
	}

	foreach (1..3)
	{
		# send prepared command to controller
		$serport->write ($plcbus_frame);
		syswrite ($handle, (sprintf ("Sent Packet     = 02 05 %02x %02x %02x %02x %02x 03\n", 
			$plcbus_usercode, $plcbus_homeunit, $plcbus_command, $plcbus_data1, $plcbus_data2))) if ($verbose);

		# listen for feedback
		$result = plcbus_check_status($handle, $plcbus_homeunit, $plcbus_command);
		last unless (!$result);
	}
	syswrite ($handle, "ERROR, no repsonse\n") if ($verbose && !$result);
	return $result;
}


# Read and decode incoming PLCBUS frames
#
sub plcbus_check_status
{
	
	# One transmitted command over the PLCBUS will result in two or three return packets, including a status message
	# We listen for a maximum of 3 seconds for all packets received and filter out the relevant status. Should we 
	# receive it earlier, then break from the loop

	my ($handle, $homeunit, $action) = @_;
	my $plcbus_status = '';
	eval
	{
		local $SIG{ALRM} = sub { die };
		alarm 1;
		READ : while (1)
		{
			my $plcbus_frame=$serport->read(9);
			my @params_data = unpack ('C*', $plcbus_frame);
                        
			if (plcbus_rx_valid_frame ($handle, @params_data))
			{
				if (plcbus_rx_status($handle, $homeunit, $action, @params_data))	# Did we receive a valid frame and does it contain a status message
				{
					$plcbus_status = plcbus_output_message ($handle, @params_data);
					last READ if $plcbus_status;
				}
			}
		}
		alarm 0;
	} or return 0;

	return $plcbus_status;
}
	

# Checks whether the received response is a valid PLCBUS frame
#
sub plcbus_rx_valid_frame
{
	my ($handle, @data) = @_;

	# Did we receive a valid 9 byte PLCBUS frame?
	if (scalar @data == 9)
	{
		syswrite ($handle, (sprintf("Received Packet = %02X %02X %02X %02X %02X %02X %02X %02X %02X",
			$data[0], $data[1], $data[2], $data[3], $data[4], $data[5], $data[6], $data[7], $data[8]))) if $verbose;

		# Does it have a payload of six bytes and start with STX and ends with ETX?
		if (($data[1] == 0x06) && ($data[0] == 0x02) && (($data[8] == 0x03)
		
		# Support for the PLCBUS-1141 PLUS (+) computer interface
		|| ((sum(@data) % 0x100) == 0x0)))
		{
			# Yes it does, we have a valid frame!
		        syswrite ($handle, "\n") if $verbose;
			return 1;
		} else
		{
			# Bummer, better luck next time
			syswrite ($handle, " - not a valid frame\n") if $verbose;
			return 0;
		}
	}
}

# Did we receive a proper status request for a device?
#
sub plcbus_rx_status
{
	my ($handle, $homeunit, $action, @data) = @_;
	my $status = sprintf ("%d", $data[4] & 0x1F);
	$action = $action & 0x1F unless !(defined($action));

	# if response is a direct response to the command issued
	#
	if ((defined($homeunit)) && ($homeunit == $data[3])) {

		# if using three phase, wait for status report from coupler
		#
		if ($phase == 3) {
			if (($data[4] == 0x0D) || ($data[4] == 0x0E) || ($data[4] >= 0x1E)) {
				return 1; }
		}

		# if a get ID query command wait for a rxed ID Feedback signal
		#
		elsif (($action == 0x1C) || ($action == 0x1D)) {
			if ($data[7] == 0x40) {
				return 1; }
		}

		# if a query command (request or get) wait for a PLCBUS success report from another unit (not the 1141(+))
		#
		elsif (($action == 0x0F) || ($action == 0x18) || ($action == 0x19)) {
			if ($data[7] == 0x0C) {
				return 1; }
		}

		# if a scene setup / erase, or a on / off to a scene address (Unit 10 - 16 for each Home) only send success is required
		#
		elsif (($action == 0x12) || ($action == 0x13) || ($action == 0x14) ||
				((($action == 0x02) || ($action == 0x03)) && (($data[3] & 0x0F) >= 0x09))) {
			if ($data[7] == 0x1C) {
				return 1; }
		}

		# all other commands only require an ACK 
		elsif ($data[7] == 0x20) {
			return 1; };
	}
	elsif (($status == 0x0D) || ($status == 0x0E) || ((defined($homeunit)) && ($homeunit != $data[3]))) { 
		syswrite ($handle, "Detected traffic initiated by seperate transmitter\n") if $verbose; 
		# TODO: decipher and send report regarding detected traffic
		plcbus_output_message ($handle, @data);
		return 0;
	}
	elsif (!defined $homeunit) {
		syswrite ($handle, "Detected traffic initiated by seperate transmitter\n") if $verbose;
		return 1;
	}
	else {
		return 0; }
}

# Output the Received PLCBUS packet
#
sub plcbus_output_message 
{
	my ($handle, @data) = @_;
	my $test = sprintf ("%d", $data[4] & 0x1f);
	return 0 unless (defined($plcbus_hex_to_status{$test}));
	$plcbus_status = $plcbus_hex_to_status{$test};
	my $home = int($data[3] / 16) + 65;
	$home = pack ("C", $home);
	my $unit = $data[3] % 16 + 1;
	$plcbus_status = $home.$unit . ',' . $plcbus_status . ',' . $data[5] . ',' . $data[6];
	syswrite ($handle, "$plcbus_status\n");
	return $plcbus_status;
}


#
# Start of MAIN program
#

my $help = '';
my $info = '';

# Process any options passed in
#
GetOptions (	'verbose' =>	\$verbose,
		'help' =>	\$help,
		'info' =>	\$info,
		'port=i' =>	\$listenport,
		'user=s' =>	\$plcbus_usercode,
		'phase=i' =>	\$phase,
		'device=s' =>	\$serdev);
if ($help) { help(); exit 0;}
if ($info) { info(); exit 0;}

$plcbus_usercode = hex ($plcbus_usercode);
die "Invalid UserCode - Valid values are 00 - FF. Stopped\n" if (($plcbus_usercode < 0x00) || ($plcbus_usercode > 0xFF));
die "Invalid number of Phases - Legal values are 1 or 3. Stopped\n" unless (($phase == 1) || ($phase == 3));

# Open serial port to the PLCBUS controller
#
$serport=Device::SerialPort->new($serdev) or die "Error opening serial port: $!\n";
$serport->baudrate(9600);
$serport->databits(8);
$serport->parity("none");
$serport->stopbits(1);
$serport->handshake("none");
$serport->write_settings;
$serport->read_const_time(200);

my $listensocket = new IO::Socket::INET (
        LocalPort => $listenport,
        Proto => 'tcp',
        Listen => 1,
        Reuse => 1,
        Blocking => 1
        );
die ("Could not create socket: $!") unless $listensocket;

my $select = new SerialLibs::IOSelectBuffered($listensocket);

while(my @ready = $select->can_read())
{
        return unless scalar(@ready);
        foreach my $handle (@ready)
        {
                #open a socket for the newly connected client
                if ($handle == $listensocket)
                {
                        my $client = $listensocket->accept();
                        $client->autoflush(1);
                        $select->add($client);

                        next;
                };

                #read the next line and test for error, EOF, socket disconnect, or just partial lines
                my $line = $select->getline($handle);
                if (!defined($line))
                {
                        $select->remove($handle);
                        $handle->close();
                        next;
                };

		my $result;
                $line =~ s/[\n\r\f]+$//ms;
		if ($line eq '')
		{
			do {
				$result = plcbus_check_status($handle);
			} while $result;
			next;
		};

                if ($line =~ /EXIT/i)
                {
                        $select->remove($handle);
                        $handle->close();
                        next;
                };

		my $plcbus_result = plcbus_tx_command ($handle, $line);

		# If illegal command or illegal reply received
#		syswrite($handle, "Command FAIL\n") unless $plcbus_result;

        };
};

exit;
