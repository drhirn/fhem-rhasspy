###########################################################################
#
# FHEM RHASSPY modul  (https://github.com/rhasspy)
#
# Originally written 2018 by Tobias Wiedenmann (Thyraz)
# as FHEM Snips.ai module (thanks to Matthias Kleine)
#
# Adapted for RHASSPY 2020/2021 by Beta-User and drhirn
#
# Thanks to Beta-User, rudolfkoenig, JensS, cb2sela and all the others
# who did a great job getting this to work!
#
# This file is part of fhem.
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
# 
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###########################################################################
package MQTT::RHASSPY; ##no critic qw(Package)
use strict;
use warnings;
use Carp qw(carp);
use GPUtils qw(:all);
use JSON;
use Encode;
use HttpUtils;
use List::Util qw(max min);
use Data::Dumper;

sub ::RHASSPY_Initialize { goto &RHASSPY_Initialize }

my %gets = (
    version => q{},
    status  => q{}
);

my %sets = (
    speak        => [],
    play         => [],
    updateSlots  => [qw(noArg)],
    textCommand  => [],
    trainRhasspy => [],
    fetchSiteIds => [],
    #reinit       => [qw(language)]
    reinit       => [qw(language devicemap all)]
#    "volume" => ""
);

my $languagevars = {
  'units' => {
      'unitHours' => '(hour|hours)',
      'unitMinutes' => '(minute|minutes)'
   },
  'responses' => { 
    'DefaultError' => "Sorry but something seems not to work as expected",
    'NoValidData' => "Sorry but the received data is not sufficient to derive any action",
    'NoDeviceFound' => "Sorry but I could not find a matching device",
    'NoMappingFound' => "Sorry but I could not find a suitable mapping",
    'NoNewValDerived' => "Sorry but I could not calculate a new value to set",
    'NoActiveMediaDevice' => "Sorry no active playback device",
    'DefaultConfirmation' => "OK",
    'DefaultConfirmationTimeout' => "Sorry too late to confirm",
    'DefaultCancelConfir' => "Thanks aborted",
    'DefaultConfirReceived' => "ok will do it",
    'timerSet'   => 'Timer in room $room has been set to $value $unit',
    'timerEnd'   => {
        '0' => 'Timer expired',
        '1' =>  'Timer in room $room expired'
    },
    'timeRequest' => 'it is $hour o clock $min minutes',
    'weekdayRequest' => 'today it is $weekDay',
    'duration_not_understood'   => "Sorry I could not understand the desired duration",
    'reSpeak_failed'   => 'i am sorry i can not remember',
    'Change' => {
      'airHumidity'  => 'air humidity in $location is $value percent',
      'battery'      => {
        '0' => 'battery level in $location is $value',
        '1' => 'battery level in $location is $value percent'
      },
      'brightness'   => '$device was set to $value',
      'setTarget'    => '$device is set to $value',
      'soilMoisture' => 'soil moisture in $location is $value percent',
      'temperature'  => {
        '0' => 'temperature in $location is $value',
        '1' => 'temperature in $location is $value degrees',
      },
      'volume'  => '$device set to $value',
      'waterLevel'   => 'water level in $location is $value percent',
      'knownType'    => '$mappingType in $location is $value percent',
      'unknownType'  => 'value in $location is $value percent'
    }
  },
  'stateResponses' => {
     'inOperation' => {
       '0' => '$deviceName is ready',
       '1' => '$deviceName is still running'
     },
     'inOut'       => {
       '0' => '$deviceName is out',
       '1' => '$deviceName is in'
     },
     'onOff'       => {
       '0' => '$deviceName is off',
       '1' => '$deviceName is on'
     },
     'openClose'   => {
       '0' => '$deviceName is open',
       '1' => '$deviceName is closed'
     }
  }
};

my $internal_mappings = {
  'Change' => {
    'lightUp' => { 
      'Type' => 'brightness',
      'up'  => '1'
    },
    'lightDown' => { 
      'Type' => 'brightness',
      'up'  => '0'
    },
    'tempUp' => { 
      'Type' => 'temperature',
      'up'  => '1'
    },
    'tempDown' => { 
      'Type' => 'temperature',
      'up'  => '0'
    },
    'volUp' => { 
      'Type' => 'volume',
      'up'  => '1'
    },
    'volDown' => { 
      'Type' => 'volume',
      'up'  => '0'
    },
    'setUp' => { 
      'Type' => 'setTarget',
      'up'  => '1'
    },
    'setDown' => { 
      'Type' => 'setTarget',
      'up'  => '0'
    }
#    'volume' => 'sound volume'
  },
  'regex' => {
    'upward' => '(higher|brighter|louder|rise|warmer)',
    'setTarget' => '(brightness|volume|target.volume)'
  },
  'stateResponseType' => {
    'on'     => 'onOff',
    'off'    => 'onOff',
    'open'   => 'openClose',
    'closed' => 'openClose',
    'in'     => 'inOut',
    'out'    => 'inOut',
    'ready'  => 'inOperation',
    'acting' => 'inOperation'
  }
};

my $de_mappings = {
  'on'      => 'an',
  'percent' => 'Prozent',
  'stateResponseType' => {
    'an'            => 'onOff',
    'aus'           => 'onOff',
    'auf'           => 'openClose',
    'zu'            => 'openClose',
    'eingefahren'   => 'inOut',
    'ausgefahren'   => 'inOut',
    'läuft'         => 'inOperation',
    'fertig'        => 'inOperation'
  },
  'ToEn' => {
    'Temperatur'       => 'temperature',
    'Luftfeuchtigkeit' => 'airHumidity',
    'Batterie'         => 'battery',
    'Wasserstand'      => 'waterLevel',
    'Bodenfeuchte'     => 'soilMoisture',
    'Helligkeit'       => 'brightness',
    'Sollwert'         => 'setTarget',
    'Lautstärke'       => 'volume',
    'kälter' => 'tempDown',
    'wärmer' => 'tempUp',
    'dunkler' => 'lightDown',
    'heller' => 'lightUp',
    'lauter' => 'volUp',
    'leiser' => 'volDown',

  },
  'regex' => {
    'upward' => '(höher|heller|lauter|wärmer)',
    'setTarget' => '(Helligkeit|Lautstärke|Sollwert)'
  }

};

BEGIN {

  GP_Import(qw(
    addToAttrList
    delFromDevAttrList
    readingsSingleUpdate
    readingsBeginUpdate
    readingsBulkUpdate
    readingsEndUpdate
    Log3
    defs
    attr
    cmds
    L
    init_done
    InternalTimer
    RemoveInternalTimer
    AssignIoPort
    IOWrite
    readingFnAttributes
    IsDisabled
    AttrVal
    InternalVal
    ReadingsVal
    devspec2array
    gettimeofday
    toJSON
    setVolume
    AnalyzeCommandChain
    AnalyzeCommand
    EvalSpecials
    AnalyzePerlCommand
    perlSyntaxCheck
    parseParams
    ResolveDateWildcards
    HttpUtils_NonblockingGet
    round
    strftime
    makeReadingName
    ReadingsNum
    FileRead
    trim
    looks_like_number
  ))

};

# MQTT Topics die das Modul automatisch abonniert
my @topics = qw(
    hermes/intent/+
    hermes/dialogueManager/sessionStarted
    hermes/dialogueManager/sessionEnded
);

sub RHASSPY_Initialize {
    my $hash = shift // return;

    # Consumer
    $hash->{DefFn}       = \&RHASSPY_Define;
    $hash->{UndefFn}     = \&RHASSPY_Undefine;
    $hash->{DeleteFn}    = \&RHASSPY_Delete;
    $hash->{SetFn}       = \&RHASSPY_Set;
    $hash->{AttrFn}      = \&RHASSPY_Attr;
    $hash->{AttrList}    = "IODev defaultRoom rhasspyIntents:textField-long shortcuts:textField-long rhasspyMaster response:textField-long forceNEXT:0,1 disable:0,1 disabledForIntervals configFile " . $readingFnAttributes;
    $hash->{Match}       = q{.*};
    $hash->{ParseFn}     = \&RHASSPY_Parse;
    $hash->{parseParams} = 1;

    return;
}

# Device anlegen
sub RHASSPY_Define {
    my $hash = shift;
    my $anon = shift;
    my $h    = shift;
    #parseParams: my ( $hash, $a, $h ) = @_;
    
    #my @args = split("[ \t]+", $def);

    # Minimale Anzahl der nötigen Argumente vorhanden?
    #return "Invalid number of arguments: define <name> RHASSPY DefaultRoom" if (int(@args) < 3);

    my $name = shift @{$anon};
    my $type = shift @{$anon};
    my $defaultRoom = $h->{defaultRoom} // shift @{$anon} // q{RHASSPY}; #Beta-User: extended Perl defined-or
    #) = @args;
    my $language = $h->{language} // shift @{$anon} // lc(AttrVal('global','language','en'));
    $hash->{MODULE_VERSION} = "0.4.4beta";
    $hash->{helper}{defaultRoom} = $defaultRoom;
    initialize_Language($hash, $language) if !defined $hash->{LANGUAGE} || $hash->{LANGUAGE} ne $language;
    $hash->{LANGUAGE} = $language;
    $hash->{devspec} = $h->{devspec} // q{room=Rhasspy};
    $hash->{fhemId} = $h->{fhemId} // q{fhem};
    initialize_prefix($hash, $h->{prefix}) if !defined $hash->{prefix} || $hash->{prefix} ne $h->{prefix};
    $hash->{prefix} = $h->{prefix} // q{rhasspy};
    $hash->{encoding} = $h->{encoding};
    
    #Beta-User: Für's Ändern von defaultRoom oder prefix vielleicht (!?!) hilfreich: https://forum.fhem.de/index.php/topic,119150.msg1135838.html#msg1135838 (Rudi zu resolveAttrRename) 


    # IODev setzen und als MQTT Client registrieren
    #$attr{$name}{IODev} = $IODev;

    return $init_done ? firstInit($hash) : InternalTimer(time+1, \&firstInit, $hash );
}

sub firstInit {
    my $hash = shift // return;
  
    # IO    
    AssignIoPort($hash);
    my $IODev = AttrVal($hash->{NAME},'IODev',undef);

    return if !$init_done || !defined $IODev;

    RemoveInternalTimer($hash);
    
    IOWrite($hash, 'subscriptions', join q{ }, @topics) if InternalVal($IODev,'TYPE',undef) eq 'MQTT2_CLIENT';
    
    RHASSPY_fetchSiteIds($hash) if !ReadingsVal( $hash->{NAME}, 'siteIds', 0 );

    return;
}

sub initialize_Language {
    my $hash = shift // return;
    my $lang = shift // return;
    my $cfg  = shift // AttrVal($hash->{NAME},'configFile',undef);
    
    #my $cp = $hash->{encoding} // q{UTF-8};
    my $cp = q{UTF-8};
    my $lngvars = $languagevars;
    
    #default to english first
    $hash->{helper}{lng} = $lngvars if !$init_done || !defined $hash->{helper}{lng};

    my ($ret, $content) = RHASSPY_readLanguageFromFile($hash, $cfg);
    return $ret if $ret;
    my $decoded;
    if ( !eval { $decoded  = decode_json(encode($cp,$content)) ; 1 } ) {
             
        Log3($hash->{NAME}, 1, "JSON decoding error in languagefile $cfg:  $@");
        return "languagefile $cfg seems not to contain valid JSON!";
    }

    $hash->{helper}{lng} = $decoded;
    return;
}

sub initialize_prefix {
    my $hash   = shift // return;
    my $prefix =  shift // q{rhasspy};
    my $old_prefix = $hash->{prefix}; #Beta-User: Marker, evtl. müssen wir uns was für Umbenennungen überlegen...
    
    # Attribute rhasspyName und rhasspyRoom für andere Devices zur Verfügung abbestellen
    addToAttrList("${prefix}Name");  #rhasspyName
    addToAttrList("${prefix}Room");  #rhasspyRoom
    addToAttrList("${prefix}Mapping:textField-long"); #rhasspyMapping

    return;
}


# Device löschen
sub RHASSPY_Undefine {
    my $hash = shift // return;

    RemoveInternalTimer($hash);

    return;
}

sub RHASSPY_Delete {
    my $hash = shift // return;
    RemoveInternalTimer($hash);

# DELETE POD AFTER TESTS ARE COMPLETED    
=begin comment
    
    #Beta-User: globale Attribute löschen
    for (devspec2array("${prefix}Mapping=.+")) {
        delFromDevAttrList($_,"${prefix}NameMapping:textField-long");
    }
    for (devspec2array("${prefix}Name=.+")) {
        delFromDevAttrList($_,"${prefix}Name");
    }
    for (devspec2array("${prefix}Room=.+")) {
        delFromDevAttrList($_,"${prefix}Room");
    }

=end comment

=cut
    return;
}

