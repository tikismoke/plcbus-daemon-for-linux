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
# Accepts commands in the following format:
#	homeunit,command,[hexvalue1],[hexvalue2]
#
# Example Command: A1,PRESET_DIM,64,5 (change dim value to max over 5 seconds)
# Example Response: PRESET_DIM,100,5 (responds in decimal)
#
# Suggested command line interaction for above example:
#	echo -e 'a1,preset_dim,64,5\nEXIT\n' | nc localhost 5151
# If sending commands across a slow network you may need to increase the 
# interval to 1 second in order to receive a response:
#	echo -e 'a1,preset_dim,64,5\nEXIT\n' | nc -i 1 serverip 5151
#
###############################################################################

use Device::SerialPort;
use IO::Socket;
use Time::HiRes qw(sleep);
use IO::Socket::INET;
use SerialLibs::IOSelectBuffered;

#my $serdev = '/dev/plcbus';	# Serial Port device (using custom udev rule)
my $serdev = '/dev/ttyS0';	# COM1
my $serport;			# handle for the serial port
my $listenport = 5151;
my $plcbus_usercode = 0xFF;	# Usercode, custom value can be (0x00-0xFF) 
                                # chosen to avoid interference with neighbors

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
	'STATUS_ON'		=> 0x0d,
	'STATUS_OFF'		=> 0x0e,
	'STATUS_REQUEST'	=> 0x0f,
	'RX_MASTER_ADDR_SETUP'	=> 0x10,
	'TX_MASTER_ADDR_SETUP'	=> 0x11,
	'SCENE_ADDR_SETUP'	=> 0x12,
	'SCENE_ADDR_ERASE'	=> 0x13,
	'ALL_SCENES_ADDR_ERASE'	=> 0x14,
	'GET_SIGNAL_STRENGTH'	=> 0x18,
	'GET_NOISE_STRENGTH'	=> 0x19,
	'REPORT_SIGNAL_STRENGTH'=> 0x1a,
	'REPORT_NOISE_STRENGTH' => 0x1b,
	'GET_ALL_ID_PULSE'	=> 0x1c,
	'GET_ONE_ID_PULSE'	=> 0x1d,
	'REPORT_ALL_ID_PULSE'	=> 0x1e,
	'REPORT_ON_ID_PULSE'	=> 0x1f, );



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
	0x1d    => "GET_ONE_ID_PULSE",
	0x1e	=> "REPORT_ALL_ID_PULSE",
	0x1f    => "REPORT_ON_ID_PULSE",
);


# Send command to PLCBUS
#
sub plcbus_tx_command
{
	$plcbus_data1 = 0x0;
	$plcbus_data2 = 0x0;

	my $result;
	my $params = uc(shift);
	my @params_data = split(/\,/, $params); # Split the command in its various parts (Example: A1,ON; D4,DIM,10,1)

	$plcbus_homeunit = hex ($params_data[0]) - 0xa1;	# Convert homeunit to hex value (Example: C9 --> 0x28)

	# if command is not valid return to main
	return 0 unless (defined ($plcbus_command_to_hex{$params_data[1]}));

	# prepare command and data
	$plcbus_command = $plcbus_command_to_hex {$params_data[1]};	# Convert ASCII command to corresponding PLCBUS hex code
	$plcbus_data1 = hex ($params_data[2]) if (($plcbus_command == 0x04) || ($plcbus_command == 0x05) || 
		($plcbus_command == 0x0a) || ($plcbus_command == 0x0c) || ($plcbus_command == 0x0d) || ($plcbus_command == 0x10) ||
		($plcbus_command == 0x11) || ($plcbus_command == 0x1a) || ($plcbus_command == 0x1b));
	$plcbus_data2 = hex ($params_data[3]) if (($plcbus_command == 0x0c) || ($plcbus_command == 0x0d) ||
		($plcbus_command == 0x10) || ($plcbus_command == 0x11) || ($plcbus_command == 0x1a) || ($plcbus_command == 0x1b));
	printf "Sent Packet     = 02 05 ff %02x %02x %02x %02x 03\n", $plcbus_homeunit, $plcbus_command|0x20, $plcbus_data1, plcbus_data2;
	$plcbus_frame = pack ('C*', 0x02, 0x05, $plcbus_usercode, $plcbus_homeunit, $plcbus_command + 0x20, $plcbus_data1, $plcbus_data2, 0x03);

	# Empty any loafing data from the serial buffer
	while (1)
	{
		my ($bytes, $read) = $serport->read(1);
		last if $bytes == 0;
		print "$bytes byte --> $read <-- cleared from buffer\n";
	}

	foreach (1..3)
	{
		# send prepared command to controller
		$serport->write ($plcbus_frame);

		# listen for feedback
		$result = plcbus_check_status();
		last unless ($result =~ 'ERROR');
	}
	return $result;
}


