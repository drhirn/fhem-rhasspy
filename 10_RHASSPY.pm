###########################################################################
#
# FHEM RHASSPY modul  (https://github.com/rhasspy)
#
# Originally written 2018 by Tobias Wiedenmann (Thyraz)
# as FHEM Snips.ai module (thanks to Matthias Kleine)
#
# Adapted for RHASSPY 2020 by drhirn
#
# Thanks to BetaUser, rudolfkoenig, JensS, cb2sela and all the others
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
    speak        => q{},
    play         => q{},
    updateSlots  => q{},
    textCommand  => q{},
    trainRhasspy => q{},
    fetchSiteIds => q{}
#    "volume" => ""
);

my $languagevars = {
    de => (
        mutated_vowels => ( 'ä' => 'ae', 'Ä' => 'Ae', 'ü' => 'ue', 'Ü' => 'Ue', 'ö' => 'oe', 'Ö' => 'Oe', 'ß' => 'ss' ),
          )
};

BEGIN {

  GP_Import(qw(
    addToAttrList
    readingsSingleUpdate
    readingsBeginUpdate
    readingsBulkUpdate
    readingsEndUpdate
    Log3
    defs
    attr
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
    HttpUtils_NonblockingGet
    round
    strftime
    makeReadingName
    ReadingsNum
  ))

};

# MQTT Topics die das Modul automatisch abonniert
my @topics = qw(
    hermes/intent/+
    hermes/dialogueManager/sessionStarted
    hermes/dialogueManager/sessionEnded
);

my $language = 'en';

sub RHASSPY_Initialize {
    my $hash = shift // return;

    # Attribute rhasspyName und rhasspyRoom für andere Devices zur Verfügung abbestellen
    addToAttrList('rhasspyName');
    addToAttrList('rhasspyRoom');
    addToAttrList('rhasspyMapping:textField-long');
    
    # Consumer
    $hash->{DefFn}       = \&RHASSPY_Define;
    $hash->{UndefFn}     = \&RHASSPY_Undefine;
    $hash->{SetFn}       = \&RHASSPY_Set;
    $hash->{AttrFn}      = \&RHASSPY_Attr;
    $hash->{AttrList}    = "IODev defaultRoom rhasspyIntents:textField-long shortcuts:textField-long rhasspyMaster response:textField-long language:multiple,en,de forceNEXT:0,1 disable:0,1 disabledForIntervals " . $readingFnAttributes;
    #$hash->{OnMessageFn} = \&RHASSPY_onmessage;
    $hash->{Match}       = ".*";
    $hash->{ParseFn}     = \&RHASSPY_Parse;

    return;
}

# Device anlegen
sub RHASSPY_Define {
    my $hash = shift;
    my $def  = shift // return; #Beta-User: Perl defined-or
    my @args = split("[ \t]+", $def);

    # Minimale Anzahl der nötigen Argumente vorhanden?
    return "Invalid number of arguments: define <name> RHASSPY DefaultRoom" if (int(@args) < 3);

    my ($name, $type, $defaultRoom) = @args;
    $hash->{MODULE_VERSION} = "0.2";
    $hash->{helper}{defaultRoom} = $defaultRoom;

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
    
    #RHASSPY_subscribeTopics($hash) if isIODevMQTT2_CLIENT($hash);
    IOWrite($hash, 'subscriptions', join(q{ }, @topics)) if InternalVal($IODev,'TYPE',undef) eq 'MQTT2_CLIENT'; # isIODevMQTT2_CLIENT($hash);
    
    $language = AttrVal($hash->{NAME},'language',lc(AttrVal('global','language',$language)));
    $hash->{LANGUAGE} = $language;

    return;
}

# Device löschen
sub RHASSPY_Undefine {
    my $hash = shift // return;
    #Beta-User: $name not needed; was ist mit den globalen Attributen? Bleiben die...?

    RemoveInternalTimer($hash);
  
    return;
}