# Set Befehl aufgerufen
sub RHASSPY_Set {
    my $hash    = shift;
    my $anon    = shift;
    my $h       = shift;
    #parseParams: my ( $hash, $a, $h ) = @_;
    my $name    = shift @{$anon};
    my $command = shift @{$anon} // q{};
    my @values  = @{$anon};
    return "Unknown argument $command, choose one of " 
    . join(q{ }, map {
        @{$sets{$_}} ? $_
                      .q{:}
                      .join q{,}, @{$sets{$_}} : $_} sort keys %sets)
    if !defined $sets{$command};

    Log3($name, 5, "set $command - value: " . join q{ }, @values);

    
    my $dispatch = {
        updateSlots  => \&RHASSPY_updateSlots,
        trainRhasspy => \&RHASSPY_trainRhasspy,
        fetchSiteIds => \&RHASSPY_fetchSiteIds
    };
    
    return $dispatch->{$command}->($hash) if ref $dispatch->{$command} eq 'CODE';
    
    $values[0] = $h->{text} if ($command eq 'speak' || $command eq 'textCommand' ) && defined $h->{text};
    if ($command eq 'play' ) {
        $values[0] = $h->{siteId} if defined $h->{siteId};
        $values[1] = $h->{path}   if defined $h->{path};
    }

    $dispatch = {
        speak       => \&RHASSPY_speak,
        textCommand => \&RHASSPY_textCommand,
        play        => \&RHASSPY_playWav
    };
    
    return Log3($name, 3, "set $name $command requires at least one argument!") if !@values;
    
    my $params = join q{ }, @values; #error case: playWav => PERL WARNING: Use of uninitialized value within @values in join or string
    $params = $h if defined $h->{text} || defined $h->{path};
    return $dispatch->{$command}->($hash, $params) if ref $dispatch->{$command} eq 'CODE';
    
    if ($command eq 'reinit') {
        if ($values[0] eq 'language') {
            return initialize_Language($hash, $hash->{LANGUAGE});
        }
        if ($values[0] eq 'devicemap') {
            return initialize_devicemap($hash);
        }
        if ($values[0] eq 'all') {
            initialize_Language($hash, $hash->{LANGUAGE});
            return initialize_devicemap($hash);
        }
    }
    
    return;
}

# Attribute setzen / löschen
sub RHASSPY_Attr {
    my $command = shift;
    my $name = shift;
    my $attribute = shift // return;
    my $value = shift;
    my $hash = $defs{$name} // return;

    # IODev Attribut gesetzt
    if ($attribute eq 'IODev') {

        return;
    }
    if ( $attribute eq 'shortcuts' ) {
        for ( keys %{ $hash->{helper}{shortcuts} } ) {
            delete $hash->{helper}{shortcuts}{$_};
        }
        if ($command eq 'set') {
            return RHASSPY_init_shortcuts($hash, $value); 
        } 
    }
    
    if ( $attribute eq 'rhasspyIntents' ) {
        for ( keys %{ $hash->{helper}{custom} } ) {
            delete $hash->{helper}{custom}{$_};
        }
        if ($command eq 'set') {
            return RHASSPY_init_custom_intents($hash, $value); 
        } 
    }
    
    if ( $attribute eq 'configFile' ) {
        if ($command ne 'set') {
            delete $hash->{CONFIGFILE};
            delete $attr{$name}{configFile}; 
            delete $hash->{helper}{lng};
            $value = undef;
        }
        return initialize_Language($hash, $hash->{LANGUAGE}, $value); 
    }
    
    return;
}

sub RHASSPY_init_shortcuts {
    my $hash    = shift // return;
    my $attrVal = shift // return;
    
    my ($intent, $perlcommand, $device, $err );
    for my $line (split m{\n}x, $attrVal) {
        #old syntax
        if ($line !~ m{\A[\s]*i=}x) {
            ($intent, $perlcommand) = split m{=}x, $line, 2;
            $err = perlSyntaxCheck( $perlcommand );
            return "$err in $line" if $err && $init_done;
            $hash->{helper}{shortcuts}{$intent}{perl} = $perlcommand;
            $hash->{helper}{shortcuts}{$intent}{NAME} = $hash->{NAME};
            next;
        } 
        next if !length $line;
        my($unnamed, $named) = parseParams($line); 
        #return "unnamed parameters are not supported! (line: $line)" if ($unnamed) > 1 && $init_done;
        $intent = $named->{i};
        if (defined($named->{f})) {
            $hash->{helper}{shortcuts}{$intent}{fhem} = $named->{f};
        } elsif (defined($named->{p})) {
            $err = perlSyntaxCheck( $perlcommand );
            return "$err in $line" if $err && $init_done;
            $hash->{helper}{shortcuts}{$intent}{perl} = $named->{p};
        } elsif ($init_done) {
            return "Either a fhem or perl command have to be provided!";
        }
        $hash->{helper}{shortcuts}{$intent}{NAME} = $named->{n} if defined $named->{n};
        $hash->{helper}{shortcuts}{$intent}{response} = $named->{r} if defined $named->{r};
        if ( defined $named->{c} ) {
            $hash->{helper}{shortcuts}{$intent}{conf_req} = !looks_like_number($named->{c}) ? $named->{c} : 'default';
            if (defined $named->{ct}) {
                $hash->{helper}{shortcuts}{$intent}{conf_timeout} = looks_like_number($named->{ct}) ? $named->{ct} : 15;
            } else {
                $hash->{helper}{shortcuts}{$intent}{conf_timeout} = looks_like_number($named->{c}) ? $named->{c} : 15;
            }
        }
    }
    return;
}

sub RHASSPY_init_custom_intents {
    my $hash    = shift // return;
    my $attrVal = shift // return;
    
    for my $line (split m{\n}x, $attrVal) {
        next if !length $line;
        #return "invalid line $line" if $line !~ m{(?<intent>[^=]+)\s*=\s*(?<perlcommand>(?<function>([^(]+))\((?<arg>.*)(\))\s*)}x;
        return "invalid line $line" if $line !~ m{ 
            (?<intent>[^=]+)\s*     #string up to  =, w/o ending whitespace 
            =\s*                    #separator = and potential whitespace
            (?<perlcommand>         #identifier
                (?<function>([^(]+))#string up to opening bracket
                \(                  #opening bracket
                (?<arg>.*)(\))\s*)  #everything up to the closing bracket, w/o ending whitespace
                }xms; 
        my $intent = trim($+{intent});
        return "no intent found in $line!" if (!$intent || $intent eq q{}) && $init_done;
        my $function = trim($+{function});
        return "invalid function in line $line" if $function =~ m{\s+}x;
        my $perlcommand = trim($+{perlcommand});
        my $err = perlSyntaxCheck( $perlcommand );
        return "$err in $line" if $err && $init_done;
        
        #$hash->{helper}{custom}{$+{intent}}{perl} = $perlcommand; #Beta-User: delete after testing!
        $hash->{helper}{custom}{$intent}{function} = $function;

        my $args = trim($+{arg});
        my @params;
        for my $ar (split m{,}x, $args) {
           $ar =trim($ar);
           #next if $ar eq q{}; #Beta-User having empty args might be intented...
           push @params, $ar; 
        }

        $hash->{helper}{custom}{$+{intent}}{args} = \@params;
    }
    return;
}


sub initialize_devicemap {
    my $hash = shift // return;
    
    my $devspec = $hash->{devspec};
    delete $hash->{helper}{devicemap};

    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück #Beta-User: ist das so?
    return if (@devices == 1 && $devices[0] eq $devspec);
    
    for (@devices) {
        my $done = _analyze_rhassypAttr($hash, $_);
        _analyze_genDevType($hash, $_) if !$done;
    }
=pod    
    $room = RHASSPY_roomName($hash, $data);
    => $data->{Room} oder defaultRoom 
    
    
    $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        $room oder $name müssen übergeben werden, es werden alle Devices mit passendem rhasspyName auf Übereinstimmung mit $room gecheckt 
        => Hash mit {$room}{rhasspyName}{FHEM-Device-Name}? (done)
    
    $device = RHASSPY_getDeviceByIntentAndType($hash, $room, $intent, $type); 
        erst wird an RHASSPY_getDevicesByIntentAndType() übergeben => 
            mapping wird ermittelt, zurückgegeben werden zwei Listen mit passenden mappings (im $room => @matchesInRoom / außerhalb $room)
        dann wird entweder das erste Device aus @matchesInRoom zurückgegeben, oder ersatzweise erste Device aus dem 2. Array
        
    $device = RHASSPY_getActiveDeviceForIntentAndType($hash, $room, $intent, undef);
        1. RHASSPY_getDevicesByIntentAndType() übergeben (s.o)
        2. erst in $room, dann "outside":
           a) RHASSPY_getMapping (GetOnOff) 
           b) RHASSPY_getOnOffState aus a)
        
    $device = RHASSPY_getDeviceByMediaChannel($hash, $room, $channel);
        1. alle Devices sammeln, 
        2. rausfiltern, was diesen $channel kennt
        3. erster Treffer wird device, es sei denn, es wird was im passenden $room gefunden
            => Hash mit {$channel}{$room}{FHEM-Device-Name}?
    
    $mapping = RHASSPY_getMapping($hash, $device, $intent, $type) if defined $device;
        $type kann ggf. offen bleiben
        => Hash mit {FHEM-Device-Name}{$intent}{$type}?
    
    
    
=cut
    return;
}


sub _analyze_rhassypAttr {
    my $hash   = shift // return;
    my $device = shift // return;
    
    my $prefix = $hash->{prefix};
    my $ret = 1;
    #rhasspyRooms ermitteln
    my @rooms = split m{,}x,AttrVal($device,"${prefix}Room",undef);
    if (!@rooms) {
        $rooms[0] = $hash->{helper}{defaultRoom};
        $ret = 0;
    };

    #rhasspyNames ermitteln
    my @names = split m{,}x, AttrVal($device,"${prefix}Name",undef);
    
    return 0 if !@names && !$ret; #might need review!
    
    for my $dn (@names) {
       for (@rooms) {
           $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$dn} = $device;
       }
    }
    for my $item ("Channels", "Colors") {
        my @rows = split m{\n}x, AttrVal($device, "${prefix}${item}", q{});

        for my $row (@rows) {
            
            my ($key, $val) = split m{=}x, $row, 2;
            next if !$val; 
            for (@rooms) {
                $hash->{helper}{devicemap}{$item}{$_}{$key} = $device;
            }
            $hash->{helper}{devicemap}{devices}{$device}{$item}{$key} = $val;
        }
    }
    
    #Hash mit {FHEM-Device-Name}{$intent}{$type}?
    my $mappingsString = AttrVal($device, "${prefix}Mapping", undef);
    for (split m{\n}x, $mappingsString) {
        my ($key, $val) = split m{:}x, $_, 2;
        #$key = lc($key);
        #$val = lc($val);
        my %currentMapping = RHASSPY_splitMappingString($val);

        # Übersetzen, falls möglich:
        $currentMapping{type} = $de_mappings->{ToEn}->{$currentMapping{type}} // $currentMapping{type};
        $hash->{helper}{devicemap}{devices}{$device}{intents}{$key}->{$currentMapping{type}} = \%currentMapping;
    }
    push @{$hash->{helper}{devicemap}{devices}{$device}{rooms}}, @rooms;

    return 1;
}


sub _analyze_genDevType {
    my $hash   = shift // return;
    my $device = shift // return;
    
    #prerequesite: gdt has to be set!
    my $gdt = AttrVal($device, 'genericDeviceType', undef) // return; 
    
    #additional names?
    my @names = split m{,}x, AttrVal($device,'alexaName',undef);
    push @names, split m{,}x, AttrVal($device,'siriName',undef);
    my $alias = AttrVal($device,'alias',undef);
    push @names, $alias if !@names && $alias;
    push @names, $device if !@names;
    
    #convert to lower case
    for (@names) { $names[$_] = lc; }
    
    my @rooms = split m{,}x,AttrVal($device,'alexaRoom',undef);
    push @rooms, split m{,}x, AttrVal($device,'room',undef);
    $rooms[0] = $hash->{helper}{defaultRoom} if !@rooms;

    #convert to lower case
    for (@rooms) { $rooms[$_] = lc; }

    for my $dn (@names) {
       for (@rooms) {
           $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$dn} = $device;
       }
    }
    
    my $hbmap = AttrVal($device, 'homeBridgeMapping', undef); 
    #{ getAllSets('lampe2') }
    
=pod    
    attr DEVICE genericDeviceType switch
    attr DEVICE genericDeviceType light
    für "brightness":
    attr DEVICE homebridgeMapping Brightness=brightness::brightness,maxValue=100,factor=0.39216,delay=true

    attr DEVICE genericDeviceType blind
    
    attr DEVICE genericDeviceType thermostat
    

    
=cut    
    return;
}


sub RHASSPY_execute {
    my $hash   = shift // return;
    my $device = shift;
    my $cmd    = shift;
    my $value  = shift;
    my $siteId = shift // $hash->{helper}{defaultRoom};
    $siteId = $hash->{helper}{defaultRoom} if $siteId eq 'default';

    # Nutzervariablen setzen
    my %specials = (
         '$DEVICE' => $device,
         '$VALUE'  => $value,
         '$ROOM'   => $siteId
    );

    $cmd  = EvalSpecials($cmd, %specials);

    # CMD ausführen
    return AnalyzePerlCommand( $hash, $cmd );
}

=pod
Beta-User: Vorbereitungen für eventuelle spätere Option, etwas erst nach Bestätigung auszuführen
Ablauf: 

1. in Shortcut wird ein passender intent konfiguriert, dabei kann angegeben werden:
c:15
oder 
c:"Bist du dir wirklich sicher, dass die Festplatte formatiert werden soll?"
ct:20

c: nummerisch ist Zeit in Sekunden, sonst Rückfragetext
ct: Zeit in Sekunden, wenn Rückfragetext angegeben

2. wird der Shortcut ausgelöst, wird der Befehl geparkt (Noch unklar: wo und wie...) und die (default)-Rückfrage zurückgegeben. 
Unklar: Dialog beenden?

3. Es kommt 
a) nicht rechtzeitig eine Rückmeldung => Abbruch und Dialog beenden
b) eine Cancel-Anweisung => Abbruch und Dialog beenden
c) eine Bestätigung => Ausführen des geparkten Befehls, Dialog beenden

Probleme: sessionId ist möglicherweise nicht mehr gültig!
=cut

