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
use Data::Dumper;

sub ::RHASSPY_Initialize { goto &RHASSPY_Initialize }

my %gets = (
    version => q{},
    status  => q{}
);

my %sets = (
    speak        => [],
    play         => [],
    updateSlots  => [],
    textCommand  => [],
    trainRhasspy => [],
    fetchSiteIds => [],
    reinit       => [qw(language)]
#    "volume" => ""
);

=pod
my $languagevars = {
    'de' => {
        'commaconversion' => '1',
        'mutated_vowels' => { 'ä' => 'ae', 'Ä' => 'Ae', 'ü' => 'ue', 'Ü' => 'Ue', 'ö' => 'oe', 'Ö' => 'Oe', 'ß' => 'ss' },
        'responses'      => { 'DefaultError' => "Da ist leider etwas schief gegangen.",
                              'NoActiveMediaDevice' => "Tut mir leid, es ist kein Wiedergabegerät aktiv.",
                              'DefaultConfirmation' => "OK",
                              'timerSet'   => 'Taimer in $room gesetzt auf $value $unit.',
                              'timerEnd'   => "taimer abgelaufen",
                              'duration_not_understood'   => "Tut mir leid ich habe die Dauer nicht verstanden"
                            }
    },
    'en' => {
        'responses'      => { 'DefaultError' => "Sorry but something seems not to work as expected.",
                              'NoActiveMediaDevice' => "Sorry no active playback device.",
                              'DefaultConfirmation' => "OK",
                              'timerSet'   => 'Timer in $room has been set to $value $unit',
                              'timerEnd'   => "Timer expired",
                              'duration_not_understood'   => "Sorry I could not understand the desired duration."
                            }
    }
};
=cut

my $languagevars = {
  'on' => "on",
  'percent' => 'percent',
  'units' => {
      'unitHours' => '(hour|hours)',
      'unitMinutes' => '(minute|minutes)'
   },
  'responses' => { 
     'DefaultError' => "Sorry but something seems not to work as expected.",
     'NoActiveMediaDevice' => "Sorry no active playback device.",
     'DefaultConfirmation' => "OK",
     'timerSet'   => 'Timer in $room has been set to $value $unit',
     'timerEnd'   => "Timer expired",
     'timeRequest' => 'it is $hour o clock $min minutes',
     'weekdayRequest' => 'today it is $weekDay',
     'duration_not_understood'   => "Sorry I could not understand the desired duration."
  },
  'Change' => {
    'Media' => {
       'pause' => 'cmdPause',
       'play' => 'cmdPlay',
       'stop' => 'cmdStop',
       'forward' => 'cmdFwd',
       'backward' => 'cmdBack'
                },
    'Types' => {
       'airHumidity' => 'air humidity',
       'battery' => 'battery',
       'brightness' => 'brightness',
       'soilMoisture' => 'soil moisture',
       'targetValue' => 'target value',
       'temperature' => 'temperature',
       'volumeSound' => 'volume',
       'waterLevel' => 'water level'
    },
    'regex' => {
       'darker' => 'brightness',
       'brighter' => 'brightness',
       'cooler' => 'temperature',
       'louder' => 'volumeSound',
       'lower' => 'volumeSound',
       'warmer' => 'temperature',
       'setTarget' => '(brightness|volume|target.volume)',
       'upward' => '(higher|brighter|louder|rise|warmer)',
       'volumeSound' => 'sound volume'
    },
    'responses' => {
       'airHumidity' => 'air humidity in $location is $value percent',
       'battery' => {
         '0' => 'battery level in $location is $value',
         '1' => 'battery level in $location is $value percent'
       },
       'brightness' => '$device was set to $value',
       'soilMoisture' => 'soil moisture in $location is $value percent',
       'temperature' => {
         '0' => 'temperature in $location is $value',
         '1' => 'temperature in $location is $value degrees',
       },
       'volumeSound' => '$device has been set to $value',
       'waterLevel' => 'water level in $location is $value percent',
       'knownType' => '$mappingType in $location is $value percent',
       'unknownType' => 'value in $location is $value percent'
    }
  },
  'stateResponseType' => {
     'on' => 'onOff',
     'off' => 'onOff',
     'open' => 'openClose',
     'closed' => 'openClose',
     'in' => 'inOut',
     'out' => 'inOut',
     'ready' => 'inOperation',
     'acting' => 'inOperation'
     },
  'stateResponses' => {
     'inOperation' => {
       '0' => '$device is ready',
       '1' => '$device is still running'
     },
     'inOut' => {
       '0' => '$device is out',
       '1' => '$device is in'
     },
     'onOff' => {
       '0' => '$device is off',
       '1' => '$device is on'
     },
     'openClose' => {
       '0' => '$device is open',
       '1' => '$device is closed'
     }
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
    $hash->{Match}       = ".*";
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
    $hash->{MODULE_VERSION} = "0.2.1";
    $hash->{helper}{defaultRoom} = $defaultRoom;
    initialize_Language($hash, $language) if !defined $hash->{LANGUAGE} || $hash->{LANGUAGE} ne $language;
    $hash->{LANGUAGE} = $language;
    
    initialize_prefix($hash, $h->{prefix}) if !defined $hash->{prefix} || $hash->{prefix} ne $h->{prefix};
    $hash->{prefix} = $h->{prefix} // q{rhasspy};
    
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

    #RemoveInternalTimer($hash);
    
    IOWrite($hash, 'subscriptions', join q{ }, @topics) if InternalVal($IODev,'TYPE',undef) eq 'MQTT2_CLIENT'; # isIODevMQTT2_CLIENT($hash);

    return;
}

sub initialize_Language {
    my $hash = shift // return;
    my $lang = shift // return;
    my $cfg  = shift // AttrVal($hash->{NAME},'configFile',undef);
    
    my $lngvars = $languagevars;
    
    #default to english first
    $hash->{helper}{lng} = $lngvars if !$init_done || !defined $hash->{helper}{lng};

    my ($ret, $content) = RHASSPY_readLanguageFromFile($hash, $cfg);
    return $ret if $ret;
    my $decoded = eval { decode_json(encode_utf8($content)) };
    if ($@) {
          Log3($hash->{NAME}, 1, "JSON decoding error in languagefile $cfg: " . $@);
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
    #my ($hash, $name, $command, @values) = @_;
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
                      .':'
                      .join ',', @{$sets{$_}} : $_} sort keys %sets)
    if !defined $sets{$command};

    Log3($name, 5, "set " . $command . " - value: " . join (" ", @values));

    
    my $dispatch = {
        updateSlots  => \&RHASSPY_updateSlots,
        trainRhasspy => \&RHASSPY_trainRhasspy,
        fetchSiteIds => \&RHASSPY_fetchSiteIds
    };
    
    return $dispatch->{$command}->($hash) if (ref $dispatch->{$command} eq 'CODE');
    
    $values[0] = $h->{text} if ($command eq 'speak' || $command eq 'textCommand' ) && defined $h->{text};

    $dispatch = {
        speak       => \&RHASSPY_speak,
        textCommand => \&RHASSPY_textCommand,
        play        => \&RHASSPY_playWav
    };
    
    return Log3($name, 3, "set $name $command requires at least one argument!") if !@values;
    
    my $params = join q{ }, @values;
    $params = $h if defined $h->{text};
    return $dispatch->{$command}->($hash, $params) if (ref $dispatch->{$command} eq 'CODE');
    
    if ($command eq 'reinit') {
        if ($values[0] eq 'language') {
            return initialize_Language($hash, $hash->{LANGUAGE});
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
        }
        return initialize_Language($hash, $hash->{LANGUAGE}, $value); 
    }
    
    return;
}

