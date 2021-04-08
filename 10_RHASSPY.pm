# $Id$
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
use List::Util 1.45 qw(max min any uniq);
use Data::Dumper;

sub ::RHASSPY_Initialize { goto &RHASSPY_Initialize }

#Beta-User: no GefFn defined...?
my %gets = (
    version => q{},
    status  => q{}
);

my %sets = (
    speak        => [],
    play         => [],
    customSlot   => [],
    textCommand  => [],
    trainRhasspy => [qw(noArg)],
    fetchSiteIds => [qw(noArg)],
    update       => [qw(devicemap devicemap_only slots slots_no_training language all)],
    volume       => []
);

my $languagevars = {
  'units' => {
      'unitHours' => {
          0    => 'hours',
          1    => 'one hour'
      },
      'unitMinutes' => {
          0    => 'minutes',
          1    => 'one minute'
      },
      'unitSeconds' => {
          0    => 'seconds',
          1    => 'one second'
      }
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
    'DefaultCancelConfirmation' => "Thanks aborted",
    'DefaultConfirmationReceived' => "ok will do it",
    'DefaultConfirmationNoOutstanding' => "no command is awaiting confirmation",
    'timerSet'   => {
        '0' => 'Timer $label in room $room has been set to $seconds seconds',
        '1' => 'Timer $label in room $room has been set to $minutes minutes $seconds',
        '2' => 'Timer $label in room $room has been set to $minutes minutes',
        '3' => 'Timer $label in room $room has been set to $hours hours $minutetext',
        '4' => 'Timer $label in room $room has been set to $hour o clock $minutes',
        '5' => 'Timer $label in room $room has been set to tomorrow $hour o clock $minutes'
    },
    'timerEnd'   => {
        '0' => 'Timer $label expired',
        '1' =>  'Timer $label in room $room expired'
    },
    'timerCancellation' => 'timer $label for $room deleted',
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
    DAYSECONDS
    HOURSECONDS
    MINUTESECONDS
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
    ReadingsNum
    devspec2array
    gettimeofday
    toJSON
    setVolume
    AnalyzeCommandChain
    AnalyzeCommand
    CommandDefMod
    CommandDelete
    EvalSpecials
    AnalyzePerlCommand
    perlSyntaxCheck
    parseParams
    ResolveDateWildcards
    HttpUtils_NonblockingGet
    round
    strftime
    makeReadingName
    FileRead
    trim
    looks_like_number
    getAllSets
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
    $hash->{AttrList}    = "IODev defaultRoom rhasspyIntents:textField-long shortcuts:textField-long rhasspyTweaks:textField-long rhasspyMaster response:textField-long forceNEXT:0,1 disable:0,1 disabledForIntervals configFile " . $readingFnAttributes;
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
    
    # Minimale Anzahl der nötigen Argumente vorhanden?
    #return "Invalid number of arguments: define <name> RHASSPY DefaultRoom" if (int(@args) < 3);

    my $name = shift @{$anon};
    my $type = shift @{$anon};
    my $Rhasspy  = $h->{WebIF} // shift @{$anon} // q{http://127.0.0.1:12101};
    my $defaultRoom = $h->{defaultRoom} // shift @{$anon} // q{default}; 
    my $language = $h->{language} // shift @{$anon} // lc(AttrVal('global','language','en'));
    $hash->{MODULE_VERSION} = "0.4.7a";
    $hash->{WebIF} = $Rhasspy;
    $hash->{helper}{defaultRoom} = $defaultRoom;
    initialize_Language($hash, $language) if !defined $hash->{LANGUAGE} || $hash->{LANGUAGE} ne $language;
    $hash->{LANGUAGE} = $language;
    $hash->{devspec} = $h->{devspec} // q{room=Rhasspy};
    $hash->{fhemId} = $h->{fhemId} // q{fhem};
    initialize_prefix($hash, $h->{prefix}) if !defined $hash->{prefix} || $hash->{prefix} ne $h->{prefix};
    $hash->{prefix} = $h->{prefix} // q{rhasspy};
    $hash->{encoding} = $h->{encoding};
    $hash->{useGenericAttrs} = $h->{useGenericAttrs};
    $hash->{'.asyncQueue'} = [];
    #Beta-User: Für's Ändern von defaultRoom oder prefix vielleicht (!?!) hilfreich: https://forum.fhem.de/index.php/topic,119150.msg1135838.html#msg1135838 (Rudi zu resolveAttrRename) 

    if ($hash->{useGenericAttrs}) {
        addToAttrList(q{genericDeviceType});
        #addToAttrList(q{homebridgeMapping});
    }

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
    initialize_rhasspyTweaks($hash);
    initialize_DialogManager($hash);
    initialize_devicemap($hash); # if defined $hash->{useHash};

    return;
}

sub initialize_Language {
    my $hash = shift // return;
    my $lang = shift // return;
    my $cfg  = shift // AttrVal($hash->{NAME},'configFile',undef);
    
                                            
    my $cp = q{UTF-8};
                                
    
    #default to english first
    $hash->{helper}->{lng} = $languagevars if !defined $hash->{helper}->{lng} || !$init_done;

    my ($ret, $content) = RHASSPY_readLanguageFromFile($hash, $cfg);
    return $ret if $ret;

    my $decoded;
    if ( !eval { $decoded  = decode_json(encode($cp,$content)) ; 1 } ) {
             
        Log3($hash->{NAME}, 1, "JSON decoding error in languagefile $cfg:  $@");
        return "languagefile $cfg seems not to contain valid JSON!";
    }
    
    if ( defined $decoded->{default} ) {
        $decoded = _combineHashes( $decoded->{default}, $decoded->{user} );
        Log3($hash->{NAME}, 4, "try to use user specific sentences and defaults in languagefile $cfg");
    }

    #$hash->{helper}{lng} = $decoded;
    #my $lng = $hash->{helper}->{lng};
    #my $lngvars = _combineHashes( $lng, $decoded);
    $hash->{helper}->{lng} = _combineHashes( $hash->{helper}->{lng}, $decoded);

    return;
}

sub initialize_prefix {
    my $hash   = shift // return;
    my $prefix =  shift // q{rhasspy};
    my $old_prefix = $hash->{prefix}; #Beta-User: Marker, evtl. müssen wir uns was für Umbenennungen überlegen...
    
    # provide attributes "rhasspyName" etc. for all devices
    addToAttrList("${prefix}Name");
    addToAttrList("${prefix}Room");
    addToAttrList("${prefix}Mapping:textField-long");
    addToAttrList("${prefix}Channels:textField-long");
    addToAttrList("${prefix}Colors:textField-long");
    addToAttrList("${prefix}Group:textField-long");
    addToAttrList("${prefix}Specials:textField-long");

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
        delFromDevAttrList($_,"${prefix}Mapping:textField-long");
    }
    for (devspec2array("${prefix}Name=.+")) {
        delFromDevAttrList($_,"${prefix}Name");
    }
    for (devspec2array("${prefix}Room=.+")) {
        delFromDevAttrList($_,"${prefix}Room");
    }
    for (devspec2array("${prefix}Channels=.+")) {
        delFromDevAttrList($_,"${prefix}Channels");
    }
    for (devspec2array("${prefix}Colors=.+")) {
        delFromDevAttrList($_,"${prefix}Colors");
    }
    for (devspec2array("${prefix}Specials=.+")) {
        delFromDevAttrList($_,"${prefix}Specials");
    }
    for (devspec2array("${prefix}Group=.+")) {
        delFromDevAttrList($_,"${prefix}Group");
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
    
    $values[0] = $h->{text} if ( $command eq 'speak' || $command eq 'textCommand' ) && defined $h->{text};
    
    if ( $command eq 'play' || $command eq 'volume' ) {
        $values[0] = $h->{siteId} if defined $h->{siteId};
        $values[1] = $h->{path}   if defined $h->{path};
        $values[1] = $h->{volume} if defined $h->{volume};
    }

    $dispatch = {
        speak       => \&RHASSPY_speak,
        textCommand => \&RHASSPY_textCommand,
        play        => \&RHASSPY_playWav,
        volume      => \&RHASSPY_setVolume
    };
    
    return Log3($name, 3, "set $name $command requires at least one argument!") if !@values;
    
    my $params = join q{ }, @values; #error case: playWav => PERL WARNING: Use of uninitialized value within @values in join or string
    $params = $h if defined $h->{text} || defined $h->{path} || defined $h->{volume};
    return $dispatch->{$command}->($hash, $params) if ref $dispatch->{$command} eq 'CODE';
    
    if ($command eq 'update') {
        if ($values[0] eq 'language') {
            return initialize_Language($hash, $hash->{LANGUAGE});
        }
        if ($values[0] eq 'devicemap') {
            initialize_devicemap($hash);
            RHASSPY_updateSlots($hash);
            return RHASSPY_trainRhasspy($hash);
        }
        if ($values[0] eq 'devicemap_only') {
            return initialize_devicemap($hash);
        }
        if ($values[0] eq 'slots') {
            RHASSPY_updateSlots($hash);
            return RHASSPY_trainRhasspy($hash);
        }
        if ($values[0] eq 'slots_no_training') {
            initialize_devicemap($hash);
            return RHASSPY_updateSlots($hash);
        }
        if ($values[0] eq 'all') {
            initialize_Language($hash, $hash->{LANGUAGE});
            initialize_devicemap($hash);
            RHASSPY_updateSlots($hash);
            return RHASSPY_trainRhasspy($hash);
        }
    }
    if ($command eq 'customSlot') {
        my $slotname = $h->{slotname}  // shift @values;
        my $slotdata = $h->{slotdata}  // shift @values;
        my $overwr   = $h->{overwrite} // shift @values;
        my $training = $h->{training}  // shift @values;
        return RHASSPY_updateSingleSlot($hash, $slotname, $slotdata, $overwr, $training);
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

sub initialize_rhasspyTweaks {
    my $hash    = shift // return;
    
    return;
}

sub initialize_DialogManager {
    my $hash    = shift // return;
    my $language = $hash->{LANGUAGE};
    my $fhemId   = $hash->{fhemId};
    
=pod    disable some intents by default https://rhasspy.readthedocs.io/en/latest/reference/#dialogue-manager
hermes/dialogueManager/configure (JSON)

    Sets the default intent filter for all subsequent dialogue sessions
    intents: [object] - Intents to enable/disable (empty for all intents)
        intentId: string - Name of intent
        enable: bool - true if intent should be eligible for recognition
    siteId: string = "default" - Hermes site ID
=cut
    my $sendData =  {
        siteId  => $fhemId,
        intents => [{intentId => "${language}.${fhemId}.ConfirmAction", enable => "false"}]
    };

    my $json = toJSON($sendData);

    IOWrite($hash, 'publish', qq{hermes/dialogueManager/configure $json});
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

    # when called with just one keyword, devspec2array may return the keyword, even if the device doesn't exist...
    return if (@devices == 1 && $devices[0] eq $devspec);
    
    for (@devices) {
        _analyze_genDevType($hash, $_) if $hash->{useGenericAttrs};
        _analyze_rhassypAttr($hash, $_);
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

    return if !defined AttrVal($device,"${prefix}Room",undef) 
           && !defined AttrVal($device,"${prefix}Name",undef)
           && !defined AttrVal($device,"${prefix}Channels",undef) 
           && !defined AttrVal($device,"${prefix}Colors",undef)
           && !defined AttrVal($device,"${prefix}Group",undef)
           && !defined AttrVal($device,"${prefix}Specials",undef);

    #rhasspyRooms ermitteln
    my @rooms;
    my $attrv = AttrVal($device,"${prefix}Room",undef);
    @rooms = split m{,}x, lc $attrv if defined $attrv;
    #for (@rooms) { $_ = lc };
    @rooms = @{$hash->{helper}{devicemap}{devices}{$device}->{rooms}} if !@rooms && defined $hash->{helper}{devicemap}{devices}{$device}->{rooms};
    if (!@rooms) {
        $rooms[0] = $hash->{helper}{defaultRoom};
    }
    @{$hash->{helper}{devicemap}{devices}{$device}{rooms}} = @rooms;

    #rhasspyNames ermitteln
    my @names;
    $attrv = AttrVal($device,"${prefix}Name",undef);
    push @names, split m{,}x, lc $attrv if $attrv;
    #for (@names) { $_ = lc };
    $hash->{helper}{devicemap}{devices}{$device}->{alias} = $names[0] if $attrv;
    
    for my $dn (@names) {
       for (@rooms) {
           $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$dn} = $device;
       }
    }

    for my $item ('Channels', 'Colors') {
        my @rows = split m{\n}x, AttrVal($device, "${prefix}${item}", q{});

        for my $row (@rows) {
            my ($key, $val) = split m{=}x, $row, 2;
            next if !$val; 
            for my $rooms (@rooms) {
                #$hash->{helper}{devicemap}{$item}{$_}{$key} = $device;
                #push @{$hash->{helper}{devicemap}{$item}{$key}{$dn}}, $device if !grep( { m{\A$device\z}x } @{$hash->{helper}{devicemap}{$item}{$key}{$dn}});
                 push @{$hash->{helper}{devicemap}{$item}{$rooms}{$key}}, $device if !grep { m{\A$device\z}x } @{$hash->{helper}{devicemap}{$item}{$rooms}{$key}};
            }
            $hash->{helper}{devicemap}{devices}{$device}{$item}{$key} = $val;
        }
    }

    #Specials
    my @lines = split m{\n}x, AttrVal($device, "${prefix}Specials", q{});
    for my $line (@lines) {
        my ($key, $val) = split m{:}x, $line, 2;
        next if !$val; 
        
        if ($key eq 'group') {
            my($unnamed, $named) = parseParams($val); 
            my $specials = {};
            my $partOf = $named->{partOf} // shift @{$unnamed};
            $specials->{partOf} = $partOf if defined $partOf;
            $specials->{async_delay} = $named->{async_delay} if defined $named->{async_delay};
            $specials->{prio} = $named->{prio} if defined $named->{prio};

            $hash->{helper}{devicemap}{devices}{$device}{group_specials} = $specials;
        }
        
    }

    #Hash mit {FHEM-Device-Name}{$intent}{$type}?
    my $mappingsString = AttrVal($device, "${prefix}Mapping", q{});
    for (split m{\n}x, $mappingsString) {
        my ($key, $val) = split m{:}x, $_, 2;
        #$key = lc($key);
        #$val = lc($val);
        my %currentMapping = RHASSPY_splitMappingString($val);
    next if !%currentMapping;
        # Übersetzen, falls möglich:
        $currentMapping{type} = 
            defined $currentMapping{type} ?
            $de_mappings->{ToEn}->{$currentMapping{type}} // $currentMapping{type} // $key
            : $key;
        $hash->{helper}{devicemap}{devices}{$device}{intents}{$key}->{$currentMapping{type}} = \%currentMapping;
    }

    #my $allrooms = $hash->{helper}{devicemap}{devices}{$device}->{rooms};
    #for (@rooms) {
        #push @{$allrooms}, $_ if !grep { m{\A$_\z}ix } @{$allrooms};
    #    push @{$allrooms}, $_ if !grep { m{\A$_\z}ix } @{$allrooms};
    #}

    my @groups;
    $attrv = AttrVal($device,"${prefix}Group", undef);
    $attrv = $attrv // AttrVal($device,'group', undef);
    #$attrv = lc $attrv if $attrv;
    @{$hash->{helper}{devicemap}{devices}{$device}{groups}} = split m{,}x, lc $attrv if $attrv;

    return;
}


sub _analyze_genDevType {
    my $hash   = shift // return;
    my $device = shift // return;

    my $prefix = $hash->{prefix};

    #prerequesite: gdt has to be set!
    my $gdt = AttrVal($device, 'genericDeviceType', undef) // return; 

    my @names;
    my $attrv;
    #additional names?
    if (!defined AttrVal($device,"${prefix}Name", undef)) {

        $attrv = AttrVal($device,'alexaName', undef);
        push @names, split m{;}x, $attrv if $attrv;

        $attrv = AttrVal($device,'siriName',undef);
        push @names, split m{,}x, $attrv if $attrv;

        my $alias = AttrVal($device,'alias',undef);
        $names[0] = $alias if !@names && $alias;
        $names[0] = $device if !@names;
    }
    $hash->{helper}{devicemap}{devices}{$device}->{alias} = $names[0] if $names[0];

    #convert to lower case
    for (@names) { $_ = lc; }
    @names = get_unique(\@names);

    my @rooms;
    if (!defined AttrVal($device,"${prefix}Room", undef)) {
        $attrv = AttrVal($device,'alexaRoom', undef);
        push @rooms, split m{,}x, $attrv if $attrv;

        $attrv = AttrVal($device,'room',undef);
        push @rooms, split m{,}x, $attrv if $attrv;
        $rooms[0] = $hash->{helper}{defaultRoom} if !@rooms;
    }

    #convert to lower case
    for (@rooms) { $_ = lc }
    @rooms = get_unique(\@rooms);

    for my $dn (@names) {
       for (@rooms) {
           $hash->{helper}{devicemap}{rhasspyRooms}{$_}{$dn} = $device;
       }
    }
    push @{$hash->{helper}{devicemap}{devices}{$device}{rooms}}, @rooms;
    
    $attrv = AttrVal($device,'group', undef);
    @{$hash->{helper}{devicemap}{devices}{$device}{groups}} = split m{,}x, lc $attrv if $attrv;

    my $hbmap  = AttrVal($device, 'homeBridgeMapping', q{}); 
    my $allset = getAllSets($device);
    my $currentMapping;

    if ( ($gdt eq 'switch' || $gdt eq 'light') && $allset =~ m{\bo[nf]+[\b:\s]}xms ) {
        $currentMapping = 
            { GetOnOff => { GetOnOff => {currentVal => 'state', type => 'GetOnOff', valueOff => 'off'}}, 
              SetOnOff => { SetOnOff => {cmdOff => 'off', type => 'SetOnOff', cmdOn => 'on'}}
            };
        if ( $gdt eq 'light' && $allset =~ m{\bdim[\b:\s]}xms ) {
            my $maxval = InternalVal($device, 'TYPE', 'unknown') eq 'ZWave' ? 99 : 100;
            $currentMapping->{SetNumeric} = {
            brightness => { cmd => 'dim', currentVal => 'state', maxVal => $maxval, minVal => '0', step => '3', type => 'brightness'}};
        }

        elsif ( $gdt eq 'light' && $allset =~ m{\bpct[\b:\s]}xms ) {
            $currentMapping->{SetNumeric} = {
            brightness => { cmd => 'pct', currentVal => 'pct', maxVal => '100', minVal => '0', step => '5', type => 'brightness'}};
        }

        elsif ( $gdt eq 'light' && $allset =~ m{\bbrightness[\b:\s]}xms ) {
            $currentMapping->{SetNumeric} = {
                brightness => { cmd => 'brightness', currentVal => 'brightness', maxVal => '255', minVal => '0', step => '10', map => 'percent', type => 'brightness'}};
        }
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }
    elsif ( $gdt eq 'thermostat' ) {
        my $desTemp = $allset =~ m{\b(desiredTemp)[\b:\s]}xms ? $1 : 'desired-temp';
        my $measTemp = InternalVal($device, 'TYPE', 'unknown') eq 'CUL_HM' ? 'measured-temp' : 'temperature';
        $currentMapping = 
            { GetNumeric => { 'desired-temp' => {currentVal => $desTemp, type => 'temperature'},
            temperature => {currentVal => $measTemp, type => 'temperature'}}, 
            SetNumeric => {'desired-temp' => { cmd => $desTemp, currentVal => $desTemp, maxVal => '28', minVal => '10', step => '0.5', type => 'temperature'}}
            };
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

    if ( $gdt eq 'blind' ) {
        if ( $allset =~ m{\bdim[\b:\s]}xms ) {
            my $maxval = InternalVal($device, 'TYPE', 'unknown') eq 'ZWave' ? 99 : 100;
            $currentMapping = 
            { GetNumeric => { dim => {currentVal => 'state', type => 'setTarget' } },
            SetOnOff => { SetOnOff => {cmdOff => 'dim 0', type => 'SetOnOff', cmdOn => "dim $maxval"} },
            SetNumeric => { setTarget => { cmd => 'dim', currentVal => 'state', maxVal => $maxval, minVal => '0', step => '11', type => 'setTarget'} }
            };
        }

        elsif ( $allset =~ m{\bpct[\b:\s]}xms ) {
            $currentMapping = { 
            GetNumeric => { 'pct' => {currentVal => 'pct', type => 'setTarget'} },
            SetOnOff => { SetOnOff => {cmdOff => 'pct 0', type => 'SetOnOff', cmdOn => 'pct 100'} },
            SetNumeric => { setTarget => { cmd => 'pct', currentVal => 'pct', maxVal => '100', minVal => '0', step => '13', type => 'setTarget'} }
            };
        }
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

    if ( $gdt eq 'media' ) { #genericDeviceType media
        $currentMapping = { 
            GetOnOff => { GetOnOff => {currentVal => 'state', type => 'GetOnOff', valueOff => 'off'}},
            SetOnOff => { SetOnOff => {cmdOff => 'off', type => 'SetOnOff', cmdOn => 'on'}},
            GetNumeric => { 'volume' => {currentVal => 'volume', type => 'volume' }},
            SetNumeric => {'volume' => { cmd => 'volume', currentVal => 'volume', maxVal => '100', minVal => '0', step => '2', type => 'volume'}, 'channel' => { cmd => 'channel', currentVal => 'channel', step => '1', type => 'channel'}}, 
            MediaControls => { MediaControls => {'cmdPlay' => 'play', cmdPause => 'pause' ,cmdStop => 'stop', cmdBack => 'previous', cmdFwd => 'next', chanUp => 'channelUp', chanDown => 'channelDown'} } };
        $hash->{helper}{devicemap}{devices}{$device}{intents} = $currentMapping;
    }

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

sub RHASSPY_confirm_timer {
    my $hash     = shift // return;
    my $mode     = shift; #undef => timeout, 1 => cancellation, 
                        #2 => set timer
    my $data     = shift // $hash->{helper}{'.delayed'};
    my $timeout  = shift;
    my $response = shift;

    #timeout Case
    if (!defined $mode) {
        RemoveInternalTimer( $hash, \&RHASSPY_confirm_timer );
        $response = $hash->{helper}{lng}->{responses}->{DefaultConfirmationTimeout};
        #Beta-User: we may need to start a new session first?
        RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
        delete $hash->{helper}{'.delayed'};
        return;
    }

    #cancellation Case
    if ( $mode == 1 ) {
        RemoveInternalTimer( $hash, \&RHASSPY_confirm_timer );
        $response = $hash->{helper}{lng}->{responses}->{DefaultCancelConfirmation};
        RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
        delete $hash->{helper}{'.delayed'};
        return $hash->{NAME};
    }
    if ( $mode == 2 ) {
        RemoveInternalTimer( $hash, \&RHASSPY_confirm_timer );
        $hash->{helper}{'.delayed'} = $data;
        #$response = $hash->{helper}{shortcuts}{$data->{input}}{conf_req};
        $response = $hash->{helper}{lng}->{responses}->{DefaultConfirmationReceived} if $response eq 'default';
        
        #InternalTimer(time + $hash->{helper}{shortcuts}{$data->{input}}{conf_timeout}, \&RHASSPY_confirm_timer, $hash, 0);
        InternalTimer(time + $timeout, \&RHASSPY_confirm_timer, $hash, 0);

        #interactive dialogue as described in https://rhasspy.readthedocs.io/en/latest/reference/#dialoguemanager_continuesession and https://docs.snips.ai/articles/platform/dialog/multi-turn-dialog
        my $reaction = { text => $response, intentFilter => [qw(ConfirmAction)]
            };

        RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $reaction);

        return $hash->{NAME};
    }
    
    return $hash->{NAME};
}


#from https://stackoverflow.com/a/43873983, modified...
sub get_unique {
    my $arr    = shift;
    my $sorted = shift; #true if shall be sorted (longest first!)
    
    #my %seen;
    
    #method 2 from https://stackoverflow.com/a/43873983
    #my @unique = grep {!$seen{$_}++} @{$arr}; #we may need to sort, see https://stackoverflow.com/a/30448251
    my @unique = uniq @{$arr};
    
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
    for my $key (keys %specials) {
        my $val = $specials{$key};
        $cmd =~ s{\Q$key\E}{$val}gxms;
    }
    Log3($hash->{NAME}, 5, "_replace from $parent returns: $cmd");
    return $cmd;
}

#based on compareHashes https://stackoverflow.com/a/56128395
#Beta-User: might be usefull in case we want to allow some kind of default + user-diff logic, especially in language...
sub _combineHashes {
    my ($hash1, $hash2, $parent) = @_;
    my $hash3 = {};
   
    for my $key (keys %{$hash1}) {
        $hash3->{$key} = $hash1->{$key};
        if (!exists $hash2->{$key}) {
            next;
        }
        if ( ref $hash3->{$key} eq 'HASH' and ref $hash2->{$key} eq 'HASH' ) {
            $hash3->{$key} = _combineHashes($hash3->{$key}, $hash2->{$key}, $key);
        } elsif ( !ref $hash3->{$key} && !ref $hash2->{$key} ) {
            $hash3->{$key} = $hash2->{$key};
        }
    }
    for (qw(commaconversion mutated_vowels)) {
        $hash3->{$_} = $hash2->{$_} if defined $hash2->{$_};
    }
    return $hash3;
}
    
# derived from structureRHASSPY_asyncQueue
sub RHASSPY_asyncQueue {
    my $hash = shift // return;
    my $next_cmd = shift @{$hash->{".asyncQueue"}};
    if (defined $next_cmd) {
        RHASSPY_runCmd($hash, $next_cmd->{device}, $next_cmd->{cmd}) if defined $next_cmd->{cmd};
        RHASSPY_handleIntentSetNumeric($hash, $next_cmd->{SetNumeric}) if defined $next_cmd->{SetNumeric};
        my $async_delay = $next_cmd->{delay} // 0;
        InternalTimer(time+$async_delay,\&RHASSPY_asyncQueue,$hash,0);
    }
    return;
}

sub _sortAsyncQueue {
    my $hash = shift // return;
    my $queue = @{$hash->{".asyncQueue"}};
    
    #push @{$hash->{".asyncQueue"}}, {$devices->{$device}->{delay}=>{cmd => $cmd}, prio=>$devices->{$device}->{prio}};
    my @devlist = sort {
        $a->{prio} <=> $b->{prio}
        or
        $a->{delay} <=> $b->{delay}
        } @{$queue};
    $hash->{".asyncQueue"} = @devlist;
    return;
}

# Get all devicenames with Rhasspy relevance
sub RHASSPY_allRhasspyNames {
    my $hash = shift // return;

    my @devices;

    return if !defined $hash->{helper}{devicemap};
    my $rRooms = $hash->{helper}{devicemap}{rhasspyRooms};
    for my $key (keys %{$rRooms}) {
        push @devices, keys %{$rRooms->{$key}};
    }
    return get_unique(\@devices, 1 );
}

# Alle Raumbezeichnungen sammeln
sub RHASSPY_allRhasspyRooms {
    my $hash = shift // return;

    return keys %{$hash->{helper}{devicemap}{rhasspyRooms}} if defined $hash->{helper}{devicemap};
    return;
}


# Alle Sender sammeln
sub RHASSPY_allRhasspyChannels {
    my $hash = shift // return;
    
    my @channels;
    
    return if !defined $hash->{helper}{devicemap};
        
    for my $room (keys %{$hash->{helper}{devicemap}{Channels}}) {
        push @channels, keys %{$hash->{helper}{devicemap}{Channels}{$room}}
    }
    return get_unique(\@channels, 1 );
}


# Alle NumericTypes sammeln
sub RHASSPY_allRhasspyTypes {
    my $hash = shift // return;
    my @types;

    return if !defined $hash->{helper}{devicemap};

    for my $dev (keys %{$hash->{helper}{devicemap}{devices}}) {
        for my $intent (keys %{$hash->{helper}{devicemap}{devices}{$dev}{intents}}) {
            my $type;
            $type = $hash->{helper}{devicemap}{devices}{$dev}{intents}{$intent};
            push @types, keys %{$type} if $intent =~ m{\A[GS]etNumeric}x;
        }
    }
    return get_unique(\@types, 1 );
}


# Alle Farben sammeln
sub RHASSPY_allRhasspyColors {
    my $hash = shift // return;
    my @colors;

    return if !defined $hash->{helper}{devicemap};

    for my $room (keys %{$hash->{helper}{devicemap}{Colors}}) {
        push @colors, keys %{$hash->{helper}{devicemap}{Colors}{$room}}
    }
    return get_unique(\@colors, 1 );
}


# get a list of all used groups
sub RHASSPY_allRhasspyGroups {
    my $hash = shift // return;
    my @groups;
    
    for my $device (keys %{$hash->{helper}{devicemap}{devices}}) {
        my $devgroups = $hash->{helper}{devicemap}{devices}{$device}->{groups};
        for (@{$devgroups}) {
            push @groups, $_;
        }
    }
    return get_unique(\@groups, 1);
}

# Raum aus gesprochenem Text oder aus siteId verwenden? (siteId "default" durch Attr defaultRoom ersetzen)
sub RHASSPY_roomName {
    my $hash = shift // return;
    my $data = shift // return;

    # Slot "Room" im JSON vorhanden? Sonst Raum des angesprochenen Satelites verwenden
    return $data->{Room} if exists($data->{Room});
    
    my $room;
    
    #Beat-User: This might be the right place to check, if there's additional logic implemented...
    
    my $rreading = makeReadingName("siteId2room_$data->{siteId}");
    $room = ReadingsVal($hash->{NAME}, $rreading, $data->{siteId});
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
    
    return if !defined $hash->{helper}{devicemap};
    
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


# Sammelt Geräte über Raum, Intent und optional Type
sub RHASSPY_getDevicesByIntentAndType {
    my $hash   = shift // return;
    my $room   = shift;
    my $intent = shift;
    my $type   = shift; #Beta-User: any necessary parameters...?

    my @matchesInRoom; my @matchesOutsideRoom;

    return if !defined $hash->{helper}{devicemap};
    for my $devs (keys %{$hash->{helper}{devicemap}{devices}}) {
        my $mapping = RHASSPY_getMapping($hash, $devs, $intent, $type, 1, 1) // next;
        my $mappingType = $mapping->{type};
        my $rooms = join q{,}, $hash->{helper}{devicemap}{devices}{$devs}->{rooms};

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
    Log3($hash->{NAME}, 5, "matches in room: @{$matchesInRoom}, matches outside: @{$matchesOutsideRoom}");
    
    # Erstes Device im passenden Raum zurückliefern falls vorhanden, sonst erstes Device außerhalb
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
    
    return if !defined $hash->{helper}{devicemap};
    my $devices = $hash->{helper}{devicemap}{Channels}{$room}->{$channel};
    $device = ${$devices}[0];
    #return $device if $device;
    if ($device) {
        Log3($hash->{NAME}, 5, "Device selected (by hash, with room and channel): $device");
        return $device ;
    }
    for (sort keys %{$hash->{helper}{devicemap}{Channels}}) {
        #$device = $hash->{helper}{devicemap}{Channels}{$_}{$channel};
        $devices = $hash->{helper}{devicemap}{Channels}{$_}{$channel};
        $device = ${$devices}[0];
    
        #return $device if $device;
        if ($device) {
            Log3($hash->{NAME}, 5, "Device selected (by hash, using only channel): $device");
            return $device ;
        }
    }
    Log3($hash->{NAME}, 1, "No device for >>$channel<< found, especially not in room >>$room<< (also not outside)!");
    return;
}

sub RHASSPY_getDevicesByGroup {
    my $hash = shift // return;
    my $data = shift // return;

    my $group = $data->{Group} // return;
    my $room  = $data->{Room}  // return;

    my $devices = {};

    for my $dev (keys %{$hash->{helper}{devicemap}{devices}}) {
        my $allrooms = $hash->{helper}{devicemap}{devices}{$dev}->{rooms};
        #next if $room ne 'global' && !grep { m{\A$room\z}ix } @{$allrooms};
        next if $room ne 'global' && !any { $_ eq $room } @{$allrooms};
        my $allgroups = $hash->{helper}{devicemap}{devices}{$dev}->{groups};
        #next if !grep { m{\A$group\z}ix } @{$allgroups};
        next if !any { $_ eq $group } @{$allgroups};
        my $specials = $hash->{helper}{devicemap}{devices}{$dev}{group_specials};
        my $label = $specials->{partOf} // $dev;
        next if defined $devices->{$label};
        my $delay = $specials->{async_delay} // 0;
        my $prio  = $specials->{prio} // 0;

        $devices->{$label} = { delay => $delay, prio => $prio };
    }
    return $devices;
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
    my $type       = shift // $intent; #Beta-User: seems first three parameters are obligatory...?
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
sub RHASSPY_getCmd {
    my $hash       = shift // return;
    my $device     = shift;
    my $reading    = shift;
    my $key        = shift; #Beta-User: any necessary parameters...?
    my $disableLog = shift // 0;
    #my ($hash, $device, $reading, $key, $disableLog) = @_;

    my $cmd;
    
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

sub RHASSPY_runCmdIndirect {

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

#Make globally available to allow later use by other functions, esp.  RHASSPY_handleIntentConfirmAction
my $dispatchFns = {
    Shortcuts       => \&RHASSPY_handleIntentShortcuts, 
    SetOnOff        => \&RHASSPY_handleIntentSetOnOff,
    SetOnOffGroup   => \&RHASSPY_handleIntentSetOnOffGroup,
    GetOnOff        => \&RHASSPY_handleIntentGetOnOff,
    SetNumeric      => \&RHASSPY_handleIntentSetNumeric,
    SetNumericGroup => \&RHASSPY_handleIntentSetNumericGroup,
    GetNumeric      => \&RHASSPY_handleIntentGetNumeric,
    Status          => \&RHASSPY_handleIntentStatus,
    MediaControls   => \&RHASSPY_handleIntentMediaControls,
    MediaChannels   => \&RHASSPY_handleIntentMediaChannels,
    SetColor        => \&RHASSPY_handleIntentSetColor,
    GetTime         => \&RHASSPY_handleIntentGetTime,
    GetWeekday      => \&RHASSPY_handleIntentGetWeekday,
    SetTimer        => \&RHASSPY_handleIntentSetTimer,
    ConfirmAction   => \&RHASSPY_handleIntentConfirmAction,
    ReSpeak         => \&RHASSPY_handleIntentReSpeak
};



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
    if (ref $dispatchFns->{$intent} eq 'CODE') {
        $device = $dispatchFns->{$intent}->($hash, $data);
    } else {
        $device = RHASSPY_handleCustomIntent($hash, $intent, $data);
    }
    #}
    #Beta-User: In welchem Fall kam es dazu, den folgenden Code-Teil anzufahren?
    #else {RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, " ");}
    #Beta-User: return value should be reviewed. If there's an option to return the name of the devices triggered by Rhasspy, then this could be a better option than just RHASSPY's own name.
    
    $device = $device // $hash->{NAME};
    my @candidates = split m{,}x, $device;
    for (@candidates) {
        push @updatedList, $_ if $defs{$_}; 
    }

    return \@updatedList;
}


# Antwort ausgeben
sub RHASSPY_respond {
    my $hash      = shift // return;
    my $type      = shift // return;
    my $sessionId = shift // return;
    my $siteId    = shift // return;
    my $response  = shift // return;

    my $topic = q{endSession};

    my $sendData =  {
        sessionId => $sessionId,
        siteId    => $siteId
    };

    if (ref $response eq 'HASH') {
        #intentFilter
        $topic = q{continueSession};
        for my $key (keys %{$response}) {
            $sendData->{$key} = $response->{$key};
        }
    } else {
        $sendData->{text} = $response
    }

    my $json = toJSON($sendData);

    readingsBeginUpdate($hash);
    $type eq 'voice' ?
        readingsBulkUpdate($hash, 'voiceResponse', $response)
      : readingsBulkUpdate($hash, 'textResponse', $response);
    readingsBulkUpdate($hash, 'responseType', $type);
    readingsEndUpdate($hash,1);
    IOWrite($hash, 'publish', qq{hermes/dialogueManager/$topic $json});
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
        return 'speak with explicite params needs siteId and text as arguments!' if !defined $cmd->{siteId} || !defined $cmd->{text};
        $sendData->{siteId} =  $cmd->{siteId};
        $sendData->{text} =  $cmd->{text};
    } else {    #Beta-User: might need review, as parseParams is used by default...!
        my $siteId = 'default';
        my $text = $cmd;
        my($unnamedParams, $namedParams) = parseParams($cmd);

        if (defined $namedParams->{siteId} && defined $namedParams->{text}) {
            $sendData->{siteId} = $namedParams->{siteId};
            $sendData->{text} = $namedParams->{text};
        } else {
            return 'speak needs siteId and text as arguments!';
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
    
    initialize_devicemap($hash) if defined $hash->{useHash} && $hash->{useHash};

    # Collect everything and store it in arrays
    my @devices   = RHASSPY_allRhasspyNames($hash);
    my @rooms     = RHASSPY_allRhasspyRooms($hash);
    my @channels  = RHASSPY_allRhasspyChannels($hash);
    my @colors    = RHASSPY_allRhasspyColors($hash);
    my @types     = RHASSPY_allRhasspyTypes($hash);
    my @groups    = RHASSPY_allRhasspyGroups($hash);
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
    return if !@devices && !@rooms && !@channels && !@types && !@groups;
    
    my $json;
    my $deviceData;
    my $url = q{/api/slots?overwrite_all=true};

    $deviceData->{qq(${language}.${fhemId}.Device)}        = \@devices if @devices;
    $deviceData->{qq(${language}.${fhemId}.Room)}          = \@rooms if @rooms;
    $deviceData->{qq(${language}.${fhemId}.MediaChannels)} = \@channels if @channels;
    $deviceData->{qq(${language}.${fhemId}.Color)}         = \@colors if @colors;
    $deviceData->{qq(${language}.${fhemId}.NumericType)}   = \@types if @types;
    $deviceData->{qq(${language}.${fhemId}.Group)}         = \@groups if @groups;

    $json = eval { toJSON($deviceData) };

    Log3($hash->{NAME}, 5, "Updating Rhasspy Slots with data ($language): $json");
      
    RHASSPY_sendToApi($hash, $url, $method, $json);

    return;
}

# Send all devices, rooms, etc. to Rhasspy HTTP-API to update the slots
sub RHASSPY_updateSingleSlot {
    my $hash     = shift // return;
    my $slotname = shift // return;
    my $slotdata = shift // return;
    my $overwr   = shift // q{true};
    my $training = shift;
    $overwr = q{false} if $overwr ne 'true';
    my @data = split m{,}xms, $slotdata;
    my $language = $hash->{LANGUAGE};
    my $fhemId   = $hash->{fhemId};
    my $method   = q{POST};
    
    my $url = qq{/api/slots?overwrite_all=$overwr};

    my $deviceData->{qq(${language}.${fhemId}.$slotname)} = \@data;

    my $json = eval { toJSON($deviceData) };

    Log3($hash->{NAME}, 5, "Updating Rhasspy single slot with data ($language): $json");

    RHASSPY_sendToApi($hash, $url, $method, $json);
    return RHASSPY_trainRhasspy($hash) if $training;

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
    my $base   = $hash->{WebIF}; #AttrVal($hash->{NAME}, 'rhasspyMaster', undef) // return;

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
    my $base  = $hash->{WebIF}; #AttrVal($name, 'rhasspyMaster', undef) // return;
    my $cp    = $hash->{encoding} // q{UTF-8};
    
    readingsBeginUpdate($hash);
    my $urls = { 
        $base.'/api/train'                      => 'training',
        $base.'/api/sentences'                  => 'updateSentences',
        $base.'/api/slots?overwrite_all=true'   => 'updateSlots'
    };

    if ( defined $urls->{$url} ) {
        readingsBulkUpdate($hash, $urls->{$url}, $data);
    }
    elsif ( $url =~ m{api/profile}ix ) {
        my $ref; 
        if ( !eval { $ref = decode_json($data) ; 1 } ) {
            readingsEndUpdate($hash, 1);
            return Log3($hash->{NAME}, 1, "JSON decoding error: $@");
        }
        #my $ref = decode_json($data);
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
        Log3($hash->{NAME}, 2, "handleIntentCustomIntent called with invalid $intentName key");
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
                $_ = qq{"$hash->{NAME}"};
            } elsif ($_ eq 'DATA') {
                $_ = $data;
            } elsif (defined $data->{$_}) {
                $_ = qq{"$data->{$_}"};
            } else {
                $_ = "undef";
            }
        }

        my $args = join q{,}, @rets;
        my $cmd = qq{ $subName( $args ) };
=pod
attr rhasspy rhasspyIntents SetAllOn=SetAllOn(Room,Type)

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
    
    my $response;
    if ( defined $hash->{helper}{shortcuts}{$data->{input}}{conf_timeout} && !$data->{Confirmation} ) {
        my $timeout = $hash->{helper}{shortcuts}{$data->{input}}{conf_timeout};
        $response = $hash->{helper}{shortcuts}{$data->{input}}{conf_req};return RHASSPY_confirm_timer($hash, 2, $data, $timeout, $response);
    }
    $response = $shortcut->{response} // RHASSPY_getResponse($hash, 'DefaultConfirmation');
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
        $cmd = qq({$cmd}) if ($cmd !~ m{\A\{.*\}\z}x); 

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
    my ($value, $numericValue, $device, $room, $siteId, $mapping, $response);

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

sub RHASSPY_handleIntentSetOnOffGroup {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentSetOnOffGroup called");
    #{"Group":"licht","Room":"wohnzimmer","Value":"on", ...
    
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoValidData')) if !defined $data->{Value}; 
    
    my $devices = RHASSPY_getDevicesByGroup($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};
        
    #$hash->{helper}->{groups2} = \@devlist;
    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoDeviceFound')) if !keys %{$devices}; 

    my $delaysum = 0;
    
    my $value = $data->{Value};
    $value = $value eq $de_mappings->{on} ? 'on' : $value;
    
    my $updatedList;

    my $init_delay = 0;
    my $needs_sorting = (@{$hash->{".asyncQueue"}});
        
    for my $device (@devlist) {
        my $mapping = RHASSPY_getMapping($hash, $device, 'SetOnOff', undef, defined $hash->{helper}{devicemap});

        # Mapping found?
        next if !defined $mapping;
        
        my $cmdOn  = $mapping->{cmdOn} // 'on';
        my $cmdOff = $mapping->{cmdOff} // 'off';
        my $cmd = $value eq 'on' ? $cmdOn : $cmdOff;

        # execute Cmd
        if ( !$delaysum) {
            RHASSPY_runCmd($hash, $device, $cmd);
            Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );
            $delaysum += $devices->{$device}->{delay};
            $updatedList = $updatedList ? "$updatedList,$device" : $device;
        } else {
            my $hlabel = $devices->{$device}->{delay};
            push @{$hash->{".asyncQueue"}}, {device => $device, cmd => $cmd, prio => $devices->{$device}->{prio}, delay => $hlabel};
            InternalTimer(time+$delaysum,\&RHASSPY_asyncQueue,$hash,0) if !$init_delay;
            $init_delay = 1;
        }
    }
    
    _sortAsyncQueue($hash) if $init_delay && $needs_sorting;

    # Send response
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'DefaultConfirmation'));
    return $updatedList;
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

sub RHASSPY_handleIntentSetNumericGroup {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentSetNumericGroup called");
    #{"Group":"licht","Room":"wohnzimmer","Value":"on", ...
    
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoValidData')) if !exists $data->{Value} && !exists $data->{Change}; 
    
    my $devices = RHASSPY_getDevicesByGroup($hash, $data);

    #see https://perlmaven.com/how-to-sort-a-hash-of-hashes-by-value for reference
    my @devlist = sort {
        $devices->{$a}{prio} <=> $devices->{$b}{prio}
        or
        $devices->{$a}{delay} <=> $devices->{$b}{delay}
        }  keys %{$devices};
        
    #$hash->{helper}->{groups2} = \@devlist;
    Log3($hash, 5, 'sorted devices list is: ' . join q{ }, @devlist);
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoDeviceFound')) if !keys %{$devices}; 

    my $delaysum = 0;
    
    my $value = $data->{Value};
    $value = $value eq $de_mappings->{on} ? 'on' : $value;
    
    my $updatedList;

    my $init_delay = 0;
    my $needs_sorting = (@{$hash->{".asyncQueue"}});
        
    for my $device (@devlist) {
        my $tempdata = $data;
        $tempdata->{'.DevName'} = $device;
        $tempdata->{'.inBulk'} = 1;
        
        # execute Cmd
        if ( !$delaysum) {
            RHASSPY_handleIntentSetNumeric($hash, $tempdata);
            Log3($hash->{NAME}, 5, "Running SetNumeric on device [$device]" );
            $delaysum += $devices->{$device}->{delay};
            $updatedList = $updatedList ? "$updatedList,$device" : $device;
        } else {
            my $hlabel = $devices->{$device}->{delay};
            push @{$hash->{".asyncQueue"}}, {device => $device, SetNumeric => $tempdata, prio => $devices->{$device}->{prio}, delay => $hlabel};
            InternalTimer(time+$delaysum,\&RHASSPY_asyncQueue,$hash,0) if !$init_delay;
            $init_delay = 1;
        }
    }
    
    _sortAsyncQueue($hash) if $init_delay && $needs_sorting;

    # Send response
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'DefaultConfirmation'));
    return $updatedList;
}

# Eingehende "SetNumeric" Intents bearbeiten
sub RHASSPY_handleIntentSetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $device = $data->{'.DevName'};
    #my $mapping;
    my $response;

    Log3($hash->{NAME}, 5, "handleIntentSetNumeric called");

    if (!defined $device && !isValidData($data)) {
        return if defined $data->{'.inBulk'};
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
    if (!defined $device && exists $data->{Device} ) {
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
    } elsif ( defined $type && ( $type eq 'volume' || $type eq 'Lautstärke' ) ) {
        $device = 
            RHASSPY_getActiveDeviceForIntentAndType($hash, $room, 'SetNumeric', $type) 
            // return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoActiveMediaDevice'));
    }

    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoDeviceFound')) if !defined $device;

    my $mapping = RHASSPY_getMapping($hash, $device, 'SetNumeric', $type, defined $hash->{helper}{devicemap}, 0);
    
    if (!defined $mapping) {
        if ( defined $data->{'.inBulk'} ) {
            #Beta-User: long forms to later add options to check upper/lower limits for pure on/off devices
            return;
        } else { 
            RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoMappingFound'));
        }
    }

    # Mapping and device found -> execute command
    my $cmd     = $mapping->{cmd} // return defined $data->{'.inBulk'} ? undef : RHASSPY_respond($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoMappingFound'));
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
        return defined $data->{'.inBulk'} ? undef : RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse($hash, 'NoNewValDerived'));
    }

    # limit to min/max  (if set)
    $newVal = max( $minVal, $newVal ) if defined $minVal;
    $newVal = min( $maxVal, $newVal ) if defined $maxVal;

    # execute Cmd
    RHASSPY_runCmd($hash, $device, $cmd, $newVal);

    # get response 
    defined $mapping->{response} 
        ? $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $newVal, $room) 
        : $response = RHASSPY_getResponse($hash, 'DefaultConfirmation'); 

    # send response
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response) if !defined $data->{'.inBulk'};
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

    my $location = $data->{Device};
    if ( !defined $location ) {
        my $rooms = join q{,}, $hash->{helper}{devicemap}{devices}{$device}->{rooms};
        $location = $data->{Room} if $rooms =~ m{\b$data->{Room}\b}ix;
        $location = ${$hash->{helper}{devicemap}{devices}{$device}->{rooms}}[0] if !defined $location;
    }
    my $deviceName = $hash->{helper}{devicemap}{devices}{$device}->{alias} // $device;

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
        #or not and at least know the type...?
        $response = defined $mappingType   
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
    
=pod

https://forum.fhem.de/index.php/topic,119447.msg1143029.html#msg1143029

 WAV abspielen lassen, so lange, bis man sie mit "stopp(e den Timer)" stoppt.
 
Übergangsweise: Die "Flasche" von JensS => https://forum.fhem.de/index.php/topic,113180.msg1130450.html#msg1130450? (Für die "finale Fassung" müßte man was copyright-unverdächtiges suchen, evtl. irgendeinen (konvertierten) Linux-Systemsound?)

Das mit dem "Stop" bringt mich auf einen weiteren Ast:
- Das Default-Abspielen könnte man in eine at-Schleife packen, wobei ich die Zahl der Wiederholungen nicht bei Unendlich sehe.
- "Stop" sollte eine Anweisung unterhalb des SetTimer-intents sein, dann kann man das at gezielt "abschießen"; das wäre sowieso ein Thema, denn- "Cancel" könnte noch ein weiterer Zweig in SetTimer darstellen, mit dem man den Timer löscht.

Die ganze Logik würde sich dann erweitern, indem erst geschaut wird, ob eines der beiden "Keywords" in $data drin ist (siehe den Shortcuts-Code zu "confirm"). Das sollte dann auch direkt mit "$label" "spielen" können...

=cut
    my $response;

    Log3($name, 5, 'handleIntentSetTimer called');

    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $hash->{helper}{lng}->{responses}->{duration_not_understood}) 
    if !defined $data->{hourabs} && !defined $data->{hour} && !defined $data->{min} && !defined $data->{sec} && !defined $data->{Cancel};

    my $room = RHASSPY_roomName($hash, $data); #$data->{Room} // $siteId

    my $hour = 0;
    my $value = time;
    my $now = $value;
    my @time = localtime($now);
    if ( defined $data->{hourabs} ) {
        $hour  = $data->{hourabs};
        $value = $value - ($time[2] * HOURSECONDS) - ($time[1] * MINUTESECONDS) - $time[0]; #last midnight
    }
    elsif ($data->{hour}) {
        $hour = $data->{hour};
    }
    $value += HOURSECONDS * $hour;
    $value += MINUTESECONDS * $data->{min} if $data->{min};
    $value += $data->{sec} if $data->{sec};
    
    my $tomorrow = 0;
    if ( $value < $now ) {
        $tomorrow = 1;
        $value += +DAYSECONDS;
    }

    my $siteIds = ReadingsVal( $name, 'siteIds',0);
    RHASSPY_fetchSiteIds($hash) if !$siteIds;

    my $timerRoom = $siteId;

    my $responseEnd = $hash->{helper}{lng}->{responses}->{timerEnd}->{1};

    if ($siteIds =~ m{\b$room\b}ix) {
        $timerRoom = $room if $siteIds =~ m{\b$room\b}ix;
        $responseEnd = $hash->{helper}{lng}->{responses}->{timerEnd}->{0};
    }
    
    my $roomReading = "timer_".makeReadingName($room);
    my $label = $data->{label} // q{};
    $roomReading .= "_$label" if $label ne ''; 

    if (defined $data->{Cancel}) {
        CommandDelete($hash, $roomReading);
        readingsSingleUpdate( $hash,$roomReading, 0, 1 );
        Log3($name, 5, "deleted timer: $roomReading");
        $response = RHASSPY_getResponse($hash, 'timerCancellation');
        $response =~ s{(\$\w+)}{$1}eegx;
        RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
        return $name;
    }


    if( $value && $timerRoom ) {
        my $seconds = $value - $now; 
        my $diff = $seconds;
        my $attime = strftime('%H', gmtime $diff);
        $attime += 24 if $tomorrow;
        $attime .= strftime(':%M:%S', gmtime $diff);

        $responseEnd =~ s{(\$\w+)}{$1}eegx;

        #my $cmd = qq(defmod $roomReading at +$attime set $name speak siteId=\"$timerRoom\" text=\"$responseEnd\";;setreading $name $roomReading 0);

        #RHASSPY_runCmd($hash,'',$cmd);
        CommandDefMod($hash, "-temporary $roomReading at +$attime set $name speak siteId=\"$timerRoom\" text=\"$responseEnd\";setreading $name $roomReading 0");

        readingsSingleUpdate($hash, $roomReading, 1, 1);

        Log3($name, 5, "Created timer: $roomReading at +$attime");

        my ($range, $minutes, $hours, $minutetext);
        @time = localtime($value);
        if ( $seconds < 101 ) { 
            $range = 0;
        } elsif ( $seconds < HOURSECONDS ) {
            $minutes = int ($seconds/MINUTESECONDS);
            $range = $seconds < 9*MINUTESECONDS ? 1 : 2;
            $seconds = $seconds % MINUTESECONDS;
            $range = 2 if !$seconds;
            $minutetext =  $hash->{helper}{lng}->{units}->{unitMinutes}->{$minutes > 1 ? 0 : 1};
            $minutetext = qq{$minutes $minutetext} if $minutes > 1;
        } elsif ( $seconds < 3 * HOURSECONDS ) {
            $hours = int ($seconds/HOURSECONDS);
            $seconds = $seconds % HOURSECONDS;
            $minutes = int ($seconds/MINUTESECONDS);
            $range = 3;
            $minutetext =  $minutes ? $hash->{helper}{lng}->{units}->{unitMinutes}->{$minutes > 1 ? 0 : 1} : q{};
            $minutetext = qq{$minutes $minutetext} if $minutes > 1;
        } else {
            $hours = $time[2];
            #$seconds = $seconds % HOURSECONDS;
            $minutes = $time[1];
            $range = 4 + $tomorrow;
        }
        $response = $hash->{helper}{lng}->{responses}->{timerSet}->{$range};
        $response =~ s{(\$\w+)}{$1}eegx;
    }

    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');

    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $name;
}

sub RHASSPY_handleIntentConfirmAction {
    my $hash = shift // return;
    my $data = shift // return;
    
    Log3($hash->{NAME}, 5, 'RHASSPY_handleIntentConfirmAction called');
    
    #cancellation case
    return RHASSPY_confirm_timer($hash, 1) if $data->{Mode} ne 'OK';
    
    #confirmed case
    my $data_old = $hash->{helper}{'.delayed'};
    
    return RHASSPY_respond( $hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, RHASSPY_getResponse( $hash, 'DefaultConfirmationNoOutstanding' ) ) if ! defined $data_old;
    delete $hash->{helper}{'.delayed'};
    
    $data_old->{siteId} = $data->{siteId};
    $data_old->{sessionId} = $data->{sessionId};
    $data_old->{requestType} = $data->{requestType};
    $data_old->{Confirmation} = 1;
    
    my $intent = $data_old->{intent};
    my $device;

    # Passenden Intent-Handler aufrufen
    if (ref $dispatchFns->{$intent} eq 'CODE') {
        $device = $dispatchFns->{$intent}->($hash, $data_old);
    }

    return $device;
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
    
    return 'playWav needs siteId and path to file as parameters!' if !defined $cmd->{siteId} || !defined $cmd->{path};
    
    #if (defined($cmd->{siteId}) && defined($cmd->{path})) {
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
    #}
    return;
}

# Set volume on specific siteId
sub RHASSPY_setVolume {
    my $hash = shift // return;
    my $cmd = shift;

    return 'setVolume needs siteId and volume as parameters!' if !defined $cmd->{siteId} || !defined $cmd->{volume};

    my $sendData =  {
        id => '0',
        sessionId => '0'
    };

    Log3($hash->{NAME}, 5, 'setVolume called');

    $sendData->{siteId} = $cmd->{siteId};
    $sendData->{volume} = 0 + $cmd->{volume};

    my $json = toJSON($sendData);
    return IOWrite($hash, 'publish', qq{rhasspy/audioServer/setVolume $json});

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

=begin ToDo

# Timer:
- Sollte als Wecker ergänzt werden, so dass man auch absolute Uhrzeiten angeben kann.
- Die Antwort sollte sich danach richten, wann der Timer abläuft, z.B. bis 100 Sekunden => "auf ... Sekunden gestellt", bis 15/20 Minuten => "auf ... Minuten gestellt", sonst: "auf [morgen] ... Uhr ... (Sekunden) gestellt" 
- "Benannten Timer" als Option ergänzen

# "rhasspySpecials" als weiteres Attribut?
Denkbare Verwendung:
- siteId2room für mobile Geräte (Denkbare Anwendungsfälle: Auswertung BT-RSSI per Perl, aktives Setzen über ein Reading? Oder einen intent?
- Ansteuerung von Lamellenpositionen (auch an anderem Device?)
- Bestätigungs-Mapping

# "rhasspyGroup" als weiteres Attribut?
Beta-User: Tendenziell fehlt zwischen Einzeldevice und Room noch ein optionales  Unterscheidungsmerkmal Die Auswertung des (allg.) group-Attributs ist vorbereitet... 

=end ToDo

=begin ToClarify

#defaultRoom (JensS):
- überhaupt erforderlich?
- Schreibweise: RHASSPY ist raus, Rhasspy scheint der überkommene Raumname für die devspec zu sein => ist erst mal weiter beides drin

# GetTimer implementieren?
https://forum.fhem.de/index.php/topic,113180.msg1130139.html#msg1130139

# Audiowiedergabe
(Beispiel: "Flasche" mit Timer)
https://forum.fhem.de/index.php/topic,113180.msg1130450.html#msg1130450

# Kopfrechnen 
ist eine Stärke von Rhasspy. Solch ein Intent benötigt wenig Code.
https://forum.fhem.de/index.php/topic,113180.msg1130754.html#msg1130754

# Wetterdurchsage
Ist möglich. Dazu hatte ich einen rudimentären Intent in diesem Thread erstellt. Müsste halt nur erweitert werden.
https://forum.fhem.de/index.php/topic,113180.msg1130754.html#msg1130754


=end ToClarify

=encoding utf8
=item device
=item summary Control FHEM with Rhasspy voice assistant
=item summary_DE Steuerung von FHEM mittels Rhasspy Sprach-Assistent
=begin html

<a id="RHASSPY"></a>
<h3>RHASSPY</h3>
<p>
<ul>
<p>This module receives, processes and executes voice commands coming from Rhasspy voice assistent.</p>
<ul>At the moment, there's been a lot of changes to the code base, so 
<li><b>not everything may work as expeced, FHEM may even crash!</b></li>
<li>not everything mentionned here is fully implemented, ideas that may come are marked with an Asterix <b>*)</b>.</li>
</ul>
</p>
<a id="RHASSPY-define"></a>
<p><b>Define</b></p>
<p><code>define &lt;name&gt; RHASSPY &lt;WebIF&gt; &lt;devspec&gt; &lt;defaultRoom&gt; &lt;language&gt; &lt;fhemId&gt; &lt;prefix&gt; &lt;useGenericAttrs&gt; &lt;encoding&gt;</code></p>
    <a id="RHASSPY-parseParams"></a><b>General Remark:</b> RHASSPY uses <a href="https://wiki.fhem.de/wiki/DevelopmentModuleAPI#parseParams"><b>parseParams</b></a> at quite a lot places, not only in define, but also to parse attribute values. <p>
    So all parameters in define should be provided in the <i><b>key=value</i></b> form. In other places you may have to start e.g. a single line in an attribute with <code>option:key="value xy shall be z"</code> or <code>identifier:yourCode={fhem("set device off")} anotherOption=blabla</code> form. <br>
    <b>All parameters in define are optional, but changing them later might lead to confusing results*)!</b>
<ul>
  <li><b>WebIF</b>: http-address of the Rhasspy service web-interface. Optional. Default is <code>WebIF=http://127.0.0.1:12101</code>.<br>Make sure, this is set to correct values (IP and Port!</li>
  <li><b>devspec</b>: A description of devices that should be controlled by Rhasspy. Optional. Default is <code>devspec=room=Rhasspy</code>, see <a href="#devspec"> as a reference</a>, how to e.g. use a comma-separated list of devices or combinations like <code>devspec=room=livingroom,room=bathroom,bedroomlamp</code>.</li>
  <li><b>defaultRoom</b>: Default room name. Used to speak commands without a room name (e.g. &quot;turn lights on&quot; to turn on the lights in the &quot;default room&quot;). Optional. Default is <code>defaultRoom=default</code>.<br>
  <a id="RHASSPY-genericDeviceType"></a>Note: Additionaly, either one of the "special" attributes provided by RHASSPY or a known <i>genericDeviceType</i> (atm: switch, light, thermostat, blind and *)media are supported).</li>
  <li><b>language</b>: Makes part of the topic tree, RHASSPY is listening to. Should (but needs not to) point to the language voice commands shall be spoken with. Default is derived from global, which defaults to <code>language=en</code></li>
  <li><b>encoding</b>: May be helpfull in case you experience problems in conversion between RHASSPY (module) and Rhasspy (service). Example: <code>encoding=cp-1252</code>
  <li><b>fhemId</b>: May be used to distinguishe between different instances of RHASSPY on the MQTT side. Also makes part of the topic tree the corresponding RHASSPY is listening to.<br>
  Might be usefull, if you have several instances of FHEM running, and *) may be a criteria to distinguishe between different users (e.g. to only allow a subset of commands and/or rooms to be addressed).</li>
  <li><b>prefix</b>: May be used to distinguishe between different instances of RHASSPY on the FHEM-internal side.<br>
  Might be usefull, if you have several instances of RHASSPY in one FHEM running and want e.g. to use different identifier for groups and rooms (e.g. a different language).</li>
  <li><b>useGenericAttrs</b>: By default, RHASSPY only uses it's own attributes (see list below) to identifiy options for the subordinated devices you want to control. Activating this with <code>useGenericAttrs=1</code> adds <code>genericDeviceType</code> to the global attribute list ( *) for the future also <code>homebridgeMapping</code> may also be on the list) and activates RHASSPY's feature to estimate appropriate settings - similar to rhasspyMapping.
  </li>