sub RHASSPY_sleep {
    my $hash   = shift // return;
    my $mode   = shift; #undef => timeout, 1 => cancellation, 
                        #2 => set timer
    my $data   = shift // $hash->{helper}{'.delayed'};
    
    my $response;
    #timeout Case
    if (!defined $mode) {
        RemoveInternalTimer($hash);
        $response = $hash->{helper}{lng}->{responses}->{DefaultConfirmationTimeout};
        RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
        delete $hash->{helper}{'.delayed'};
        return;
    }

    #cancellation Case
    if ( $mode == 1 ) {
        RemoveInternalTimer($hash);
        $response = $hash->{helper}{lng}->{responses}->{DefaultCancelConfir};
        RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
        delete $hash->{helper}{'.delayed'};
        return $hash->{NAME};
    }
    if ( $mode == 2 ) {
        RemoveInternalTimer($hash);
        $hash->{helper}{'.delayed'} = $data;
        $response = $hash->{helper}{shortcuts}{$data->{input}}{conf_req};
        $response = $hash->{helper}{lng}->{responses}->{DefaultConfirReceived} if $response eq 'default';
        
        InternalTimer(time + $hash->{helper}{shortcuts}{$data->{input}}{conf_timeout}, \&RHASSPY_sleep, $hash, 0);

        RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);

        return $hash->{NAME};
    }
    
    return $hash->{NAME};
}

sub RHASSPY_handleIntentConfirmation {
    my $hash = shift // return;
    my $data = shift // return;
    
    RemoveInternalTimer($hash);
    my $data2 = $hash->{helper}{'.delayed'};
    delete $hash->{helper}{'.delayed'};
    
    #Beta-User: most likely we will have to change some fields in $data2 to content from $data
    return RHASSPY_handleIntentShortcuts($hash,$data2,1);
}

#from https://stackoverflow.com/a/43873983, modified...
sub get_unique {
    my $arr    = shift;
    my $sorted = shift; #true if shall be sorted (longest first!)
    
    my %seen;
    
    #method 2 from https://stackoverflow.com/a/43873983
    my @unique = grep {!$seen{$_}++} @{$arr}; #we may need to sort, see https://stackoverflow.com/a/30448251
    
    return if !@unique;

    return @unique if !$sorted;

    my @sorted = sort { length($b) <=> length($a) } @unique;
    #Log3(undef, 5, "get_unique sorted to ".join q{ }, @sorted);
    return @sorted;
}

#small function to replace variables
sub _replace {
    my $hash  = shift // return;
    my $cmd   = shift // return;
    my $hash2 = shift;
    my $self = $hash2->{'$SELF'} // $hash->{NAME};
    my $name = $hash2->{'$NAME'} // $hash->{NAME};
    my $parent = ( caller(1) )[3];
    Log3($hash->{NAME}, 5, "_replace from $parent starting with: $cmd");

    my %specials = (
        '$SELF' => $self,
        '$NAME' => $name
    );
    %specials = (%specials, %{$hash2});
    #@specials{keys %hash2} = values %hash2;
    for my $key (keys %specials) {
        my $val = $specials{$key};
        #$key =~ s{\$}{\\\$}gxms;
        #$cmd =~ s{$key}{$val}gxms
        $cmd =~ s{\Q$key\E}{$val}gxms;
    }
    Log3($hash->{NAME}, 5, "_replace from $parent returns: $cmd");
    return $cmd;
}

#based on compareHashes https://stackoverflow.com/a/56128395
#Beta-User: might be usefull in case we want to allow some kind of default + user-diff logic, especially in language...

sub _combineHashes {
    my ($hash1, $hash2, $parent) = @_;

    for my $key (keys %{$hash1}) {
        if (!exists $hash2->{$key}) {
            next;
        }
        if ( ref $hash1->{$key} eq 'HASH' and ref $hash2->{$key} eq 'HASH' ) {
            _combineHashes($hash1->{$key}, $hash2->{$key}, $key);
        } else { 
            $hash1->{$key} = $hash2->{$key};
        }
    }
    return $hash1;
}
    

# Alle Gerätenamen sammeln
sub RHASSPY_allRhasspyNames {
    my $hash = shift // return;
    #my $devspec = 'room=Rhasspy';
    #return keys %{$hash->{helper}{devicemap}{devices}} if defined $hash->{helper}{devicemap};
    my @devices;
    
    if (defined $hash->{helper}{devicemap}) {
        my $rRooms = $hash->{helper}{devicemap}{rhasspyRooms};
        for my $key (keys %{$rRooms}) {
            push @devices, keys %{$rRooms->{$key}};
        }
        return get_unique(\@devices, 1 );
    }

    my @devs = devspec2array($hash->{devspec});

    my $prefix = $hash->{prefix};

    # Alle RhasspyNames sammeln
    for (@devs) {
        my $attrv = AttrVal($_,"${prefix}Name",undef) // next;
        push @devices, split m{,}x, $attrv;
    }
    return get_unique(\@devices, 1 );
}

# Alle Raumbezeichnungen sammeln
sub RHASSPY_allRhasspyRooms {
    my $hash = shift // return;

    return keys %{$hash->{helper}{devicemap}{rhasspyRooms}} if defined $hash->{helper}{devicemap};

    my @rooms;

    my $prefix = $hash->{prefix};
    # Alle RhasspyNames sammeln
    for (devspec2array($hash->{devspec})) {
        my $attrv = AttrVal($_,"${prefix}Room",undef) // next;
        push @rooms, split m{,}x, $attrv;
    }
    return get_unique(\@rooms, 1 );
}


# Alle Sender sammeln
sub RHASSPY_allRhasspyChannels {
    my $hash = shift // return;
    
    my @channels;
    
    if (defined $hash->{helper}{devicemap}) {
        
        for my $room (keys %{$hash->{helper}{devicemap}{Channels}}) {
            push @channels, keys %{$hash->{helper}{devicemap}{Channels}{$room}}
        }
        return get_unique(\@channels, 1 );
    }

    my $prefix = $hash->{prefix};
    # Alle RhasspyNames sammeln
    for (devspec2array($hash->{devspec})) { 
        my $attrv = AttrVal($_,"${prefix}Channels",undef) // next;
        my @rows = split m{\n}x, $attrv;
        for (@rows) {
            my @tokens = split m{=}x;
            push @channels, shift @tokens;
        }
    }
    return get_unique(\@channels, 1 );
}


# Alle NumericTypes sammeln
sub RHASSPY_allRhasspyTypes {
    my $hash = shift // return;
    my @types;

    if (defined $hash->{helper}{devicemap}) {
        for my $dev (keys %{$hash->{helper}{devicemap}{devices}}) {
            for my $intent (keys %{$hash->{helper}{devicemap}{devices}{$dev}{intents}}) {
                my $type;
                $type = $hash->{helper}{devicemap}{devices}{$dev}{intents}{$intent};
                push @types, keys %{$type} if $intent =~ m{\A[GS]etNumeric}x;
            }
        }
        return get_unique(\@types, 1 );
    }

    #my $devspec = q{room=Rhasspy};
    my @devs = devspec2array($hash->{devspec});

    my $prefix = $hash->{prefix};
    # Alle RhasspyNames sammeln
    for (@devs) {
        my $attrv = AttrVal($_,"${prefix}Mapping",undef) // next;
        my @mappings = split m{\n}x, $attrv;
        for (@mappings) {
            # Nur GetNumeric und SetNumeric verwenden
            next if $_ !~ m{\A[SG]etNumeric}x;
            #$_ =~ s{[SG]etNumeric:}{}x;
            s{[SG]etNumeric:}{}x;
            my %mapping = RHASSPY_splitMappingString($_);

            push @types, $mapping{type} if defined $mapping{type};
        }
    }
    return get_unique(\@types, 1 );
}


# Alle Farben sammeln
sub RHASSPY_allRhasspyColors {
    my $hash = shift // return;
    my @colors;

    if (defined $hash->{helper}{devicemap}) {
        
        for my $room (keys %{$hash->{helper}{devicemap}{Colors}}) {
            push @colors, keys %{$hash->{helper}{devicemap}{Colors}{$room}}
        }
        return get_unique(\@colors, 1 );
    }

    my @devs = devspec2array($hash->{devspec});

    my $prefix = $hash->{prefix};
    # Alle RhasspyNames sammeln
    for(@devs) {
        my $attrv = AttrVal($_,"${prefix}Colors",undef) // next;
        for (split m{\n}x, $attrv) {
            my @tokens = split m{=}x;
            my $color = shift @tokens;
            push @colors, $color;
        }
    }
    return get_unique(\@colors, 1 );
}


# Raum aus gesprochenem Text oder aus siteId verwenden? (siteId "default" durch Attr defaultRoom ersetzen)
sub RHASSPY_roomName {
    my $hash = shift // return;
    my $data = shift // return;

    # Slot "Room" im JSON vorhanden? Sonst Raum des angesprochenen Satelites verwenden
    return $data->{Room} if exists($data->{Room});
    
    my $room = $data->{siteId};
    $room = $hash->{helper}{defaultRoom} if ($room eq 'default' || !(length $room));

    return $room;
}


# Gerät über Raum und Namen suchen.
sub RHASSPY_getDeviceByName {
    my $hash = shift // return;
    my $room = shift; 
    my $name = shift; #either of the two required
    
    return if !$room && !$name;
    
    my $device;
    
    if (defined $hash->{helper}{devicemap}) {
        $device = $hash->{helper}{devicemap}{rhasspyRooms}{$room}{$name};
        #return $device if $device;
        if ($device) {
            Log3($hash->{NAME}, 5, "Device selected (by hash, with room and name): $device");
            return $device ;
        }
        for (keys %{$hash->{helper}{devicemap}{rhasspyRooms}}) {
            $device = $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$name};
            #return $device if $device;
            if ($device) {
                Log3($hash->{NAME}, 5, "Device selected (by hash, using only name): $device");
                return $device ;
            }
        }
        Log3($hash->{NAME}, 1, "No device for >>$name<< found, especially not in room >>$room<< (also not outside)!");
        return;
    }
    my $devspec = $hash->{devspec}; # q{room=Rhasspy};
    my @devices = devspec2array($devspec);

    my $prefix = $hash->{prefix};
    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);

    for (@devices) {
        # 2 Arrays bilden mit Namen und Räumen des Devices
        my @names = split m{,}x, AttrVal($_,"${prefix}Name",q{});
        my $rooms = AttrVal($_, "${prefix}Room", undef);
        #my @rooms = split m{,}x, AttrVal($_,"${prefix}Room",q{});

        # Case Insensitive schauen ob der gesuchte Name (oder besser Name und Raum) in den Arrays vorhanden ist
#        if (grep( /^$name$/i, @names)) {
        my $inRoom = $rooms =~ m{\b$room\b}ix;
        if (grep { m{\A$name\z}ix } @names ) {
            if (!defined($device) || $inRoom) {
                $device = $_;
                last if $inRoom;
            }
        }
    }

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Sammelt Geräte über Raum, Intent und optional Type
sub RHASSPY_getDevicesByIntentAndType {
    my $hash   = shift // return;
    my $room   = shift;
    my $intent = shift;
    my $type   = shift; #Beta-User: any necessary parameters...?
    
    my @matchesInRoom; my @matchesOutsideRoom;
    my $prefix = $hash->{prefix};
    
    if (defined $hash->{helper}{devicemap}) {
        for my $devs (keys %{$hash->{helper}{devicemap}{devices}}) {
            my $mapping = RHASSPY_getMapping($hash, $devs, $intent, $type, 1, 1) // next;
            my $mappingType = $mapping->{type};
            my @rooms = $hash->{helper}{devicemap}{devices}{$devs}{rooms};

            # Geräte sammeln
            if ( !defined $type ) {
                grep { m{\A$room\z}ix } @rooms
                    ? push @matchesInRoom, $devs 
                    : push @matchesOutsideRoom, $devs;
            }
            elsif ( defined $type && $mappingType && $type =~ m{\A$mappingType\z}ix ) {
                grep { m{\A$room\z}ix } @rooms
                ? push @matchesInRoom, $devs
                : push @matchesOutsideRoom, $devs;
            }
        }
        return (\@matchesInRoom, \@matchesOutsideRoom);;
    }
    
    #old method
    my $devspec = $hash->{devspec}; 
    my @devices = devspec2array($hash->{devspec});

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);

    for my $devs (@devices) {
        # Array bilden mit Räumen des Devices
        #my @rooms = split m{,}x, AttrVal($_,"${prefix}Room",undef);
        my $rooms = AttrVal($_, "${prefix}Room", undef);
        # Mapping mit passendem Intent vorhanden?
        my $mapping = RHASSPY_getMapping($hash, $_, $intent, $type, 0, 1) // next;

        my $mappingType = $mapping->{type};

        # Geräte sammeln
        if ( !defined $type ) {
            $rooms =~ m{\b$room\b}ix
                ? push @matchesInRoom, $devs 
                : push @matchesOutsideRoom, $devs;
        }
        elsif ( defined $type && $mappingType && $type =~ m{\A$mappingType\z}ix ) {
            $rooms =~ m{\b$room\b}ix
            ? push @matchesInRoom, $devs
            : push @matchesOutsideRoom, $devs;
        }
    }

    return (\@matchesInRoom, \@matchesOutsideRoom);
}


# Geräte über Raum, Intent und ggf. Type suchen.
sub RHASSPY_getDeviceByIntentAndType {
    my $hash   = shift // return;
    my $room   = shift;
    my $intent = shift;
    my $type   = shift; #Beta-User: any necessary parameters...?

    my $device;

    # Devices sammeln
    my ($matchesInRoom, $matchesOutsideRoom) = RHASSPY_getDevicesByIntentAndType($hash, $room, $intent, $type);

    # Erstes Device im passenden Raum zurückliefern falls vorhanden, sonst erstes Device außerhalb
    #Log3($hash->{NAME}, 4, "Devices in Room $room: ".join q{, }, @{$matchesInRoom});
    #Log3($hash->{NAME}, 4, "Devices outside Room $room: ".join q{, }, @{$matchesOutsideRoom});
    $device = (@{$matchesInRoom}) ? shift @{$matchesInRoom} : shift @{$matchesOutsideRoom};

    Log3($hash->{NAME}, 5, "Device selected: ". $device ? $device : "none");

    return $device;
}