# Set Befehl aufgerufen
sub RHASSPY_Set($$$@) {
    my ($hash, $name, $command, @values) = @_;
    return "Unknown argument $command, choose one of " . join(" ", sort keys %sets) if(!defined($sets{$command}));

    Log3($hash->{NAME}, 5, "set " . $command . " - value: " . join (" ", @values));

    # Speak Cmd
    if ($command eq "speak") {
            return RHASSPY_speak($hash, join  q{ }, @values);
    }
    # TextCommand Cmd
    if ($command eq "textCommand") {
        my $text = join (" ", @values);
        return RHASSPY_textCommand($hash, $text);
    }
    # Update Model Cmd
    if ($command eq "updateSlots") {
        return RHASSPY_updateSlots($hash);
    }
    # TrainRhasspy Cmd
    if ($command eq "trainRhasspy") {
        return RHASSPY_trainRhasspy($hash);
    }
    # playWav Cmd
    if ($command eq "play") {
        my $params = join (" ", @values);
        return RHASSPY_playWav($hash, $params);
    }
    # fetch all defined siteIds
    if ($command eq "fetchSiteIds") {
        return RHASSPY_fetchSiteIds($hash);
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
    if ($attribute eq 'language') {
        if( $command eq 'set' ) {
          $language = lc($value);
        } else {
          $language = lc(AttrVal('global','language','en'));
        }
        $hash->{LANGUAGE} = $language;
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
    
    return;
}

sub RHASSPY_init_shortcuts {
    my $hash    = shift // return;
    my $attrVal = shift // return;
    
    my ($intend, $perlcommand, $fhemcommand, $device, $retsring, $err );
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

sub RHASSPY_execute {
    my $hash   = shift // return;
    my $device = shift;# // carp q[No target device provided!] && return;
    my $cmd    = shift;# // carp q[No command provided!]       && return;
    my $value  = shift;# // carp q[No value provided!]         && return;
    my $siteId = shift // $hash->{helper}{defaultRoom};
    $siteId = $hash->{helper}{defaultRoom} if $siteId eq "default";


    # Nutzervariablen setzen
    my %specials = (
         '$DEVICE' => $device,
         '$VALUE'  => $value,
         '$ROOM'   => $siteId
    );

    $cmd  = EvalSpecials($cmd, %specials);

    # CMD ausführen
    #my $returnVal = eval $cmd;
    return AnalyzePerlCommand( $hash, $cmd );
}
#from https://stackoverflow.com/a/43873983, modified...
sub get_unique {
    my @arr    = shift;
    my $sorted = shift; #true if shall be sorted (longest first!)
    my %seen;
    my @unique = grep {!$seen{$_}++} @arr;

    return @unique if !$sorted;

    my @sorted = sort { length($b) <=> length($a) } @unique;
    return @sorted;
}

sub RHASSPY_EvalSpecialsDefaults {
    my $hash  = shift // return;
    my $cmd   = shift // return;
    my $hash2 = shift;
    my $self = $hash2->{'$SELF'} // $hash->{NAME};
    my $name = $hash2->{'$NAME'} // $hash->{NAME};
    
    my %specials = (
        '$SELF' => $self,
        '$NAME' => $name
    );
    %specials = (%specials, %{$hash2});
    #@specials{keys %hash2} = values %hash2;
    
    for my $key (keys %specials) {
        my $val = $specials{$key};
        $key =~ s{\$}{\\\$}gxms;
        $cmd =~ s{$key}{$val}gxms
    }
    
    return $cmd;
}

# Alle Gerätenamen sammeln
sub RHASSPY_allRhasspyNames {
    #my @devices;#, my @sorted;
    #my %devicesHash;
    my $devspec = 'room=Rhasspy';
    my @devs = devspec2array($devspec);
    my @devices;

    # Alle RhasspyNames sammeln
    for (@devs) {
        push @devices, split(',', AttrVal($_,'rhasspyName',undef));
    }

    # Doubletten rausfiltern
    #%devicesHash = map { if (defined($_)) { $_, 1 } else { () } } @devices;
    #@devices = keys %devicesHash;
    #from https://stackoverflow.com/a/43873983
    #my @unique = get_unique(@devices, 1 );
    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'lampe' gefunden wird bevor der eigentliche Treffer 'deckenlampe' versucht wurde
    #my @sorted = sort { length($b) <=> length($a) } @unique;

    #return @sorted
    #return sort { length($b) <=> length($a) } @devices;
    return get_unique(@devices, 1 );
}

# Alle Raumbezeichnungen sammeln
sub RHASSPY_allRhasspyRooms {
    my @rooms, my @sorted;
    my %roomsHash;
    my $devspec = "room=Rhasspy";
    my @devs = devspec2array($devspec);

    # Alle RhasspyNames sammeln
    foreach (@devs) {
        push @rooms, split(',', AttrVal($_,"rhasspyRoom",undef));
    }

    # Doubletten rausfiltern
    %roomsHash = map { if (defined($_)) { $_, 1 } else { () } } @rooms;
    @rooms = keys %roomsHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'küche' gefunden wird bevor der eigentliche Treffer 'waschküche' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @rooms;

    return @sorted
#    return sort { length($b) <=> length($a) } @rooms;
}


# Alle Sender sammeln
sub RHASSPY_allRhasspyChannels {
    my @channels, my @sorted;
    my %channelsHash;
    my $devspec = "room=Rhasspy";
    my @devs = devspec2array($devspec);

    # Alle RhasspyNames sammeln
    foreach (@devs) {
        my @rows = split(/\n/, AttrVal($_,"rhasspyChannels",undef));
        foreach (@rows) {
            my @tokens = split('=', $_);
            my $channel = shift(@tokens);
            push @channels, $channel;
        }
    }

    # Doubletten rausfiltern
    %channelsHash = map { if (defined($_)) { $_, 1 } else { () } } @channels;
    @channels = keys %channelsHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'S.W.R.' gefunden wird bevor der eigentliche Treffer 'S.W.R.3' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @channels;

    return @sorted
}


# Alle NumericTypes sammeln
sub RHASSPY_allRhasspyTypes {
    my @types, my @sorted;
    my %typesHash;
    my $devspec = "room=Rhasspy";
    my @devs = devspec2array($devspec);

    # Alle RhasspyNames sammeln
    for (@devs) {
        my @mappings = split(/\n/, AttrVal($_,"rhasspyMapping",undef));
        for (@mappings) {
            # Nur GetNumeric und SetNumeric verwenden
            next if $_ !~ m/^(SetNumeric|GetNumeric)/;
            $_ =~ s/(SetNumeric|GetNumeric)://;
            my %mapping = RHASSPY_splitMappingString($_);

            push @types, $mapping{'type'} if (defined($mapping{'type'}));
        }
    }

    # Doubletten rausfiltern
    %typesHash = map { if (defined($_)) { $_, 1 } else { () } } @types;
    @types = keys %typesHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'S.W.R.' gefunden wird bevor der eigentliche Treffer 'S.W.R.3' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @types;

    return @sorted
}


# Alle Farben sammeln
sub RHASSPY_allRhasspyColors() {
    my @colors, my @sorted;
    my %colorHash;
    my $devspec = "room=Rhasspy";
    my @devs = devspec2array($devspec);

    # Alle RhasspyNames sammeln
    for(@devs) {
        #my @rows = split(/\n/, AttrVal($_,"rhasspyColors",undef));
        #foreach (@rows) {
        for (split(/\n/, AttrVal($_,"rhasspyColors",undef))) {
            my @tokens = split('=', $_);
            my $color = shift(@tokens);
            push @colors, $color;
        }
    }

    # Doubletten rausfiltern
    %colorHash = map { if (defined($_)) { $_, 1 } else { () } } @colors;
    @colors = keys %colorHash;

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'S.W.R.' gefunden wird bevor der eigentliche Treffer 'S.W.R.3' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @colors;

    return @sorted
}


# Alle Shortcuts sammeln
sub RHASSPY_allRhasspyShortcuts($) {
#sub RHASSPY_allRhasspyShortcuts {
    my ($hash) = @_;
#    my $hash = shift // return;
    my @shortcuts, my @sorted, my @rows;

    if (defined($hash)){
        @rows = split(/\n/, AttrVal($hash->{NAME},'shortcuts',q{}));
    };
    for (@rows) {
        my @tokens = split('=', $_);
        my $shortcut = shift(@tokens);
        push @shortcuts, $shortcut;
    }

    # Längere Werte zuerst, damit bei Ersetzungen z.B. nicht 'S.W.R.' gefunden wird bevor der eigentliche Treffer 'S.W.R.3' versucht wurde
    @sorted = sort { length($b) <=> length($a) } @shortcuts;

    return @sorted
}


# Raum aus gesprochenem Text oder aus siteId verwenden? (siteId "default" durch Attr defaultRoom ersetzen)
sub RHASSPY_roomName ($$) {
    my ($hash, $data) = @_;

    my $room;
    my $defaultRoom = $hash->{helper}{defaultRoom};

    # Slot "Room" im JSON vorhanden? Sonst Raum des angesprochenen Satelites verwenden
    if (exists($data->{'Room'})) {
        $room = $data->{'Room'};
    } else {
        $room = $data->{'siteId'};
        $room = $defaultRoom if ($room eq 'default' || !(length $room));
    }

    return $room;
}


# Gerät über Raum und Namen suchen.
sub RHASSPY_getDeviceByName($$$) {
    my ($hash, $room, $name) = @_;
    my $device;
    my $devspec = "room=Rhasspy";
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);

    for (@devices) {
        # 2 Arrays bilden mit Namen und Räumen des Devices
        my @names = split(',', AttrVal($_,'rhasspyName',q{}));
        my @rooms = split(',', AttrVal($_,'rhasspyRoom',q{}));

        # Case Insensitive schauen ob der gesuchte Name (oder besser Name und Raum) in den Arrays vorhanden ist
#        if (grep( /^$name$/i, @names)) {
        if (grep( { /^$name$/i } @names)) {
            if (!defined($device) || grep( { /^$room$/i} @rooms)) {
                $device = $_;
            }
        }
    }

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Sammelt Geräte über Raum, Intent und optional Type
sub RHASSPY_getDevicesByIntentAndType($$$$) {
    my ($hash, $room, $intent, $type) = @_;
    my @matchesInRoom, my @matchesOutsideRoom;
    my $devspec = "room=Rhasspy";
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);

    for(@devices) {
        # Array bilden mit Räumen des Devices
        my @rooms = split(',', AttrVal($_,"rhasspyRoom",undef));
        # Mapping mit passendem Intent vorhanden?
        my $mapping = RHASSPY_getMapping($hash, $_, $intent, $type, 1) // next;
        #next unless defined($mapping);

        my $mappingType = $mapping->{'type'}; # if (defined($mapping->{'type'})); #Beta-User: no conditional variable declarations!

        # Geräte sammeln
        if (!defined($type)) {
            grep ( {/^$room$/i} @rooms)
                ? push @matchesInRoom, $_ 
                : push @matchesOutsideRoom, $_;
        }
#        elsif (!defined($type) && grep(/^$room$/i, @rooms)) {
#            push @matchesInRoom, $_;
#        }
        elsif (defined($type) && $mappingType && $type =~ m/^$mappingType$/i) {
            grep( {/^$room$/i} @rooms)
            ? push @matchesInRoom, $_
            : push @matchesOutsideRoom, $_;
        }
#        elsif (defined($type) && $mappingType && $type =~ m/^$mappingType$/i && grep(/^$room$/i, @rooms)) {
#            push @matchesInRoom, $_;
#        }
    }

    return (\@matchesInRoom, \@matchesOutsideRoom);
}


# Geräte über Raum, Intent und ggf. Type suchen.
sub RHASSPY_getDeviceByIntentAndType($$$$) {
    my ($hash, $room, $intent, $type) = @_;
    my $device;

    # Devices sammeln
    my ($matchesInRoom, $matchesOutsideRoom) = RHASSPY_getDevicesByIntentAndType($hash, $room, $intent, $type);

    # Erstes Device im passenden Raum zurückliefern falls vorhanden, sonst erstes Device außerhalb
    $device = (@{$matchesInRoom} > 0) ? shift @{$matchesInRoom} : shift @{$matchesOutsideRoom};

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Eingeschaltetes Gerät mit bestimmten Intent und optional Type suchen
sub RHASSPY_getActiveDeviceForIntentAndType($$$$) {
    my ($hash, $room, $intent, $type) = @_;
    my $device;
    my ($matchesInRoom, $matchesOutsideRoom) = RHASSPY_getDevicesByIntentAndType($hash, $room, $intent, $type);

    # Anonyme Funktion zum finden des aktiven Geräts
    my $activeDevice = sub ($$) {
        my ($hash, $devices) = @_;
        my $match;

        for (@{$devices}) {
            my $mapping = RHASSPY_getMapping($hash, $_, 'GetOnOff', undef, 1);
            if (defined($mapping)) {
                # Gerät ein- oder ausgeschaltet?
                my $value = RHASSPY_getOnOffState($hash, $_, $mapping);
                if ($value == 1) {
                    $match = $_;
                    last;
                }
            }
        }
        return $match;
    };

    # Gerät finden, erst im aktuellen Raum, sonst in den restlichen
    $device = $activeDevice->($hash, $matchesInRoom);
    $device = $activeDevice->($hash, $matchesOutsideRoom) if (!defined($device));

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Gerät mit bestimmtem Sender suchen
sub RHASSPY_getDeviceByMediaChannel($$$) {
    my ($hash, $room, $channel) = @_;
    my $device;
    my $devspec = "room=Rhasspy";
    my @devices = devspec2array($devspec);

    # devspec2array sendet bei keinen Treffern als einziges Ergebnis den devSpec String zurück
    return if (@devices == 1 && $devices[0] eq $devspec);

    for (@devices) {
        # Array bilden mit Räumen des Devices
        my @rooms = AttrVal($_,"rhasspyRoom",undef);
        if (index(@rooms, ",") != -1) {
            my @rooms = split(',', AttrVal($_,"rhasspyRoom",undef));
        }
        # Cmd mit passendem Intent vorhanden?
        my $cmd = RHASSPY_getCmd($hash, $_, "rhasspyChannels", $channel, 1) // next;
        #next if !defined($cmd);

        # Erster Treffer wälen, überschreiben falls besserer Treffer (Raum matched auch) kommt
        if (!defined($device) || grep( {/^$room$/i} @rooms)) {
            $device = $_;
        }
    }

    Log3($hash->{NAME}, 5, "Device selected: $device");

    return $device;
}


# Mappings in Key/Value Paare aufteilen
sub RHASSPY_splitMappingString {
    my $mapping = shift // return;
    my @tokens, my $token = '';
    #my $char, 
    my $lastChar = '';
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
        elsif ($char eq ',' && $lastChar ne '\\' && $bracketLevel == 0) {
            push(@tokens, $token);
            $token = '';
        }
        else {
            $token .= $char;
        }

        $lastChar = $char;
    }
    push(@tokens, $token) if (length($token) > 0);

    # Tokens in Keys/Values trennen
    %parsedMapping = map {split /=/, $_, 2} @tokens;

    return %parsedMapping;
}


# rhasspyMapping parsen und gefundene Settings zurückliefern
sub RHASSPY_getMapping($$$$;$) {
    my ($hash, $device, $intent, $type, $disableLog) = @_;
    my @mappings, my $matchedMapping;
    my $mappingsString = AttrVal($device, "rhasspyMapping", undef);

    if (defined($mappingsString)) {
        # String in einzelne Mappings teilen
        @mappings = split(/\n/, $mappingsString);

        foreach (@mappings) {
            # Nur Mappings vom gesuchten Typ verwenden
            next if $_ !~ qr/^$intent/;
            $_ =~ s/$intent://;
            my %currentMapping = RHASSPY_splitMappingString($_);

            # Erstes Mapping vom passenden Intent wählen (unabhängig vom Type), dann ggf. weitersuchen ob noch ein besserer Treffer mit passendem Type kommt
            if (!defined($matchedMapping) || (defined($type) && lc($matchedMapping->{'type'}) ne lc($type) && lc($currentMapping{'type'}) eq lc($type))) {
                $matchedMapping = \%currentMapping;

                Log3($hash->{NAME}, 5, "rhasspyMapping selected: $_") if (!defined($disableLog) || (defined($disableLog) && $disableLog != 1));
            }
        }
    }
    return $matchedMapping;
}


# Cmd von Attribut mit dem Format value=cmd pro Zeile lesen
sub RHASSPY_getCmd($$$$;$) {
    my ($hash, $device, $reading, $key, $disableLog) = @_;

    my @rows, my $cmd;
    #my $attrString = AttrVal($device, $reading, undef);

    # String in einzelne Mappings teilen
    @rows = split(/\n/, AttrVal($device, $reading, q{}));

    for (@rows) {
        # Nur Zeilen mit gesuchten Identifier verwenden
        next if $_ !~ qr/^$key=/i;
        $_ =~ s/$key=//i;
        $cmd = $_;

        Log3($hash->{NAME}, 5, "cmd selected: $_") if (!defined($disableLog) || (defined($disableLog) && $disableLog != 1));
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
    $siteId = $hash->{helper}{defaultRoom} if $siteId eq "default";

    Log3($hash->{NAME}, 5, "runCmd called with command: $cmd");

    # Perl Command
    if ($cmd =~ m{\A\s*\{.*\}\s*\z}x) { #escaping closing bracket for editor only
        # CMD ausführen
        Log3($hash->{NAME}, 5, "$cmd is a perl command");
        return RHASSPY_execute($hash, $device, $cmd, $val,$siteId);
    }

    # String in Anführungszeichen (mit ReplaceSetMagic)
    if ($cmd =~ m/^\s*".*"\s*$/) {
        my $DEVICE = $device;
        my $ROOM = $siteId;
        my $VALUE = $val;

        Log3($hash->{NAME}, 5, "$cmd has quotes...");
        # Anführungszeichen entfernen
        $cmd =~ s{\A\s*"}{}x;
        $cmd =~ s{"\s*\z}{}x;

        # Variablen ersetzen?
        eval { $cmd =~ s/(\$\w+)/$1/eeg; };

        # [DEVICE:READING] Einträge ersetzen
        $returnVal = RHASSPY_ReplaceReadingsVal($hash, $cmd);
        # Escapte Kommas wieder durch normale ersetzen
        $returnVal =~ s/\\,/,/;
        Log3($hash->{NAME}, 5, "...and is now: $cmd ($returnVal)");
    }
    # FHEM Command oder CommandChain
    elsif (defined($main::cmds{ (split " ", $cmd)[0] })) {
        my @test = split q{ }, $cmd;
        print Dumper("device"=>$device,"test"=>@test[1]);
        Log3($hash->{NAME}, 5, "$cmd is a FHEM command");
        $error = AnalyzeCommandChain($hash, $cmd);
        $returnVal = @test[1];
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
sub RHASSPY_getValue($$$;$$) {
    my ($hash, $device, $getString, $val, $siteId) = @_;
    my $value;

    # Perl Command? -> Umleiten zu RHASSPY_runCmd
    if ($getString =~ m{\A\s*\{.*\}\s*\z}x) { 
        # Wert lesen
        $value = RHASSPY_runCmd($hash, $device, $getString, $val, $siteId);
    }
    # String in Anführungszeichen -> Umleiten zu RHASSPY_runCmd
    elsif ($getString =~ m/^\s*".*"\s*$/) {
        # Wert lesen
        $value = RHASSPY_runCmd($hash, $device, $getString, $val, $siteId);
    }
    # Reading oder Device:Reading
    else {
      # Soll Reading von einem anderen Device gelesen werden?
      my $readingsDev = ($getString =~ m/:/) ? (split(/:/, $getString))[0] : $device;
      my $reading = ($getString =~ m/:/) ? (split(/:/, $getString))[1] : $getString;

      $value = ReadingsVal($readingsDev, $reading, 0);
    }

    return $value;
}


# Zustand eines Gerätes über GetOnOff Mapping abfragen
sub RHASSPY_getOnOffState ($$$) {
    my ($hash, $device, $mapping) = @_;
    my $valueOn   = (defined($mapping->{'valueOn'}))  ? $mapping->{'valueOn'}  : undef;
    my $valueOff  = (defined($mapping->{'valueOff'})) ? $mapping->{'valueOff'} : undef;
    my $value = RHASSPY_getValue($hash, $device, $mapping->{'currentVal'});

    # Entscheiden ob $value 0 oder 1 ist
    if (defined($valueOff)) {
        $value = (lc($value) eq lc($valueOff)) ? 0 : 1;
    } elsif (defined($valueOn)) {
        $value = (lc($value) eq lc($valueOn)) ? 1 : 0;
    } else {
        # valueOn und valueOff sind nicht angegeben worden, alles außer "off" wird als eine 1 gewertet
        $value = (lc($value) eq "off") ? 0 : 1;
    }

    return $value;
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
    (($data->{'intent'} = $decoded->{'intent'}{'intentName'}) =~ s/^.*.://) if exists($decoded->{'intent'}{'intentName'}); #Beta-User: unless not... => doppelte Negation?
    $data->{'probability'} = $decoded->{'intent'}{'confidenceScore'}        if exists($decoded->{'intent'}{'confidenceScore'}); #Beta-User: macht diese Abfrage überhaupt Sinn? Ist halt so
    $data->{'sessionId'} = $decoded->{'sessionId'}                          if exists($decoded->{'sessionId'});
    $data->{'siteId'} = $decoded->{'siteId'}                                if exists($decoded->{'siteId'});
    $data->{'input'} = $decoded->{'input'}                                  if exists($decoded->{'input'});
    $data->{'rawInput'} = $decoded->{'rawInput'}                            if exists($decoded->{'rawInput'});


    # Überprüfen ob Slot Array existiert
    if (exists($decoded->{'slots'})) {
        #my @slots = @{$decoded->{'slots'}};

        # Key -> Value Paare aus dem Slot Array ziehen
        for my $slot (@{$decoded->{'slots'}}) { #Beta-User: foreach=for, "Einmalvariablen" machen keinen großen Sinn...
            my $slotName = $slot->{'slotName'};
            my $slotValue;

            $slotValue = $slot->{'value'}{'value'} if (exists($slot->{'value'}{'value'}));
            $slotValue = $slot->{'value'} if (exists($slot->{'entity'}) && $slot->{'entity'} eq "rhasspy/duration");

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
        # Name mit IODev vegleichen
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
    readingsBulkUpdate($hash, "lastIntentTopic", $topic);
    readingsBulkUpdate($hash, "lastIntentPayload", toJSON($data));
    readingsEndUpdate($hash, 1);
    return;
}

# Daten vom MQTT Modul empfangen -> Device und Room ersetzen, dann erneut an NLU übergeben
sub RHASSPY_onmessage {
    my $hash    = shift // return;
    my $topic   = shift // carp q[No topic provided!]   && return;
    my $message = shift // carp q[No message provided!] && return;;
    my $data  = RHASSPY_parseJSON($hash, $message);

    my $input = $data->{'input'};
    
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
    if ($topic =~ m{\Ahermes\/dialogueManager}x) {
        my $room = RHASSPY_roomName($hash, $data);

        return if !defined($room);
        my %mutated_vowels = ("ä" => "ae", "Ä" => "Ae", "ü" => "ue", "Ü" => "Ue", "ö" => "oe", "Ö" => "Oe", "ß" => "ss" );
        #my %mutated_vowels = \$languagevars->{$language}{mutated_vowels};
        my $keys = join q{|}, keys %mutated_vowels;
        #Log3($hash->{NAME}, 5, "mutated_vowels regex is $keys");

        $room =~ s/($keys)/$mutated_vowels{$1}/g;

        if ($topic =~ m/sessionStarted/) {
            readingsSingleUpdate($hash, "listening_" . makeReadingName($room), 1, 1);
        } elsif ($topic =~ m/sessionEnded/) {
            readingsSingleUpdate($hash, "listening_" . makeReadingName($room), 0, 1);
        }
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    if ($topic =~ qr/^hermes\/intent\/.*[:_]SetMute/ && defined($siteId)) {
        $type = ($message =~ m/fhem.textCommand/) ? "text" : "voice";
        $data->{requestType} = $type;

        # update Readings
        RHASSPY_updateLastIntentReadings($hash, $topic,$data);
        RHASSPY_handleIntentSetMute($hash, $data);
        push @updatedList, $hash->{NAME};
        return \@updatedList;
    }

    #elsif ($topic =~ qr/^hermes\/intent\/.*[:_]/ && !$mute && $topic !~ qr/^hermes\/intent\/${language}.fhem[:_]SetMute/) {
    
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
    push @updatedList, $device;
    return \@updatedList;
}
    

# Antwort ausgeben
sub RHASSPY_respond($$$$$) {
    my ($hash, $type, $sessionId, $siteId, $response) = @_;
    #my $json;

    my $sendData =  {
        sessionId => $sessionId,
        siteId => $siteId,
        text => $response
    };

    my $json = toJSON($sendData);

    if ($type eq "voice") {
        readingsSingleUpdate($hash, "voiceResponse", $response, 1);
    }
    elsif ($type eq "text") {
        readingsSingleUpdate($hash, "textResponse", $response, 1);
    }
    readingsSingleUpdate($hash, "responseType", $type, 1);
    IOWrite($hash, 'publish', 'hermes/dialogueManager/endSession '.$json);
    return;
}


# Antworttexte festlegen
sub RHASSPY_getResponse {
    my $hash = shift;
    my $identifier = shift // return 'Programmfehler, es wurde kein Identifier übergeben' ;

    my %messages = (
        DefaultError => "Da ist leider etwas schief gegangen.",
        NoActiveMediaDevice => "Tut mir leid, es ist kein Wiedergabegerät aktiv.",
        DefaultConfirmation => "OK"
    );

    return RHASSPY_getCmd($hash, $hash->{NAME}, "response", $identifier) // $messages{$identifier};
}


# Send text command to Rhasspy NLU
sub RHASSPY_textCommand($$) {
    my ($hash, $text) = @_;

    my $data = {
         input => $text,
         sessionId => 'fhem.textCommand'
    };
    my $message = toJSON($data);

    # Send fake command, so it's forwarded to NLU
#    my $topic2 = "hermes/intent/FHEM:TextCommand";
    my $topic = "hermes/nlu/query";
#    onmessage($hash, $topic2, $message);
    #return MQTT::send_publish($hash->{IODev}, topic => $topic, message => $message, qos => 0, retain => "0");
    
    return IOWrite($hash, 'publish', qq{$topic $message});
}


# Sprachausgabe / TTS über RHASSPY
sub RHASSPY_speak($$) {
    my ($hash, $cmd) = @_;
    my $sendData, my $json;
    my $siteId = "default";
    my $text = $cmd;
    my($unnamedParams, $namedParams) = parseParams($cmd);
    
    if (defined($namedParams->{'siteId'}) && defined($namedParams->{'text'})) {
        $siteId = $namedParams->{'siteId'};
        $text = $namedParams->{'text'};
    }
    
    $sendData =  {
        siteId => $siteId,
        text => $text,
        id => "0",
        sessionId => "0"
    };

    $json = toJSON($sendData);
    #MQTT::send_publish($hash->{IODev}, topic => 'hermes/tts/say', message => $json, qos => 0, retain => "0");
    return IOWrite($hash, 'publish', qq{hermes/tts/say $json});
}

# Send all devices, rooms, etc. to Rhasspy HTTP-API to update the slots
sub RHASSPY_updateSlots {
    my $hash = shift // return;
    my $method = q{POST};
    my $contenttype = q{application/json};

    # Collect everything and store it in arrays
    my @devices = RHASSPY_allRhasspyNames();
    my @rooms = RHASSPY_allRhasspyRooms();
    my @channels = RHASSPY_allRhasspyChannels();
    my @colors = RHASSPY_allRhasspyColors();
    my @types = RHASSPY_allRhasspyTypes();
    #my @shortcuts = RHASSPY_allRhasspyShortcuts($hash);
    my @shortcuts = keys %{$hash->{helper}{Shortcuts}};

    if (@shortcuts > 0) {
#        my $json;
        my $deviceData;
        my $url = "/api/sentences";
        
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
    if (@devices > 0 || @rooms > 0 || @channels > 0 || @types > 0) {
      my $json;
      my $deviceData;
      my $url = "/api/slots";

      $deviceData->{qq(${language}.fhem.Device)} = \@devices if @devices;
      $deviceData->{$language.'.fhem.Room'} = \@rooms if @rooms > 0;
      $deviceData->{$language.'.fhem.MediaChannels'} = \@channels if @channels > 0;
      $deviceData->{$language.'.fhem.Color'} = \@colors if @colors > 0;
      $deviceData->{$language.'.fhem.NumericType'} = \@types if @types > 0;

      $json = eval { toJSON($deviceData) };

      Log3($hash->{NAME}, 5, "Updating Rhasspy Slots with data: $json");
      
      RHASSPY_sendToApi($hash, $url, $method, $json);
    }
    return;
}

# Use the HTTP-API to instruct Rhasspy to re-train it's data
sub RHASSPY_trainRhasspy ($) {
    my ($hash) = @_;
    my $url = "/api/train";
    my $method = "POST";
    my $contenttype = "application/json";
    
    RHASSPY_sendToApi($hash, $url, $method, undef);
}

# Use the HTTP-API to fetch all available siteIds
sub RHASSPY_fetchSiteIds {
    my $hash = shift // return;
    my $url = "/api/profile?layers=profile";
    my $method = "GET";
    
    RHASSPY_sendToApi($hash, $url, $method, undef);
}
    

# Send request to HTTP-API of Rhasspy
sub RHASSPY_sendToApi {
    my $hash = shift // return;
    my $url = shift;
    my $method = shift;
    my $data = shift;
    my $base = AttrVal($hash->{NAME}, 'rhasspyMaster', undef);

    if ($base) {
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
    }
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

    if (grep({/api\/train/i} $url)) {
        readingsBulkUpdate($hash, 'training', $data);
    }
    elsif (grep({/api\/sentences/i} $url)) {
        readingsBulkUpdate($hash, 'updateSentences', $data);
    }
    elsif (grep({/api\/slots/i} $url)) {
        readingsBulkUpdate($hash, 'updateSlots', $data);
    }
    elsif (grep({/api\/profile/i} $url)) {
        my $ref = JSON->new->decode($data);
        my $siteIds = encode('cp-1252',$ref->{'dialogue'}{'satellite_site_ids'});
        readingsBulkUpdate($hash, 'siteIds', $siteIds);
    }
    else {
        Log3($hash->{NAME}, 3, qq(error while requesting $param->{url} - $data));
    }
    
    readingsEndUpdate($hash, 1);
    
    return;
}


# Eingehender Custom-Intent
sub RHASSPY_handleCustomIntent($$$) {
    my ($hash, $intentName, $data) = @_;
    my @intents, my $intent;
    my $intentsString = AttrVal($hash->{NAME},"rhasspyIntents",undef);
    my $response;
    my $error;

    Log3($hash->{NAME}, 5, "handleCustomIntent called");

    # Suchen ob ein passender Custom Intent existiert
    @intents = split(/\n/, $intentsString);
    for (@intents) {
        next if $_ !~ qr/^$intentName/;

        $intent = $_;
        Log3($hash->{NAME}, 5, "rhasspyIntent selected: $_");
    }

    # Gerät setzen falls Slot Device vorhanden
    if (exists($data->{'Device'})) {
      my $room = RHASSPY_roomName($hash, $data);
      my $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
      $data->{'Device'} = $device;
    }

    # Custom Intent Definition Parsen
    return if $intent !~ qr/^$intentName=.*\(.*\)/;
    #if ($intent =~ qr/^$intentName=.*\(.*\)/) {
        my @tokens = split(/=|\(|\)/, $intent);
        my $subName; my @paramNames;
        if (@tokens > 0){$subName = $tokens[1]} ;
        if (@tokens > 1){@paramNames = split(/,/, $tokens[2])};

        if (defined($subName)) {
            my @params = map { $data->{$_} } @paramNames;

            # Sub aus dem Custom Intent aufrufen
            $subName = "main::$subName";
            eval {
                Log3($hash->{NAME}, 5, "Calling sub: $subName");

                no strict 'refs';
                $response = $subName->(@params, $hash);
            };

            if ($@) {
                Log3($hash->{NAME}, 5, $@);
            }
        }
        #$response = RHASSPY_getResponse($hash, "DefaultError") if (!defined($response));
        $response = $response // RHASSPY_getResponse($hash, "DefaultError");

        # Antwort senden
        return RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
    #}
}

# Handle incoming "SetMute" intents
sub RHASSPY_handleIntentSetMute($$) {
    my ($hash, $data) = @_;
    my $value, my $siteId, my $state = 0;
    my $response = RHASSPY_getResponse($hash, "DefaultError");
    
    Log3($hash->{NAME}, 5, "handleIntentSetMute called");
    
    if (exists($data->{'Value'}) && exists($data->{'siteId'})) {
        $siteId = makeReadingName($data->{'siteId'});
        $value = $data->{'Value'};
        
#        Log3($hash->{NAME}, 5, "siteId: $siteId, value: $value");
        
        if ($value eq "on") {$state = 1};

        readingsSingleUpdate($hash, "mute_$siteId", $state, 1);
        $response = RHASSPY_getResponse($hash, "DefaultConfirmation");
    }
    return RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}

sub RHASSPY_handleIntentShortcuts {
    my $hash = shift // return;
    my $data = shift // return;
    
    my $shortcut = $hash->{helper}{shortcuts}{$data->{input}};
    Log3($hash->{NAME}, 5, "handleIntentShortcuts called with $data->{input} key");
    
    my $response = $shortcut->{response} // RHASSPY_getResponse($hash, 'DefaultError');
    my $ret;
    my $device;
    my $cmd = $shortcut->{perl};
    my $name = $shortcut->{NAME};
    my $self = $hash->{NAME};
    my %specials = (
         '$DEVICE' => $name,
         '$SELF'   => $self,
         '$NAME'   => $name
        );

    if (defined($cmd)) {
        Log3($hash->{NAME}, 4, "Perl shortcut identified: $cmd, shortc name is $shortcut->{NAME}");
        #partly replace variables:
        #$cmd = EvalSpecials($cmd, %specials);
        for my $key (keys %specials) {
            my $val = $specials{$key};
            $key =~ s{\$}{\\\$}gxms;
            $cmd =~ s{$key}{$val}gxms
        }
        #$cmd  = RHASSPY_EvalSpecialsDefaults($hash, $cmd, \$specials);
        #execute Perl command
        Log3($hash->{NAME}, 4, "Perl shortcut modified: $cmd");
        $ret = RHASSPY_runCmd($hash, undef, $cmd, undef, $data->{'siteId'});
        $device = $ret;
        #$response = $ret // EvalSpecials($response, %specials);
        $response = $ret // RHASSPY_EvalSpecialsDefaults($hash, $response, \%specials);
    } else {
        $cmd = $shortcut->{fhem} // return;
        #$cmd = EvalSpecials($cmd, $specials);
        #$cmd  = RHASSPY_EvalSpecialsDefaults($hash, $cmd, %specials);
        $device = split m{,}x, $shortcut->{NAME};
        #$response = EvalSpecials($response, %specials);
        #$response = RHASSPY_EvalSpecialsDefaults($hash, $response, %specials);
        AnalyzeCommand($hash, $cmd);
    }
    
    RHASSPY_respond ($hash, $data->{requestType}, $data->{sessionId}, $data->{siteId}, $response);
    # update Readings
    #RHASSPY_updateLastIntentReadings($hash, $topic,$data);
    return $device;
}

# Eingehende "SetOnOff" Intents bearbeiten
sub RHASSPY_handleIntentSetOnOff($$) {
    my ($hash, $data) = @_;
    my $value, my $numericValue, my $device, my $room, my $siteId;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentSetOnOff called");

    # Mindestens Gerät und Wert müssen übergeben worden sein
    if (exists($data->{'Device'}) && exists($data->{'Value'})) {
        $room = RHASSPY_roomName($hash, $data);
        $value = $data->{'Value'};
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = RHASSPY_getMapping($hash, $device, "SetOnOff", undef);

        # Mapping gefunden?
        if (defined($device) && defined($mapping)) {
            my $cmdOn  = (defined($mapping->{'cmdOn'}))  ? $mapping->{'cmdOn'}  : "on";
            my $cmdOff = (defined($mapping->{'cmdOff'})) ? $mapping->{'cmdOff'} : "off";
            my $cmd = ($value eq 'an') ? $cmdOn : $cmdOff;

            # Cmd ausführen
            RHASSPY_runCmd($hash, $device, $cmd);
            Log3($hash->{NAME}, 5, "Running command [$cmd] on device [$device]" );

            # Antwort bestimmen
            $numericValue = ($value eq 'an') ? 1 : 0;
            if (defined($mapping->{'response'})) { $response = RHASSPY_getValue($hash, $device, $mapping->{'response'}, $numericValue, $room); }
            else { $response = RHASSPY_getResponse($hash, "DefaultConfirmation"); }
        }
    }
    # Antwort senden
    RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
    return $device;
}


# Eingehende "GetOnOff" Intents bearbeiten
sub RHASSPY_handleIntentGetOnOff($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $status;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentGetOnOff called");

    # Mindestens Gerät und Status-Art wurden übergeben
    if (exists($data->{'Device'}) && exists($data->{'Status'})) {
        $room = RHASSPY_roomName($hash, $data);
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = RHASSPY_getMapping($hash, $device, "GetOnOff", undef);
        $status = $data->{'Status'};

#        Log3($hash->{NAME}, 5, "handleIntentGetOnOff - Device: $device - Status: $status");

        # Mapping gefunden?
        if (defined($mapping)) {
            # Gerät ein- oder ausgeschaltet?
            $value = RHASSPY_getOnOffState($hash, $device, $mapping);

            # Antwort bestimmen
            if    (defined($mapping->{'response'})) { $response = RHASSPY_getValue($hash, $device, $mapping->{'response'}, $value, $room); }
            elsif ($status =~ m/^(an|aus)$/ && $value == 1) { $response = $data->{'Device'} . " ist eingeschaltet"; }
            elsif ($status =~ m/^(an|aus)$/ && $value == 0) { $response = $data->{'Device'} . " ist ausgeschaltet"; }
            elsif ($status =~ m/^(auf|zu)$/ && $value == 1) { $response = $data->{'Device'} . " ist geöffnet"; }
            elsif ($status =~ m/^(auf|zu)$/ && $value == 0) { $response = $data->{'Device'} . " ist geschlossen"; }
            elsif ($status =~ m/^(eingefahren|ausgefahren)$/ && $value == 1) { $response = $data->{'Device'} . " ist eingefahren"; }
            elsif ($status =~ m/^(eingefahren|ausgefahren)$/ && $value == 0) { $response = $data->{'Device'} . " ist ausgefahren"; }
            elsif ($status =~ m/^(läuft|fertig)$/ && $value == 1) { $response = $data->{'Device'} . " läuft noch"; }
            elsif ($status =~ m/^(läuft|fertig)$/ && $value == 0) { $response = $data->{'Device'} . " ist fertig"; }
        }
    }
    # Antwort senden
    RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
    $device ? return $device : return;
}


# Eingehende "SetNumeric" Intents bearbeiten
sub RHASSPY_handleIntentSetNumeric($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $change, my $type, my $unit;
    my $mapping;
    my $validData = 0;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentSetNumeric called");

    # Mindestens Device und Value angegeben -> Valid (z.B. Deckenlampe auf 20%)
    $validData = 1 if (exists($data->{'Device'}) && exists($data->{'Value'}));
    # Mindestens Device und Change angegeben -> Valid (z.B. Radio lauter)
    $validData = 1 if (exists($data->{'Device'}) && exists($data->{'Change'}));
    # Nur Change für Lautstärke angegeben -> Valid (z.B. lauter)
    $validData = 1 if (!exists($data->{'Device'}) && defined($data->{'Change'}) && $data->{'Change'} =~ m/^(lauter|leiser)$/i);
    # Nur Type = Lautstärke und Value angegeben -> Valid (z.B. Lautstärke auf 10)
    $validData = 1 if (!exists($data->{'Device'}) && defined($data->{'Type'}) && $data->{'Type'} =~ m/^Lautstärke$/i && exists($data->{'Value'}));

    if ($validData == 1) {
        $unit = $data->{'Unit'};
        $type = $data->{'Type'};
        $value = $data->{'Value'};
        $change = $data->{'Change'};
        $room = RHASSPY_roomName($hash, $data);

        # Type nicht belegt -> versuchen Type über change Value zu bestimmen
        if (!defined($type) && defined($change)) {
            if    ($change =~ m/^(kälter|wärmer)$/)  { $type = "Temperatur"; }
            elsif ($change =~ m/^(dunkler|heller)$/) { $type = "Helligkeit"; }
            elsif ($change =~ m/^(lauter|leiser)$/)  { $type = "Lautstärke"; }
        }

        # Gerät über Name suchen, oder falls über Lautstärke ohne Device getriggert wurde das ActiveMediaDevice suchen
        if (exists($data->{'Device'})) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        } elsif (defined($type) && $type =~ m/^Lautstärke$/i) {
            $device = RHASSPY_getActiveDeviceForIntentAndType($hash, $room, "SetNumeric", $type);
            $response = RHASSPY_getResponse($hash, "NoActiveMediaDevice") if (!defined($device));
        }

        if (defined($device)) {
            $mapping = RHASSPY_getMapping($hash, $device, "SetNumeric", $type);

            # Mapping und Gerät gefunden -> Befehl ausführen
            if (defined($mapping) && defined($mapping->{'cmd'})) {
                my $cmd     = $mapping->{'cmd'};
                my $part    = $mapping->{'part'};
                my $minVal  = (defined($mapping->{'minVal'})) ? $mapping->{'minVal'} : 0; # Rhasspy kann keine negativen Nummern bisher, daher erzwungener minVal
                my $maxVal  = $mapping->{'maxVal'};
                my $diff    = (defined($value)) ? $value : ((defined($mapping->{'step'})) ? $mapping->{'step'} : 10);
                my $up      = (defined($change) && ($change =~ m/^(höher|heller|lauter|wärmer)$/)) ? 1 : 0;
                my $forcePercent = (defined($mapping->{'map'}) && lc($mapping->{'map'}) eq "percent") ? 1 : 0;

                # Alten Wert bestimmen
                my $oldVal  = RHASSPY_getValue($hash, $device, $mapping->{'currentVal'});
                if (defined($part)) {
                    my @tokens = split(/ /, $oldVal);
                    $oldVal = $tokens[$part] if (@tokens >= $part);
                }

                # Neuen Wert bestimmen
                my $newVal;
                # Direkter Stellwert ("Stelle Lampe auf 50")
                if ($unit ne "Prozent" && defined($value) && !defined($change) && !$forcePercent) {
                    $newVal = $value;
                }
                # Direkter Stellwert als Prozent ("Stelle Lampe auf 50 Prozent", oder "Stelle Lampe auf 50" bei forcePercent)
                elsif (defined($value) && ((defined($unit) && $unit eq "Prozent") || $forcePercent) && !defined($change) && defined($minVal) && defined($maxVal)) {
                    # Wert von Prozent in Raw-Wert umrechnen
                    $newVal = $value;
                    $newVal =   0 if ($newVal <   0);
                    $newVal = 100 if ($newVal > 100);
                    $newVal = round((($newVal * (($maxVal - $minVal) / 100)) + $minVal), 0);
                }
                # Stellwert um Wert x ändern ("Mache Lampe um 20 heller" oder "Mache Lampe heller")
                elsif ((!defined($unit) || $unit ne "Prozent") && defined($change) && !$forcePercent) {
                    $newVal = ($up) ? $oldVal + $diff : $oldVal - $diff;
                }
                # Stellwert um Prozent x ändern ("Mache Lampe um 20 Prozent heller" oder "Mache Lampe um 20 heller" bei forcePercent oder "Mache Lampe heller" bei forcePercent)
                elsif (($unit eq "Prozent" || $forcePercent) && defined($change)  && defined($minVal) && defined($maxVal)) {
                    my $diffRaw = round((($diff * (($maxVal - $minVal) / 100)) + $minVal), 0);
                    $newVal = ($up) ? $oldVal + $diffRaw : $oldVal - $diffRaw;
                }

                if (defined($newVal)) {
                    # Begrenzung auf evtl. gesetzte min/max Werte
                    $newVal = $minVal if (defined($minVal) && $newVal < $minVal);
                    $newVal = $maxVal if (defined($maxVal) && $newVal > $maxVal);

                    # Cmd ausführen
                    RHASSPY_runCmd($hash, $device, $cmd, $newVal);
                    
                    # Antwort festlegen
                    if (defined($mapping->{'response'})) { $response = RHASSPY_getValue($hash, $device, $mapping->{'response'}, $newVal, $room); }
                    else { $response = RHASSPY_getResponse($hash, "DefaultConfirmation"); }
                }
            }
        }
    }
    # Antwort senden
    RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "GetNumeric" Intents bearbeiten
sub RHASSPY_handleIntentGetNumeric($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room, my $type;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentGetNumeric called");

    # Mindestens Type oder Device muss existieren
    if (exists($data->{'Type'}) || exists($data->{'Device'})) {
        $type = $data->{'Type'};
        $room = RHASSPY_roomName($hash, $data);

        # Passendes Gerät suchen
        if (exists($data->{'Device'})) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = RHASSPY_getDeviceByIntentAndType($hash, $room, "GetNumeric", $type);
        }

        $mapping = RHASSPY_getMapping($hash, $device, "GetNumeric", $type) if (defined($device));

        # Mapping gefunden
        if (defined($mapping)) {
            my $part = $mapping->{'part'};
            my $minVal  = $mapping->{'minVal'};
            my $maxVal  = $mapping->{'maxVal'};
            my $mappingType = $mapping->{'type'};
            my $forcePercent = (defined($mapping->{'map'}) && lc($mapping->{'map'}) eq "percent" && defined($minVal) && defined($maxVal)) ? 1 : 0;
            my $isNumber;

            # Zurückzuliefernden Wert bestimmen
            $value = RHASSPY_getValue($hash, $device, $mapping->{'currentVal'});
            if (defined($part)) {
              my @tokens = split(/ /, $value);
              $value = $tokens[$part] if (@tokens >= $part);
            }
            $value = round((($value * (($maxVal - $minVal) / 100)) + $minVal), 0) if ($forcePercent);
            $isNumber = main::looks_like_number($value);

            # Punkt durch Komma ersetzen in Dezimalzahlen
            $value =~ s/\./\,/g;

            # Antwort falls Custom Response definiert ist
            if    (defined($mapping->{'response'})) { $response = RHASSPY_getValue($hash, $device, $mapping->{'response'}, $value, $room); }

            # Antwort falls mappingType matched
            elsif ($mappingType =~ m/^(Helligkeit|Lautstärke|Sollwert)$/i) { $response = $data->{'Device'} . " ist auf $value gestellt."; }
            elsif ($mappingType =~ m/^Temperatur$/i) { $response = "Die Temperatur von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value" . ($isNumber ? " Grad" : ""); }
            elsif ($mappingType =~ m/^Luftfeuchtigkeit$/i) { $response = "Die Luftfeuchtigkeit von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value" . ($isNumber ? " Prozent" : ""); }
            elsif ($mappingType =~ m/^Batterie$/i) { $response = "Der Batteriestand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . ($isNumber ?  " beträgt $value Prozent" : " ist $value"); }
            elsif ($mappingType =~ m/^Wasserstand$/i) { $response = "Der Wasserstand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value"; }
            elsif ($mappingType =~ m/^Bodenfeuchte$/i) { $response = "Die Bodenfeuchte von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value Prozent"; }

            # Andernfalls Antwort falls type aus Intent matched
            elsif ($type =~ m/^(Helligkeit|Lautstärke|Sollwert)$/) { $response = $data->{'Device'} . " ist auf $value gestellt."; }
            elsif ($type =~ m/^Temperatur$/i) { $response = "Die Temperatur von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value" . ($isNumber ? " Grad" : ""); }
            elsif ($type =~ m/^Luftfeuchtigkeit$/i) { $response = "Die Luftfeuchtigkeit von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value" . ($isNumber ? " Prozent" : ""); }
            elsif ($type =~ m/^Batterie$/i) { $response = "Der Batteriestand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . ($isNumber ?  " beträgt $value Prozent" : " ist $value"); }
            elsif ($type =~ m/^Wasserstand$/i) { $response = "Der Wasserstand von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value"; }
            elsif ($type =~ m/^Bodenfeuchte$/i) { $response = "Die Bodenfeuchte von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value Prozent"; }

            # Antwort wenn Custom Type
            elsif (defined($mappingType)) { $response = "$mappingType von " . (exists $data->{'Device'} ? $data->{'Device'} : $data->{'Room'}) . " beträgt $value"; }

            # Standardantwort falls der Type überhaupt nicht bestimmt werden kann
            else { $response = "Der Wert von " . $data->{'Device'} . " beträgt $value."; }
        }
    }
    # Antwort senden
    return RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "Status" Intents bearbeiten
sub RHASSPY_handleIntentStatus($$) {
    my ($hash, $data) = @_;
    my $value, my $device, my $room;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentStatus called");

    # Mindestens Device muss existieren
    if (exists($data->{'Device'})) {
        $room = RHASSPY_roomName($hash, $data);
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        $mapping = RHASSPY_getMapping($hash, $device, "Status", undef);

        if (defined($mapping->{'response'})) {
            $response = RHASSPY_getValue($hash, $device, $mapping->{'response'},undef,  $room);
        }
    }
    # Antwort senden
    return RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "MediaControls" Intents bearbeiten
sub RHASSPY_handleIntentMediaControls($$) {
    my ($hash, $data) = @_;
    my $command, my $device, my $room;
    my $mapping;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentMediaControls called");

    # Mindestens Kommando muss übergeben worden sein
    if (exists($data->{'Command'})) {
        $room = RHASSPY_roomName($hash, $data);
        $command = $data->{'Command'};

        # Passendes Gerät suchen
        if (exists($data->{'Device'})) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = RHASSPY_getActiveDeviceForIntentAndType($hash, $room, "MediaControls", undef);
            $response = RHASSPY_getResponse($hash, "NoActiveMediaDevice") if (!defined($device));
        }

        $mapping = RHASSPY_getMapping($hash, $device, "MediaControls", undef);

        if (defined($device) && defined($mapping)) {
            my $cmd;

            if    ($command =~ m/^play$/i)   { $cmd = $mapping->{'cmdPlay'}; }
            elsif ($command =~ m/^pause$/i)  { $cmd = $mapping->{'cmdPause'}; }
            elsif ($command =~ m/^stop$/i)   { $cmd = $mapping->{'cmdStop'}; }
            elsif ($command =~ m/^vor$/i)    { $cmd = $mapping->{'cmdFwd'}; }
            elsif ($command =~ m/^zurück$/i) { $cmd = $mapping->{'cmdBack'}; }

            if (defined($cmd)) {
                # Cmd ausführen
                RHASSPY_runCmd($hash, $device, $cmd);
                
                # Antwort festlegen
                if (defined($mapping->{'response'})) { $response = RHASSPY_getValue($hash, $device, $mapping->{'response'}, $command, $room); }
                else { $response = RHASSPY_getResponse($hash, "DefaultConfirmation"); }
            }
        }
    }
    # Antwort senden
    return RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "GetTime" Intents bearbeiten
sub RHASSPY_handleIntentGetTime($$) {
    my ($hash, $data) = @_;
    #my $channel, my $device, my $room;
    Log3($hash->{NAME}, 5, "handleIntentGetTime called");

    (my $sec,my $min,my $hour,my $mday,my $mon,my $year,my $wday,my $yday,my $isdst) = localtime();
    my $response = "Es ist $hour Uhr $min";
    Log3($hash->{NAME}, 5, "Response: $response");
    
    # Antwort senden
    return RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "GetWeekday" Intents bearbeiten
sub RHASSPY_handleIntentGetWeekday($$) {
    my ($hash, $data) = @_;
    #my $channel, my $device, my $room;
    my $weekDay  = strftime "%A", localtime;
    my $response = qq(Heute ist $weekDay);
    
    
    # Get configured language from attribut "language" of device "global"
    # to determine locale for DateTime
    #my $language = lc AttrVal("global", "language", "de");

    #$language = lc $data->{'lang'} if (exists($data->{'lang'}));
    Log3($hash->{NAME}, 5, "handleIntentGetWeekday called");

    #$response = "Heute ist " . DateTime->now(locale => $language)->day_name;
    Log3($hash->{NAME}, 5, "Response: $response");

    # Antwort senden
    return RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "MediaChannels" Intents bearbeiten
sub RHASSPY_handleIntentMediaChannels($$) {
    my ($hash, $data) = @_;
    my $channel, my $device, my $room;
    my $cmd;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentMediaChannels called");

    # Mindestens Channel muss übergeben worden sein
    if (exists($data->{'Channel'})) {
        $room = RHASSPY_roomName($hash, $data);
        $channel = $data->{'Channel'};

        # Passendes Gerät suchen
        if (exists($data->{'Device'})) {
            $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        } else {
            $device = RHASSPY_getDeviceByMediaChannel($hash, $room, $channel);
        }

        $cmd = RHASSPY_getCmd($hash, $device, "rhasspyChannels", $channel, undef);

        if (defined($device) && defined($cmd)) {
            $response = RHASSPY_getResponse($hash, "DefaultConfirmation");
            # Cmd ausführen
            RHASSPY_runCmd($hash, $device, $cmd);
        }
    }

    # Antwort senden
    RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}


# Eingehende "SetColor" Intents bearbeiten
sub RHASSPY_handleIntentSetColor($$) {
    my ($hash, $data) = @_;
    my $color, my $device, my $room;
    my $cmd;
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentSetColor called");

    # Mindestens Device und Color muss übergeben worden sein
    if (exists($data->{'Color'}) && exists($data->{'Device'})) {
        $room = RHASSPY_roomName($hash, $data);
        $color = $data->{'Color'};

        # Passendes Gerät & Cmd suchen
        $device = RHASSPY_getDeviceByName($hash, $room, $data->{'Device'});
        $cmd = RHASSPY_getCmd($hash, $device, "rhasspyColors", $color, undef);

        if (defined($device) && defined($cmd)) {
            $response = RHASSPY_getResponse($hash, "DefaultConfirmation");

            # Cmd ausführen
            RHASSPY_runCmd($hash, $device, $cmd);
        }
    }
    # Antwort senden
    RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}


# Handle incoming SetTimer intents
sub RHASSPY_handleIntentSetTimer {
    my $hash = shift;
    my $data = shift // return;
    my $value, my $unit, my $room, my $siteId, my $time;
    my $name = $hash->{'NAME'};
    my $cmd;
    my $validData = 0;
    my @unitHours = ("stunde","stunden","hour","hours","heure","heures");
    my @unitMinutes = ("minute","minuten","minute","minutes");
    my $response = RHASSPY_getResponse($hash, "DefaultError");

    Log3($hash->{NAME}, 5, "handleIntentSetTimer called");

    if ($data->{'Room'}) {$room = makeReadingName($data->{'Room'})};
    if ($data->{'Value'}) {$value = $data->{'Value'}} else {$response = "Tut mir leid ich habe die Dauer nicht verstanden"};
    if ($data->{'Unit'}) {$unit = $data->{'Unit'}} else {$response = "Tut mir leid ich habe die Dauer nicht verstanden"};
    if ($data->{'siteId'}) {$siteId = $data->{'siteId'}};

    if($value && $unit && ($room||$siteId)) {$validData = 1};
    if (!$room){$room = $siteId};
    
    if ($validData == 1) {
        $time = $value;

        if ( grep $_ eq $unit, @unitMinutes ) {$time = $value*60};
        if ( grep $_ eq $unit, @unitHours ) {$time = $value*3600};
        
        $time = strftime('%T', gmtime($time));

        $cmd = "defmod timer_$room at +$time set $name speak siteId=\"$room\" text=\"taimer abgelaufen\";;setreading $name timer_".$room." 0";
        
        RHASSPY_runCmd($hash,"",$cmd);

        readingsSingleUpdate($hash, "timer_" . makeReadingName($room), 1, 1);
        
        Log3($hash->{NAME}, 5, "Created timer: $cmd");
        
        $response = "Taimer in $room gesetzt auf $value $unit";
    }

    RHASSPY_respond ($hash, $data->{'requestType'}, $data->{sessionId}, $data->{siteId}, $response);
}

sub RHASSPY_playWav($$) {
    my ($hash, $params) = @_;
    my $siteId = "default";
    my $json;
    my $url = "/api/play-wav";
    my $method = "POST";
    my $contenttype = "audio/wav";
    my($unnamedParams, $namedParams) = parseParams($params);

    Log3($hash->{NAME}, 5, "action playWav called");
    
    if (defined($namedParams->{'siteId'}) && defined($namedParams->{'path'})) {
        $siteId = $namedParams->{'siteId'};
        my $filename = $namedParams->{'path'};
        my $encoding = ":raw :bytes";
        my $handle   = undef;
        my $topic = "hermes/audioServer/$siteId/playBytes/999";

        Log3($hash->{NAME}, 3, "Playing file $filename on $siteId");

        if (-e $filename) {
            open($handle, "< $encoding", $filename)
                || warn "$0: can't open $filename for reading: $!";

            while (read($handle,my $file_contents,1000000) ) { 
                #MQTT::send_publish($hash->{IODev}, topic => $topic, message => $file_contents, qos => 0, retain => "0");
                IOWrite($hash, 'publish', qq{$topic $file_contents});
            }

            close($handle);
        }
    }
}


# Abgespeckte Kopie von ReplaceSetMagic aus fhem.pl
#sub	RHASSPY_ReplaceReadingsVal($@) {
sub RHASSPY_ReplaceReadingsVal {
    my $hash = shift;
    my @arr  = shift // return;
    my $to_analyze = join q{ }, @arr;
#    my $a = join(" ", @_);

    my $readingsVal = sub ($$$$$) {
#    sub readingsVal($$$$$) { #Nested named subroutine. Declaring a named sub inside another named sub does not prevent the inner sub from being global. Umbauen wie "my $activeDevice = sub ($$) {"...?
        #my ($all, $t, $d, $n, $s, $val) = @_;
        my ($all, $t, $d, $n, $s) = @_;
        my $val;
        my $hash = $defs{$d};
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
#        $val = $hash->{$n}   if(!defined($val) && (!$t || $t eq "i:"));
#        $val = $attr{$d}{$n} if(!defined($val) && (!$t || $t eq "a:") && $attr{$d});
        $val = $hash->{$n}   if(!defined($val) && (!$t || $t eq 'i:'));
        $val = $attr{$d}{$n} if(!defined($val) && (!$t || $t eq 'a:') && $attr{$d});
        return $all if(!defined($val));

        if($s && $s =~ /:d|:r|:i/ && $val =~ /(-?\d+(\.\d+)?)/) {
            $val = $1;
            $val = int($val) if ( $s eq ":i" );
            $val = round($val, defined($1) ? $1 : 1) if($s =~ /^:r(\d)?/);
        }
        return $val;
    };

#    $a =~s/(\[([ari]:)?([a-zA-Z\d._]+):([a-zA-Z\d._\/-]+)(:(t|sec|i|d|r|r\d))?\])/readingsVal($1,$2,$3,$4,$5)/eg;
#    return $a;
    $to_analyze =~s/(\[([ari]:)?([a-zA-Z\d._]+):([a-zA-Z\d._\/-]+)(:(t|sec|i|d|r|r\d))?\])/$readingsVal->($1,$2,$3,$4,$5)/eg;
    return $to_analyze;
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
<p><code>define &lt;name&gt; RHASSPY &lt;MqttDevice&gt; &lt;DefaultRoom&gt;</code></p>
<ul>
  <li>MqttDevice: Name of the MQTT Device in FHEM which connects to Rhasspys MQTT server</li>
  <li>DefaultRoom: Default room name. Used to speak commands without a room name (e.g. &quot;turn lights on&quot; to turn on the lights in the &quot;default room&quot;)</li>
</ul>
<p>Example for defining an MQTT device and the Rhasspy device in FHEM:</p>
<p>
  <code>define rhasspyMQTT MQTT &lt;ip-or-hostname-of-rhasspy-master&gt;:12101</code><br>
  <code>define Rhasspy RHASSPY rhasspyMQTT Wohnzimmer</code>
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
	Example:<pre><code>mute on={fhem ("set receiver mute on")}
mute off={fhem ("set receiver mute off")}</code></pre>
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