</ul>
<p>RHASSPY needs a <a href="#MQTT2_CLIENT">MQTT2_CLIENT</a> device connected to the same MQTT-Server as the voice assistant (Rhasspy) service.</p>
<p>Example for defining an MQTT2_CLIENT device and the Rhasspy device in FHEM:</p>
<p>
  <code><pre>defmod rhasspyMQTT2 MQTT2_CLIENT rhasspy:12183
attr rhasspyMQTT2 clientOrder RHASSPY MQTT_GENERIC_BRIDGE MQTT2_DEVICE
attr rhasspyMQTT2 subscriptions hermes/intent/+ hermes/dialogueManager/sessionStarted hermes/dialogueManager/sessionEnded</pre></code>
  <code>define Rhasspy RHASSPY devspec=room=Rhasspy defaultRoom=Livingroom language=en</code>
</p>
<ul>
  <b>Note:</b><br>
  <a id="RHASSPY-list"></a>RHASSPY consolidates a lot of data from different sources. The <b>final data structure RHASSPY uses</b> at runtime you get using the <a href="#list">list command</a>. It's highly recommended to have a close look at this data structure, especially when starting with RHASSPY or in case something doesn't work as expected! <br> 
  When changing something relevant within FHEM for either the data structure in<ul>
  <li><b>RHASSPY</b> (this form is used when reffering to module or the FHEM device) or for </li>
  <li><b>Rhasspy</b> (this form is used when reffering to the remote service), </li></ul>
  these changes must be get to known to RHASSPY and (often, but not allways) to Rhasspy, see the different versions provided by the <a href="#RHASSPY-set-update">update command</a>.<br>
  </li>