# Eingeschaltetes Gerät mit bestimmten Intent und optional Type suchen
sub RHASSPY_getActiveDeviceForIntentAndType {
    my $hash   = shift // return;
    my $room   = shift;
    my $intent = shift;
    my $type   = shift; #Beta-User: any necessary parameters...?
    
    my $device;
    my ($matchesInRoom, $matchesOutsideRoom) = RHASSPY_getDevicesByIntentAndType($hash, $room, $intent, $type);

    # Anonyme Funktion zum finden des aktiven Geräts
    my $activeDevice = sub ($$) {
        my $subhash = shift;
        my $devices = shift // return;
        my $match;

        for (@{$devices}) {
            my $mapping = RHASSPY_getMapping($subhash, $_, 'GetOnOff', undef, defined $hash->{helper}{devicemap}, 1);
            if (defined $mapping ) {
                # Gerät ein- oder ausgeschaltet?
                my $value = RHASSPY_getOnOffState($subhash, $_, $mapping);
                if ($value) {
                    $match = $_;
                    last;
                }
            }
        }
        return $match;
    };

    # Gerät finden, erst im aktuellen Raum, sonst in den restlichen
    $device = $activeDevice->($hash, $matchesInRoom);
    $device = $activeDevice->($hash, $matchesOutsideRoom) if !defined $device;

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Gerät mit bestimmtem Sender suchen
sub RHASSPY_getDeviceByMediaChannel {
    my $hash    = shift // return;
    my $room    = shift;
    my $channel = shift; #Beta-User: any necessary parameters...?
    
    my $device;
    
    if (defined $hash->{helper}{devicemap}) {
        $device = $hash->{helper}{devicemap}{Channels}{$room}{$channel};
        #return $device if $device;
        if ($device) {
            Log3($hash->{NAME}, 5, "Device selected (by hash, with room and channel): $device");
            return $device ;
        }
        for (sort keys %{$hash->{helper}{devicemap}{Channels}}) {
            $device = $hash->{helper}{devicemap}{Channels}{$_}{$channel};
            #return $device if $device;
            if ($device) {
                Log3($hash->{NAME}, 5, "Device selected (by hash, using only channel): $device");
                return $device ;
            }
        }
        Log3($hash->{NAME}, 1, "No device for >>$channel<< found, especially not in room >>$room<< (also not outside)!");
        return;
    }
    
    my $devspec = $hash->{devspec};
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);
    
    my $prefix = $hash->{prefix};
    for (@devices) {
        my $rooms = AttrVal($_,"${prefix}Room",undef) // next;
                                        
        my $cmd = RHASSPY_getCmd($hash, $_, "${prefix}Channels", $channel, 1) // next;
        
        # Erster Treffer wählen, überschreiben falls besserer Treffer (Raum matched auch) kommt
        my $inRoom = $rooms =~ m{\b$room\b}ix;
        if (!defined $device || $inRoom ) {
            $device = $_;
            last if $inRoom;
        }
    }

    Log3($hash->{NAME}, 5, "Device selected: ". $device ? $device : 'unknown');

    return $device;
}


# Mappings in Key/Value Paare aufteilen
sub RHASSPY_splitMappingString {
    my $mapping = shift // return;
    my @tokens; my $token = q{};
    #my $char, 
    my $lastChar = q{};
    my $bracketLevel = 0;
    my %parsedMapping;

    # String in Kommagetrennte Tokens teilen
    for my $char ( split q{}, $mapping ) {
        if ($char eq q<{> && $lastChar ne '\\') {
            $bracketLevel += 1;
            $token .= $char;
        }
        elsif ($char eq q<}> && $lastChar ne '\\') {
            $bracketLevel -= 1;
            $token .= $char;
        }
        elsif ($char eq ',' && $lastChar ne '\\' && !$bracketLevel) {
            push(@tokens, $token);
            $token = q{};
        }
        else {
            $token .= $char;
        }
        $lastChar = $char;
    }
    push @tokens, $token if length $token;

    # Tokens in Keys/Values trennen
    %parsedMapping = map {split m{=}x, $_, 2} @tokens;

    return %parsedMapping;
}


# rhasspyMapping parsen und gefundene Settings zurückliefern
sub RHASSPY_getMapping { #($$$$;$)
    #my ($hash, $device, $intent, $type, $disableLog) = @_;
    my $hash       = shift // return;
    my $device     = shift // return;
    my $intent     = shift // return;
    my $type       = shift; #Beta-User: seems first three parameters are obligatory...?
    my $fromHash   = shift // 0;
    my $disableLog = shift // 0;
    
    my $matchedMapping;

    if ($fromHash) {
        $matchedMapping = $hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}{type};
        return $matchedMapping if $matchedMapping;
        
        for (sort keys %{$hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}}) {
            #simply pick first item in alphabetical order...
            return $hash->{helper}{devicemap}{devices}{$device}{intents}{$intent}{$_};
        }
    }
    my $prefix = $hash->{prefix};
    my $mappingsString = AttrVal($device, "${prefix}Mapping", undef) // return;

    for (split m{\n}x, $mappingsString) {

        # Nur Mappings vom gesuchten Typ verwenden
        next if $_ !~ qr/^$intent/x;
        $_ =~ s/$intent://x;
        my %currentMapping = RHASSPY_splitMappingString($_);

        # Erstes Mapping vom passenden Intent wählen (unabhängig vom Type), dann ggf. weitersuchen ob noch ein besserer Treffer mit passendem Type kommt
        
        if (!defined $matchedMapping 
            || lc($matchedMapping->{type}) ne lc($type) && lc($currentMapping{type}) eq lc($type)
            || $de_mappings->{ToEn}->{$matchedMapping->{type}} ne $type && $de_mappings->{ToEn}->{$currentMapping{type}} eq $type
            ) {
            $matchedMapping = \%currentMapping;
            #Beta-User: könnte man ergänzen durch den match "vorne" bei Reading, kann aber sein, dass es effektiver geht, wenn wir das künftig sowieso anders machen...

            Log3($hash->{NAME}, 5, "${prefix}Mapping selected: $_") if !$disableLog;
        }
    }
    return $matchedMapping;
}


# Cmd von Attribut mit dem Format value=cmd pro Zeile lesen
sub RHASSPY_getCmd { #($$$$;$)
    my $hash       = shift // return;
    my $device     = shift;
    my $reading    = shift;
    my $key        = shift; #Beta-User: any necessary parameters...?
    my $disableLog = shift // 0;
    #my ($hash, $device, $reading, $key, $disableLog) = @_;

    my $cmd;
    #my $attrString = AttrVal($device, $reading, undef);

    # String in einzelne Mappings teilen
    my @rows = split(m{\n}x, AttrVal($device, $reading, q{}));

    for (@rows) {
        # Nur Zeilen mit gesuchten Identifier verwenden
        next if $_ !~ qr/^$key=/ix;
        $_ =~ s{$key=}{}ix;
        $cmd = $_;

        Log3($hash->{NAME}, 5, "cmd selected: $_") if !$disableLog;
        last;
    }

    return $cmd;
}

# Cmd String im Format 'cmd', 'device:cmd', 'fhemcmd1; fhemcmd2' oder '{<perlcode}' ausführen
sub RHASSPY_runCmd {
    my $hash   = shift // return;
    my $device = shift;
    my $cmd    = shift;
    my $val    = shift; 
    my $siteId = shift // $hash->{helper}{defaultRoom};
    my $error;
    my $returnVal;
    $siteId = $hash->{helper}{defaultRoom} if $siteId eq 'default';

    Log3($hash->{NAME}, 5, "runCmd called with command: $cmd");

    # Perl Command
    if ($cmd =~ m{\A\s*\{.*\}\s*\z}x) { #escaping closing bracket for editor only
        # CMD ausführen
        Log3($hash->{NAME}, 5, "$cmd is a perl command");
        return RHASSPY_execute($hash, $device, $cmd, $val,$siteId);
    }

    # String in Anführungszeichen (mit ReplaceSetMagic)
    if ($cmd =~ m{\A\s*"(?<inner>.*)"\s*\z}x) {
        my $DEVICE = $device;
        my $ROOM   = $siteId;
        my $VALUE  = $val;

        Log3($hash->{NAME}, 5, "$cmd has quotes...");

        # Anführungszeichen entfernen
        $cmd = $+{inner};

        # Variablen ersetzen?
        if ( !eval { $cmd =~ s{(\$\w+)}{$1}eegx; 1 } ) {
            Log3($hash->{NAME}, 1, "$cmd returned Error: $@") 
        };
        # [DEVICE:READING] Einträge ersetzen
        $returnVal = RHASSPY_ReplaceReadingsVal($hash, $cmd);
        # Escapte Kommas wieder durch normale ersetzen
        $returnVal =~ s{\\,}{,}x;
        Log3($hash->{NAME}, 5, "...and is now: $cmd ($returnVal)");
    }
    # FHEM Command oder CommandChain
    elsif (defined $cmds{ (split m{\s+}x, $cmd)[0] }) {
        #my @test = split q{ }, $cmd;
        Log3($hash->{NAME}, 5, "$cmd is a FHEM command");
        $error = AnalyzeCommandChain($hash, $cmd);
        $returnVal = (split m{\s+}x, $cmd)[1];
    }
    # Soll Command auf anderes Device umgelenkt werden?
    elsif ($cmd =~ m{:}x) {
    $cmd   =~ s{:}{ }x;
        $cmd   = qq($cmd $val) if defined($val);
        Log3($hash->{NAME}, 5, "$cmd redirects to another device");
        $error = AnalyzeCommand($hash, "set $cmd");
        $returnVal = (split q{ }, $cmd)[1];
    }
    # Nur normales Cmd angegeben
    else {
        $cmd   = qq($device $cmd);
        $cmd   = qq($cmd $val) if defined $val;
        Log3($hash->{NAME}, 5, "$cmd is a normal command");
        $error = AnalyzeCommand($hash, "set $cmd");
        $returnVal = (split q{ }, $cmd)[1];
    }
    Log3($hash->{NAME}, 1, $_) if defined $error;

    return $returnVal;
}

# Wert über Format 'reading', 'device:reading' oder '{<perlcode}' lesen
sub RHASSPY_getValue {
    my $hash      = shift // return;
    my $device    = shift // return;
    my $getString = shift // return;
    my $val       = shift;
    my $siteId    = shift;
    
    # Perl Command oder in Anführungszeichen? -> Umleiten zu RHASSPY_runCmd
    if ($getString =~ m{\A\s*\{.*\}\s*\z}x || $getString =~ m{\A\s*".*"\s*\z}x) {
        return RHASSPY_runCmd($hash, $device, $getString, $val, $siteId);
    }

    # Soll Reading von einem anderen Device gelesen werden?
    if ($getString =~ m{:}x) {
        $getString =~ s{\[([^]]+)]}{$1}x; #remove brackets
        my @replace = split m{:}x, $getString;
        $device = $replace[0];
        $getString = $replace[1] // $getString;
        return ReadingsVal($device, $getString, 0);
    }

    # If it's only a string without quotes, return string for TTS
    #return ReadingsVal($device, $getString, $getString);
    return ReadingsVal($device, $getString, $getString);
}


# Zustand eines Gerätes über GetOnOff Mapping abfragen
sub RHASSPY_getOnOffState {
    my $hash     = shift // return;
    my $device   = shift // return; 
    my $mapping  = shift // return;
    
    my $valueOn  = $mapping->{valueOn};
    my $valueOff = $mapping->{valueOff};
    my $value    = lc(RHASSPY_getValue($hash, $device, $mapping->{currentVal}));

    # Entscheiden ob $value 0 oder 1 ist
    if ( defined $valueOff ) {
        $value eq lc($valueOff) ? return 0 : return 1;
    } 
    if ( defined $valueOn ) {
        $value eq lc($valueOn) ? return 1 : return 0;
    } 

    # valueOn und valueOff sind nicht angegeben worden, alles außer "off" wird als eine 1 gewertet
    return $value eq 'off' ? 0 : 1;
}


# JSON parsen
sub RHASSPY_parseJSON {
    my $hash = shift;
    my $json = shift // return;
    my $data;
    my $cp = $hash->{encoding} // q{UTF-8};

    # JSON Decode und Fehlerüberprüfung
    my $decoded;  #= eval { decode_json(encode_utf8($json)) };
    if ( !eval { $decoded  = decode_json(encode($cp,$json)) ; 1 } ) {
        return Log3($hash->{NAME}, 1, "JSON decoding error: $@");
    }

    # Standard-Keys auslesen
    ($data->{intent} = $decoded->{intent}{intentName}) =~ s{\A.*.:}{}x if exists $decoded->{intent}{intentName};
    $data->{probability} = $decoded->{intent}{confidenceScore}         if exists $decoded->{intent}{confidenceScore}; #Beta-User: macht diese Abfrage überhaupt Sinn? Ist halt so
    $data->{sessionId} = $decoded->{sessionId}                         if exists $decoded->{sessionId};
    $data->{siteId} = $decoded->{siteId}                               if exists $decoded->{siteId};
    $data->{input} = $decoded->{input}                                 if exists $decoded->{input};
    $data->{rawInput} = $decoded->{rawInput}                           if exists $decoded->{rawInput};


    # Überprüfen ob Slot Array existiert
    if (exists $decoded->{slots}) {
        # Key -> Value Paare aus dem Slot Array ziehen
        for my $slot (@{$decoded->{slots}}) { 
            my $slotName = $slot->{slotName};
            my $slotValue;

            $slotValue = $slot->{value}{value} if exists $slot->{value}{value} && $slot->{value}{value} ne '';#Beta-User: dismiss effectively empty fields
            $slotValue = $slot->{value} if exists $slot->{entity} && $slot->{entity} eq 'rhasspy/duration';

            $data->{$slotName} = $slotValue;
        }
    }

    for (keys %{ $data }) {
        my $value = $data->{$_};
        Log3($hash->{NAME}, 5, "Parsed value: $value for key: $_");
    }

    return $data;
}

