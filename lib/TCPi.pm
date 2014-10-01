use strict;

# Define Room groups for floorplan and add the motion and objects
# Type		Address				Name				Groups							Other Info
#Group A
#TCPi,		216484051283335346,	LR_Lamp,			All_Lights|LivingRoom(1;11),  	Light,	

#Private MH.INI -> TCPiHost = 192.168.1.X

#read_table_a.pl
#elsif ($type eq "TCPI"){
#	#require 'TCPi.pm';
#	($address, $name, $grouplist, @other) = @item_info;
#	$other = join ', ', (map {"'$_'"} @other); # Quote data
#	&::print_log("$address, $name, $grouplist, $other");
#	$object = "TCPi('$address',$other)";
#	if( ! $packages{TCPi}++ ) {   # first time for this object type?
#		&::print_log("First Time TCPi Usage");
#		$code .= "use TCPi;\n";
#		&::MainLoop_pre_add_hook( \&TCPi::GetDevicesAndStatus, 1 );
#	}
#}

package TCPi;
@TCPi::ISA= ('Generic_Item');
use LWP::Simple;
use LWP::UserAgent;

#http://lighting/gwr/gop.php?cmd=GWRBatch&data=<gwrcmds><gwrcmd><gcmd>RoomGetCarousel</gcmd><gdata><gip><version>1</version><token>1234567890</token><fields>name,image,imageurl,control,power,product,class,realtype,status</fields></gip></gdata></gwrcmd></gwrcmds>&fmt=xml

my $TCPiHost = "lighting";
my $tGetInfo = "/gwr/gop.php?cmd=GWRBatch&data=<gwrcmds><gwrcmd><gcmd>RoomGetCarousel</gcmd><gdata><gip><version>1</version><token>1234567890</token><fields>name,image,imageurl,control,power,product,class,realtype,status</fields></gip></gdata></gwrcmd></gwrcmds>&fmt=xml";
my $last_time;
my $rate = 1; #in minutes how often shall we get the status
my $debug = 0; #set to 1 to force debug

my @tcpi_obj;

sub new {
    my ($class, $p_address) = @_;
	my $self = $class->SUPER::new();
	bless $self,$class;

	&::print_log("$p_address, $class") if $debug;
    $$self{lamp_id} = $class;
	$$self{address} = $p_address;
	$$self{state}='';
	$$self{name}='';
    
    $self->addStates ('on', 'off', '5%', '10%', '15%', '20%', '25%', '30%', '35%', '40%', '45%', '50%', '55%', '60%', '65%', '70%', '75%', '80%', '85%', '90%', '95%', '100%');
    return $self;
}

sub addStates {
    my $self = shift;
    push(@{$$self{states}}, @_);
}

sub default_setstate
{
    my ($self, $state, $substate, $set_by) = @_;
	my $cmnd;
	
	my %replacements = ("off" => "0", "on" => "1", "%" => "");
	($cmnd = $state) =~ s/(@{[join "|", keys %replacements]})/$replacements{$1}/g;
    	
    return -1 if ($self->state eq $state); # Don't propagate state unless it has changed.
	
	#call the function to turn on/off light
	SetTCPi ($$self{address}, $cmnd);
	return;
	
}

sub property_changed {
    my ($self, $property, $new_value, $old_value) = @_;
	&::print_log("$self, $property, $new_value, $old_value") if $debug;
}

sub SetTCPi {
	my($devid, $cmd) = @_;	
	my $lvl="";#<type>level</type>
	if (($cmd!=0)&&($cmd!=1)){
		$lvl="<type>level</type>";
	}
	my $url = "http://$TCPiHost/gwr/gop.php?cmd=DeviceSendCommand&data=<gip><version>1</version><token>1</token><did>$devid</did><value>$cmd</value>$lvl</gip>&fmt=xml";
	my $ua       = LWP::UserAgent->new();
	my $response = $ua->get($url);
	my $content  = $response->decoded_content();
	
	if ($content =~ /<rc>200<\/rc>/) {   #<gip><version>1</version><rc>200</rc></gip>
		&::print_log("Setting TCPi $devid to State $cmd ->Success!") if $debug;
	}else{
		&::print_log("Setting TCPi $devid to State $cmd ->FAILED!");
	}
}

sub startup {
	if ($main::config_parms{TCPiHost} != ""){
		$TCPiHost = $main::config_parms{TCPiHost};
	}
	&::MainLoop_pre_add_hook( \&TCPi::GetDevicesAndStatus, 1 );
	&PollDevice;
	if (exists $main::Debug{tcpi}) {$debug = ($main::Debug{tcpi} >= 1) ? 1 : $debug;}
}

sub GetDevicesAndStatus {
	my $now_time = Time::HiRes::time;
	if (($now_time - $last_time) > (60 * $rate)){
		&PollDevice;
	}
	
}

sub PollDevice {
	my $ua       = LWP::UserAgent->new();
	my $url = "http://$TCPiHost/gwr/gop.php?cmd=GWRBatch&data=<gwrcmds><gwrcmd><gcmd>RoomGetCarousel</gcmd><gdata><gip><version>1</version><token>1234567890</token><fields>name,image,imageurl,control,power,product,class,realtype,status</fields></gip></gdata></gwrcmd></gwrcmds>&fmt=xml";
	my $response = $ua->get($url);
	my $content  = $response->decoded_content();
	my @matches = ($content =~ /<device><did>(.*?)<\/did>/g);
	my $st = ""; my $lvl = ""; my $name = ""; my $offline = "";
	while (@matches) { 
		my $did = shift @matches; 
		($st) = $content =~ /<device><did>$did<\/did><known>\d<\/known><lock>\d<\/lock><state>(.*?)<\/state>/;
		($lvl) = $content =~ /<device><did>$did<\/did><known>\d<\/known><lock>\d<\/lock><state>$st<\/state><level>(.*?)<\/level>/;
		($offline) = $content =~ /<device><did>$did<\/did><known>\d<\/known><lock>\d<\/lock><state>$st<\/state><offline>(.*?)<\/offline>/;
		($name) = $content =~ /<device><did>$did<\/did><known>\d<\/known><lock>\d<\/lock><state>$st<\/state>.*?<name>(.*?)<\/name>/;
		if ($st == 0){
			$lvl = 0;
		}elsif (($st == 1)&&($lvl == 100)){
			$lvl = 1;
		}
		if ($offline == 1){&::print_log("Warning DID: $did Name: $name is offline.");}
		&SetDeviceInfo($did, $lvl, $name);
		&::print_log("Level: $lvl DID: $did Name: $name") if $debug;
	}
	$last_time = Time::HiRes::time;
}

sub SetDeviceInfo {
	my($devid, $cmd, $name) = @_;
	my $objfound = 0;
	for my $name (&main::list_objects_by_type('TCPi')) {
		my $object = &main::get_object_by_name($name);
		if ($object->{address} == $devid){
			if ($cmd == 0){
				$cmd = 'Off';
			}elsif ($cmd == 1){
				$cmd = 'On';
			}else {
				$cmd = $cmd."%";
			}
			if ($object->{state}!=$cmd){
				$object->{state}=$cmd;
			}
			if ($object->{name}!=$name){
				$object->{name}=$name;
			}
			$objfound = 1;
		}
	}
	if($objfound == 0){
		&::print_log("No entry found for TCPi Item; DID:$devid Name:$name");
	}	
}

1;