</ul>

<a id="RHASSPY-set"></a>
<p><b>Set</b></p>
<ul>
  <li>
    <b><a id="RHASSPY-set-update">update</a></b><br>
    Choose between one of the following:
    <ul>
      <li><b>devicemap</b><br>
      When having finished the configuration work to RHASSPY and the subordinated devices, issuing a devicemap-update is mandatory, to get the RHASSPY data structure updated, inform Rhasspy on changes that may have occured (update slots) and initiate a training on updated slot values etc., see <a href="#RHASSPY-list">remarks on data structure above</a>.
      </li>
      <li><b>devicemap_only</b><br>
      This may be helpfull to make an intermediate check, whether attribute changes have found their way to the data structure. This will neither update slots nor initiate any training towards Rhasspy.
      </li>
      <li><b>slots</b><br>
      This may be helpfull after checks on the FHEM side to send all data to Rhasspy and initiate training.
      </li>
      <li><b>slots_no_training</b><br>
      This may be helpfull to make checks, whether all data is sent to Rhasspy. This will not initiate any training.
      </li>
      <li><b>language</b><br>
      Reinitialization of language file.<br>
      Be sure to execute this command after changing something within in the language configuration file!<br>
      Example: <code>set &lt;rhasspyDevice&gt update language</code>
      </li>
      <li><b>all</b><br>
      Surprise: means language file and full update to RHASSPY and Rhasspy including training.
      </li>
    </ul>
  </li>

  <li>
    <b><a id="RHASSPY-set-play">play</a></b><br>
    Send WAV file to Rhasspy.<br>
    <b>Not fully implemented yet</b><br>
    Both arguments (siteId and path) are required!<br>
    Example: <code>set &lt;rhasspyDevice&gt play siteId="default" path="/opt/fhem/test.wav"</code>
  </li>
  <li>
    <b><a id="RHASSPY-set-speak">speak</a></b><br>
    Voice output over TTS.<br>
    Both arguments (siteId and text) are required!<br>
    Example: <code>set &lt;rhasspyDevice&gt speak siteId="default" text="This is a test"</code>
  </li>
  <li>
    <b><a id="RHASSPY-set-textCommand">textCommand</a></b><br>
    Send a text command to Rhasspy.<br>
    Example: <code>set &lt;rhasspyDevice&gt textCommand turn the light on</code>
  </li>
  <li><b>fetchSiteIds</b>
    Send a request to Rhasspy to send all siteId's. This by default is done once, so in case you add more satellites to your system, this may help to get RHASSPY updated.
  </li>

  <li>
    <i><b>trainRhasspy</b><br>
    Sends a train-command to the HTTP-API of the Rhasspy master.<br>
    As prerequisite, <i>Rhasspy</i> (in define) has to point to correct IP and Port.<br>
    Example: <code>set &lt;rhasspyDevice&gt; trainRhasspy</code><br>
    *) Might be removed in the future in favor of the update features</i>
  </li>

  <li>
    <b><a id="RHASSPY-set-volume">volume</a></b><br>
    Sets volume of given siteId between 0 and 1 (float)<br>
    Both arguments (siteId and volume) are required!<br>
    Example: <code>set &lt;rhasspyDevice&gt; siteId="default" volume="0.5"</code>
  </li>
    <li>
    <s><b>updateSlots</b><br>
    Sends a command to the HTTP-API of the Rhasspy master to update all slots on Rhasspy with actual FHEM-devices, rooms, etc.<br>
    The attribute <i>rhasspyMaster</i> has to be defined to work.<br>
    Example: <code>set &lt;rhasspyDevice&gt; updateSlots</code><br>
    Do not forget to train Rhasspy afterwards!</s> (deprecated)
  </li>
    <li>
    <b><a id="RHASSPY-set-customSlot">customSlot</a></b><br>
    Provide slotname, slotdata and (optional) info, if existing data shall be overwritten and training shall be initialized immediately afterwards. 
    First two arguments are required, third and fourth are optional!<br>
    <i>overwrite</i> defaults to <i>true</i>, setting any other value than <i>true</i> will keep existing Rhasspy slot data.<br>
    Examples: <code>set &lt;rhasspyDevice&gt; customSlot mySlot a,b,c overwrite training </code> or 
    <code>set &lt;rhasspyDevice&gt; customSlot slotname=mySlot slotdata=a,b,c overwrite=false</code>
  </li>

  