# Call von IODev-Dispatch (e.g.MQTT2)
sub RHASSPY_Parse {
    my $iodev = shift // carp q[No IODev provided!] && return;;
    my $msg   = shift // carp q[No message to analyze!] && return;;

    my $ioname = $iodev->{NAME};
    $msg =~ s{\Aautocreate=([^\0]+)\0(.*)\z}{$2}sx;
    my ($cid, $topic, $value) = split m{\0}xms, $msg, 3;
    my @ret=();
    my $forceNext = 0;
    #my $cptopic = $topic;
    #$cptopic =~ m{([^/]+/[^/]+/)}x;
    my $shorttopic = $topic =~ m{([^/]+/[^/]+/)}x ? $1 : return q{[NEXT]};
    
    return q{[NEXT]} if !grep( { m{\A$shorttopic}x } @topics);
    
    my @instances = devspec2array('TYPE=RHASSPY');

    for my $dev (@instances) {
        my $hash = $defs{$dev};
        # Name mit IODev vergleichen
        next if $ioname ne AttrVal($hash->{NAME}, 'IODev', undef);
        next if IsDisabled( $hash->{NAME} );

        Log3($hash,5,"RHASSPY: [$hash->{NAME}] Parse (IO: ${ioname}): Msg: $topic => $value");

        my $fret = RHASSPY_onmessage($hash, $topic, $value);
        next if !defined $fret;
        if( ref $fret eq 'ARRAY' ) {
          push (@ret, @{$fret});
          $forceNext = 1 if AttrVal($hash->{NAME},'forceNEXT',0);
        } else {
          Log3($hash->{NAME},5,"RHASSPY: [$hash->{NAME}] Parse: internal error:  onmessage returned an unexpected value: ".$fret);  
        }
    }
    unshift(@ret, '[NEXT]') if !(@ret) || $forceNext;
    #Log3($iodev, 4, "Parse collected these devices: ". join q{ },@ret);
    return @ret;
}

# Update the readings lastIntentPayload and lastIntentTopic
# after and intent is received
sub RHASSPY_updateLastIntentReadings {
    my $hash  = shift;
    my $topic = shift;
    my $data  = shift // return;
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'lastIntentTopic', $topic);
    readingsBulkUpdate($hash, 'lastIntentPayload', toJSON($data));
    readingsEndUpdate($hash, 1);
    return;
}