sub RHASSPY_init_shortcuts {
    my $hash    = shift // return;
    my $attrVal = shift // return;
    
    my ($intend, $perlcommand, $device, $err );
    for my $line (split m{\n}x, $attrVal) {
        #old syntax
        if ($line !~ m{\A[\s]*i=}x) {
            ($intend, $perlcommand) = split q{=}, $line, 2;
            $err = perlSyntaxCheck( $perlcommand );
            return "$err in $line" if $err && $init_done;
            $hash->{helper}{shortcuts}{$intend}{perl} = $perlcommand;
            $hash->{helper}{shortcuts}{$intend}{NAME} = $hash->{NAME};
            next;
        } 
        next if !length $line;
        my($unnamed, $named) = parseParams($line); 
        #return "unnamed parameters are not supported! (line: $line)" if ($unnamed) > 1 && $init_done;
        $intend = $named->{i};
        if (defined($named->{f})) {
            $hash->{helper}{shortcuts}{$intend}{fhem} = $named->{f};
        } elsif (defined($named->{p})) {
            $err = perlSyntaxCheck( $perlcommand );
            return "$err in $line" if $err && $init_done;
            $hash->{helper}{shortcuts}{$intend}{perl} = $named->{p};
        } elsif ($init_done) {
            return "Either a fhem or perl command have to be provided!";
        }
        $hash->{helper}{shortcuts}{$intend}{NAME} = $named->{n} if defined($named->{n});
        $hash->{helper}{shortcuts}{$intend}{response} = $named->{r} if defined($named->{r});
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
        
        $hash->{helper}{custom}{$+{intent}}{perl} = $perlcommand; #Beta-User: delete after testing!
        $hash->{helper}{custom}{$intent}{function} = $function;

        my $args = trim($+{arg});
        my @params;
        for my $ar (split m{,}x, $args) {
           $ar =trim($ar);
           next if $ar eq q{};
           push @params, $ar; 
        }
        #push @params, \$hash;
        $hash->{helper}{custom}{$+{intent}}{args} = @params;
        $hash->{helper}{custom}{$+{intent}}{argslong} = join q{,}, @params; #Beta-User: delete after testing!
        
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

# Alle Gerätenamen sammeln
sub RHASSPY_allRhasspyNames {
    my $hash = shift // return;
    my $devspec = 'room=Rhasspy';
    my @devs = devspec2array($devspec);
    my @devices;
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
    my @rooms;

    my $prefix = $hash->{prefix};
    # Alle RhasspyNames sammeln
    for (devspec2array(q{room=Rhasspy})) {
        my $attrv = AttrVal($_,"${prefix}Room",undef) // next;
        push @rooms, split m{,}x, $attrv;
    }
    return get_unique(\@rooms, 1 );
}


# Alle Sender sammeln
sub RHASSPY_allRhasspyChannels {
    my $hash = shift // return;
    my @channels; #, my @sorted;

    my $prefix = $hash->{prefix};
    # Alle RhasspyNames sammeln
    for (devspec2array(q{room=Rhasspy})) { # $devspec)) {
        my $attrv = AttrVal($_,"${prefix}Channels",undef) // next;
        my @rows = split m{\n}x, $attrv;
        for (@rows) {
            my @tokens = split('=', $_);
            #my $channel = shift(@tokens);
            #push @channels, $channel;
            push @channels, shift @tokens;
        }
    }
    return get_unique(\@channels, 1 );
}


# Alle NumericTypes sammeln
sub RHASSPY_allRhasspyTypes {
    my $hash = shift // return;
    my @types;
    my $devspec = q{room=Rhasspy};
    my @devs = devspec2array($devspec);

    my $prefix = $hash->{prefix};
    # Alle RhasspyNames sammeln
    for (@devs) {
        my $attrv = AttrVal($_,"${prefix}Mapping",undef) // next;
        my @mappings = split m{\n}x, $attrv;
        for (@mappings) {
            # Nur GetNumeric und SetNumeric verwenden
            next if $_ !~ m/^(SetNumeric|GetNumeric)/;
            $_ =~ s/(SetNumeric|GetNumeric)://;
            my %mapping = RHASSPY_splitMappingString($_);

            push @types, $mapping{type} if (defined($mapping{type}));
        }
    }
    return get_unique(\@types, 1 );
}


# Alle Farben sammeln
sub RHASSPY_allRhasspyColors {
    my $hash = shift // return;
    my @colors;
    my $devspec = q{room=Rhasspy};
    my @devs = devspec2array($devspec);

    my $prefix = $hash->{prefix};
    # Alle RhasspyNames sammeln
    for(@devs) {
        my $attrv = AttrVal($_,"${prefix}Colors",undef) // next;
        for (split m{\n}x, $attrv) {
            my @tokens = split m{=}x, $_;
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
    my $device;
    my $devspec = q{room=Rhasspy};
    my @devices = devspec2array($devspec);

    my $prefix = $hash->{prefix};
    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);

    for (@devices) {
        # 2 Arrays bilden mit Namen und Räumen des Devices
        my @names = split m{,}x, AttrVal($_,"${prefix}Name",q{});
        my @rooms = split m{,}x, AttrVal($_,"${prefix}Room",q{});

        # Case Insensitive schauen ob der gesuchte Name (oder besser Name und Raum) in den Arrays vorhanden ist
#        if (grep( /^$name$/i, @names)) {
        if (grep { /^$name$/i } @names ) {
            if (!defined($device) || grep( { /^$room$/i} @rooms)) {
                $device = $_;
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
    
    my @matchesInRoom, my @matchesOutsideRoom;
    my $devspec = q{room=Rhasspy};
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);

    my $prefix = $hash->{prefix};
    for(@devices) {
        # Array bilden mit Räumen des Devices
        my @rooms = split m{,}x, AttrVal($_,"${prefix}Room",undef);
        # Mapping mit passendem Intent vorhanden?
        my $mapping = RHASSPY_getMapping($hash, $_, $intent, $type, 1) // next;

        my $mappingType = $mapping->{type};

        # Geräte sammeln
        if (!defined($type)) {
            grep ( {/^$room$/i} @rooms)
                ? push @matchesInRoom, $_ 
                : push @matchesOutsideRoom, $_;
        }
        elsif (defined($type) && $mappingType && $type =~ m/^$mappingType$/i) {
            grep( {/^$room$/i} @rooms)
            ? push @matchesInRoom, $_
            : push @matchesOutsideRoom, $_;
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
    $device = (@{$matchesInRoom}) ? shift @{$matchesInRoom} : shift @{$matchesOutsideRoom};

    Log3($hash->{NAME}, 5, "Device selected: $device");

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
            my $mapping = RHASSPY_getMapping($subhash, $_, 'GetOnOff', undef, 1);
            if (defined($mapping)) {
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
    my $devspec = q{room=Rhasspy};
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);
    
    my $prefix = $hash->{prefix};
    for (@devices) {
        my $attrv = AttrVal($_,"${prefix}Room",undef) // next;
        my @rooms = split m{,}x, $attrv;
        my $cmd = RHASSPY_getCmd($hash, $_, "${prefix}Channels", $channel, 1) // next;
        
        # Erster Treffer wälen, überschreiben falls besserer Treffer (Raum matched auch) kommt
        if (!defined $device || grep {/^$room$/i} @rooms) {
            $device = $_;
        }
    }

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Mappings in Key/Value Paare aufteilen
sub RHASSPY_splitMappingString {
    my $mapping = shift // return;
    my @tokens, my $token = q{};
    #my $char, 
    my $lastChar = q{};
    my $bracketLevel = 0;
    my %parsedMapping;

    # String in Kommagetrennte Tokens teilen
    for my $char (split(//, $mapping)) {
        if ($char eq '{' && $lastChar ne '\\') {
            $bracketLevel += 1;
            $token .= $char;
        }
        elsif ($char eq '}' && $lastChar ne '\\') {
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
    my $device     = shift;
    my $intent     = shift;
    my $type       = shift; #Beta-User: any necessary parameters...?
    my $disableLog = shift // 0;
    
    my @mappings, my $matchedMapping;
    
    my $prefix = $hash->{prefix};
    my $mappingsString = AttrVal($device, "${prefix}Mapping", undef);

    if (defined($mappingsString)) {
        # String in einzelne Mappings teilen
        @mappings = split m{\n}x, $mappingsString;

        for (@mappings) {
            # Nur Mappings vom gesuchten Typ verwenden
            next if $_ !~ qr/^$intent/;
            $_ =~ s/$intent://;
            my %currentMapping = RHASSPY_splitMappingString($_);

            # Erstes Mapping vom passenden Intent wählen (unabhängig vom Type), dann ggf. weitersuchen ob noch ein besserer Treffer mit passendem Type kommt
            if (!defined $matchedMapping || defined $type && lc($matchedMapping->{type}) ne lc($type) && lc($currentMapping{type}) eq lc($type)) {
                $matchedMapping = \%currentMapping;

                Log3($hash->{NAME}, 5, "${prefix}Mapping selected: $_") if !$disableLog;
            }
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
        next if $_ !~ qr/^$key=/i;
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
        #$cmd =~ s{\A\s*"}{}x;
        #$cmd =~ s{"\s*\z}{}x;
        $cmd = $+{inner};

        # Variablen ersetzen?
        eval { $cmd =~ s/(\$\w+)/$1/eeg; };

        # [DEVICE:READING] Einträge ersetzen
        $returnVal = RHASSPY_ReplaceReadingsVal($hash, $cmd);
        # Escapte Kommas wieder durch normale ersetzen
        $returnVal =~ s/\\,/,/;
        Log3($hash->{NAME}, 5, "...and is now: $cmd ($returnVal)");
    }
    # FHEM Command oder CommandChain
    elsif (defined($cmds{ (split " ", $cmd)[0] })) {
        my @test = split q{ }, $cmd;
        Log3($hash->{NAME}, 5, "$cmd is a FHEM command");
        $error = AnalyzeCommandChain($hash, $cmd);
        $returnVal = $test[1];
    }
    # Soll Command auf anderes Device umgelenkt werden?
    elsif ($cmd =~ m/:/) {
        $cmd   =~ s/:/ /;
        $cmd   = qq($cmd $val) if defined($val);
        Log3($hash->{NAME}, 5, "$cmd redirects to another device");
        $error = AnalyzeCommand($hash, "set $cmd");
    }
    # Nur normales Cmd angegeben
    else {
        $cmd   = qq($device $cmd);
        $cmd   = qq($cmd $val) if defined($val);
        Log3($hash->{NAME}, 5, "$cmd is a normal command");
        $error = AnalyzeCommand($hash, "set $cmd");
    }
    Log3($hash->{NAME}, 1, $_) if (defined($error));

    return $returnVal;
}

# Wert über Format 'reading', 'device:reading' oder '{<perlcode}' lesen
sub RHASSPY_getValue { #($$$;$$)
    #my ($hash, $device, $getString, $val, $siteId) = @_;
    my $hash      = shift // return;
    my $device    = shift // return;
    my $getString = shift // return;
    my $val       = shift;
    my $siteId    = shift;
    
    #my $value;

    # Perl Command? -> Umleiten zu RHASSPY_runCmd
    if ($getString =~ m{\A\s*\{.*\}\s*\z}x #) { 
        # Wert lesen
        #$value = RHASSPY_runCmd($hash, $device, $getString, $val, $siteId);
    ##}
    # String in Anführungszeichen -> Umleiten zu RHASSPY_runCmd
    #elsif (
        || $getString =~ m/^\s*".*"\s*$/) {
        # Wert lesen
        #$value = RHASSPY_runCmd($hash, $device, $getString, $val, $siteId);
        return RHASSPY_runCmd($hash, $device, $getString, $val, $siteId);
    }
    # Reading oder Device:Reading
    #else {
      # Soll Reading von einem anderen Device gelesen werden?
      if ($getString =~ m{:}x) {
          my @replace = split m{:}x, $getString;
          $device = $replace[0];
          $getString = $replace[1] // $getString;
      }
      #$value = ReadingsVal($device, $getString, 0);
      return ReadingsVal($device, $getString, 0);
    #}

    #return $value;
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
    if (defined($valueOff)) {
        $value eq lc($valueOff) ? return 0 : return 1;
    } 
    if (defined($valueOn)) {
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

    # JSON Decode und Fehlerüberprüfung
    my $decoded = eval { decode_json(encode_utf8($json)) };
    if ($@) {
          Log3($hash->{NAME}, 1, "JSON decoding error: " . $@);
          return;
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

            $slotValue = $slot->{value}{value} if exists $slot->{value}{value};
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
    my $cptopic = $topic;
    $cptopic =~ m{([^/]+/[^/]+/)}x;
    my $shorttopic = $1;
    
    return q{[NEXT]} if !grep( {m{\A$shorttopic}x} @topics);
    
    my @instances = devspec2array('TYPE=RHASSPY');

    for my $dev (@instances) {
        my $hash = $defs{$dev};
        # Name mit IODev vergleichen
        next if $ioname ne AttrVal($hash->{NAME}, 'IODev', undef);
        next if IsDisabled( $hash->{NAME} );

        Log3($hash,5,"RHASSPY: [$hash->{NAME}] Parse (IO: ${ioname}): Msg: $topic => $value");

        my $fret = RHASSPY_onmessage($hash, $topic, $value);
        next if !defined $fret;
        if( ref($fret) eq 'ARRAY' ) {
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
    my $data  = RHASSPY_parseJSON($hash, $message);

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
            my $keys = join q{|}, keys %{$mutated_vowels};
            #Log3($hash->{NAME}, 5, "mutated_vowels regex is $keys");

            $room =~ s/($keys)/$mutated_vowels->{$1}/g;
        }

        if ($topic =~ m/sessionStarted/) {
            readingsSingleUpdate($hash, "listening_" . makeReadingName($room), 1, 1);
        } elsif ($topic =~ m/sessionEnded/) {
            readingsSingleUpdate($hash, "listening_" . makeReadingName($room), 0, 1);
        }
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ($topic =~ qr/^hermes\/intent\/.*[:_]SetMute/ && defined $siteId) {
        $type = $message =~ m{fhem.textCommand}x ? 'text' : 'voice';
        $data->{requestType} = $type;

        # update Readings
        RHASSPY_updateLastIntentReadings($hash, $topic,$data);
        RHASSPY_handleIntentSetMute($hash, $data);
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    return if $mute;
    
    my $command = $data->{input};
    $type = $message =~ m{fhem.textCommand}x ? 'text' : 'voice';
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
        SetTimer      => \&RHASSPY_handleIntentSetTimer
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
sub RHASSPY_respond { #($$$$$)
    #my ($hash, $type, $sessionId, $siteId, $response) = @_;
    my $hash      = shift // return;
    my $type      = shift // return;
    my $sessionId = shift // return;
    my $siteId    = shift // return;
    my $response  = shift // return;
    
    #my $json;

    my $sendData =  {
        sessionId => $sessionId,
        siteId => $siteId,
        text => $response
    };

    my $json = toJSON($sendData);

    if ($type eq 'voice') {
        readingsSingleUpdate($hash, 'voiceResponse', $response, 1);
    }
    elsif ($type eq 'text') {
        readingsSingleUpdate($hash, 'textResponse', $response, 1);
    }
    readingsSingleUpdate($hash, 'responseType', $type, 1);
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
         sessionId => 'fhem.textCommand'
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
        id => "0",
        sessionId => "0"
    };
    if (ref $cmd eq 'HASH') {
        $sendData->{siteId} =  $cmd->{siteId};
        $sendData->{text} =  $cmd->{text};
    } else {    
        my $siteId = 'default';
        my $text = $cmd;
        my($unnamedParams, $namedParams) = parseParams($cmd);
    
        if (defined($namedParams->{siteId}) && defined($namedParams->{text})) {
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
    my $method = q{POST};
    my $contenttype = q{application/json};

    # Collect everything and store it in arrays
    my @devices   = RHASSPY_allRhasspyNames($hash);
    my @rooms     = RHASSPY_allRhasspyRooms($hash);
    my @channels  = RHASSPY_allRhasspyChannels($hash);
    my @colors    = RHASSPY_allRhasspyColors($hash);
    my @types     = RHASSPY_allRhasspyTypes($hash);
    my @shortcuts = keys %{$hash->{helper}{shortcuts}};

#print Dumper($hash->{helper}{shortcuts});
    if (@shortcuts) {
#        my $json;
        my $deviceData;
        my $url = q{/api/sentences};
        
        $deviceData =qq({"intents/${language}.fhem.Shortcuts.ini":"[${language}.fhem:Shortcuts]\\n);
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
      my $url = "/api/slots";

      $deviceData->{qq(${language}.fhem.Device)}        = \@devices if @devices;
      $deviceData->{qq(${language}.fhem.Room)}          = \@rooms if @rooms;
      $deviceData->{qq(${language}.fhem.MediaChannels)} = \@channels if @channels;
      $deviceData->{qq(${language}.fhem.Color)}         = \@colors if @colors;
      $deviceData->{qq(${language}.fhem.NumericType)}   = \@types if @types;

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
    my $err = shift;
    my $data = shift;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $url = $param->{url};

    readingsBeginUpdate($hash);

    if (grep {/api\/train/i} $url) {
        readingsBulkUpdate($hash, 'training', $data);
    }
    elsif (grep {/api\/sentences/i} $url) {
        readingsBulkUpdate($hash, 'updateSentences', $data);
    }
    elsif (grep {/api\/slots/i} $url) {
        readingsBulkUpdate($hash, 'updateSlots', $data);
    }
    elsif (grep {/api\/profile/i} $url) {
        my $ref = decode_json($data);
        my $siteIds = encode('cp-1252',$ref->{dialogue}{satellite_site_ids});
        readingsBulkUpdate($hash, 'siteIds', $siteIds);
    }
    else {
        Log3($hash->{NAME}, 3, qq(error while requesting $param->{url} - $data));
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
    my @paramNames = $custom->{args};

    if (defined $subName) { #might not be necessary...
        my @params = map { $data->{$_} } @paramNames;
        my $params = join q{,}, @params;
        my $cmd = qq{ $subName( $params , $hash) };
        Log3($hash->{NAME}, 5, "Calling sub: $cmd");
        my $error = AnalyzePerlCommand($hash, $cmd);
        $response = $error if $error !~ m{Please.define.*first}x;
      
    }
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');

    # Antwort senden
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}

# Handle incoming "SetMute" intents
sub RHASSPY_handleIntentSetMute {
    my $hash = shift // return;
    my $data = shift // return;
    my $value, my $siteId, my $state = 0;
    my $response = RHASSPY_getResponse($hash, 'DefaultError');
    
    Log3($hash->{NAME}, 5, "handleIntentSetMute called");
    
    if (exists($data->{Value}) && exists($data->{siteId})) {
        $siteId = makeReadingName($data->{siteId});
        $value = $data->{Value};
        
#        Log3($hash->{NAME}, 5, "siteId: $siteId, value: $value");
        
        if ($value eq 'on') {$state = 1};

        readingsSingleUpdate($hash, "mute_$siteId", $state, 1);
        $response = RHASSPY_getResponse($hash, 'DefaultConfirmation');
    }
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}

sub RHASSPY_handleIntentShortcuts {
    my $hash = shift // return;
    my $data = shift // return;
    
    my $shortcut = $hash->{helper}{shortcuts}{$data->{input}};
    Log3($hash->{NAME}, 5, "handleIntentShortcuts called with $data->{input} key");
    
    my $response = $shortcut->{response} // RHASSPY_getResponse($hash, 'DefaultError');
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

    if (defined($cmd)) {
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

# Eingehende "SetOnOff" Intents bearbeiten
sub RHASSPY_handleIntentSetOnOff {
    my $hash = shift // return;
    my $data = shift // return;
    my $value, my $numericValue, my $device, my $room, my $siteId;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentSetOnOff called");

    # Mindestens Gerät und Wert müssen übergeben worden sein
    if (exists($data->{Device}) && exists($data->{Value})) {
        $room = RHASSPY_roomName($hash, $data);
        $value = $data->{Value};
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        $mapping = RHASSPY_getMapping($hash, $device, 'SetOnOff', undef);

        # Mapping gefunden?
        if (defined $device && defined $mapping) {
            my $cmdOn  = $mapping->{cmdOn} //'on';
            my $cmdOff = $mapping->{cmdOff} // 'off';
            my $cmd = $value eq $hash->{helper}{lng}->{on} ? $cmdOn : $cmdOff;

            # Cmd ausführen
            RHASSPY_runCmd($hash, $device, $cmd);
            Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );

            # Antwort bestimmen
            #$numericValue = ($value eq 'an') ? 1 : 0;

            if (defined $mapping->{response}) { 
                $numericValue = $value eq $hash->{helper}{lng}->{on} ? 1 : 0; #Beta-User: language
                #Log3($hash->{NAME}, 5, "numericValue is $numericValue" );
                $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $numericValue, $room); 
            }
            else { $response = RHASSPY_getResponse($hash, 'DefaultConfirmation'); }
        }
    }
    # Antwort senden
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Eingehende "GetOnOff" Intents bearbeiten
sub RHASSPY_handleIntentGetOnOff {
    my $hash = shift // return;
    my $data = shift // return;
    my $device;
    my $response;# = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentGetOnOff called");

    # Mindestens Gerät und Status-Art wurden übergeben
    if (exists($data->{Device}) && exists($data->{Status})) {
        my $room = RHASSPY_roomName($hash, $data);
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        my $mapping = RHASSPY_getMapping($hash, $device, 'GetOnOff', undef);
        my $status = $data->{Status};

#        Log3($hash->{NAME}, 5, "handleIntentGetOnOff - Device: $device - Status: $status");

        # Mapping gefunden?
        if (defined $mapping) {
            # Gerät ein- oder ausgeschaltet?
            my $value = RHASSPY_getOnOffState($hash, $device, $mapping);

            # Antwort bestimmen
            if    (defined $mapping->{response}) { $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $value, $room); }
            else {
                my $stateResponseType = $hash->{helper}{lng}->{stateResponseType}->{$status};
                $response = $hash->{helper}{lng}->{stateResponses}{$stateResponseType}->{$value};
                eval { $response =~ s{(\$\w+)}{$1}eeg; };
            }
=pod
            elsif ($status =~ m/^(an|aus)$/ && $value == 1) { $response = $data->{'Device'} . " ist eingeschaltet"; }
            elsif ($status =~ m/^(an|aus)$/ && $value == 0) { $response = $data->{'Device'} . " ist ausgeschaltet"; }
            elsif ($status =~ m/^(auf|zu)$/ && $value == 1) { $response = $data->{'Device'} . " ist geöffnet"; }
            elsif ($status =~ m/^(auf|zu)$/ && $value == 0) { $response = $data->{'Device'} . " ist geschlossen"; }
            elsif ($status =~ m/^(eingefahren|ausgefahren)$/ && $value == 1) { $response = $data->{'Device'} . " ist eingefahren"; }
            elsif ($status =~ m/^(eingefahren|ausgefahren)$/ && $value == 0) { $response = $data->{'Device'} . " ist ausgefahren"; }
            elsif ($status =~ m/^(läuft|fertig)$/ && $value == 1) { $response = $data->{'Device'} . " läuft noch"; }
            elsif ($status =~ m/^(läuft|fertig)$/ && $value == 0) { $response = $data->{'Device'} . " ist fertig"; }
=cut
        }
    }
    # Antwort senden
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Eingehende "SetNumeric" Intents bearbeiten
sub RHASSPY_handleIntentSetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $value, my $device, my $room, my $change, my $type, my $unit;
    my $mapping;
    my $validData = 0;
    my $response; # = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentSetNumeric called");

    # Mindestens Device und Value angegeben -> Valid (z.B. Deckenlampe auf 20%)
=pod
    $validData = 1 if (exists($data->{Device}) && exists($data->{Value}));
    # Mindestens Device und Change angegeben -> Valid (z.B. Radio lauter)
    $validData = 1 if (exists($data->{Device}) && exists($data->{Change}));
    # Nur Change für Lautstärke angegeben -> Valid (z.B. lauter)
    $validData = 1 if (!exists $data->{Device} && defined $data->{Change} && $data->{Change} =~ m/^(lauter|leiser)$/i);
    
    # Nur Type = Lautstärke und Value angegeben -> Valid (z.B. Lautstärke auf 10)
    $validData = 1 if (!exists $data->{Device} && defined $data->{Type} && $data->{Type} =~ m/^Lautstärke$/i && exists($data->{Value}));
=cut    
    $validData = 1 if exists $data->{Device} && exists $data->{Value} #);
    # Mindestens Device und Change angegeben -> Valid (z.B. Radio lauter)
    || exists $data->{Device} && exists $data->{Change}
    # Nur Change für Lautstärke angegeben -> Valid (z.B. lauter)
    || !exists $data->{Device} && defined $data->{Change} 
        && defined $hash->{helper}{lng}->{regex}->{$data->{Change}} #$data->{Change}=  =~ m/^(lauter|leiser)$/i);
        #Beta-User: muss auf lauter/leiser begrenzt werden? Was ist mit Kleinschreibung? (Letzteres muss/kann ggf. vorher erledigt werden?

    # Nur Type = Lautstärke und Value angegeben -> Valid (z.B. Lautstärke auf 10)
    ||!exists $data->{Device} && defined $data->{Type} && exists $data->{Value} && $data->{Type} =~ 
    m{\A$hash->{helper}{lng}->{Change}->{regex}->{volumeSound}\z}xim;

    if ($validData) {
        $unit = $data->{Unit};
        $type = $data->{Type};
        $value = $data->{Value};
        $change = $data->{Change};
        $room = RHASSPY_roomName($hash, $data);

        # Type nicht belegt -> versuchen Type über change Value zu bestimmen
        if (!defined $type && defined $change) {
            $type = $hash->{helper}{lng}->{regex}->{$change};
            #if    ($change =~ m/^(kälter|wärmer)$/)  { $type = "Temperatur"; }
            #elsif ($change =~ m/^(dunkler|heller)$/) { $type = "Helligkeit"; }
            #elsif ($change =~ m/^(lauter|leiser)$/)  { $type = "Lautstärke"; }
        }

        # Gerät über Name suchen, oder falls über Lautstärke ohne Device getriggert wurde das ActiveMediaDevice suchen
        if (exists($data->{Device})) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        #} elsif (defined($type) && $type =~ m/^Lautstärke$/i) {
        } elsif (defined($type) && $type =~ m{\A$hash->{helper}{lng}->{Change}->{Types}->{volumeSound}\z}xi) {
            $device = RHASSPY_getActiveDeviceForIntentAndType($hash, $room, 'SetNumeric', $type);
            $response = RHASSPY_getResponse($hash, 'NoActiveMediaDevice') if (!defined $device);
        }

        if (defined($device)) {
            $mapping = RHASSPY_getMapping($hash, $device, 'SetNumeric', $type);

            # Mapping und Gerät gefunden -> Befehl ausführen
            if (defined $mapping  && defined $mapping->{cmd}) {
                my $cmd     = $mapping->{cmd};
                my $part    = $mapping->{part};
                #my $minVal  = (defined($mapping->{minVal})) ? $mapping->{minVal} : 0; # Rhasspy kann keine negativen Nummern bisher, daher erzwungener minVal
                my $minVal  = $mapping->{minVal} // 0; # Rhasspy kann keine negativen Nummern bisher, daher erzwungener minVal
                my $maxVal  = $mapping->{maxVal};
                #my $diff    = (defined $value) ? $value : ((defined($mapping->{step})) ? $mapping->{step} : 10);

                my $diff    = $value // $mapping->{step} // 10;
                #my $up      = (defined($change) && ($change =~ m/^(höher|heller|lauter|wärmer)$/)) ? 1 : 0;

                my $up      = (defined $change && $change =~ m{\A$hash->{helper}{lng}->{regex}->{upward}\z}xi) ? 1 : 0;
                my $forcePercent = (defined $mapping->{map} && lc($mapping->{map}) eq 'percent') ? 1 : 0;

                # Alten Wert bestimmen
                my $oldVal  = RHASSPY_getValue($hash, $device, $mapping->{currentVal});
                if (defined $part) {
                    my @tokens = split(m{ }x, $oldVal);
                    $oldVal = $tokens[$part] if (@tokens >= $part);
                }

                # Neuen Wert bestimmen
                my $newVal;
                # Direkter Stellwert ("Stelle Lampe auf 50")
                #if ($unit ne 'Prozent' && defined $value && !defined $change && !$forcePercent) {
                if ($unit ne $hash->{helper}{lng}->{percent} && defined $value && !defined $change && !$forcePercent) {
                    $newVal = $value;
                }
                # Direkter Stellwert als Prozent ("Stelle Lampe auf 50 Prozent", oder "Stelle Lampe auf 50" bei forcePercent)
                #elsif (defined $value && ( defined $unit && $unit eq 'Prozent' || $forcePercent ) && !defined $change && defined $minVal && defined $maxVal) {
                elsif (defined $value && ( defined $unit && $unit eq $hash->{helper}{lng}->{percent} || $forcePercent ) && !defined $change && defined $minVal && defined $maxVal) {                    # Wert von Prozent in Raw-Wert umrechnen
                    $newVal = $value;
                    $newVal =   0 if ($newVal <   0);
                    $newVal = 100 if ($newVal > 100);
                    $newVal = round((($newVal * (($maxVal - $minVal) / 100)) + $minVal), 0);
                }
                # Stellwert um Wert x ändern ("Mache Lampe um 20 heller" oder "Mache Lampe heller")
                #elsif ((!defined $unit || $unit ne 'Prozent') && defined $change && !$forcePercent) {
                elsif ((!defined $unit || $unit ne $hash->{helper}{lng}->{percent}) && defined $change && !$forcePercent) {
                    $newVal = ($up) ? $oldVal + $diff : $oldVal - $diff;
                }
                # Stellwert um Prozent x ändern ("Mache Lampe um 20 Prozent heller" oder "Mache Lampe um 20 heller" bei forcePercent oder "Mache Lampe heller" bei forcePercent)
                #elsif (($unit eq 'Prozent' || $forcePercent) && defined($change)  && defined $minVal && defined $maxVal) {
                elsif (($unit eq $hash->{helper}{lng}->{percent} || $forcePercent) && defined($change)  && defined $minVal && defined $maxVal) {
                    my $diffRaw = round((($diff * (($maxVal - $minVal) / 100)) + $minVal), 0);
                    $newVal = ($up) ? $oldVal + $diffRaw : $oldVal - $diffRaw;
                }

                if (defined $newVal) {
                    # Begrenzung auf evtl. gesetzte min/max Werte
                    $newVal = $minVal if (defined $minVal && $newVal < $minVal);
                    $newVal = $maxVal if (defined $maxVal && $newVal > $maxVal);

                    # Cmd ausführen
                    RHASSPY_runCmd($hash, $device, $cmd, $newVal);
                    
                    # Antwort festlegen
                    defined $mapping->{response} 
                        ? $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $newVal, $room) 
                        : $response = RHASSPY_getResponse($hash, 'DefaultConfirmation'); 
                }
            }
        }
    }
    # Antwort senden
    $response = $response // RHASSPY_getResponse($hash, 'DefaultError');
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "GetNumeric" Intents bearbeiten
sub RHASSPY_handleIntentGetNumeric {
    my $hash = shift // return;
    my $data = shift // return;
    my $value, my $device, my $room, my $type;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentGetNumeric called");

    # Mindestens Type oder Device muss existieren
    if (exists($data->{Type}) || exists($data->{Device})) {
        $type = $data->{Type};
        $room = RHASSPY_roomName($hash, $data);

        # Passendes Gerät suchen
        if (exists($data->{Device})) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        } else {
            $device = RHASSPY_getDeviceByIntentAndType($hash, $room, 'GetNumeric', $type);
        }

        $mapping = RHASSPY_getMapping($hash, $device, 'GetNumeric', $type) if defined $device;

        # Mapping gefunden
        if (defined $mapping) {
            my $part = $mapping->{part};
            my $minVal  = $mapping->{minVal};
            my $maxVal  = $mapping->{maxVal};
            my $mappingType = $mapping->{type};
            my $forcePercent = defined $mapping->{map} && lc($mapping->{map}) eq 'percent' && defined $minVal && defined $maxVal ? 1 : 0;
            my $isNumber;

            # Zurückzuliefernden Wert bestimmen
            $value = RHASSPY_getValue($hash, $device, $mapping->{currentVal});
            if (defined($part)) {
              my @tokens = split(m{ }x, $value);
              $value = $tokens[$part] if (@tokens >= $part);
            }
            $value = round((($value * (($maxVal - $minVal) / 100)) + $minVal), 0) if ($forcePercent);
            $isNumber = ::looks_like_number($value);

            # Punkt durch Komma ersetzen in Dezimalzahlen
            $value =~ s/\./\,/gx if $hash->{helper}{lng}->{commaconversion};

            my $location = $data->{Device} // $data->{Room};
            # Antwort falls mappingType matched

            # Antwort falls Custom Response definiert ist
            if    (defined($mapping->{response})) { $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $value, $room); }
            
            elsif ($mappingType =~ m/^(Helligkeit|Lautstärke|Sollwert)$/i) { $response = $data->{Device} . " ist auf $value gestellt."; }
            elsif ($mappingType =~ m/^Temperatur$/i) { $response = "Die Temperatur von $location beträgt $value" . ($isNumber ? " Grad" : ""); }
            elsif ($mappingType =~ m/^Luftfeuchtigkeit$/i) { $response = "Die Luftfeuchtigkeit von $location beträgt $value" . ($isNumber ? " Prozent" : ""); }
            elsif ($mappingType =~ m/^Batterie$/i) { $response = "Der Batteriestand von $location " . ($isNumber ?  " beträgt $value Prozent" : " ist $value"); }
            elsif ($mappingType =~ m/^Wasserstand$/i) { $response = "Der Wasserstand von $location beträgt $value"; }
            elsif ($mappingType =~ m/^Bodenfeuchte$/i) { $response = "Die Bodenfeuchte von $location beträgt $value Prozent"; }

            # Andernfalls Antwort falls type aus Intent matched
            elsif ($type =~ m/^(Helligkeit|Lautstärke|Sollwert)$/) { $response = $data->{Device} . " ist auf $value gestellt."; }
            elsif ($type =~ m/^Temperatur$/i) { $response = "Die Temperatur von $location beträgt $value" . ($isNumber ? " Grad" : ""); }
            elsif ($type =~ m/^Luftfeuchtigkeit$/i) { $response = "Die Luftfeuchtigkeit von $location beträgt $value" . ($isNumber ? " Prozent" : ""); }
            elsif ($type =~ m/^Batterie$/i) { $response = "Der Batteriestand von $location" . ($isNumber ?  " beträgt $value Prozent" : " ist $value"); }
            elsif ($type =~ m/^Wasserstand$/i) { $response = "Der Wasserstand von $location beträgt $value"; }
            elsif ($type =~ m/^Bodenfeuchte$/i) { $response = "Die Bodenfeuchte von $location beträgt $value Prozent"; }

            # Antwort wenn Custom Type
            elsif (defined($mappingType)) { $response = "$mappingType von $location beträgt $value"; }

            # Standardantwort falls der Type überhaupt nicht bestimmt werden kann
            else { $response = "Der Wert von $location beträgt $value."; }
        }
    }
    # Antwort senden
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "Status" Intents bearbeiten
sub RHASSPY_handleIntentStatus {
    my $hash = shift // return;
    my $data = shift // return;
    
    my $response = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentStatus called");

    # Mindestens Device muss existieren
    if (exists($data->{Device})) {
        my $room = RHASSPY_roomName($hash, $data);
        my $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        my $mapping = RHASSPY_getMapping($hash, $device, 'Status', undef);

        if (defined($mapping->{response})) {
            $response = RHASSPY_getValue($hash, $device, $mapping->{response},undef, $room);
        }
    }
    # Antwort senden
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "MediaControls" Intents bearbeiten
sub RHASSPY_handleIntentMediaControls {
    my $hash = shift // return;
    my $data = shift // return;
    my $command, my $device, my $room;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentMediaControls called");

    # Mindestens Kommando muss übergeben worden sein
    if (exists($data->{Command})) {
        $room = RHASSPY_roomName($hash, $data);
        $command = $data->{'Command'};

        # Passendes Gerät suchen
        if (exists($data->{Device})) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = RHASSPY_getActiveDeviceForIntentAndType($hash, $room, 'MediaControls', undef);
            $response = RHASSPY_getResponse($hash, 'NoActiveMediaDevice') if (!defined($device));
        }

        $mapping = RHASSPY_getMapping($hash, $device, 'MediaControls', undef);

        if (defined($device) && defined($mapping)) {
            my $cmd;
            #Beta-User - language

            if    ($command =~ m/^play$/i)   { $cmd = $mapping->{cmdPlay}; }
            elsif ($command =~ m/^pause$/i)  { $cmd = $mapping->{cmdPause}; }
            elsif ($command =~ m/^stop$/i)   { $cmd = $mapping->{cmdStop}; }
            elsif ($command =~ m/^vor$/i)    { $cmd = $mapping->{cmdFwd}; }
            elsif ($command =~ m/^zurück$/i) { $cmd = $mapping->{cmdBack}; }

            if (defined($cmd)) {
                # Cmd ausführen
                RHASSPY_runCmd($hash, $device, $cmd);
                
                # Antwort festlegen
                if (defined($mapping->{response})) { $response = RHASSPY_getValue($hash, $device, $mapping->{response}, $command, $room); }
                else { $response = RHASSPY_getResponse($hash, 'DefaultConfirmation'); }
            }
        }
    }
    # Antwort senden
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Eingehende "GetTime" Intents bearbeiten
sub RHASSPY_handleIntentGetTime {
    my $hash = shift // return;
    my $data = shift // return;
    Log3($hash->{NAME}, 5, "handleIntentGetTime called");

    (my $sec,my $min,my $hour,my $mday,my $mon,my $year,my $wday,my $yday,my $isdst) = localtime();
    #my $response = "Es ist $hour Uhr $min"; #Beta-User - language
    my $response = $hash->{helper}{lng}->{responses}->{timeRequest};
    eval { $response =~ s{(\$\w+)}{$1}eeg; };
    Log3($hash->{NAME}, 5, "Response: $response");
    
    # Antwort senden
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "GetWeekday" Intents bearbeiten
sub RHASSPY_handleIntentGetWeekday {
    my $hash = shift // return;
    my $data = shift // return;

    Log3($hash->{NAME}, 5, "handleIntentGetWeekday called");

    my $weekDay  = strftime "%A", localtime;
    #Beta-User - language
    #my $response = qq(Heute ist $weekDay);
    my $response = $hash->{helper}{lng}->{responses}->{weekdayRequest};
    eval { $response =~ s{(\$\w+)}{$1}eeg; };
    
    Log3($hash->{NAME}, 5, "Response: $response");

    # Antwort senden
    return RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "MediaChannels" Intents bearbeiten
sub RHASSPY_handleIntentMediaChannels {
    my $hash = shift // return;
    my $data = shift // return;
    my $channel, my $device, my $room;
    my $cmd;
    my $response = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentMediaChannels called");

    # Mindestens Channel muss übergeben worden sein
    if (exists($data->{Channel})) {
        $room = RHASSPY_roomName($hash, $data);
        $channel = $data->{Channel};

        # Passendes Gerät suchen
        if (exists($data->{Device})) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = RHASSPY_getDeviceByMediaChannel($hash, $room, $channel);
        }

        $cmd = RHASSPY_getCmd($hash, $device, 'rhasspyChannels', $channel, undef);

        if (defined($device) && defined($cmd)) {
            $response = RHASSPY_getResponse($hash, 'DefaultConfirmation');
            # Cmd ausführen
            RHASSPY_runCmd($hash, $device, $cmd);
        }
    }

    # Antwort senden
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return;
}


# Eingehende "SetColor" Intents bearbeiten
sub RHASSPY_handleIntentSetColor {
    my $hash = shift // return;
    my $data = shift // return;
    my $color, my $device, my $room;
    my $cmd;
    my $response = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($hash->{NAME}, 5, "handleIntentSetColor called");

    # Mindestens Device und Color muss übergeben worden sein
    if (exists $data->{Color} && exists $data->{Device}) {
        $room = RHASSPY_roomName($hash, $data);
        $color = $data->{Color};

        # Passendes Gerät & Cmd suchen
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{Device});
        $cmd = RHASSPY_getCmd($hash, $device, 'rhasspyColors', $color, undef);

        if (defined($device) && defined($cmd)) {
            $response = RHASSPY_getResponse($hash, 'DefaultConfirmation');

            # Cmd ausführen
            RHASSPY_runCmd($hash, $device, $cmd);
        }
    }
    # Antwort senden
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return;
}


# Handle incoming SetTimer intents
sub RHASSPY_handleIntentSetTimer {
    my $hash = shift;
    my $data = shift // return;

    my $name = $hash->{NAME};
    my $unit, my $room, my $value;
                                  
    my @unitHours = ('stunde','stunden','hour','hours','heure','heures');
    my @unitMinutes = ('minute','minuten','minute','minutes');
    my $response = RHASSPY_getResponse($hash, 'DefaultError');

    Log3($name, 5, 'handleIntentSetTimer called');

    if ($data->{Room}) {$room = makeReadingName($data->{Room})};
    if ($data->{Value}) {$value = $data->{Value}} else {$response = $hash->{helper}{lng}->{responses}->{duration_not_understood}};
    #if ($data->{Value}) {$value = $data->{Value}} else {$response = 'Tut mir leid ich habe die Dauer nicht verstanden'};

                                   
    if ($data->{Unit}) {$unit = $data->{Unit}} else {$response = $hash->{helper}{lng}->{responses}->{duration_not_understood}};
    
    my $siteId = $data->{siteId};

    $room = $room // $siteId;

    if( $value && $unit && $room ) {
        my $time = $value;
        my $roomReading = makeReadingName($room);
        
        if    ( grep { $_ eq $unit } @unitMinutes ) {$time = $value*60}
        elsif ( grep { $_ eq $unit } @unitHours )   {$time = $value*3600};
        
        #$time = strftime('%T', gmtime $time); # Beta-User: %T seems to fail in non-POSIX-Environments...
        $time = strftime('%H:%M:%S', gmtime $time);
        
        $response = $hash->{helper}{lng}->{responses}->{timerEnd};
        my $cmd = qq(defmod timer_$room at +$time set $name speak siteId=\"$room\" text=\"$response\";;setreading $name timer_$roomReading 0);
        
        RHASSPY_runCmd($hash,'',$cmd);

        readingsSingleUpdate($hash, "timer_" . $roomReading, 1, 1);
        
        Log3($name, 5, "Created timer: $cmd");
        
        #$response = "Taimer in $room gesetzt auf $value $unit";
        # Variablen ersetzen? (Testcode aus RHASSPY_runCmd())
        $response = $hash->{helper}{lng}->{responses}->{timerSet};
        eval { $response =~ s{(\$\w+)}{$1}eeg; };
        
        #$response = _replace( $hash, 
        #            $hash->{helper}{lng}->{responses}->{timerSet},
        #            {'$unit' => $unit, '$time' => $time, '$room' => $room, '$value' => $value });
    }

    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    return $name;
}

sub RHASSPY_playWav {
    my $hash = shift // return;
    my($unnamedParams, $namedParams) = parseParams(shift);
    
    my $siteId = q{default};
    my $json;
    my $url = q{/api/play-wav};
    my $method = q{POST};
    my $contenttype = q{audio/wav};
    
    Log3($hash->{NAME}, 5, "action playWav called");
    
    if (defined($namedParams->{siteId}) && defined($namedParams->{path})) {
        $siteId = $namedParams->{siteId};
        my $filename = $namedParams->{path};
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
    my $to_analyze = join q{ }, @{$arr};

    #my @arr  = shift // return;
    #my $to_analyze = join q{ }, @arr;

    my $readingsVal = sub ($$$$$) {
        my $all = shift;
        my $t = shift;
        my $d = shift;
        my $n = shift;
        my $s = shift;
        my $val;
        my $hash = $defs{$d}; #Beta-User: vermutlich nicht benötigt, bitte mal testweise auskommentieren...
        return $all if(!$hash);

        if(!$t || $t eq "r:") {
            my $r = $hash->{READINGS};
            if($s && ($s eq ":t" || $s eq ":sec")) {
                return $all if (!$r || !$r->{$n});
                $val = $r->{$n}{TIME};
                $val = int(gettimeofday()) - time_str2num($val) if($s eq ":sec");
                return $val;
            }
            $val = $r->{$n}{VAL} if($r && $r->{$n});
        }
        $val = $hash->{$n}   if(!defined($val) && (!$t || $t eq 'i:'));
        $val = $attr{$d}{$n} if(!defined($val) && (!$t || $t eq 'a:') && $attr{$d});
        return $all if !defined($val);

        if($s && $s =~ m/:d|:r|:i/x && $val =~ /(-?\d+(\.\d+)?)/) {
            $val = $1;
            $val = int($val) if ( $s eq ":i" );
            $val = round($val, defined($1) ? $1 : 1) if($s =~ /^:r(\d)?/);
        }
        return $val;
    };

    $to_analyze =~s/(\[([ari]:)?([a-zA-Z\d._]+):([a-zA-Z\d._\/-]+)(:(t|sec|i|d|r|r\d))?\])/$readingsVal->($1,$2,$3,$4,$5)/eg;
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
    my $cfg  = shift;
    
    my $name = $hash->{NAME};
    my $filename = RHASSPY_getDataFile($hash, $cfg);
    Log3($name, 5, "trying to read language from $filename");
    my ($ret, @content) = FileRead($filename);
    if ($ret) {
        Log3($name, 1, "$name failed to read configFile $filename!") ;
        return $ret, undef;
    }
    my @cleaned = grep { $_ !~ m{\A\s*[#]}x } @content;

    #my $string = join q{ }, @content;
    #return 0, join q{ }, @content;
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
<p><code>define &lt;name&gt; RHASSPY &lt;DefaultRoom&gt;</code></p>
<ul>
  <li>DefaultRoom: Default room name. Used to speak commands without a room name (e.g. &quot;turn lights on&quot; to turn on the lights in the &quot;default room&quot;)</li>
</ul>
<p>Before defining RHASSPY an MQTT2_CLIENT device has to be created which connects to the same MQTT-Server the voice assistant connects to.</p>
<p>Example for defining an MQTT2_CLIENT device and the Rhasspy device in FHEM:</p>
<p>
  <code><pre>defmod rhasspyMQTT2 MQTT2_CLIENT rhasspy:12183
attr rhasspyMQTT2 clientOrder RHASSPY MQTT_GENERIC_BRIDGE MQTT2_DEVICE
attr rhasspyMQTT2 subscriptions hermes/intent/+ hermes/dialogueManager/sessionStarted hermes/dialogueManager/sessionEnded</pre></code><br>
  <code>define Rhasspy RHASSPY Wohnzimmer</code>
</p>
<a name="RHASSPYset"></a>
<p><b>Set</b></p>
<ul>
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
    Defines the URL to the Rhasspy Master for sending requests to the HTTP-API. Has to be in Format <code>protocol://fqdn:port</code> (e.g. <i>http://rhasspy.example.com:12101</i>).
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
    <!--Defines custom intents. See <a href="https://github.com/Thyraz/Snips-Fhem#f%C3%BCr-fortgeschrittene-eigene-custom-intents-erstellen-und-in-fhem-darauf-reagieren" hreflang="de">Custom Intent erstellen</a>.<br>-->
    Not implemented yet
  </li>
  <li>
    <b>shortcuts</b><br>
    Define custom sentences without editing Rhasspy sentences.ini<br>
    The shortcuts are uploaded to Rhasspy when using the updateSlots set-command.<br>
    Example:<pre><code>mute on=set receiver mute on
mute off=set receiver mute off</code></pre>
  </li>
  <li>
    <b>forceNEXT</b><br>
     If set to 1, RHASSPY will forward incoming messages also to further MQTT2-IO-client modules like MQTT2_DEVICE, even if the topic matches to one of it's own subscriptions. By default, these messages will not be forwarded for better compability with autocreate feature on MQTT2_DEVICE. See also <a href="#MQTT2_CLIENTclientOrder">clientOrder attribute in MQTT2 IO-type commandrefs</a>; setting this in one instance of RHASSPY might affect others, too.</p>
     <br>Additionals remarks on MQTT2-IO's:
     Using a separate MQTT server (and not the internal MQTT2_SERVER) is highly recommended, as the Rhasspy scripts also use the MQTT protocol for internal (sound!) data transfers. Best way is to either use MQTT2_CLIENT (see below) or bridge only the relevant topics from mosquitto to MQTT2_SERVER (see e.g. http://www.steves-internet-guide.com/mosquitto-bridge-configuration/ for the principles). When using MQTT2_CLIENT, it's necessary to set clientOrder to include RHASSPY (as most likely, it's the only module listening to the CLIENT, it could be just set to 
     <pre><code>attr <m2client> clientOrder RHASSPY</code></pre><br>
     Furthermore, you are highly encouraged to restrict subscriptions only to the relevant topics:
     <pre><code>attr <m2client> subscriptions setByTheProgram</code></pre><br>
     In case you are using the MQTT server also for other purposes than Rhasspy, you have to set <i>subscriptions</i> manually to at least include
     <pre><code>hermes/intent/+
hermes/dialogueManager/sessionStarted
hermes/dialogueManager/sessionEnded</code></pre>
     additionally to the other subscriptions desired for other purposes.
    </li>
    <li>
      <b>language</b><br>
     Placeholder, this is not operational yet....
    </li>  
</ul>
</ul>

=end html
=cut