</ul>
<a id="RHASSPY-attr"></a>
<p><b>Attributes</b></p>
    Note: To get RHASSPY to work properly, you have to configure attributes at RHASSPY itself and the subordinated devices as well! 
   <p><b>RHASSPY itself</b> supports the following attributes:</p>
  <ul>
  <li>
    <a id="RHASSPY-attr-rhasspyMaster"></a><b>rhasspyMaster</b><br>
    Defines the URL to the Rhasspy Master for sending requests to the HTTP-API. Has to be in Format <code>protocol://fqdn:port</code>
    This attribute is <b>mandatory</b>!<br>
    Example: <code>attr &lt;rhasspyDevice&gt; rhasspyMaster http://rhasspy.example.com:12101</code>
  </li>
  <li>
    <a id="RHASSPY-attr-configFile"></a><b>configFile</b>
    Path to the language-config file. If this attribute isn't set, a default set of english responses is used for voice responses.<br>
    Example (placed in the same dir fhem.pl is located): <code>attr &lt;rhasspyDevice&gt; configFile ./rhasspy-de.cfg</code>
    The file itself must contain a JSON-encoded keyword-value structure (partly with sub-structures) following the given structure for the mentionned english defaults. As a reference, there's one available in German also, or just make a dump of the English structure with e.g. (replace RHASSPY by your device's name): <br><code>{toJSON($defs{RHASSPY}->{helper}{lng})}</code>, edit the result e.g. using https://jsoneditoronline.org and place this in your own configFile version. There might be some variables to be used - these should also work in your sentences.<br>
    configFile also allows combining e.g. a default set of German sentences with some few own modifications by using "defaults" subtree for the defaults and "user" subtree for your modified versions. This feature might be helpfull in case the base language structure has to be changed in the future.
  </li>
  <li>
    <b>response</b><br>
    Optionally define alternative default answers. Available keywords are <code>DefaultError</code>, <code>NoActiveMediaDevice</code> and <code>DefaultConfirmation</code>.<br>
    Example:
    <pre><code>DefaultError=