# Daten vom MQTT Modul empfangen -> Device und Room ersetzen, dann erneut an NLU übergeben
sub RHASSPY_onmessage {
    my $hash    = shift // return;
    my $topic   = shift // carp q[No topic provided!]   && return;
    my $message = shift // carp q[No message provided!] && return;;
    
    my $data    = RHASSPY_parseJSON($hash, $message);
    my $fhemId  = $hash->{fhemId};

    my $input = $data->{input};
    
    my $device;
    my @updatedList;

    my $type      = $data->{type} // q{text};
    my $sessionId = $data->{sessionId};
    my $siteId    = $data->{siteId};
    my $mute = 0;
    
    if (defined $siteId) {
        my $reading = makeReadingName($siteId);
        $mute = ReadingsNum($hash->{NAME},"mute_$reading",0);
    }
    
    # Hotword Erkennung
    if ($topic =~ m{\Ahermes/dialogueManager}x) {
        my $room = RHASSPY_roomName($hash, $data);

        return if !defined $room;
        my $mutated_vowels = $hash->{helper}{lng}->{mutated_vowels};
        if (defined $mutated_vowels) {
            for (keys %{$mutated_vowels}) {
                $room =~ s{$_}{$mutated_vowels->{$_}}gx;
            }
            #my $keys = join q{|}, keys %{$mutated_vowels};
            #Log3($hash->{NAME}, 5, "mutated_vowels regex is $keys");

            #$room =~ s{($keys)}{$mutated_vowels->{$1}}gx;
        }

        if ( $topic =~ m{sessionStarted}x ) {
            readingsSingleUpdate($hash, "listening_" . makeReadingName($room), 1, 1);
        } elsif ( $topic =~ m{sessionEnded}x ) {
            readingsSingleUpdate($hash, 'listening_' . makeReadingName($room), 0, 1);
        }
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ($topic =~ m{\Ahermes/intent/.*[:_]SetMute}x && defined $siteId) {
        $type = $message =~ m{${fhemId}.textCommand}x ? 'text' : 'voice';
        $data->{requestType} = $type;

        # update Readings
        RHASSPY_updateLastIntentReadings($hash, $topic,$data);
        RHASSPY_handleIntentSetMute($hash, $data);
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ($mute) {
        $data->{requestType} = $message =~ m{${fhemId}.textCommand}x ? 'text' : 'voice';
        RHASSPY_respond($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, q{ });
        #Beta-User: Da fehlt mir der Soll-Ablauf für das "room-listening"-Reading; das wird ja über einen anderen Topic abgewickelt
        return \@updatedList;
    }

    my $command = $data->{input};
    $type = $message =~ m{${fhemId}
.textCommand}x ? 'text' : 'voice';
    $data->{requestType} = $type;
    my $intent = $data->{intent};

    # update Readings
    RHASSPY_updateLastIntentReadings($hash, $topic,$data);

    # Passenden Intent-Handler aufrufen
    my $dispatch = {
        Shortcuts     => \&RHASSPY_handleIntentShortcuts, 
        SetOnOff      => \&RHASSPY_handleIntentSetOnOff, 
        GetOnOff      => \&RHASSPY_handleIntentGetOnOff,
        SetNumeric    => \&RHASSPY_handleIntentSetNumeric,
        GetNumeric    => \&RHASSPY_handleIntentGetNumeric,
        Status        => \&RHASSPY_handleIntentStatus,
        MediaControls => \&RHASSPY_handleIntentMediaControls,
        MediaChannels => \&RHASSPY_handleIntentMediaChannels,
        SetColor      => \&RHASSPY_handleIntentSetColor,
        GetTime       => \&RHASSPY_handleIntentGetTime,
        GetWeekday    => \&RHASSPY_handleIntentGetWeekday,
        SetTimer      => \&RHASSPY_handleIntentSetTimer,
        ReSpeak       => \&RHASSPY_handleIntentReSpeak
    };
    if (ref $dispatch->{$intent} eq 'CODE') {
        $device = $dispatch->{$intent}->($hash, $data);
    } else {
        $device = RHASSPY_handleCustomIntent($hash, $intent, $data);
    }
    #}
    #Beta-User: In welchem Fall kam es dazu, den folgenden Code-Teil anzufahren?
    #else {RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, " ");}
    #Beta-User: return value should be reviewed. If there's an option to return the name of the devices triggered by Rhasspy, then this could be a better option than just RHASSPY's own name.
    
    $device = $device // $hash->{NAME};
    #several devices? 
#    if ($device =~ m{,}x) {
        my @candidates = split m{,}x, $device;
        for (@candidates) {
            push @updatedList, $_ if $defs{$_}; 
        }    
#    } else { 
#        push @updatedList, $device if $defs{$device};
#    }
    return \@updatedList;
}
    

# Antwort ausgeben
sub RHASSPY_respond {
    my $hash      = shift // return;
    my $type      = shift // return;
    my $sessionId = shift // return;
    my $siteId    = shift // return;
    my $response  = shift // return;

    my $sendData =  {
        sessionId => $sessionId,
        siteId => $siteId,
        text => $response
    };

    my $json = toJSON($sendData);

    readingsBeginUpdate($hash);
    $type eq 'voice' ?
        readingsBulkUpdate($hash, 'voiceResponse', $response)
      : readingsBulkUpdate($hash, 'textResponse', $response);
    readingsBulkUpdate($hash, 'responseType', $type);
    readingsEndUpdate($hash,1);
    IOWrite($hash, 'publish', qq{hermes/dialogueManager/endSession $json});
    return;
}


# Antworttexte festlegen
sub RHASSPY_getResponse {
    my $hash = shift;
    my $identifier = shift // return 'Programmfehler, es wurde kein Identifier übergeben' ;

    return RHASSPY_getCmd($hash, $hash->{NAME}, 'response', $identifier) // $hash->{helper}{lng}->{responses}->{$identifier};
}


# Send text command to Rhasspy NLU
sub RHASSPY_textCommand {
    my $hash = shift // return;
    my $text = shift // return;
    
    my $data = {
         input => $text,
         sessionId => "$hash->{fhemId}.textCommand"
    };
    my $message = toJSON($data);

    # Send fake command, so it's forwarded to NLU
    # my $topic2 = "hermes/intent/FHEM:TextCommand";
    my $topic = q{hermes/nlu/query};
    
    return IOWrite($hash, 'publish', qq{$topic $message});
}


# Sprachausgabe / TTS über RHASSPY
sub RHASSPY_speak {
    my $hash = shift;
    my $cmd  = shift;
    
    my $sendData =  {
        id => '0',
        sessionId => '0'
    };
    if (ref $cmd eq 'HASH') {
        $sendData->{siteId} =  $cmd->{siteId};
        $sendData->{text} =  $cmd->{text};
    } else {    
        my $siteId = 'default';
        my $text = $cmd;
        my($unnamedParams, $namedParams) = parseParams($cmd);
    
        if (defined $namedParams->{siteId} && defined $namedParams->{text}) {
            $sendData->{siteId} = $namedParams->{siteId};
            $sendData->{text} = $namedParams->{text};
        }
    }
    my $json = toJSON($sendData);
    return IOWrite($hash, 'publish', qq{hermes/tts/say $json});
}

# Send all devices, rooms, etc. to Rhasspy HTTP-API to update the slots
sub RHASSPY_updateSlots {
    my $hash = shift // return;
    my $language = $hash->{LANGUAGE};
    my $fhemId   = $hash->{fhemId};
    my $method   = q{POST};
    my $contenttype = q{application/json};

    # Collect everything and store it in arrays
    my @devices   = RHASSPY_allRhasspyNames($hash);
    my @rooms     = RHASSPY_allRhasspyRooms($hash);
    my @channels  = RHASSPY_allRhasspyChannels($hash);
    my @colors    = RHASSPY_allRhasspyColors($hash);
    my @types     = RHASSPY_allRhasspyTypes($hash);
    my @shortcuts = keys %{$hash->{helper}{shortcuts}};

                                          
    if (@shortcuts) {
                  
        my $deviceData;
        my $url = q{/api/sentences};
        
        $deviceData =qq({"intents/${language}.${fhemId}.Shortcuts.ini":"[${language}.${fhemId}:Shortcuts]\\n);
        for (@shortcuts)
        {
            $deviceData = $deviceData . ($_) . '\n';
        }
        $deviceData = $deviceData . '"}';
        
        Log3($hash->{NAME}, 5, "Updating Rhasspy Sentences with data: $deviceData");
          
        RHASSPY_sendToApi($hash, $url, $method, $deviceData);
    }

    # If there are any devices, rooms, etc. found, create JSON structure and send it the the API
    if (@devices || @rooms || @channels || @types ) {
      my $json;
      my $deviceData;
      my $url = "/api/slots?overwrite_all=true";

      $deviceData->{qq(${language}.${fhemId}.Device)}        = \@devices if @devices;
      $deviceData->{qq(${language}.${fhemId}.Room)}          = \@rooms if @rooms;
      $deviceData->{qq(${language}.${fhemId}.MediaChannels)} = \@channels if @channels;
      $deviceData->{qq(${language}.${fhemId}.Color)}         = \@colors if @colors;
      $deviceData->{qq(${language}.${fhemId}.NumericType)}   = \@types if @types;

      $json = eval { toJSON($deviceData) };

      Log3($hash->{NAME}, 5, "Updating Rhasspy Slots with data ($language): $json");
      
      RHASSPY_sendToApi($hash, $url, $method, $json);
    }
    return;
}

# Use the HTTP-API to instruct Rhasspy to re-train it's data
sub RHASSPY_trainRhasspy {
    my $hash = shift // return;
    my $url         = q{/api/train};
    my $method      = q{POST};
    my $contenttype = q{application/json};
    
    return RHASSPY_sendToApi($hash, $url, $method, undef);
}

# Use the HTTP-API to fetch all available siteIds
sub RHASSPY_fetchSiteIds {
    my $hash   = shift // return;
    my $url    = q{/api/profile?layers=profile};
    my $method = q{GET};
    
    Log3($hash->{NAME}, 5, "fetchSiteIds called");
    return RHASSPY_sendToApi($hash, $url, $method, undef);
}
    

# Send request to HTTP-API of Rhasspy
sub RHASSPY_sendToApi {
    my $hash   = shift // return;
    my $url    = shift;
    my $method = shift;
    my $data   = shift;
    my $base   = AttrVal($hash->{NAME}, 'rhasspyMaster', undef) // return;

    #Retrieve URL of Rhasspy-Master from attribute
    $url = $base.$url;

    my $apirequest = {
        url        => $url,
        hash       => $hash,
        timeout    => 120,
        method     => $method,
        data       => $data,
        header     => 'Content-Type: application/json',
        callback   => \&RHASSPY_ParseHttpResponse
    };

    HttpUtils_NonblockingGet($apirequest);
    return;
}

# Parse the response of the request to the HTTP-API
sub RHASSPY_ParseHttpResponse {
    my $param = shift // return;
    my $err   = shift;
    my $data  = shift;
    my $hash  = $param->{hash};
    my $url   = lc($param->{url});
    my $name  = $hash->{NAME};
    my $base  = AttrVal($name, 'rhasspyMaster', undef) // return;
    my $cp    = $hash->{encoding} // q{UTF-8};
    
    readingsBeginUpdate($hash);
    my $urls = { 
        $base.'/api/train'     => 'training', 
        $base.'/api/sentences' => 'updateSentences',
        $base.'/api/slots'     => 'updateSlots'
    };

    if ( defined $urls->{$url} ) {
        readingsBulkUpdate($hash, $urls->{$url}, $data);
    }
    elsif ( $url =~ m{api/profile}ix ) {
        my $ref = decode_json($data);
        my $siteIds = encode($cp,$ref->{dialogue}{satellite_site_ids});
        readingsBulkUpdate($hash, 'siteIds', $siteIds);
    }
    else {
        Log3($name, 3, qq(error while requesting $param->{url} - $data));
    }
    
    readingsEndUpdate($hash, 1);
    
    return;
}


# Eingehender Custom-Intent
sub RHASSPY_handleCustomIntent {
    my $hash       = shift // return;
    my $intentName = shift;
    my $data       = shift;
   
    if (!defined $hash->{helper}{custom} || !defined $hash->{helper}{custom}{$intentName}) {
        Log3($hash->{NAME}, 2, "handleIntentShortcuts called with invalid $intentName key");
        return;
    }
    my $custom = $hash->{helper}{custom}{$intentName};
    Log3($hash->{NAME}, 5, "handleCustomIntent called with $intentName key");
   
    my ($intent, $response, $room);

    if (exists $data->{Device} ) {
      $room = RHASSPY_roomName($hash, $data);
      $data->{Device} = RHASSPY_getDeviceByName($hash, $room, $data->{Device}); #Beta-User: really...?
    }

    my $subName = $custom->{function};
    my $params = $custom->{args};
    my @rets = @{$params};

    if (defined $subName) { #might not be necessary...
        for (@rets) {
            if ($_ eq 'NAME') {
                $_ = $hash->{NAME};
            } elsif ($_ eq 'DATA') {
                $_ = $data;
            } elsif (defined $data->{$_}) {
                $_ = $data->{$_};
            }
        }

        my $args = join q{","}, @rets;
        my $cmd = qq{ $subName( "$args" ) };
=pod
attr rhasspy rhasspyIntents GetAllOff=GetAllOff(Room,Type)\
SetAllOff=SetAllOff(Room,Type)\
SetAllOn=SetAllOn(Room,Type)

sub SetAllOn($$){
my ($Raum,$Typ) = @_;
return Log3('rhasspy',3 , "RHASSPY: Raum $Raum, Typ $Typ");
}
=cut
        Log3($hash->{NAME}, 5, "Calling sub: $cmd" );
        my $error = AnalyzePerlCommand($hash, $cmd);
        
        $response = $error; # if $error && $error !~ m{Please.define.*first}x;
     
    }
    $response = $response // RHASSPY_getResponse($hash, 'DefaultConfirmation');

    # Antwort senden
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Handle incoming "SetMute" intents
sub RHASSPY_handleIntentSetMute {
    my $hash = shift // return;
    my $data = shift // return;
    my $response;
    
    Log3($hash->{NAME}, 5, "handleIntentSetMute called");
    
    if (exists $data->{Value} && exists $data->{siteId}) {
        my $siteId = makeReadingName($data->{siteId});
        readingsSingleUpdate($hash, "mute_$siteId", $data->{Value} eq 'on' ? 1 : 0, 1);
        $response = RHASSPY_getResponse($hash, 'DefaultConfirmation');
    }
    $response = $response  // RHASSPY_getResponse($hash, 'DefaultError');
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}

# Handle custom Shortcuts
sub RHASSPY_handleIntentShortcuts {
    my $hash = shift // return;
    my $data = shift // return;
    my $cfdd = shift // 0;
    
    my $shortcut = $hash->{helper}{shortcuts}{$data->{input}};
    Log3($hash->{NAME}, 5, "handleIntentShortcuts called with $data->{input} key");
    
    my $response = $shortcut->{response} // RHASSPY_getResponse($hash, 'DefaultConfirmation');
    my $ret;
    my $device = $shortcut->{NAME};;
    my $cmd    = $shortcut->{perl};
                                 
    my $self   = $hash->{NAME};
    my $name   = $shortcut->{NAME} // $self;
    my %specials = (
         '$DEVICE' => $name,
         '$SELF'   => $self,
         '$NAME'   => $name
        );

    if (defined $cmd) {
        Log3($hash->{NAME}, 5, "Perl shortcut identified: $cmd, device name is $name");

        $cmd  = _replace($hash, $cmd, \%specials);
        #execute Perl command

        $ret = RHASSPY_runCmd($hash, undef, $cmd, undef, $data->{siteId});
        $device = $ret if $ret !~ m{Please.define.*first}x;

        $response = $ret // _replace($hash, $response, \%specials);
    } else {
        $cmd = $shortcut->{fhem} // return;
        Log3($hash->{NAME}, 5, "FHEM shortcut identified: $cmd, device name is $name");
        $cmd      = _replace($hash, $cmd, \%specials);
        $response = _replace($hash, $response, \%specials);
        AnalyzeCommand($hash, $cmd);
    }
    
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    # update Readings
    #RHASSPY_updateLastIntentReadings($hash, $topic,$data);

    return $device;
}

# Handle incoming "SetOnOff" intents
sub RHASSPY_handleIntentSetOnOff {
    my $hash = shift // return;
    my $data = shift // return;
    my $value, my $numericValue, my $device, my $room, my $siteId;
    my $mapping;
    my $response;

    Log3($hash->{NAME}, 5, "handleIntentSetOnOff called");

    # Device AND Value must exist
    if (exists $data->{Device} && exists $data->{Value}) {
        $room = RHASSPY_roomName($hash, $data);
        $value = $data->{Value};
        $value = $value eq $de_mappings->{on} ? 'on' : $value; #Beta-User: compability
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        $mapping = RHASSPY_getMapping($hash, $device, 'SetOnOff', undef, defined $hash->{helper}{devicemap});

        # Mapping found?
        if (defined $device && defined $mapping) {
            my $cmdOn  = $mapping->{cmdOn} // 'on';
            my $cmdOff = $mapping->{cmdOff} // 'off';
            my $cmd = $value eq 'on' ? $cmdOn : $cmdOff;

            # execute Cmd
            RHASSPY_runCmd($hash, $device, $cmd);
            Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );

            # Define response
            if (defined $mapping->{response}) { 
                $numericValue = $value eq 'on' ? 1 : 0;
                $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $numericValue, $room); 
                Log3($hash->{NAME}, 5, "Response is $response" );
            }
            else { $response = RHASSPY_getResponse($hash, 'DefaultConfirmation'); }
        }
    }
    # Send response
    $response = $response  // RHASSPY_getResponse($hash, 'DefaultError');
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Handle incomint GetOnOff intents
sub RHASSPY_handleIntentGetOnOff {
    my $hash = shift // return;
    my $data = shift // return;
    my $device;
    my $response;

    Log3($hash->{NAME}, 5, "handleIntentGetOnOff called");

    # Device AND Status must exist
    if (exists($data->{Device}) && exists($data->{Status})) {
        my $room = RHASSPY_roomName($hash, $data);
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        my $deviceName = $data->{Device};
        my $mapping;
        $mapping = RHASSPY_getMapping($hash, $device, 'GetOnOff', undef, defined $hash->{helper}{devicemap}, 0) if defined $device;
        my $status = $data->{Status};

        # Mapping found?
        if (defined $mapping) {
            # Device on or off?
            my $value = RHASSPY_getOnOffState($hash, $device, $mapping);

            # Define reponse
            if    (defined $mapping->{response}) { 
                $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $value, $room); 
            }
            else {
                my $stateResponseType = $internal_mappings->{stateResponseType}->{$status} // $de_mappings->{stateResponseType}->{$status};
                $response = $hash->{helper}{lng}->{stateResponses}{$stateResponseType}->{$value};
                $response =~ s{(\$\w+)}{$1}eegx;
            }
        }
    }
    # Send response
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


sub isValidData {
    my $data = shift // return 0;
    my $validData = 0;
    
    $validData = 1 if exists $data->{Device} && ( exists $data->{Value} || exists $data->{Change}) #);

    # Mindestens Device und Change angegeben -> Valid (z.B. Radio lauter)
    #|| exists $data->{Device} && exists $data->{Change}
    # Nur Change für Lautstärke angegeben -> Valid (z.B. lauter)
    #|| !exists $data->{Device} && defined $data->{Change} 
    #    && defined $hash->{helper}{lng}->{regex}->{$data->{Change}}
    || !exists $data->{Device} && defined $data->{Change} 
        && (defined $internal_mappings->{Change}->{$data->{Change}} ||defined $de_mappings->{ToEn}->{$data->{Change}})
        #$data->{Change}=  =~ m/^(lauter|leiser)$/i);

    # Nur Type = Lautstärke und Value angegeben -> Valid (z.B. Lautstärke auf 10)
    #||!exists $data->{Device} && defined $data->{Type} && exists $data->{Value} && $data->{Type} =~ 
    #m{\A$hash->{helper}{lng}->{Change}->{regex}->{volume}\z}xim;
    || !exists $data->{Device} && defined $data->{Type} && exists $data->{Value} && ( $data->{Type} eq 'volume' || $data->{Type} eq 'Lautstärke' );

    return $validData;
}

# Eingehende "SetNumeric" Intents bearbeiten
sub RHASSPY_handleIntentSetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $device;
    #my $mapping;
    my $response;

    Log3($hash->{NAME}, 5, "handleIntentSetNumeric called");

    if (!isValidData($data)) {
        return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoValidData'));
    
    }
    
    my $unit   = $data->{Unit};
    my $change = $data->{Change};
    my $type   = $data->{Type}
            # Type not defined? try to derive from Type (en and de)
            // $internal_mappings->{Change}->{$change}->{Type} 
            // $internal_mappings->{Change}->{$de_mappings->{ToEn}->{$change}}->{Type};
    my $value  = $data->{Value};
    my $room   = RHASSPY_roomName($hash, $data);

    # Gerät über Name suchen, oder falls über Lautstärke ohne Device getriggert wurde das ActiveMediaDevice suchen
    if ( exists $data->{Device} ) {
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
    } elsif ( defined $type && ( $type eq 'volume' || $type eq 'Lautstärke' ) ) {
        $device = 
            RHASSPY_getActiveDeviceForIntentAndType($hash, $room, 'SetNumeric', $type) 
                                                                          
            // return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoActiveMediaDevice'));
    }

    if ( !defined $device ) {
        return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoDeviceFound'));
    }
    
    my $mapping = 
        RHASSPY_getMapping($hash, $device, 'SetNumeric', $type, defined $hash->{helper}{devicemap}, 0)
        // return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoMappingFound'));

    # Mapping und Gerät gefunden -> Befehl ausführen
                                                        
    my $cmd     = $mapping->{cmd} // return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoMappingFound'));

    my $part    = $mapping->{part};
    my $minVal  = $mapping->{minVal};
    my $maxVal  = $mapping->{maxVal};
    
    $minVal     =   0 if defined $minVal && !looks_like_number($minVal);
    $maxVal     = 100 if defined $maxVal && !looks_like_number($maxVal);
    my $checkMinMax = defined $minVal && defined $maxVal ? 1 : 0;

    my $diff    = $value // $mapping->{step} // 10;

    #my $up      = (defined($change) && ($change =~ m/^(höher|heller|lauter|wärmer)$/)) ? 1 : 0;
    my $up = $change;
    $up    = $internal_mappings->{Change}->{$change}->{up} 
          // $internal_mappings->{Change}->{$de_mappings->{ToEn}->{$change}}->{up}
          // ($change =~ m{\A$internal_mappings->{regex}->{upward}\z}xi || $change =~ m{\A$de_mappings->{regex}->{upward}\z}xi ) ? 1 
           : 0;

    my $forcePercent = (defined $mapping->{map} && lc($mapping->{map}) eq 'percent') ? 1 : 0;

    # Alten Wert bestimmen
    my $oldVal  = RHASSPY_getValue($hash, $device, $mapping->{currentVal});

    if (defined $part) {
        my @tokens = split m{\s+}x, $oldVal;
        $oldVal = $tokens[$part] if @tokens >= $part;
    }

    # Neuen Wert bestimmen
    my $newVal;
    my $ispct = $unit eq 'percent' || $unit eq $de_mappings->{percent} ? 1 : 0;
    
    if (!defined $change) {
        # Direkter Stellwert ("Stelle Lampe auf 50")
        #if ($unit ne 'Prozent' && defined $value && !defined $change && !$forcePercent) {
        if (!defined $value) {
            #do nothing...
        } elsif (!$ispct && !$forcePercent) {
            $newVal = $value;
        } elsif ( ( $ispct || $forcePercent ) && $checkMinMax ) { 
            # Direkter Stellwert als Prozent ("Stelle Lampe auf 50 Prozent", oder "Stelle Lampe auf 50" bei forcePercent)
            #elsif (defined $value && ( defined $unit && $unit eq 'Prozent' || $forcePercent ) && !defined $change && defined $minVal && defined $maxVal) {

            # Wert von Prozent in Raw-Wert umrechnen
            $newVal = $value;
            #$newVal =   0 if ($newVal <   0);
            #$newVal = 100 if ($newVal > 100);
            $newVal = round((($newVal * (($maxVal - $minVal) / 100)) + $minVal), 0);
        }
    } else { # defined $change
        # Stellwert um Wert x ändern ("Mache Lampe um 20 heller" oder "Mache Lampe heller")
        #elsif ((!defined $unit || $unit ne 'Prozent') && defined $change && !$forcePercent) {
        if ( ( !defined $unit || !$ispct ) && !$forcePercent) {
            $newVal = ($up) ? $oldVal + $diff : $oldVal - $diff;
        }
        # Stellwert um Prozent x ändern ("Mache Lampe um 20 Prozent heller" oder "Mache Lampe um 20 heller" bei forcePercent oder "Mache Lampe heller" bei forcePercent)
        #elsif (($unit eq 'Prozent' || $forcePercent) && defined($change)  && defined $minVal && defined $maxVal) {
        elsif (($ispct || $forcePercent) && $checkMinMax) {
            #$maxVal = 100 if !looks_like_number($maxVal); #Beta-User: Workaround, should be fixed in mapping (tbd)
            #my $diffRaw = round((($diff * (($maxVal - $minVal) / 100)) + $minVal), 0);
            my $diffRaw = round(($diff * ($maxVal - $minVal) / 100), 0);
            $newVal = ($up) ? $oldVal + $diffRaw : $oldVal - $diffRaw;
            $newVal = max( $minVal, min( $maxVal, $newVal ) );
        }
    }

    if (!defined $newVal) {
        return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoNewValDerived'));
    }

    # Begrenzung auf evtl. gesetzte min/max Werte
    $newVal = max( $minVal, $newVal ) if defined $minVal;
    $newVal = min( $maxVal, $newVal ) if defined $maxVal;

    # Cmd ausführen
    RHASSPY_runCmd($hash, $device, $cmd, $newVal);

    # Antwort festlegen
    defined $mapping->{response} 
        ? $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $newVal, $room) 
        : $response = RHASSPY_getResponse($hash, 'DefaultConfirmation'); 

    # Antwort senden
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Eingehende "GetNumeric" Intents bearbeiten
sub RHASSPY_handleIntentGetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $value;
    #my $mapping;
    #my $response; 

    Log3($hash->{NAME}, 5, "handleIntentGetNumeric called");

    # Mindestens Type oder Device muss existieren
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'DefaultError')) if !exists $data->{Type} && !exists $data->{Device};

    my $type = $data->{Type};
    my $room = RHASSPY_roomName($hash, $data);

    # Passendes Gerät suchen
    #if (exists($data->{Device})) {
    #    $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
    #} else {
    #    $device = RHASSPY_getDeviceByIntentAndType($hash, $room, 'GetNumeric', $type);
    #}
    my $device = exists $data->{Device}
        ? RHASSPY_getDeviceByName($hash, $room, $data->{Device})
        : RHASSPY_getDeviceByIntentAndType($hash, $room, 'GetNumeric', $type)
        // return RHASSPY_respond($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoDeviceFound'));

    my $mapping = RHASSPY_getMapping($hash, $device, 'GetNumeric', $type, defined $hash->{helper}{devicemap}, 0) 
        // return RHASSPY_respond($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoMappingFound'));

    # Mapping gefunden
    my $part = $mapping->{part};
    my $minVal  = $mapping->{minVal};
    my $maxVal  = $mapping->{maxVal};
    my $mappingType = $mapping->{type};
    my $forcePercent = defined $mapping->{map} && lc($mapping->{map}) eq 'percent' && defined $minVal && defined $maxVal ? 1 : 0;
    
    # Zurückzuliefernden Wert bestimmen
    $value = RHASSPY_getValue($hash, $device, $mapping->{currentVal});
    if ( defined $part ) {
      my @tokens = split m{\s+}x, $value;
      $value = $tokens[$part] if @tokens >= $part;
    }
    $value = round( ($value * ($maxVal - $minVal) / 100 + $minVal), 0) if $forcePercent;

    my $isNumber = looks_like_number($value);
    # Punkt durch Komma ersetzen in Dezimalzahlen
    $value =~ s{\.}{\,}gx if $hash->{helper}{lng}->{commaconversion};

    my $location = $data->{Device} // $data->{Room};

    # Antwort falls Custom Response definiert ist
    if ( defined $mapping->{response} ) { 
        return RHASSPY_getValue($hash, $device, $mapping->{response}, $value, $location);
    }
    my $responses = $hash->{helper}{lng}->{responses}->{Change};
    #elsif ($mappingType =~ m/^(Helligkeit|Lautstärke|Sollwert)$/i) { $response = $data->{Device} . " ist auf $value gestellt."; }
    #if ($mappingType =~ m{\A$hash->{helper}{lng}->{Change}->{regex}->{setTarget}\z}xim) {

    # Antwort falls mappingType oder type matched
    my $response = 
        $responses->{$mappingType} 
        //  $responses->{$de_mappings->{ToEn}->{$mappingType}} 
        //  $responses->{$type} 
        //  $responses->{$de_mappings->{ToEn}->{$type}}; 
        $response = $response->{$isNumber} if ref $response eq 'HASH';
    #Log3($hash->{NAME}, 3, "#2378: resp is $response, mT is $mappingType");

    # Antwort falls mappingType auf regex (en bzw. de) matched
    if (!defined $response && (
            $mappingType=~ m{\A$internal_mappings->{regex}->{setTarget}\z}xim 
            || $mappingType=~ m{\A$de_mappings->{regex}->{setTarget}\z}xim)) { 
        $response = $responses->{setTarget}; 
        #Log3($hash->{NAME}, 3, "#2384: resp now is $response");
    }
    if (!defined $response) {
                                                          
        defined $mappingType   #or not and at least know the type...
            ? $responses->{knownType}
            : $responses->{unknownType};
    }

    # Variablen ersetzen?
    $response =~ s{(\$\w+)}{$1}eegx;
    # Antwort senden
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "Status" Intents bearbeiten
sub RHASSPY_handleIntentStatus {
    my $hash = shift // return;
    my $data = shift // return;
    my $device = $data->{Device} // return;
    my $response; # = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentStatus called");

    # Mindestens Device muss existieren
    if (exists $data->{Device}) {
        my $room = RHASSPY_roomName($hash, $data);
        $device = RHASSPY_getDeviceByName($hash, $room, $device);
        my $mapping = RHASSPY_getMapping($hash, $device, 'Status', undef, defined $hash->{helper}{devicemap}, 0);

        if ( defined $mapping->{response} ) {
            $response = RHASSPY_getValue($hash, $device, $mapping->{response}, undef, $room);
            $response = RHASSPY_ReplaceReadingsVal($hash, $mapping->{response}) if !$response; #Beta-User: case: plain Text with [device:reading]
        }
    }
    # Antwort senden
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Handle incomint "MediaControls" intents
sub RHASSPY_handleIntentMediaControls {
    my $hash = shift // return;
    my $data = shift // return;
    my $command, my $device, my $room;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentMediaControls called");

    # At least one command has to be received
    if (exists $data->{Command}) {
        $room = RHASSPY_roomName($hash, $data);
        $command = $data->{Command};

        # Search for matching device
        if (exists $data->{Device}) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        } else {
            $device = RHASSPY_getActiveDeviceForIntentAndType($hash, $room, 'MediaControls', undef);
            $response = RHASSPY_getResponse($hash, 'NoActiveMediaDevice') if !defined $device;
        }

        $mapping = RHASSPY_getMapping($hash, $device, 'MediaControls', undef, defined $hash->{helper}{devicemap}, 0);

        if (defined $device && defined $mapping) {
            my $cmd = $mapping->{$command};

            #Beta-User: backwards compability check; might be removed later...
            if (!defined $cmd) {
                my $Media = { 
                    play => 'cmdPlay', pause => 'cmdPause', 
                    stop => 'cmdStop', vor => 'cmdFwd', next => 'cmdFwd',
                    'zurück' => 'cmdBack', previous => 'cmdBack'
                };
                $cmd = $mapping->{ $Media->{$command} };
                Log3($hash->{NAME}, 4, "MediaControls with outdated mapping $command called. Please change to avoid future problems...");
            }

            else {
                # Execute Cmd
                RHASSPY_runCmd($hash, $device, $cmd);
                
                # Define voice response
                $response = defined $mapping->{response} ?
                     RHASSPY_getValue($hash, $device, $mapping->{response}, $command, $room)
                     : RHASSPY_getResponse($hash, 'DefaultConfirmation');
            }
        }
    }
    # Send voice response
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Handle incoming "GetTime" intents
sub RHASSPY_handleIntentGetTime {
    my $hash = shift // return;
    my $data = shift // return;
    Log3($hash->{NAME}, 5, "handleIntentGetTime called");

    (my $sec,my $min,my $hour,my $mday,my $mon,my $year,my $wday,my $yday,my $isdst) = localtime();
    my $response = $hash->{helper}{lng}->{responses}->{timeRequest};
    $response =~ s{(\$\w+)}{$1}eegx;
    Log3($hash->{NAME}, 5, "Response: $response");
    
    # Send voice reponse
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Handle incoming "GetWeekday" intents
sub RHASSPY_handleIntentGetWeekday {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentGetWeekday called");

    my $weekDay  = strftime "%A", localtime;
    my $response = $hash->{helper}{lng}->{responses}->{weekdayRequest};
    $response =~ s{(\$\w+)}{$1}eegx;
    
    Log3($hash->{NAME}, 5, "Response: $response");

    # Send voice reponse
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "MediaChannels" Intents bearbeiten
sub RHASSPY_handleIntentMediaChannels {
    my $hash = shift // return;
    my $data = shift // return;
    my $channel; my $device; my $room;
    my $cmd;
    my $response; # = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentMediaChannels called");

    # Mindestens Channel muss übergeben worden sein
    if ( exists $data->{Channel} ) {
        $room = RHASSPY_roomName($hash, $data);
        $channel = $data->{Channel};

        # Passendes Gerät suchen
        if ( exists $data->{Device} ) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        } else {
            $device = RHASSPY_getDeviceByMediaChannel($hash, $room, $channel);
        }
        
        if (defined $hash->{helper}{devicemap}) {
            $cmd = $hash->{helper}{devicemap}{devices}{$device}{Channels}{$channel};
        }
        else {
            $cmd = RHASSPY_getCmd($hash, $device, 'rhasspyChannels', $channel, undef);
        }
        #$cmd = (split m{=}x, $cmd, 2)[1];

        if ( defined $device && defined $cmd ) {
            $response = RHASSPY_getResponse($hash, 'DefaultConfirmation');
            # Cmd ausführen
            RHASSPY_runCmd($hash, $device, $cmd);
        }
    }

    # Antwort senden
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Handle incoming "SetColor" intents
sub RHASSPY_handleIntentSetColor {
    my $hash = shift // return;
    my $data = shift // return;
    my $color, my $device, my $room;
    my $cmd;
    my $response;

    Log3($hash->{NAME}, 5, "handleIntentSetColor called");

    # At least Device AND Color have to be received
    if (exists $data->{Color} && exists $data->{Device}) {
        $room = RHASSPY_roomName($hash, $data);
        $color = $data->{Color};

        # Search for matching device and command
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        $cmd = RHASSPY_getCmd($hash, $device, 'rhasspyColors', $color, undef);

        if ( defined $device && defined $cmd ) {
            $response = RHASSPY_getResponse($hash, 'DefaultConfirmation');

            # Execute Cmd
            RHASSPY_runCmd($hash, $device, $cmd);
        }
    }
    # Send voice response
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}

# Handle incoming SetTimer intents
sub RHASSPY_handleIntentSetTimer {
    my $hash = shift;
    my $data = shift // return;
    my $siteId = $data->{siteId} // return;
    my $name = $hash->{NAME};
    my $unit, my $value;

    my $response = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($name, 5, 'handleIntentSetTimer called');

    my $room = $data->{Room} // $siteId;
    if ($data->{Value}) {$value = $data->{Value}} else {$response = $hash->{helper}{lng}->{responses}->{duration_not_understood}};
    if ($data->{Unit}) {$unit = $data->{Unit}} else {$response = $hash->{helper}{lng}->{responses}->{duration_not_understood}};
    
    my $siteIds = ReadingsVal( $name, 'siteIds',0);
    RHASSPY_fetchSiteIds($hash) if !$siteIds;

    my $timerRoom = $siteId;

    my $responseEnd = $hash->{helper}{lng}->{responses}->{timerEnd}->{1};

    if ($siteIds =~ m{\b$room\b}ix) {
        $timerRoom = $room if $siteIds =~ m{\b$room\b}ix;
        $responseEnd = $hash->{helper}{lng}->{responses}->{timerEnd}->{0};
    }

    if( $value && $unit && $timerRoom ) {
        my $time = $value;
        my $roomReading = "timer_".makeReadingName($room);
        
        if    (  $unit =~ m{ $hash->{helper}{lng}->{units}->{unitMinutes} }x ) {$time = $value*60}
        elsif ( (  $unit =~ m{ $hash->{helper}{lng}->{units}->{unitHours} }x ) )   {$time = $value*3600};
        
        $time = strftime('%H:%M:%S', gmtime $time);
        
        $responseEnd =~ s{(\$\w+)}{$1}eegx;

        my $cmd = qq(defmod $roomReading at +$time set $name speak siteId=\"$timerRoom\" text=\"$responseEnd\";;setreading $name $roomReading 0);
        
        RHASSPY_runCmd($hash,'',$cmd);

        readingsSingleUpdate($hash, $roomReading, 1, 1);
        
        Log3($name, 5, "Created timer: $cmd");
        
        $response = $hash->{helper}{lng}->{responses}->{timerSet};
        $response =~ s{(\$\w+)}{$1}eegx;
    }

    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $name;
}

sub RHASSPY_handleIntentReSpeak {
    my $hash = shift // return;
    my $data = shift // return;
    my $name = $hash->{NAME};
    
    my $response = ReadingsVal($name,"voiceResponse",$hash->{helper}{lng}->{responses}->{reSpeak_failed});
    
    Log3($hash->{NAME}, 5, 'handleIntentReSpeak called');
    
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    
    return;
}

sub RHASSPY_playWav {
    my $hash = shift //return;
    my $cmd = shift;
    
    Log3($hash->{NAME}, 5, "action playWav called");
    
    if (defined($cmd->{siteId}) && defined($cmd->{path})) {
        my $siteId = $cmd->{siteId};
        my $filename = $cmd->{path};
        my $encoding = q{:raw :bytes};
        my $handle   = undef;
        my $topic = "hermes/audioServer/$siteId/playBytes/999";

        Log3($hash->{NAME}, 3, "Playing file $filename on $siteId");

        if (-e $filename) {
            open($handle, "< $encoding", $filename)
                || carp "$0: can't open $filename for reading: $!";

            while (read($handle,my $file_contents,1000000) ) { 
                IOWrite($hash, 'publish', qq{$topic $file_contents});
            }

            close($handle);
        }
    }
    return;
}

# Abgespeckte Kopie von ReplaceSetMagic aus fhem.pl
sub RHASSPY_ReplaceReadingsVal {
    my $hash = shift;
    my $arr  = shift // return;
    my $to_analyze = $arr;

    my $readingsVal = sub ($$$$$) {
        my $all = shift;
        my $t = shift;
        my $d = shift;
        my $n = shift;
        my $s = shift;
        my $val;
        my $dhash = $defs{$d};
        return $all if(!$dhash);

        if(!$t || $t eq 'r:') {
            my $r = $dhash->{READINGS};
            if($s && ($s eq ':t' || $s eq ':sec')) {
                return $all if (!$r || !$r->{$n});
                $val = $r->{$n}{TIME};
                $val = int(gettimeofday()) - time_str2num($val) if($s eq ':sec');
                return $val;
            }
            $val = $r->{$n}{VAL} if($r && $r->{$n});
        }
        $val = $dhash->{$n}  if(!defined $val && (!$t || $t eq 'i:'));
        $val = $attr{$d}{$n} if(!defined $val && (!$t || $t eq 'a:') && $attr{$d});
        return $all if !defined $val;

        if($s && $s =~ m{:d|:r|:i}x && $val =~ m{(-?\d+(\.\d+)?)}x) {
            $val = $1;
            $val = int($val) if $s eq ':i';
            $val = round($val, defined $1 ? $1 : 1) if $s =~ m{\A:r(\d)?}x;
        }
        return $val;
    };

    $to_analyze =~s{(\[([ari]:)?([a-zA-Z\d._]+):([a-zA-Z\d._\/-]+)(:(t|sec|i|d|r|r\d))?\])}{$readingsVal->($1,$2,$3,$4,$5)}egx;
    return $to_analyze;
}

sub RHASSPY_getDataFile {
    my $hash     = shift // return;
    my $filename = shift;
    
    my $name = $hash->{NAME};
    my $lang = $hash->{LANGUAGE};
    $filename = $filename // AttrVal($name,'configFile',undef);
    my @t = localtime gettimeofday();
    $filename = ResolveDateWildcards($filename, @t);
    $hash->{CONFIGFILE} = $filename; # for configDB migration
    return $filename;
}

sub RHASSPY_readLanguageFromFile {
    my $hash = shift // return;
    my $cfg  = shift // return 0, toJSON($languagevars);
    
    my $name = $hash->{NAME};
    my $filename = RHASSPY_getDataFile($hash, $cfg);
    Log3($name, 5, "trying to read language from $filename");
    my ($ret, @content) = FileRead($filename);
    if ($ret) {
        Log3($name, 1, "$name failed to read configFile $filename!") ;
        return $ret, undef;
    }
    my @cleaned = grep { $_ !~ m{\A\s*[#]}x } @content;

    return 0, join q{ }, @cleaned;
}

1;

__END__

=pod
=encoding utf8
=item device
=item summary Control FHEM with Rhasspy voice assistant
=item summary_DE Steuerung von FHEM mittels Rhasspy Sprach-Assistent
=begin html

<a name="RHASSPY"></a>
<h3>RHASSPY</h3>
<ul>
<p>This module receives, processes and executes voice commands coming from Rhasspy voice assistent.</p>
<a name="RHASSPYdefine"></a>
<p><b>Define</b></p>
<p><code>define &lt;name&gt; RHASSPY &lt;devspec&gt; &lt;defaultRoom&gt; &lt;language&gt;</code></p>
<ul>
  <li><b>devspec</b>: A description of devices that should be controlled by Rhasspy. Optional. Default is <code>devspec=room=Rhasspy</code></li>
  <li><b>defaultRoom</b>: Default room name. Used to speak commands without a room name (e.g. &quot;turn lights on&quot; to turn on the lights in the &quot;default room&quot;). Optional. Default is <code>defaultRoom=default</code></li>
  <li><b>language</b>: The language voice commands are spoken with. Optional. Default is derived from global, which defaults to <code>language=en</code></li>
</ul>
<p>Before defining RHASSPY an MQTT2_CLIENT device has to be created which connects to the same MQTT-Server the voice assistant connects to.</p>
<p>Example for defining an MQTT2_CLIENT device and the Rhasspy device in FHEM:</p>
<p>
  <code><pre>defmod rhasspyMQTT2 MQTT2_CLIENT rhasspy:12183
attr rhasspyMQTT2 clientOrder RHASSPY MQTT_GENERIC_BRIDGE MQTT2_DEVICE
attr rhasspyMQTT2 subscriptions hermes/intent/+ hermes/dialogueManager/sessionStarted hermes/dialogueManager/sessionEnded</pre></code><br>
  <code>define Rhasspy RHASSPY devspec=room=Rhasspy defaultRoom=Livingroom language=en</code>
</p>
<a name="RHASSPYset"></a>
<p><b>Set</b></p>
<ul>
  <li>
    <b>play</b><br>
    Send WAV file to Rhasspy.<br>
    <b>Not fully implemented yet</b><br>
    Both arguments (siteId and path) are required!<br>
    Example: <code>set &lt;rhasspyDevice&gt play siteId="default" path="/opt/fhem/test.wav"</code>
  </li>
  <li>
    <b>reinit</b>
    Reinitialization of language file.<br>
    Be sure to execute this command after changing something in the language-configuration files or the attribut <i>configFile</i>!<br>
    Example: <code>set &lt;rhasspyDevice&gt reinit language</code>
  </li>
  <li>
    <b>speak</b><br>
    Voice output over TTS.<br>
    Both arguments (siteId and text) are required!<br>
    Example: <code>set &lt;rhasspyDevice&gt speak siteId="default" text="This is a test"</code>
  </li>
  <li>
    <b>textCommand</b><br>
    Send a text command to Rhasspy.<br>
    Example: <code>set &lt;rhasspyDevice&gt textCommand turn the light on</code>
  </li>
  <li>
    <b>trainRhasspy</b><br>
    Sends a train-command to the HTTP-API of the Rhasspy master.<br>
    The attribute <i>rhasspyMaster</i> has to be defined to work.<br>
    Example: <code>set &lt;rhasspyDevice&gt; trainRhasspy</code>
  </li>
  <li>
    <b>updateSlots</b><br>
    Sends a command to the HTTP-API of the Rhasspy master to update all slots on Rhasspy with actual FHEM-devices, rooms, etc.<br>
    The attribute <i>rhasspyMaster</i> has to be defined to work.<br>
    Example: <code>set &lt;rhasspyDevice&gt; updateSlots</code><br>
    Do not forget to train Rhasspy afterwards!
  </li>
</ul>
<a name="RHASSPYattr"></a>
<p><b>Attributes</b></p>
<ul>
  <li>
    <b>rhasspyMaster</b><br>
    Defines the URL to the Rhasspy Master for sending requests to the HTTP-API. Has to be in Format <code>protocol://fqdn:port</code>
    This attribute is <b>mandatory</b>!<br>
    Example: <code>attr &lt;rhasspyDevice&gt; rhasspyMaster http://rhasspy.example.com:12101</code>
  </li>
  <li>
    <b>configFile</b>
    Path to the language-config file. If this attribute isn't set, english is used as for voice responses.<br>
    Example: <code>attr &lt;rhasspyDevice&gt; configFile /opt/fhem/.config/rhasspy/rhasspy-de.cfg</code>
  </li>
  <li>
    <b>response</b><br>
    Optionally define alternative default answers. Available keywords are <code>DefaultError</code>, <code>NoActiveMediaDevice</code> and <code>DefaultConfirmation</code>.<br>
    Example:
    <pre><code>DefaultError=
DefaultConfirmation=Klaro, mach ich</code></pre>
  </li>
  <li>
    <b>rhasspyIntents</b><br>
    Optionally defines custom intents. See <a href="https://github.com/Thyraz/Snips-Fhem#f%C3%BCr-fortgeschrittene-eigene-custom-intents-erstellen-und-in-fhem-darauf-reagieren" hreflang="de">Custom Intent erstellen</a>.<br>
    One intent per line.<br>
    Example: <code>attr &lt;rhasspyDevice&gt; rhasspyIntents Respeak=Respeak()</code>
  </li>
  <li>
    <b>shortcuts</b><br>
    Define custom sentences without editing Rhasspy sentences.ini<br>
    The shortcuts are uploaded to Rhasspy when using the updateSlots set-command.<br>
    One shortcut per line.<br>
    Example:<pre><code>mute on=set receiver mute on
mute off=set receiver mute off</code></pre>
  </li>
  <li>
    <b>forceNEXT</b><br>
    If set to 1, RHASSPY will forward incoming messages also to further MQTT2-IO-client modules like MQTT2_DEVICE, even if the topic matches to one of it's own subscriptions. By default, these messages will not be forwarded for better compability with autocreate feature on MQTT2_DEVICE. See also <a href="#MQTT2_CLIENTclientOrder">clientOrder attribute in MQTT2 IO-type commandrefs</a>; setting this in one instance of RHASSPY might affect others, too.
  </li>
</ul>
<p>&nbsp;</p>
<p><b>Additionals remarks on MQTT2-IOs:</b></p>
<p>Using a separate MQTT server (and not the internal MQTT2_SERVER) is highly recommended, as the Rhasspy scripts also use the MQTT protocol for internal (sound!) data transfers. Best way is to either use MQTT2_CLIENT (see below) or bridge only the relevant topics from mosquitto to MQTT2_SERVER (see e.g. <a href="http://www.steves-internet-guide.com/mosquitto-bridge-configuration/">http://www.steves-internet-guide.com/mosquitto-bridge-configuration</a> for the principles). When using MQTT2_CLIENT, it's necessary to set <code>clientOrder</code> to include RHASSPY (as most likely, it's the only module listening to the CLIENT). It could be just set to <pre><code>attr <m2client> clientOrder RHASSPY</code></pre></p>
<p>Furthermore, you are highly encouraged to restrict subscriptions only to the relevant topics: <pre><code>attr <m2client> subscriptions setByTheProgram</code></pre></p>
<p>In case you are using the MQTT server also for other purposes than Rhasspy, you have to set <code>subscriptions</code> manually to at least include the following topics additionally to the other subscriptions desired for other purposes.<pre><code>hermes/intent/+
hermes/dialogueManager/sessionStarted
hermes/dialogueManager/sessionEnded</code></pre></p>
</ul>
<p>&nbsp;</p>
<p><b>ToDo</b></p>
<ul>
<li>Status: &quot;[Device:Reading]&quot; isn't recognized</li>
<li>MediaChannels <code>RHASSPY_getCmd($hash, $device, 'rhasspyChannels', $channel, undef);</code> stays undef</li>
<li>Add Shortcuts to README (<a href="https://forum.fhem.de/index.php/topic,118926.msg1136115.html#msg1136115">https://forum.fhem.de/index.php/topic,118926.msg1136115.html#msg1136115</a>) (drhirn)</li>
<li>Shortcuts: &quot;Longpoll&quot; only works when &quot;n&quot; is given. Perl-Code does never &quot;longpoll&quot;</li>
<li>GetNumeric: Answer "already at max/min" if minVal or maxVal is reached</li>
<li><s>getValue doesn't work with device/reading (e.g. [lampe1:volume])</s></li>
<li><s>SetTimer: $hash->{siteIds} leer beim Start von FHEM: <code>PERL WARNING: Use of uninitialized value in split at ./FHEM/10_RHASSPY.pm line 2194.</code></s></li>
<li><s>Dialogue Session wird nicht beendet, wenn SetMute = 1; Reading listening_$roomReading wird nicht 0. Weil das in onmessage nicht zurück gesetzt wird.</s></li>
<li><s>Shortcuts always returning Default-Error but commands are executed. #Beta-User: solved by changing default in line 1630 to DefaultConfirmation?</s></li>
<li><s>Zeile 1571 u. 1572 (<code>my @params = map { $data->{$_} } @paramNames; my $params = join q{,}, @params;</code>)<br><code>PERL WARNING: Hexadecimal number > 0xffffffff non-portable at (eval 931) line 1</code>#Beta-User: solved by code refactoring?</s></li>
<li><s>Response-Mappings werden nicht gesprochen</s></li>
<li><s>playWav: <code>PERL WARNING: Use of uninitialized value within @values in join or string at ./FHEM/10_RHASSPY.pm line 414.</code> #Beta-User: strange behaviour, as code should return in case no arg is provided... pls. provide typical call of this function<br><code>set Rhasspy play siteId="wohnzimmer" path="/opt/fhem/test.wav"</code></s></li>
<li><s>SetNumeric/SetColor don't change readings of FHEM-Device (&quote;longpoll&quote;) #Beta-User: solved by returning $device?</s></li>
<li><s>getValue doesn't work with device/reading (e.g. [lampe1:volume])</s></li>
</ul>

=end html
=cut