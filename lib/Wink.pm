=begin comment
Larry Roudebush
Initial release GE/TCPi lights only 2015-11-01

In items.mht
Type		Address				Name				Groups							Other Info
Group A
WINK,		64684,	Mstr BR NS L,			All_Lights|LivingRoom(1;11),  	Light,

In your mh private.ini
Private MH.INI -> WinkUser =  email address 
					WinkPassword = XXXXXXXXX
					
Add the below to \lib\read_table_a.pl
read_table_a.pl
elsif ($type eq "WINK"){
	($address, $name, $grouplist, @other) = @item_info;
	$other = join ', ', (map {"'$_'"} @other); # Quote data
	$object = "Wink('$address',$other)";
	if( ! $packages{Wink}++ ) {   # first time for this object type?
		$code .= "use Wink;\n";
		&::MainLoop_pre_add_hook( \&Wink::GetDevicesAndStatus, 1 );
	}
}


=cut


package Wink;
@Wink::ISA = ('Generic_Item');
require LWP::UserAgent;
use HTTP::Request;
use JSON;
use strict;

#use Data::Dumper;

#my $baseUrl = "http://private-baa47-wink.apiary-mock.com";
my $baseUrl  = "https://winkapi.quirky.com";
my $allDev   = "/users/me/wink_devices";
my $getToken = "/oauth2/token";
my %objtypes = ( 5 => 'light_bulbs', 15 => 'Hubs', 73 => 'light_bulbs' );

my ( $refresh_token, $access_token, $token_type, $data );

my $last_time;
my $rate  = 1;    #in minutes how often shall we get the status
my $debug = 1;    #set to 1 to force debug

sub new {
    my ( $class, $p_address ) = @_;
    my $self = $class->SUPER::new();
    bless $self, $class;

    &::print_log("$p_address, $class") if $debug;
    $$self{lamp_id} = $class;
    $$self{address} = $p_address;
    $$self{upc_id}  = '';
    $$self{state}   = '';
    $$self{name}    = '';

    $self->addStates(
        'on',  'off', '5%',  '10%', '15%', '20%', '25%', '30%',
        '35%', '40%', '45%', '50%', '55%', '60%', '65%', '70%',
        '75%', '80%', '85%', '90%', '95%', '100%'
    );
    &startup;
    return $self;
}

sub startup {
    &::print_log("Initializing Wink") if $debug;
    $data = "{\n    \"client_id\": \"quirky_wink_android_app\"
				,\n    \"client_secret\": \"e749124ad386a5a35c0ab554a4f2c045\"
				,\n    \"username\": \"$main::config_parms{WinkUser}\"
				,\n    \"password\": \"$main::config_parms{WinkPassword}\"
				,\n    \"grant_type\": \"password\"\n}";
    if ( exists $main::Debug{Wink} ) {
        $debug = ( $main::Debug{Wink} >= 1 ) ? 1 : $debug;
    }
}