DefaultConfirmation=Klaro, mach ich</code></pre><p>
    Note: Kept for compability reasons. Consider using configFile instead!
  </li>
  <li>
    <a id="RHASSPY-attr-rhasspyIntents"></a><b>rhasspyIntents</b><br>
    Optional, defines custom intents. See <a href="https://github.com/Thyraz/Snips-Fhem#f%C3%BCr-fortgeschrittene-eigene-custom-intents-erstellen-und-in-fhem-darauf-reagieren" hreflang="de">Custom Intent erstellen</a>.<br>
    One intent per line.<br>
    Example: <code>attr &lt;rhasspyDevice&gt; rhasspyIntents SetCustomIntentsTest=SetCustomIntentsTest(siteId,Device)</code>
    together with the follwoing myUtils-Code should get a short impression of the possibilities:
    <code><pre>sub SetCustomIntentsTest {
        my $room = shift; 
        my $type = shift;
        Log3('rhasspy',3 , "RHASSPY: Room $room, Type $type");
        return "RHASSPY: Room $room, Type $type";
    }</pre></code>
    The following arguments can be handed over:<br>
    <ul>
    <li>NAME => name of the RHASSPY device addressed, </li>
    <li>DATA => entire JSON-$data (as parsed internally), </li>
    <li>siteId, Device etc. => any element out of the JSON-$data.</li>
    </ul>
  </li>
  <li>
    <a id="RHASSPY-attr-shortcuts"></a><b>shortcuts</b><br>
    Define custom sentences without editing Rhasspy sentences.ini<br>
    The shortcuts are uploaded to Rhasspy when using the updateSlots set-command.<br>
    One shortcut per line, syntax is either a simple and an extended version:<br>
    
    Examples:<pre><code>mute on=set amplifier2 mute on