# Read and decode incoming PLCBUS frames
#
sub plcbus_check_status
{
	
	# One transmitted command over the PLCBUS will result in two or three return packets, including a status message
	# We listen for a maximum of 3 seconds for all packets received and filter out the relevant status. Should we 
	# receive it earlier, then break from the loop
	#
	my $plcbus_status = '';
	eval
	{
		local $SIG{ALRM} = sub { die };
		alarm 3;
		READ : while (1)
		{
			my $plcbus_frame=$serport->read(9);
			my @params_data = unpack ('C*', $plcbus_frame);
                        
			if (plcbus_rx_valid_frame (@params_data))
			{
				if (plcbus_rx_status(@params_data))	# Did we receive a valid frame and does it contain a status message
				{
					my $test=sprintf ("%d", $params_data[4] & 0x1f);
					next READ unless (defined($plcbus_hex_to_status{$test}));
					$plcbus_status = $plcbus_hex_to_status{$test};
					$plcbus_status = $plcbus_status . "\," . $params_data[5] . "\," . $params_data[6];
					last READ;
				}
			}
		}
		alarm 0;
		1;
	} or $plcbus_status = "ERROR, no response";

	return $plcbus_status;
}
	

# Checks whether the received response is a valid PLCBUS frame
#
sub plcbus_rx_valid_frame
{
	my @data = @_;

	# Did we receive a valid 9 byte PLCBUS frame?
	if (scalar @data == 9)
	{
		printf "Received Packet = %02X %02X %02X %02X %02X %02X %02X %02X %02X", $data[0], $data[1], $data[2],
			$data[3], $data[4], $data[5], $data[6], $data[7], $data[8];
		# Does it have a payload of six bytes and start with STX and ends with ETX?
		if ((($data[1] == 0x06) && ($data[0] == 0x02) && ($data[8] == 0x03))
		
		# Support for the PLCBUS-1141 PLUS (+) computer interface
		|| (($data[1] == 0x06) && ((($data[0] + $data[1] + $data[2] + $data[3] + $data[4] + $data[5] + $data[6] + $data[7] + $data[8]) % 0x100) == 0x00)))
		{
		# Yes it does, we have a valid frame!
		        printf "\n";
			return 1;
		} else
		{
			# Bummer, better luck next time
			printf " - not a valid frame\n";
			return 0;
		}
	}
}

# Did we receive a proper status request for a device?
#
sub plcbus_rx_status
{
	my @data = @_;
	my $status = sprintf ("%d", $data[4] & 0x1F);
	if (($data[7] == 0x0C) || (($data[7] == 0x20) && (($status != 0x0F) && ($status != 0x18) && ($status != 0x19))) ||
		(($data[7] == 0x1C) && (($status == 0x00) || ($status == 0x01) || ($status == 0x06) || ($status == 0x07) ||
		($status == 0x08) || ($status == 0x09))))
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

#
# Start of MAIN program
#

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
                next if $line eq '';

                $line =~ s/[\n\r\f]+$//ms;

                if ($line =~ /EXIT/i)
                {
                        $select->remove($handle);
                        $handle->close();
                        next;
                };

		my $plcbus_result = plcbus_tx_command ($line);

		# If illegal command or illegal reply received
		$plcbus_result = "ERROR, Illegal PLCBUS Command or Reply" if ($plcbus_result eq '0');

		# Send the caller a status report
		syswrite($handle, "$plcbus_result\n");

        };
};
print "EXITING\n";
exit;