sub getJsonArg {
    my ( $devid, $upc_id, $state ) = @_;
    my ( $arg, $cmnd, $pwrd );
    my $cmnd = "";
    my %replacements = ( "off" => "0", "on" => "1", "%" => "" );
    ( $cmnd = $state ) =~
      s/(@{[join "|", keys %replacements]})/$replacements{$1}/g;
    if ( getObjType($upc_id) == "light_bulbs" ) {

#Current: ON, New 50%  -----   Current: 50%, New off  ----------   Current: off, New on
#{ 'desired_state': { 'brightness': 0.5, 'powered': True } }
        if   ( $cmnd == 0 ) { $pwrd = "false" }
        else                { $pwrd = "true" }
        if ( ( $cmnd != 0 ) && ( $cmnd != 1 ) ) { $cmnd = $cmnd / 100 }
        $arg ="{\"desired_state\": 
				{\"brightness\": \"$cmnd\"
				, \"powered\": \"$pwrd\"}}";
    }

    return $arg;
}

sub getDeviceUrl {
    my ( $devid, $upc_id ) = @_;
    my $obj = getObjType($upc_id);
    return "/$obj/$devid";
}

sub putWinkData {
    my ( $url, $data ) = @_;
    $url = $baseUrl . $url;
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new( PUT => $url );
    $request->header( authorization => "$token_type $access_token" );
    $request->content_type("application/json");
    $request->content($data);

    #$ua->default_header(content_type => "application/json");
    #$ua->default_header(authorization => "$token_type $access_token");
    #my $response = $ua->put($url, Content => $data);
    my $response = $ua->request($request);
    if ( $response->is_success ) {
        &::print_log("Set Wink Object Success") if $debug;;
        return 1;
    }
    else {
        &::print_log("Set Wink Object Failed");
        return 0;
    }
}

sub addStates {
    my $self = shift;
    push( @{ $$self{states} }, @_ );
}

sub default_setstate {
    my ( $self, $state, $substate, $set_by ) = @_;
    my $cmnd;

    my %replacements = ( "off" => "0", "on" => "1", "%" => "" );
    ( $cmnd = $state ) =~
      s/(@{[join "|", keys %replacements]})/$replacements{$1}/g;
    my $curr = $self->state;
    &::print_log("Current: $curr, New $state") if $debug;

    return -1
      if ( $self->state eq $state )
      ;    # Don't propagate state unless it has changed.

    #call the function to turn on/off light
    setWinkDevice( $$self{address}, $$self{upc_id}, $cmnd );
    return;
}

sub setWinkDevice {
    my ( $devid, $upc_id, $cmd ) = @_;
    getWinkToken();
    if ( $token_type ne "" ) {
        my $arg = getJsonArg( $devid, $upc_id, $cmd );
        my $url = getDeviceUrl( $devid, $upc_id );
        my $stat = putWinkData( $url, $arg );
        if ( $stat == 1 ) {
            &::print_log("Setting TCPi $devid to State $cmd ->Success!")
              if $debug;
        }
        else {
            &::print_log("Setting TCPi $devid to State $cmd ->FAILED!");
        }
    }
    else {
        &::print_log("Token Failure!");
    }
}

sub GetDevicesAndStatus {
    my $now_time = Time::HiRes::time;
    if ( ( $now_time - $last_time ) > ( 60 * $rate ) ) {
        &::print_log("Polling Device") if $debug;
        &PollDevice;
    }

}

sub PollDevice {
    my $url = $baseUrl . $allDev;
    getWinkToken();
    if ( $token_type eq "" ) { return; }
    my $ua = LWP::UserAgent->new;
    $ua->default_header( authorization => "$token_type $access_token" );
    my $response = $ua->get($url);

    my $decoded_json = decode_json( $response->content() );
    my $aref         = $decoded_json->{data};
    for my $href (@$aref) {
        if ( getObjType( $href->{upc_id} ) == "light_bulbs" ) {
            &SetDeviceInfo(
                $href->{light_bulb_id},
                $href->{desired_state}{brightness},
                $href->{name}, $href->{upc_id}
            );
        }
        &::print_log(
            "Level:$href->{desired_state}{brightness}
					, DID: $href->{light_bulb_id}
					, Name:$href->{name} 
					, UPC:$href->{upc_id}"
        ) if $debug;
    }
    $last_time = Time::HiRes::time;
}

sub SetDeviceInfo {
    my ( $devid, $cmd, $name, $upc_id ) = @_;
    my $objfound = 0;
    for my $name ( &main::list_objects_by_type('Wink') ) {
        my $object = &main::get_object_by_name($name);
        if ( $object->{address} == $devid ) {
            if ( $cmd == 0 ) {
                $cmd = 'OFF';
            }
            elsif ( $cmd == 1 ) {
                $cmd = 'ON';
            }
            else {
                $cmd = $cmd . "%";
            }
            &::print_log(
                "Setting State:$object->{state} Device:$devid Command:$cmd")
              if $debug;
            if ( $object->{state} ne $cmd ) {
                &::print_log("State is no match, updating...") if $debug;
                $object->{state} = $cmd;
            }
            if ( $object->{name} ne $name ) {
                $object->{name} = $name;
            }
            if ( $object->{upc_id} ne $upc_id ) {
                $object->{upc_id} = $upc_id;
            }

            $objfound = 1;
        }
    }
    if ( $objfound == 0 ) {
        &::print_log(
            "No entry found for Wink Item; DID:$devid Name:$name UPC Id:$upc_id"
        );
    }
}

sub property_changed {
    my ( $self, $property, $new_value, $old_value ) = @_;
    &::print_log("$self, $property, $new_value, $old_value") if $debug;
}

sub getObjType {
    my $upc_id = shift;
    foreach my $key ( keys %objtypes ) {
        if ( $key == $upc_id ) {
            return $objtypes{$key};
        }
    }
    return "UNDEFINED";
}

sub getWinkToken {
    my $url = $baseUrl . $getToken;
    my $req = HTTP::Request->new( 'POST', $url );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content($data);
    my $lwp          = LWP::UserAgent->new;
    my $response     = $lwp->request($req);
    my $decoded_json = decode_json( $response->content() );
    if ( $response->is_success ) {
        $refresh_token = $decoded_json->{'data'}{'refresh_token'};
        $access_token  = $decoded_json->{'data'}{'access_token'};
        $token_type    = $decoded_json->{'data'}{'token_type'};
    }
    else {
        $refresh_token = "";
        $access_token  = "";
        $token_type    = "";
    }
}

1;