lamp off={fhem("set lampe1 off")}
i="you are so exciting" f="set $NAME speak siteId='livingroom' text='Thanks a lot, you are even more exciting!'"
i="mute off" p={fhem ("set $NAME mute off")} n=amplifier2 c="Please confirm!"
    </code></pre>
    Abbreviations explanation:
    <ul>
    <li>i => intent<br>
    Lines starting with "i:" will be interpreted as extended version, so if you want to use that syntax style, starting with "i:" is mandatory.</li> 
    <li>f => FHEM command<br>
    Syntax as usual in FHEMWEB command field.</li>
    <li>p => Perl command<br>
    Syntax as usual in FHEMWEB command field, enclosed in {}; this has priority to "f=".
    </li>
    <li>n => device name(s, comma separated) that shall be handed over to fhem.pl as updated. Needed for triggering further actions and longpoll! If not set, the return value of the called function will be used. </li>
    <li>r => Response to be set to the caller. If not set, the return value of the called function will be used.</li>
    You may ask for confirmation as well using the following (optional) shorts:
    <li>c => either numeric or text. If numeric: Timeout to wait for automatic cancellation. If text: response to send to ask for confirmation.</li>
    <li>ct => numeric value for timeout in seconds, default: 15.</li>
    </ul>
  </li>
  <li>
  <a id="RHASSPY-attr-rhasspyTweaks"></a><b>rhasspyTweaks</b><br>
    *) placeholder...<br>
    Might be the place to configure additional things like additional siteId2room info or code links, allowed commands, duration of SetTimer sounds, confirmation requests etc.     
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
<ul>
    <p><b>For the subordinated devices</b>, a list of the possible attributes is automatically extended by several further entries. 
    Their names all start with the prefix previously defined in RHASSPY - except for <a href="#RHASSPY-genericDeviceType">genericDeviceType</a> (gDT). These attributes are used to configure the actual mapping to the intents and content sent by Rhasspy.<br/>
    Note: As the analyses of the gDT is intented *) to lead to fast configuration progress, it's highly recommended to use this as a starting point. All other RHASSPY-specific attributes will then be considered as a user command to <b>overwrite</b> the results provided by the automatics initiated by gDT usage.
    
    By default, the following attribute names are used: rhasspyName, rhasspyRoom, rhasspyGroup, rhasspyChannels, rhasspyColors, rhasspySpecials.<br>
    Each of the keywords found in these attributes will be sent by <a href="#RHASSPY-set-update">update</a> to Rhasspy to make part of the corresponding slot.<br>
    <br/>The meaning of these attributes is explained below.
    <ul>
    <li>
    <b><a id="RHASSPY-attr-rhasspyName">rhasspyName</a></b><br>
    Comma-separated "labels" for the subordineted device. They will be used as keywords by Rhasspy. May contain space or mutated vovels.<br>
    Example: <code>attr m2_wz_08_sw rhasspyName kitchen lamp,ceiling lamp,workspace,whatever</code><br>
    Needs not to be unique, as long as identification is possible by room (derived from siteId) (or group).
    </li>
    <li>
    <b><a id="RHASSPY-attr-rhasspyRoom">rhasspyRoom</a></b><br>
    Comma-separated "labels" for the "rooms" the subordineted device is located. Recommended to be unique.<br>
    For further details see <i>rhasspyName</i>.
    </li>
    <li>
    <b><a id="RHASSPY-attr-rhasspyGroup">rhasspyGroup</a></b><br>
    Comma-separated "labels" for the "groups" the subordineted device makes part of. Recommended to be unique.<br> For further details see <i>rhasspyRoom</i>.
    </li>
    
    
    <li>
    <b><a id="RHASSPY-attr-Mapping">rhasspyMapping</a></b><br>
    If automatic detection does not work or is not desired, this is the central place to get your devices work with RHASSPY:
    Example: <pre><code>attr lamp rhasspyMapping SetOnOff:cmdOn=on,cmdOff=off,response="All right"
GetOnOff:currentVal=state,valueOff=off
GetNumeric:currentVal=pct,type=brightness
SetNumeric:currentVal=brightness,minVal=0,maxVal=255,map=percent,cmd=brightness,step=1,type=brightness
Status:response=The temperature in the kitchen is at [lamp:temparature] degrees
MediaControls:cmdPlay=play,cmdPause=pause,cmdStop=stop,cmdBack=previous,cmdFwd=next</pre></code>
    </li>
    
    
    <li>
    <b><a id="RHASSPY-attr-rhasspyChannels">rhasspyChannels</a></b><br>
    key=value line by line arguments mapping command strings to fhem- or Perl commands.
    Example: <pre><code>attr m2_wz_08_sw rhasspyChannels orf eins=set lampe1 on
orf zwei=set lampe1 off
orf drei=set lampe1 on
</pre></code><br>
    </li>
    <li>
    <b><a id="RHASSPY-attr-rhasspyColors">rhasspyColors</a></b><br>
    key=value line by line arguments mapping keys to setter strings on the same device.
    Example: <pre><code>attr lamp1 rhasspyColors red=rgb FF0000
green=rgb 00FF00
blue=rgb 0000FF
yellow=rgb 00F000</pre></code><br>
    </li>
    <li>
    <b><a id="RHASSPY-attr-rhasspySpecials">rhasspySpecials</a></b><br>
    key=value line by line arguments similar to <a href="#RHASSPY-attr-rhasspyTweaks">rhasspyTweaks</a>.
    Example: </pre><code>attr lamp1 rhasspySpecials group:async_delay=100 prio=1 group=lights</pre></code><br>
    *) At the moment, only group related stuff is implemented, this could be the place to hold additional options, e.g. for confirmation requests
    Explanation on the above group line, all arguments are optional:
    <ul>
    <li>group<br>
    If set, the device will not be directly addressed, but the mentioned group - typically a FHEM <a href="#structure">structure</a> device or a HUEDevice-type group. This has the advantage of saving RF ressources and/or already implemented logics. Note: all addressed devices will be switched, even if they are not member of the rhasspyGroup! Each group should only be addressed once, but it's recommended to put this info in all devices beeing unter RHASSPY control in the same external group logic.
    <li>async_delay<br>
    Float nummeric value, just as async_delay in structure; the delay will be obeyed prior to the next sending command.</li> 
    <li>prio<br>
    Numeric value, defaults to "0". <i>prio</i> and <i>async_delay</i> will be used to determine the sending order as follows: first devices will be those with lowest prio arg, second sort argument is <i>async_delay</i> with lowest value first </li>
    </ul>
    </li>

    </ul>

    
    </p>
<ul>
   <a id="RHASSPY-intent"></a><p><b>intents</b>
   <p>The following intents are directly implemented in RHASSPY code:
   <ul>
    <li>Shortcuts</li>
    <li>SetOnOff</li>
    <li>SetOnOffGroup</li>
    <li>GetOnOff</li>
    <li>SetNumeric</li>
    <li>GetNumeric</li>
    <li>Status</li>
    <li>MediaControls</li>
    <li>MediaChannels</li>
    <li>SetColor</li>
    <li>GetTime</li>
    <li>GetWeekday</li>
    <li>SetTimer</li>
    <li>ConfirmAction</li>
    <li>ReSpeak</li>
   </ul>
</ul>

=end html
=cut
